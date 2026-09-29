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
    case cloudKit = "CloudKit Private DB (Same Apple ID)"
    case httpWebhook = "HTTP Webhook Relay"
    case dual = "Dual Sync (CloudKit + Webhook)"

    public var id: String { rawValue }

    public var isCloudKitEnabled: Bool {
        self == .cloudKit || self == .dual
    }

    public var isWebhookEnabled: Bool {
        self == .httpWebhook || self == .dual
    }

    public var subtitle: String {
        switch self {
        case .cloudKit:
            return "Zero servers or open ports. Syncs securely via your Apple ID to macOS Hermes."
        case .httpWebhook:
            return "Transmits coordinates directly to an HTTP relay or Cloudflare tunnel endpoint."
        case .dual:
            return "Syncs to both CloudKit Private Database and HTTP Webhook simultaneously."
        }
    }
}

public struct TrackingConfiguration: Codable, Equatable {
    public var trackingMode: TrackingMode
    public var syncDestination: SyncDestination
    public var cloudKitContainerIdentifier: String
    public var serverURL: String
    public var apiKey: String
    public var deviceName: String
    public var autoSyncEnabled: Bool
    public var dynamicGeofenceEnabled: Bool
    public var geofenceRadiusMeters: Double
    public var distanceFilterMeters: Double
    public var backgroundIndicatorEnabled: Bool

    public static let defaultContainerIdentifier = "iCloud.com.hermes.HermesCompanion"

    public static let `default` = TrackingConfiguration(
        trackingMode: .smartAlways,
        syncDestination: .cloudKit,
        cloudKitContainerIdentifier: defaultContainerIdentifier,
        serverURL: "http://127.0.0.1:8080/api/location",
        apiKey: "",
        deviceName: "iPhone Companion",
        autoSyncEnabled: true,
        dynamicGeofenceEnabled: true,
        geofenceRadiusMeters: 100.0,
        distanceFilterMeters: 10.0,
        backgroundIndicatorEnabled: true
    )

    public init(
        trackingMode: TrackingMode = .smartAlways,
        syncDestination: SyncDestination = .cloudKit,
        cloudKitContainerIdentifier: String = defaultContainerIdentifier,
        serverURL: String = "http://127.0.0.1:8080/api/location",
        apiKey: String = "",
        deviceName: String = "iPhone Companion",
        autoSyncEnabled: Bool = true,
        dynamicGeofenceEnabled: Bool = true,
        geofenceRadiusMeters: Double = 100.0,
        distanceFilterMeters: Double = 10.0,
        backgroundIndicatorEnabled: Bool = true
    ) {
        self.trackingMode = trackingMode
        self.syncDestination = syncDestination
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.serverURL = serverURL
        self.apiKey = apiKey
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
        self.syncDestination = try container.decodeIfPresent(SyncDestination.self, forKey: .syncDestination) ?? .cloudKit
        self.cloudKitContainerIdentifier = try container.decodeIfPresent(String.self, forKey: .cloudKitContainerIdentifier) ?? Self.defaultContainerIdentifier
        self.serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? "http://127.0.0.1:8080/api/location"
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "iPhone Companion"
        self.autoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? true
        self.dynamicGeofenceEnabled = try container.decodeIfPresent(Bool.self, forKey: .dynamicGeofenceEnabled) ?? true
        self.geofenceRadiusMeters = try container.decodeIfPresent(Double.self, forKey: .geofenceRadiusMeters) ?? 100.0
        self.distanceFilterMeters = try container.decodeIfPresent(Double.self, forKey: .distanceFilterMeters) ?? 10.0
        self.backgroundIndicatorEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundIndicatorEnabled) ?? true
    }
}
