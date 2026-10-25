import Foundation
import CloudKit
import Combine

public final class ICloudSyncTransport: SyncTransportProtocol {
    public static let shared = ICloudSyncTransport()

    private let cloudKitManager: CloudKitSyncManager

    public var destination: SyncDestination { .cloudKit }

    public var isSyncing: Bool {
        cloudKitManager.isSyncing
    }

    public var lastSyncDate: Date? {
        cloudKitManager.lastSyncDate
    }

    public var statusDescription: String {
        cloudKitManager.accountStatusDescription
    }

    public init(cloudKitManager: CloudKitSyncManager = .shared) {
        self.cloudKitManager = cloudKitManager
    }

    public func syncLocation(
        records: [LocationRecord],
        latestRecord: LocationRecord?,
        config: TrackingConfiguration,
        completion: ((Result<Int, Error>) -> Void)?
    ) {
        cloudKitManager.syncPendingRecords(config: config, records: records)
        completion?(.success(records.count))
    }

    public func syncHealth(
        snapshot: HealthSnapshot,
        config: TrackingConfiguration,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        cloudKitManager.syncHealthRecord(config: config, snapshot: snapshot)
        completion?(.success(()))
    }

    public func syncPlaces(
        places: [Place],
        completion: ((Result<[Place], Error>) -> Void)?
    ) {
        // PlacesStore already handles local and iCloud container Documents/places.json mirroring
        completion?(.success(places))
    }

    public func testConnection(
        config: TrackingConfiguration,
        completion: @escaping (Bool, String) -> Void
    ) {
        cloudKitManager.sendTestPing(config: config, completion: completion)
    }
}
