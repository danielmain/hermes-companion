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

/// Why a GPS fix was persisted, or why it was refused. `stationary_drift` is a refusal: that fix is not written.
public enum MovementReason: String, Codable, Equatable, CaseIterable {
    case moved
    case stationaryDrift = "stationary_drift"
    case distance
    case noMotionReading = "no_motion_reading"
}

/// Pure persist gate. CoreMotion confirms movement; the distance filter is the fallback when motion is missing or stale.
public struct GPSPersistDecision: Equatable {
    public enum Basis: String, Equatable {
        case movement
        case distance
    }

    public let shouldPersist: Bool
    public let reason: MovementReason
    public let basis: Basis
    public let thresholdMeters: Double
    public let displacementMeters: Double?
    public let motionActivity: MotionActivity
    public let motionAgeSeconds: TimeInterval?
    public let horizontalAccuracyMeters: Double

    public var auditLog: String {
        let displacement = displacementMeters.map { String(format: "%.1f", $0) } ?? "none"
        let age = motionAgeSeconds.map { String(format: "%.1f", $0) } ?? "none"
        let action = shouldPersist ? "write" : "skip"
        return String(
            format: "GPS persist %@: displacement_m=%@ threshold_m=%.1f motion=%@ motion_age_s=%@ accuracy_m=%.1f by=%@ reason=%@",
            action,
            displacement,
            thresholdMeters,
            motionActivity.rawValue,
            age,
            horizontalAccuracyMeters,
            basis.rawValue,
            reason.rawValue
        )
    }

    public static func evaluate(
        displacementMeters: Double?,
        horizontalAccuracyMeters: Double,
        speedMps: Double,
        motionActivity: MotionActivity,
        motionSampleReceivedAt: Date?,
        now: Date,
        distanceFilterMeters: Double
    ) -> GPSPersistDecision {
        let normalThreshold = max(distanceFilterMeters, TrackingConfiguration.distanceFilterFloorMeters)
        let stationaryThreshold = TrackingConfiguration.stationaryUnambiguousDisplacementMeters
        let motionAge = motionSampleReceivedAt.map { now.timeIntervalSince($0) }
        let motionIsFresh = motionAge.map { age in
            age >= 0 && age <= TrackingConfiguration.motionFreshnessSeconds
        } ?? false
        let speedConfirmsMovement = speedMps > TrackingConfiguration.stationarySpeedOverrideMps

        func decide(
            shouldPersist: Bool,
            reason: MovementReason,
            basis: Basis,
            thresholdMeters: Double
        ) -> GPSPersistDecision {
            GPSPersistDecision(
                shouldPersist: shouldPersist,
                reason: reason,
                basis: basis,
                thresholdMeters: thresholdMeters,
                displacementMeters: displacementMeters,
                motionActivity: motionActivity,
                motionAgeSeconds: motionAge,
                horizontalAccuracyMeters: horizontalAccuracyMeters
            )
        }

        guard let displacementMeters else {
            if motionIsFresh && motionActivity.isMoving {
                return decide(shouldPersist: true, reason: .moved, basis: .movement, thresholdMeters: normalThreshold)
            }
            return decide(shouldPersist: true, reason: .noMotionReading, basis: .distance, thresholdMeters: normalThreshold)
        }

        if motionIsFresh && motionActivity == .stationary {
            if displacementMeters > stationaryThreshold {
                return decide(shouldPersist: true, reason: .distance, basis: .distance, thresholdMeters: stationaryThreshold)
            }
            if speedConfirmsMovement && displacementMeters >= normalThreshold {
                return decide(shouldPersist: true, reason: .moved, basis: .movement, thresholdMeters: normalThreshold)
            }
            if speedConfirmsMovement {
                return decide(shouldPersist: false, reason: .distance, basis: .distance, thresholdMeters: normalThreshold)
            }
            return decide(shouldPersist: false, reason: .stationaryDrift, basis: .movement, thresholdMeters: stationaryThreshold)
        }

        if motionIsFresh && motionActivity.isMoving {
            let shouldPersist = displacementMeters >= normalThreshold
            return decide(
                shouldPersist: shouldPersist,
                reason: shouldPersist ? .moved : .distance,
                basis: shouldPersist ? .movement : .distance,
                thresholdMeters: normalThreshold
            )
        }

        let shouldPersist = displacementMeters >= normalThreshold
        return decide(
            shouldPersist: shouldPersist,
            reason: .noMotionReading,
            basis: .distance,
            thresholdMeters: normalThreshold
        )
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
    /// Why this coordinate was written. Nil on records saved before the field existed.
    public let movementReason: MovementReason?
    public var synced: Bool

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Displacement below this is treated as an unchanged GPS position when the caller does not pass a threshold.
    public static let unchangedPositionThresholdMeters: Double = TrackingConfiguration.defaultDistanceFilterMeters

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
        movementReason: MovementReason? = nil,
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
        self.movementReason = movementReason
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
        motionConfidence: String? = nil,
        movementReason: MovementReason? = nil
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
        self.movementReason = movementReason
        self.synced = false
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case latitude
        case longitude
        case altitude
        case horizontalAccuracy
        case verticalAccuracy
        case speed
        case course
        case source
        case batteryLevel
        case batteryState
        case appState
        case motionActivity
        case motionTimestamp
        case motionConfidence
        case movementReason
        case synced
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            timestamp: container.decode(Date.self, forKey: .timestamp),
            latitude: container.decode(Double.self, forKey: .latitude),
            longitude: container.decode(Double.self, forKey: .longitude),
            altitude: container.decodeIfPresent(Double.self, forKey: .altitude) ?? 0,
            horizontalAccuracy: container.decodeIfPresent(Double.self, forKey: .horizontalAccuracy) ?? 0,
            verticalAccuracy: container.decodeIfPresent(Double.self, forKey: .verticalAccuracy) ?? 0,
            speed: container.decodeIfPresent(Double.self, forKey: .speed) ?? -1,
            course: container.decodeIfPresent(Double.self, forKey: .course) ?? -1,
            source: container.decodeIfPresent(LocationTriggerSource.self, forKey: .source) ?? .standardGPS,
            batteryLevel: container.decodeIfPresent(Float.self, forKey: .batteryLevel) ?? -1,
            batteryState: container.decodeIfPresent(String.self, forKey: .batteryState) ?? "unknown",
            appState: container.decodeIfPresent(String.self, forKey: .appState) ?? "active",
            motionActivity: container.decodeIfPresent(MotionActivity.self, forKey: .motionActivity),
            motionTimestamp: container.decodeIfPresent(Date.self, forKey: .motionTimestamp),
            motionConfidence: container.decodeIfPresent(String.self, forKey: .motionConfidence),
            movementReason: container.decodeIfPresent(MovementReason.self, forKey: .movementReason),
            synced: container.decodeIfPresent(Bool.self, forKey: .synced) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(altitude, forKey: .altitude)
        try container.encode(horizontalAccuracy, forKey: .horizontalAccuracy)
        try container.encode(verticalAccuracy, forKey: .verticalAccuracy)
        try container.encode(speed, forKey: .speed)
        try container.encode(course, forKey: .course)
        try container.encode(source, forKey: .source)
        try container.encode(batteryLevel, forKey: .batteryLevel)
        try container.encode(batteryState, forKey: .batteryState)
        try container.encode(appState, forKey: .appState)
        try container.encodeIfPresent(motionActivity, forKey: .motionActivity)
        try container.encodeIfPresent(motionTimestamp, forKey: .motionTimestamp)
        try container.encodeIfPresent(motionConfidence, forKey: .motionConfidence)
        try container.encodeIfPresent(movementReason, forKey: .movementReason)
        try container.encode(synced, forKey: .synced)
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
        if let movementReason = movementReason {
            record["movementReason"] = movementReason.rawValue as NSString
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
        let movementReason = (record["movementReason"] as? String).flatMap { MovementReason(rawValue: $0) }

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
            movementReason: movementReason,
            synced: true
        )
    }
}
