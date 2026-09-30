import Foundation
import CoreLocation
import CloudKit

public enum LocationTriggerSource: String, Codable, CaseIterable, Identifiable {
    case standardGPS = "Standard GPS"
    case significantChange = "Significant Change"
    case visitArrival = "Visit (Arrival)"
    case visitDeparture = "Visit (Departure)"
    case geofenceExit = "Geofence Exit"
    case geofenceEnter = "Geofence Enter"
    case wakeFromTerminated = "Launch (Woke App)"
    case manualPing = "Manual Ping"
    case backgroundFetch = "Background Task"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .standardGPS: return "location.fill"
        case .significantChange: return "antenna.radiowaves.left.and.right"
        case .visitArrival: return "arrow.down.right.and.arrow.up.left"
        case .visitDeparture: return "figure.walk.motion"
        case .geofenceExit: return "circle.dashed.rectangle"
        case .geofenceEnter: return "target"
        case .wakeFromTerminated: return "bolt.fill"
        case .manualPing: return "hand.tap.fill"
        case .backgroundFetch: return "arrow.triangle.2.circlepath"
        }
    }
}

public enum MotionActivity: String, Codable, CaseIterable, Identifiable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown

    public var id: String { rawValue }

    public var isMoving: Bool {
        switch self {
        case .walking, .running, .cycling, .automotive: return true
        case .stationary, .unknown: return false
        }
    }

    public var label: String {
        switch self {
        case .stationary: return "stationary"
        case .walking: return "walking"
        case .running: return "running"
        case .cycling: return "cycling"
        case .automotive: return "driving"
        case .unknown: return "unknown"
        }
    }

    public var systemIcon: String {
        switch self {
        case .stationary: return "figure.stand"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .automotive: return "car.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

public struct LocationRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let horizontalAccuracy: Double
    public let verticalAccuracy: Double
    public let speed: Double // in m/s, negative if invalid
    public let course: Double // in degrees 0-360, negative if invalid
    public let source: LocationTriggerSource
    public let batteryLevel: Float
    public let batteryState: String
    public let appState: String
    // Real motion state from CoreMotion (CMMotionActivity), independent of the GPS fix age.
    public let motionActivity: MotionActivity?
    public let motionTimestamp: Date?
    public let motionConfidence: String?
    public var synced: Bool

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Displacement below this is treated as an unchanged GPS position (matches the default distance filter).
    public static let unchangedPositionThresholdMeters: Double = 10.0

    /// Haversine displacement in meters between two WGS-84 coordinates.
    public static func displacementMeters(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    /// True when the two coordinates represent the same GPS position (below `thresholdMeters`).
    public static func isUnchangedGPS(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        thresholdMeters: Double = LocationRecord.unchangedPositionThresholdMeters
    ) -> Bool {
        displacementMeters(from: from, to: to) < thresholdMeters
    }

    /// True when this record's coordinates have not moved relative to `other`.
    public func isUnchangedPosition(
        from other: LocationRecord,
        thresholdMeters: Double = LocationRecord.unchangedPositionThresholdMeters
    ) -> Bool {
        Self.isUnchangedGPS(from: other.coordinate, to: coordinate, thresholdMeters: thresholdMeters)
    }

    public var speedKmH: Double {
        speed > 0 ? (speed * 3.6) : 0
    }

    public var formattedSpeed: String {
        if speed < 0 { return "0.0 km/h" }
        return String(format: "%.1f km/h", speedKmH)
    }

    public var formattedAccuracy: String {
        String(format: "±%.1fm", horizontalAccuracy)
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        horizontalAccuracy: Double = 0,
        verticalAccuracy: Double = 0,
        speed: Double = -1,
        course: Double = -1,
        source: LocationTriggerSource = .standardGPS,
        batteryLevel: Float = -1,
        batteryState: String = "unknown",
        appState: String = "active",
        motionActivity: MotionActivity? = nil,
        motionTimestamp: Date? = nil,
        motionConfidence: String? = nil,
        synced: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.source = source
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
        self.appState = appState
        self.motionActivity = motionActivity
        self.motionTimestamp = motionTimestamp
        self.motionConfidence = motionConfidence
        self.synced = synced
    }

    public init(
        location: CLLocation,
        source: LocationTriggerSource,
        appState: String,
        batteryLevel: Float,
        batteryState: String,
        motionActivity: MotionActivity? = nil,
        motionTimestamp: Date? = nil,
        motionConfidence: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = location.timestamp
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.speed = location.speed
        self.course = location.course
        self.source = source
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
        self.appState = appState
        self.motionActivity = motionActivity
        self.motionTimestamp = motionTimestamp
        self.motionConfidence = motionConfidence
        self.synced = false
    }

    // MARK: - CloudKit Serialization
    public func toCKRecord(recordType: String = "LocationRecord", customRecordID: CKRecord.ID? = nil, deviceName: String = "iPhone") -> CKRecord {
        let recordID = customRecordID ?? CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["latitude"] = latitude as NSNumber
        record["longitude"] = longitude as NSNumber
        record["altitude"] = altitude as NSNumber
        record["horizontalAccuracy"] = horizontalAccuracy as NSNumber
        record["verticalAccuracy"] = verticalAccuracy as NSNumber
        record["speed"] = speed as NSNumber
        record["course"] = course as NSNumber
        record["source"] = source.rawValue as NSString
        record["batteryLevel"] = Double(batteryLevel) as NSNumber
        record["batteryState"] = batteryState as NSString
        record["appState"] = appState as NSString
        record["timestamp"] = timestamp as NSDate
        record["deviceName"] = deviceName as NSString
        record["motionActivity"] = (motionActivity?.rawValue ?? MotionActivity.unknown.rawValue) as NSString
        if let motionConfidence = motionConfidence {
            record["motionConfidence"] = motionConfidence as NSString
        }
        if let motionTimestamp = motionTimestamp {
            record["motionTimestamp"] = motionTimestamp as NSDate
        }
        return record
    }

    public func toLatestCKRecord(deviceName: String = "iPhone") -> CKRecord {
        let recordID = CKRecord.ID(recordName: "latest_user_location")
        return toCKRecord(recordType: "LatestLocation", customRecordID: recordID, deviceName: deviceName)
    }

    public static func fromCKRecord(_ record: CKRecord) -> LocationRecord? {
        guard let latNum = record["latitude"] as? NSNumber,
              let lonNum = record["longitude"] as? NSNumber else {
            return nil
        }
        let latitude = latNum.doubleValue
        let longitude = lonNum.doubleValue
        let timestamp = (record["timestamp"] as? Date) ?? record.creationDate ?? Date()

        let id = UUID(uuidString: record.recordID.recordName) ?? UUID()
        let altitude = (record["altitude"] as? NSNumber)?.doubleValue ?? 0.0
        let horizontalAccuracy = (record["horizontalAccuracy"] as? NSNumber)?.doubleValue ?? 0.0
        let verticalAccuracy = (record["verticalAccuracy"] as? NSNumber)?.doubleValue ?? 0.0
        let speed = (record["speed"] as? NSNumber)?.doubleValue ?? -1.0
        let course = (record["course"] as? NSNumber)?.doubleValue ?? -1.0
        let sourceRaw = (record["source"] as? String) ?? LocationTriggerSource.standardGPS.rawValue
        let source = LocationTriggerSource(rawValue: sourceRaw) ?? .standardGPS
        let batteryLevel = Float((record["batteryLevel"] as? NSNumber)?.doubleValue ?? -1.0)
        let batteryState = (record["batteryState"] as? String) ?? "unknown"
        let appState = (record["appState"] as? String) ?? "unknown"
        let motionActivity = (record["motionActivity"] as? String).flatMap { MotionActivity(rawValue: $0) }
        let motionTimestamp = record["motionTimestamp"] as? Date
        let motionConfidence = record["motionConfidence"] as? String

        return LocationRecord(
            id: id,
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            speed: speed,
            course: course,
            source: source,
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            appState: appState,
            motionActivity: motionActivity,
            motionTimestamp: motionTimestamp,
            motionConfidence: motionConfidence,
            synced: true
        )
    }
}
