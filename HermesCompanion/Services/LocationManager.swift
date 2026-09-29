import Foundation
import CoreLocation
import UIKit
import Combine

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

        case .batterySaver:
            // In battery saver mode, we don't keep GPS radio open constantly;
            // we rely on Significant Location Changes + Visits + Geofencing
            locationManager.stopUpdatingLocation()
        }

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
            self.currentLocation = location

            // Determine trigger source
            var source: LocationTriggerSource = .standardGPS
            if self.wasLaunchedFromTerminated {
                source = .wakeFromTerminated
                self.wasLaunchedFromTerminated = false // reset flag after first consume
            } else if self.configuration.trackingMode == .batterySaver {
                source = .significantChange
            }

            let record = LocationRecord(
                location: location,
                source: source,
                appState: self.currentAppStateString,
                batteryLevel: self.currentBatteryLevel,
                batteryState: self.currentBatteryStateString
            )

            self.latestRecord = record
            LocationStore.shared.saveRecord(record)

            // Setup rolling geofence when stopped
            if location.speed < 1.0 { // Stationary or slow
                self.setupDynamicGeofence(around: location.coordinate)
            }

            // Sync with configured destinations (CloudKit / Webhook)
            self.triggerRecordSync()
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

            let record = LocationRecord(
                location: location,
                source: source,
                appState: self.currentAppStateString,
                batteryLevel: self.currentBatteryLevel,
                batteryState: self.currentBatteryStateString
            )

            self.latestRecord = record
            LocationStore.shared.saveRecord(record)
            LocationStore.shared.logDiagnostic(
                title: isArrival ? "Visit: Arrived at Place" : "Visit: Departed Place",
                details: "Accuracy: \(record.formattedAccuracy)",
                severity: .info
            )

            // Sync with configured destinations (CloudKit / Webhook)
            self.triggerRecordSync()
        }
    }

    private func triggerRecordSync() {
        guard configuration.autoSyncEnabled else { return }
        let records = LocationStore.shared.records
        if configuration.syncDestination.isWebhookEnabled {
            SyncManager.shared.syncPendingRecords(config: configuration, records: records)
        }
        if configuration.syncDestination.isCloudKitEnabled {
            CloudKitSyncManager.shared.syncPendingRecords(config: configuration, records: records)
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
