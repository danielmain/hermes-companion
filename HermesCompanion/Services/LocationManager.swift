import Foundation
import CoreLocation
import CoreMotion
import UIKit
import Combine
import os

public final class LocationManager: NSObject, ObservableObject {
    public static let shared = LocationManager()

    // MARK: - Published State
    @Published public private(set) var currentLocation: CLLocation?
    @Published public private(set) var latestRecord: LocationRecord?
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public private(set) var isTrackingActive: Bool = false
    @Published public private(set) var isSignificantMonitoringActive: Bool = false
    @Published public private(set) var isVisitsMonitoringActive: Bool = false
    @Published public private(set) var activeGeofenceRadius: Double?
    @Published public private(set) var wasLaunchedFromTerminated: Bool = false
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var currentMotionActivity: MotionActivity = .unknown
    @Published public private(set) var motionUpdatedAt: Date?
    @Published public var configuration: TrackingConfiguration {
        didSet {
            saveConfiguration()
            applyConfiguration()
        }
    }

    // MARK: - CoreLocation
    private let locationManager = CLLocationManager()
    private var lastRecordedCoordinate: CLLocationCoordinate2D?
    private var currentGeofenceRegion: CLCircularRegion?
    private let userDefaultsKey = "com.hermes.companion.trackingConfig"
    private let logger = Logger(subsystem: "com.hermes.HermesCompanion", category: "LocationManager")

    // MARK: - CoreMotion (real motion state, independent of the GPS fix age)
    private let motionManager = CMMotionActivityManager()
    private var currentMotionConfidence: String = "unknown"

    private override init() {
        // Load configuration
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(TrackingConfiguration.self, from: data) {
            self.configuration = saved
        } else {
            self.configuration = .default
        }

        super.init()

        UIDevice.current.isBatteryMonitoringEnabled = true
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = configuration.distanceFilterMeters
        locationManager.activityType = .otherNavigation

        self.authorizationStatus = locationManager.authorizationStatus

        // Check if tracking was enabled previously
        let wasActive = UserDefaults.standard.bool(forKey: "com.hermes.trackingActiveState")
        if wasActive {
            startTracking()
        }
    }

    // MARK: - App Lifecycle Hook (Called from AppDelegate when launched)
    public func handleAppLaunch(with launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        if let _ = launchOptions?[.location] {
            wasLaunchedFromTerminated = true
            LocationStore.shared.logDiagnostic(
                title: "App Woke From Closed State",
                details: "Relaunched in background by iOS for incoming location event",
                severity: .success
            )

            // Make sure location manager starts immediately as required by Apple
            if !isTrackingActive {
                startTracking()
            }
        } else {
            LocationStore.shared.logDiagnostic(
                title: "App Launched Normally",
                details: "Started by user interaction",
                severity: .info
            )
        }
    }

    // MARK: - Permissions
    public func requestPermissions() {
        LocationStore.shared.logDiagnostic(
            title: "Requesting Location Authorization",
            details: "Current status: \(authorizationStatusDescription)",
            severity: .info
        )

        // Request Always authorization
        locationManager.requestAlwaysAuthorization()
    }

    public var isAlwaysAuthorized: Bool {
        authorizationStatus == .authorizedAlways
    }

    public var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    public var authorizationStatusDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted (MDM/Parental)"
        case .denied: return "Denied"
        case .authorizedWhenInUse: return "When In Use Only (Always needed)"
        case .authorizedAlways: return "Always (Full Background Access)"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Tracking Controls
    public func toggleTracking() {
        if isTrackingActive {
            stopTracking()
        } else {
            startTracking()
        }
    }

    public func startTracking() {
        guard isAuthorized else {
            requestPermissions()
            return
        }

        isTrackingActive = true
        UserDefaults.standard.set(true, forKey: "com.hermes.trackingActiveState")

        // Configure background updates
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = configuration.backgroundIndicatorEnabled

        // Always enable Significant Location Changes (Apple's guarantee for wakes when closed)
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.startMonitoringSignificantLocationChanges()
            isSignificantMonitoringActive = true
        }

        // Always enable Visits monitoring (Apple's guarantee for arrival/departure wakes)
        locationManager.startMonitoringVisits()
        isVisitsMonitoringActive = true

        // Configure standard updates according to mode
        switch configuration.trackingMode {
        case .ultraContinuous:
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.distanceFilter = kCLDistanceFilterNone
            locationManager.startUpdatingLocation()

        case .smartAlways:
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = configuration.distanceFilterMeters
            locationManager.startUpdatingLocation()
            locationManager.requestLocation()

        case .batterySaver:
            // In battery saver mode, we don't keep GPS radio open constantly;
            // we rely on Significant Location Changes + Visits + Geofencing
            locationManager.stopUpdatingLocation()
        }

        // Start real motion activity monitoring (walking/running/driving/stationary)
        startMotionUpdates()

        // Immediately trigger sync for any existing or latest records
        triggerRecordSync()

        LocationStore.shared.logDiagnostic(
            title: "Tracking Started",
            details: "Mode: \(configuration.trackingMode.rawValue), Always: \(isAlwaysAuthorized)",
            severity: .success
        )
    }

    public func stopTracking() {
        isTrackingActive = false
        UserDefaults.standard.set(false, forKey: "com.hermes.trackingActiveState")

        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()

        // Clear any active geofence
        clearDynamicGeofence()

        motionManager.stopActivityUpdates()

        isSignificantMonitoringActive = false
        isVisitsMonitoringActive = false

        LocationStore.shared.logDiagnostic(
            title: "Tracking Stopped",
            details: "All location monitors paused by user",
            severity: .warning
        )
    }

    public func requestSingleLocationUpdate(source: LocationTriggerSource = .manualPing) {
        guard isAuthorized else {
            requestPermissions()
            return
        }
        locationManager.requestLocation()
        LocationStore.shared.logDiagnostic(
            title: "One-Shot Location Requested",
            details: "Source: \(source.rawValue)",
            severity: .info
        )
    }

    // MARK: - Dynamic Perimeter Geofencing (Guarantees wake when closed)
    private func setupDynamicGeofence(around coordinate: CLLocationCoordinate2D) {
        guard configuration.dynamicGeofenceEnabled,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        // Remove old geofence
        clearDynamicGeofence()

        let radius = max(50.0, configuration.geofenceRadiusMeters)
        let region = CLCircularRegion(
            center: coordinate,
            radius: radius,
            identifier: "hermes.dynamic.perimeter"
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false

        locationManager.startMonitoring(for: region)
        self.currentGeofenceRegion = region
        self.activeGeofenceRadius = radius

        LocationStore.shared.logDiagnostic(
            title: "Stationary Geofence Set",
            details: "Radius: \(Int(radius))m at (\(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude)))",
            severity: .info
        )
    }

    private func clearDynamicGeofence() {
        if let existing = currentGeofenceRegion {
            locationManager.stopMonitoring(for: existing)
            currentGeofenceRegion = nil
            activeGeofenceRadius = nil
        }
    }

    // MARK: - Motion Activity (CoreMotion)
    private func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            LocationStore.shared.logDiagnostic(
                title: "Motion Activity Unavailable",
                details: "CMMotionActivityManager is not available on this device (e.g. Simulator).",
                severity: .warning
            )
            return
        }

        motionManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.applyMotionActivity(activity)
        }

        LocationStore.shared.logDiagnostic(
            title: "Motion Monitoring Started",
            details: "CMMotionActivity updates enabled (stationary/walking/running/automotive)",
            severity: .success
        )
    }

    private func applyMotionActivity(_ activity: CMMotionActivity) {
        let mapped: MotionActivity
        if activity.automotive {
            mapped = .automotive
        } else if activity.cycling {
            mapped = .cycling
        } else if activity.running {
            mapped = .running
        } else if activity.walking {
            mapped = .walking
        } else if activity.stationary {
            mapped = .stationary
        } else {
            mapped = .unknown
        }

        let confidence: String
        switch activity.confidence {
        case .high: confidence = "high"
        case .medium: confidence = "medium"
        case .low: confidence = "low"
        @unknown default: confidence = "low"
        }

        self.currentMotionActivity = mapped
        self.currentMotionConfidence = confidence
        self.motionUpdatedAt = activity.startDate
    }

    private func saveConfiguration() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func applyConfiguration() {
        locationManager.distanceFilter = configuration.distanceFilterMeters
        locationManager.showsBackgroundLocationIndicator = configuration.backgroundIndicatorEnabled

        if isTrackingActive {
            startTracking()
        }
    }

    // MARK: - Battery Info
    private var currentBatteryLevel: Float {
        UIDevice.current.batteryLevel
    }

    private var currentBatteryStateString: String {
        switch UIDevice.current.batteryState {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return "unknown"
        }
    }

    private var currentAppStateString: String {
        if wasLaunchedFromTerminated {
            return "resumed_terminated"
        }
        switch UIApplication.shared.applicationState {
        case .active: return "foreground"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    /// Minimum displacement required before a GPS fix is persisted. Floor of 1 m absorbs identical ticks even when the slider is 0.
    private var persistDistanceThreshold: Double {
        max(configuration.distanceFilterMeters, 1.0)
    }

    private var lastPersistedCoordinate: CLLocationCoordinate2D? {
        if let lastRecordedCoordinate {
            return lastRecordedCoordinate
        }
        return LocationStore.shared.records.first?.coordinate
    }

    /// Writes a GPS record and touches iCloud/CloudKit files only when the coordinate has actually changed.
    private func ingestLocation(_ location: CLLocation, source: LocationTriggerSource) {
        currentLocation = location

        let threshold = persistDistanceThreshold
        if let last = lastPersistedCoordinate,
           LocationRecord.isUnchangedGPS(from: last, to: location.coordinate, thresholdMeters: threshold) {
            let displacement = LocationRecord.displacementMeters(from: last, to: location.coordinate)
            logger.info("Skipped GPS persist (\(source.rawValue)): displacement \(displacement, format: .fixed(precision: 1))m is below \(threshold, format: .fixed(precision: 1))m. No record written, no file touched.")
            return
        }

        let record = LocationRecord(
            location: location,
            source: source,
            appState: currentAppStateString,
            batteryLevel: currentBatteryLevel,
            batteryState: currentBatteryStateString,
            motionActivity: currentMotionActivity,
            motionTimestamp: motionUpdatedAt,
            motionConfidence: currentMotionConfidence
        )

        latestRecord = record
        lastRecordedCoordinate = location.coordinate

        let saved = LocationStore.shared.saveRecord(record, minDisplacementMeters: threshold)
        guard saved else {
            logger.info("LocationStore rejected duplicate GPS record (\(source.rawValue)). Files untouched.")
            return
        }

        logger.info("Persisted GPS record (\(source.rawValue)) at (\(location.coordinate.latitude, format: .fixed(precision: 5)), \(location.coordinate.longitude, format: .fixed(precision: 5)))")

        if location.speed < 1.0 {
            setupDynamicGeofence(around: location.coordinate)
        }

        triggerRecordSync()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            LocationStore.shared.logDiagnostic(
                title: "Location Permission Changed",
                details: "New status: \(self.authorizationStatusDescription)",
                severity: self.isAlwaysAuthorized ? .success : .warning
            )

            if self.isAuthorized && self.isTrackingActive {
                self.startTracking()
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter out unreasonable accuracy if accuracy is negative
        guard location.horizontalAccuracy >= 0 else { return }

        DispatchQueue.main.async {
            var source: LocationTriggerSource = .standardGPS
            if self.wasLaunchedFromTerminated {
                source = .wakeFromTerminated
                self.wasLaunchedFromTerminated = false // reset flag after first consume
            } else if self.configuration.trackingMode == .batterySaver {
                source = .significantChange
            }
            self.ingestLocation(location, source: source)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        DispatchQueue.main.async {
            let isArrival = visit.departureDate == Date.distantFuture
            let source: LocationTriggerSource = isArrival ? .visitArrival : .visitDeparture

            let location = CLLocation(
                coordinate: visit.coordinate,
                altitude: 0,
                horizontalAccuracy: visit.horizontalAccuracy,
                verticalAccuracy: -1,
                timestamp: isArrival ? visit.arrivalDate : visit.departureDate
            )

            let previousCoordinate = self.lastPersistedCoordinate
            self.ingestLocation(location, source: source)

            if let previous = previousCoordinate,
               LocationRecord.isUnchangedGPS(from: previous, to: location.coordinate, thresholdMeters: self.persistDistanceThreshold) {
                return
            }

            LocationStore.shared.logDiagnostic(
                title: isArrival ? "Visit: Arrived at Place" : "Visit: Departed Place",
                details: "Accuracy: \(String(format: "±%.1fm", location.horizontalAccuracy))",
                severity: .info
            )
        }
    }

    private func triggerRecordSync() {
        guard configuration.autoSyncEnabled else { return }
        let records = LocationStore.shared.records
        CloudKitSyncManager.shared.syncPendingRecords(config: configuration, records: records)
        if let health = HealthKitManager.shared.latestSnapshot {
            CloudKitSyncManager.shared.syncHealthRecord(config: configuration, snapshot: health)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        DispatchQueue.main.async {
            LocationStore.shared.logDiagnostic(
                title: "Exited Stationary Perimeter",
                details: "Geofence: \(region.identifier). Woke from background/closed state!",
                severity: .success
            )

            // Device moved! Re-trigger standard update or request high accuracy fix
            self.locationManager.requestLocation()

            if self.configuration.trackingMode != .batterySaver {
                self.locationManager.startUpdatingLocation()
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        DispatchQueue.main.async {
            LocationStore.shared.logDiagnostic(
                title: "Entered Monitored Region",
                details: "Region: \(region.identifier)",
                severity: .info
            )
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastErrorMessage = error.localizedDescription
            LocationStore.shared.logDiagnostic(
                title: "Location Error",
                details: error.localizedDescription,
                severity: .error
            )
        }
    }
}
