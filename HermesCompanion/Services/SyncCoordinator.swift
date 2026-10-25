import Foundation
import Combine
import UIKit
import os

public final class SyncCoordinator: ObservableObject {
    public static let shared = SyncCoordinator()

    @Published public private(set) var activeDestination: SyncDestination = .cloudKit
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastSyncStatus: String = "Idle"
    @Published public private(set) var directLatencyMs: Double?
    @Published public private(set) var directOfflineQueueCount: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "dev.funktional.HermesCompanion", category: "SyncCoordinator")

    private init() {
        bindTransports()
    }

    private func bindTransports() {
        // Observe DirectHttpSyncTransport
        DirectHttpSyncTransport.shared.$isSyncing
            .combineLatest(DirectHttpSyncTransport.shared.$lastSyncDate, DirectHttpSyncTransport.shared.$lastSyncStatus)
            .sink { [weak self] syncing, date, status in
                guard let self = self, self.activeDestination == .direct else { return }
                self.isSyncing = syncing
                if let date = date { self.lastSyncDate = date }
                self.lastSyncStatus = status
            }
            .store(in: &cancellables)

        DirectHttpSyncTransport.shared.$lastLatencyMs
            .sink { [weak self] latency in
                self?.directLatencyMs = latency
            }
            .store(in: &cancellables)

        DirectHttpSyncTransport.shared.$offlineQueueCount
            .sink { [weak self] count in
                self?.directOfflineQueueCount = count
            }
            .store(in: &cancellables)

        // Observe CloudKitSyncManager
        CloudKitSyncManager.shared.$isSyncing
            .combineLatest(CloudKitSyncManager.shared.$lastSyncDate, CloudKitSyncManager.shared.$accountStatusDescription)
            .sink { [weak self] syncing, date, desc in
                guard let self = self, self.activeDestination == .cloudKit else { return }
                self.isSyncing = syncing
                if let date = date { self.lastSyncDate = date }
                self.lastSyncStatus = desc
            }
            .store(in: &cancellables)
    }

    public func updateActiveDestination(_ destination: SyncDestination) {
        if activeDestination != destination {
            activeDestination = destination
            logger.info("Sync provider switched to: \(destination.rawValue)")
            switch destination {
            case .cloudKit:
                lastSyncStatus = CloudKitSyncManager.shared.accountStatusDescription
                lastSyncDate = CloudKitSyncManager.shared.lastSyncDate
            case .direct:
                lastSyncStatus = DirectHttpSyncTransport.shared.lastSyncStatus
                lastSyncDate = DirectHttpSyncTransport.shared.lastSyncDate
            }
        }
    }

    // MARK: - Synchronize Pending Telemetry

    public func syncPendingRecords(
        config: TrackingConfiguration,
        records: [LocationRecord],
        latestRecord: LocationRecord? = nil
    ) {
        updateActiveDestination(config.syncDestination)

        switch config.syncDestination {
        case .cloudKit:
            ICloudSyncTransport.shared.syncLocation(
                records: records,
                latestRecord: latestRecord,
                config: config,
                completion: nil
            )
        case .direct:
            DirectHttpSyncTransport.shared.syncLocation(
                records: records,
                latestRecord: latestRecord,
                config: config,
                completion: nil
            )
        }
    }

    public func syncHealthRecord(
        config: TrackingConfiguration,
        snapshot: HealthSnapshot
    ) {
        updateActiveDestination(config.syncDestination)

        switch config.syncDestination {
        case .cloudKit:
            ICloudSyncTransport.shared.syncHealth(
                snapshot: snapshot,
                config: config,
                completion: nil
            )
        case .direct:
            DirectHttpSyncTransport.shared.syncHealth(
                snapshot: snapshot,
                config: config,
                completion: nil
            )
        }
    }

    // MARK: - Places Sync

    public func syncPlaces(places: [Place]) {
        let config = LocationManager.shared.configuration
        updateActiveDestination(config.syncDestination)

        switch config.syncDestination {
        case .cloudKit:
            ICloudSyncTransport.shared.syncPlaces(places: places, completion: nil)
        case .direct:
            DirectHttpSyncTransport.shared.syncPlaces(places: places, completion: nil)
        }
    }

    // MARK: - Handshake Connection Test

    public func testConnection(
        config: TrackingConfiguration,
        completion: @escaping (Bool, String) -> Void
    ) {
        updateActiveDestination(config.syncDestination)

        switch config.syncDestination {
        case .cloudKit:
            ICloudSyncTransport.shared.testConnection(config: config, completion: completion)
        case .direct:
            DirectHttpSyncTransport.shared.testConnection(config: config, completion: completion)
        }
    }

    // MARK: - Background Cycle Sync

    public func performBackgroundSync(config: TrackingConfiguration) {
        updateActiveDestination(config.syncDestination)

        let records = LocationStore.shared.records
        syncPendingRecords(config: config, records: records)

        if let health = HealthKitManager.shared.latestSnapshot {
            syncHealthRecord(config: config, snapshot: health)
        }

        if config.syncDestination == .direct {
            // Check for pending inbox replies in background
            DispatchStore.shared.pullDirectInboxUpdates()
        }
    }
}
