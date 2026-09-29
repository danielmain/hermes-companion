import Foundation
import CloudKit
import Combine
import UIKit

public final class CloudKitSyncManager: ObservableObject {
    public static let shared = CloudKitSyncManager()

    // MARK: - Published State
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastSyncStatus: String = "Idle"
    @Published public private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published public private(set) var accountStatusDescription: String = "Checking..."
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var syncedRecordCount: Int = 0

    private var activeContainerIdentifier: String = TrackingConfiguration.defaultContainerIdentifier
    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshAccountStatusSafely()

        // Re-check iCloud status whenever user returns from Settings
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.refreshAccountStatusSafely()
            }
            .store(in: &cancellables)

        // Re-check on system-level iCloud account sign-in/out
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.refreshAccountStatusSafely()
            }
            .store(in: &cancellables)
    }

    // MARK: - Safe Account Status Refresh
    public func refreshAccountStatusSafely() {
        if FileManager.default.ubiquityIdentityToken == nil {
            self.accountStatus = .noAccount
            self.accountStatusDescription = "No Apple ID Signed In"
            return
        }
        checkAccountStatus(containerIdentifier: activeContainerIdentifier)
    }

    // MARK: - Settings Navigation
    public func openSettingsForAccount() {
        if let accountURL = URL(string: "App-Prefs:root=APPLE_ACCOUNT"), UIApplication.shared.canOpenURL(accountURL) {
            UIApplication.shared.open(accountURL)
            return
        }
        if let castURL = URL(string: "App-prefs:root=CAST"), UIApplication.shared.canOpenURL(castURL) {
            UIApplication.shared.open(castURL)
            return
        }
        if let appSettingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(appSettingsURL)
        }
    }

    // MARK: - Container Resolution
    private func getContainer(identifier: String) -> CKContainer {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.lowercased() == "default" {
            return CKContainer.default()
        }
        return CKContainer(identifier: trimmed)
    }

    private func formatCloudKitError(_ error: Error, containerId: String) -> String {
        let desc = error.localizedDescription
        if desc.contains("Couldn't get container configuration") || (error as? CKError)?.code == .badContainer {
            return "Container '\(containerId)' is not registered on Apple's servers. In Xcode (Signing & Capabilities -> iCloud -> Containers), select your Developer Team and click '+' to link your container, or switch to HTTP Webhook Relay."
        }
        return desc
    }

    // MARK: - Account Status Verification
    public func checkAccountStatus(containerIdentifier: String, completion: ((CKAccountStatus) -> Void)? = nil) {
        self.activeContainerIdentifier = containerIdentifier

        if FileManager.default.ubiquityIdentityToken == nil {
            DispatchQueue.main.async {
                self.accountStatus = .noAccount
                self.accountStatusDescription = "No Apple ID Signed In"
                completion?(.noAccount)
            }
            return
        }

        let container = getContainer(identifier: containerIdentifier)

        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.accountStatus = status

                switch status {
                case .available:
                    self.accountStatusDescription = "iCloud Active (Private DB Ready)"
                    LocationStore.shared.logDiagnostic(
                        title: "CloudKit Account Verified",
                        details: "User signed into iCloud. Private database operational.",
                        severity: .success
                    )
                case .noAccount:
                    self.accountStatusDescription = "No iCloud Account Signed In"
                    LocationStore.shared.logDiagnostic(
                        title: "CloudKit Account Warning",
                        details: "No Apple ID signed into this iPhone. Sign in via iOS Settings to use CloudKit.",
                        severity: .warning
                    )
                case .restricted:
                    self.accountStatusDescription = "iCloud Restricted (MDM/ScreenTime)"
                    LocationStore.shared.logDiagnostic(
                        title: "CloudKit Restricted",
                        details: "iCloud access restricted by system policy.",
                        severity: .warning
                    )
                case .couldNotDetermine:
                    self.accountStatusDescription = "Could Not Determine Account"
                    if let error = error {
                        self.lastErrorMessage = error.localizedDescription
                        LocationStore.shared.logDiagnostic(
                            title: "CloudKit Account Check Error",
                            details: error.localizedDescription,
                            severity: .error
                        )
                    }
                case .temporarilyUnavailable:
                    self.accountStatusDescription = "iCloud Temporarily Unavailable"
                @unknown default:
                    self.accountStatusDescription = "Unknown Status"
                }

                completion?(status)
            }
        }
    }

    // MARK: - Sync Pending Records
    public func syncPendingRecords(config: TrackingConfiguration, records: [LocationRecord]) {
        guard config.autoSyncEnabled, config.syncDestination.isCloudKitEnabled else { return }

        let unsynced = records.filter { !$0.synced }
        guard !unsynced.isEmpty else { return }

        // Take up to 50 records per batch
        let batch = Array(unsynced.prefix(50))
        let deviceName = config.deviceName

        // Convert batch into CKRecords
        var recordsToSave: [CKRecord] = batch.map { $0.toCKRecord(deviceName: deviceName) }

        // Also update singleton latest location record if the batch has a fresh coordinate
        if let newest = batch.max(by: { $0.timestamp < $1.timestamp }) {
            recordsToSave.append(newest.toLatestCKRecord(deviceName: deviceName))
            self.mirrorLatestLocationToFile(record: newest, config: config)
        }

        let container = getContainer(identifier: config.cloudKitContainerIdentifier)
        let privateDatabase = container.privateCloudDatabase

        DispatchQueue.main.async {
            self.isSyncing = true
            self.lastSyncStatus = "Uploading \(batch.count) records to CloudKit..."
        }

        let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .utility

        operation.modifyRecordsResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSyncing = false
                self.lastSyncDate = Date()

                switch result {
                case .success:
                    self.lastSyncStatus = "Synced \(batch.count) locations to iCloud Private DB"
                    self.syncedRecordCount += batch.count
                    let ids = Set(batch.map { $0.id })
                    LocationStore.shared.markSynced(ids: ids)
                    LocationStore.shared.logDiagnostic(
                        title: "CloudKit Upload Succeeded",
                        details: "Successfully pushed \(batch.count) points + latest singleton to iCloud Private DB",
                        severity: .success
                    )

                case .failure(let error):
                    let formatted = self.formatCloudKitError(error, containerId: config.cloudKitContainerIdentifier)
                    self.lastErrorMessage = formatted
                    self.lastSyncStatus = "CloudKit Error: \(formatted)"
                    LocationStore.shared.logDiagnostic(
                        title: "CloudKit Upload Failed",
                        details: formatted,
                        severity: .error
                    )
                }
            }
        }

        privateDatabase.add(operation)
    }

    // MARK: - Test Ping to CloudKit
    public func sendTestPing(config: TrackingConfiguration, completion: @escaping (Bool, String) -> Void) {
        let container = getContainer(identifier: config.cloudKitContainerIdentifier)
        let privateDatabase = container.privateCloudDatabase

        let testID = CKRecord.ID(recordName: "test_ping_\(UUID().uuidString)")
        let testRecord = CKRecord(recordType: "DiagnosticPing", recordID: testID)
        testRecord["timestamp"] = Date() as NSDate
        testRecord["deviceName"] = config.deviceName as NSString
        testRecord["clientVersion"] = "1.0.0" as NSString

        privateDatabase.save(testRecord) { [weak self] savedRecord, error in
            if let error = error {
                let formatted = self?.formatCloudKitError(error, containerId: config.cloudKitContainerIdentifier) ?? error.localizedDescription
                DispatchQueue.main.async {
                    completion(false, "Save failed: \(formatted)")
                }
                return
            }

            // Immediately fetch back to verify read access
            guard let savedRecord = savedRecord else {
                DispatchQueue.main.async {
                    completion(false, "No record returned by CloudKit")
                }
                return
            }

            privateDatabase.fetch(withRecordID: savedRecord.recordID) { fetchedRecord, fetchError in
                DispatchQueue.main.async {
                    if let fetchError = fetchError {
                        completion(false, "Saved but fetch failed: \(fetchError.localizedDescription)")
                        return
                    }

                    // Clean up test record asynchronously
                    privateDatabase.delete(withRecordID: savedRecord.recordID) { _, _ in }

                    LocationStore.shared.logDiagnostic(
                        title: "CloudKit Ping Verified",
                        details: "Read & write verified on container \(config.cloudKitContainerIdentifier)",
                        severity: .success
                    )
                    completion(true, "CloudKit Private DB verified! (Read & Write confirmed)")
                }
            }
        }
    }

    // MARK: - iCloud Ubiquity Container File Mirroring
    private func mirrorLatestLocationToFile(record: LocationRecord, config: TrackingConfiguration) {
        DispatchQueue.global(qos: .utility).async {
            let containerId = config.cloudKitContainerIdentifier.trimmingCharacters(in: .whitespaces).isEmpty ? nil : config.cloudKitContainerIdentifier
            guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId) ?? FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                return
            }

            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)

            let fileURL = documentsURL.appendingPathComponent("latest_location.json")
            let payload: [String: Any] = [
                "id": record.id.uuidString,
                "timestamp": ISO8601DateFormatter().string(from: record.timestamp),
                "latitude": record.latitude,
                "longitude": record.longitude,
                "altitude": record.altitude,
                "horizontal_accuracy": record.horizontalAccuracy,
                "vertical_accuracy": record.verticalAccuracy,
                "speed_mps": record.speed,
                "course": record.course,
                "source": record.source.rawValue,
                "battery_level": record.batteryLevel,
                "battery_state": record.batteryState,
                "app_state": record.appState,
                "device_name": config.deviceName
            ]

            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
