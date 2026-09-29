import Foundation
import UIKit

public final class SyncManager: ObservableObject {
    public static let shared = SyncManager()

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastSyncStatus: String = "Idle"
    @Published public private(set) var lastHttpCode: Int?

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    public func syncPendingRecords(config: TrackingConfiguration, records: [LocationRecord]) {
        guard config.autoSyncEnabled, !config.serverURL.isEmpty else { return }
        guard let url = URL(string: config.serverURL) else {
            LocationStore.shared.logDiagnostic(title: "Sync Failed", details: "Invalid server URL: \(config.serverURL)", severity: .error)
            return
        }

        let unsynced = records.filter { !$0.synced }
        guard !unsynced.isEmpty else { return }

        // Take up to 50 at a time
        let batch = Array(unsynced.prefix(50))
        let payload: [String: Any] = [
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "device_name": config.deviceName,
            "sent_at": ISO8601DateFormatter().string(from: Date()),
            "locations": batch.map { rec in
                [
                    "id": rec.id.uuidString,
                    "timestamp": ISO8601DateFormatter().string(from: rec.timestamp),
                    "latitude": rec.latitude,
                    "longitude": rec.longitude,
                    "altitude": rec.altitude,
                    "horizontal_accuracy": rec.horizontalAccuracy,
                    "speed_mps": rec.speed,
                    "course": rec.course,
                    "source": rec.source.rawValue,
                    "battery_level": rec.batteryLevel,
                    "battery_state": rec.batteryState,
                    "app_state": rec.appState
                ]
            }
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        DispatchQueue.main.async {
            self.isSyncing = true
            self.lastSyncStatus = "Uploading \(batch.count) locations..."
        }

        session.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    self?.lastSyncStatus = "Error: \(error.localizedDescription)"
                    LocationStore.shared.logDiagnostic(
                        title: "Webhook Sync Failed",
                        details: error.localizedDescription,
                        severity: .error
                    )
                    return
                }

                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? 0
                self?.lastHttpCode = statusCode
                self?.lastSyncDate = Date()

                if (200...299).contains(statusCode) {
                    self?.lastSyncStatus = "Synced \(batch.count) points (HTTP \(statusCode))"
                    let ids = Set(batch.map { $0.id })
                    LocationStore.shared.markSynced(ids: ids)
                    LocationStore.shared.logDiagnostic(
                        title: "Webhook Synced Successfully",
                        details: "Uploaded \(batch.count) points (HTTP \(statusCode))",
                        severity: .success
                    )
                } else {
                    self?.lastSyncStatus = "HTTP Error \(statusCode)"
                    LocationStore.shared.logDiagnostic(
                        title: "Webhook Server Error",
                        details: "HTTP \(statusCode)",
                        severity: .warning
                    )
                }
            }
        }.resume()
    }

    public func sendTestPing(config: TrackingConfiguration, completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: config.serverURL) else {
            completion(false, "Invalid URL format")
            return
        }

        let testPayload: [String: Any] = [
            "type": "ping",
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "device_name": config.deviceName,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "message": "Hermes Companion Always-Location Ping"
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: testPayload) else {
            completion(false, "Could not encode JSON")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        session.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200...299).contains(code) {
                    completion(true, "Success (HTTP \(code))")
                } else {
                    completion(false, "Server returned HTTP \(code)")
                }
            }
        }.resume()
    }
}
