import Foundation

public struct ConnectionTestReport: Equatable {
    public let isOnline: Bool
    public let latencyMs: Double?
    public let serverVersion: String?
    public let message: String

    public init(isOnline: Bool, latencyMs: Double? = nil, serverVersion: String? = nil, message: String) {
        self.isOnline = isOnline
        self.latencyMs = latencyMs
        self.serverVersion = serverVersion
        self.message = message
    }
}

public protocol SyncTransportProtocol: AnyObject {
    var destination: SyncDestination { get }
    var isSyncing: Bool { get }
    var lastSyncDate: Date? { get }
    var statusDescription: String { get }

    func syncLocation(
        records: [LocationRecord],
        latestRecord: LocationRecord?,
        config: TrackingConfiguration,
        completion: ((Result<Int, Error>) -> Void)?
    )

    func syncHealth(
        snapshot: HealthSnapshot,
        config: TrackingConfiguration,
        completion: ((Result<Void, Error>) -> Void)?
    )

    func syncPlaces(
        places: [Place],
        completion: ((Result<[Place], Error>) -> Void)?
    )

    func testConnection(
        config: TrackingConfiguration,
        completion: @escaping (Bool, String) -> Void
    )
}
