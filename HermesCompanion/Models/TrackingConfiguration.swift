import Foundation

public enum TrackingMode: String, Codable, CaseIterable, Identifiable {
    case smartAlways = "Smart Always (Recommended)"
    case ultraContinuous = "Ultra Continuous GPS"
    case batterySaver = "Battery Saver (Significant Movements)"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .smartAlways:
            return "Continuous updates while traveling, significant changes & dynamic geofences when app is closed."
        case .ultraContinuous:
            return "Non-stop high accuracy GPS updates in background and active states. Highest battery consumption."
        case .batterySaver:
            return "Uses cell-tower significant changes & visits. Zero battery drain, wakes up app when moving."
        }
    }
}

public enum SyncDestination: String, Codable, CaseIterable, Identifiable {
    case cloudKit = "Apple iCloud / CloudKit (Zero Network)"

    public var id: String { rawValue }

    public var isCloudKitEnabled: Bool { true }

    public var subtitle: String {
        "Zero servers, zero open ports, zero TCP. Syncs securely via Apple iCloud across NAT and cellular networks directly to macOS Hermes."
    }
}

public struct TrackingConfiguration: Codable, Equatable {
    public var trackingMode: TrackingMode
    public var syncDestination: SyncDestination
    public var cloudKitContainerIdentifier: String
    public var deviceName: String
    public var autoSyncEnabled: Bool
    public var dynamicGeofenceEnabled: Bool
    public var geofenceRadiusMeters: Double
    public var distanceFilterMeters: Double
    public var backgroundIndicatorEnabled: Bool

    public static let defaultContainerIdentifier = "iCloud.com.hermes.HermesCompanion"

    /// Previous factory default. Indoor GPS drift crosses 10 m, so a stored 10 m filter is treated as "never customized" and raised on launch.
    public static let legacyDistanceFilterMeters: Double = 10
    /// Static persist threshold when CoreMotion has no fresh reading, and the normal threshold while walking, running, cycling, or driving.
    public static let defaultDistanceFilterMeters: Double = 30
    /// `saveRecord` never treats a sub-meter jitter as movement, even if the slider is 0.
    public static let distanceFilterFloorMeters: Double = 1
    public static let distanceFilterSliderMinMeters: Double = 0
    public static let distanceFilterSliderMaxMeters: Double = 50
    public static let distanceFilterSliderStepMeters: Double = 5
    /// A CoreMotion sample newer than this is fresh enough to confirm or veto a GPS write.
    public static let motionFreshnessSeconds: TimeInterval = 120
    /// While CoreMotion says stationary, only a displacement past this is unambiguous movement.
    public static let stationaryUnambiguousDisplacementMeters: Double = 150
    /// GPS speed above this overrides a fresh stationary reading, still subject to the normal distance filter.
    public static let stationarySpeedOverrideMps: Double = 1.0

    public static let `default` = TrackingConfiguration(
        trackingMode: .smartAlways,
        syncDestination: .cloudKit,
        cloudKitContainerIdentifier: defaultContainerIdentifier,
        deviceName: "iPhone Companion",
        autoSyncEnabled: true,
        dynamicGeofenceEnabled: true,
        geofenceRadiusMeters: 100.0,
        distanceFilterMeters: defaultDistanceFilterMeters,
        backgroundIndicatorEnabled: true
    )

    public init(
        trackingMode: TrackingMode = .smartAlways,
        syncDestination: SyncDestination = .cloudKit,
        cloudKitContainerIdentifier: String = defaultContainerIdentifier,
        deviceName: String = "iPhone Companion",
        autoSyncEnabled: Bool = true,
        dynamicGeofenceEnabled: Bool = true,
        geofenceRadiusMeters: Double = 100.0,
        distanceFilterMeters: Double = defaultDistanceFilterMeters,
        backgroundIndicatorEnabled: Bool = true
    ) {
        self.trackingMode = trackingMode
        self.syncDestination = syncDestination
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.deviceName = deviceName
        self.autoSyncEnabled = autoSyncEnabled
        self.dynamicGeofenceEnabled = dynamicGeofenceEnabled
        self.geofenceRadiusMeters = geofenceRadiusMeters
        self.distanceFilterMeters = distanceFilterMeters
        self.backgroundIndicatorEnabled = backgroundIndicatorEnabled
    }

    // Backwards-compatible decoder for existing stored configurations
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.trackingMode = try container.decodeIfPresent(TrackingMode.self, forKey: .trackingMode) ?? .smartAlways
        self.syncDestination = .cloudKit
        self.cloudKitContainerIdentifier = try container.decodeIfPresent(String.self, forKey: .cloudKitContainerIdentifier) ?? Self.defaultContainerIdentifier
        self.deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "iPhone Companion"
        self.autoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? true
        self.dynamicGeofenceEnabled = try container.decodeIfPresent(Bool.self, forKey: .dynamicGeofenceEnabled) ?? true
        self.geofenceRadiusMeters = try container.decodeIfPresent(Double.self, forKey: .geofenceRadiusMeters) ?? 100.0
        self.distanceFilterMeters = try container.decodeIfPresent(Double.self, forKey: .distanceFilterMeters) ?? Self.defaultDistanceFilterMeters
        self.backgroundIndicatorEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundIndicatorEnabled) ?? true
    }
}
