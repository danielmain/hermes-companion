import Foundation
import UIKit
import Combine
import CoreLocation
import os

public enum DirectSyncError: LocalizedError, Equatable {
    case unconfigured(String)
    case unauthorized
    case invalidResponse(Int)
    case networkError(String)
    case encodingError

    public var errorDescription: String? {
        switch self {
        case .unconfigured(let reason):
            return "Direct Connection unconfigured: \(reason)"
        case .unauthorized:
            return "Unauthorized (401): Check Bearer Token in Settings."
        case .invalidResponse(let code):
            return "Host responded with HTTP \(code)."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .encodingError:
            return "Failed to serialize JSON payload."
        }
    }
}

public struct DirectInboxThread: Codable, Identifiable {
    public let id: String
    public let subject: String
    public let targetProfile: String?
    public let status: String
    public let createdAt: String?
    public let updatedAt: String?
    public let messageCount: Int?
    public let lastSnippet: String?
    public let messages: [DirectInboxMessage]?

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case targetProfile = "target_profile"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messageCount = "message_count"
        case lastSnippet = "last_snippet"
        case messages
    }
}

public struct DirectInboxMessage: Codable, Identifiable {
    public let id: String
    public let threadId: String?
    public let sender: String
    public let timestamp: String
    public let body: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case sender
        case timestamp
        case body
    }
}

public final class DirectHttpSyncTransport: ObservableObject, SyncTransportProtocol {
    public static let shared = DirectHttpSyncTransport()

    public var destination: SyncDestination { .direct }

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var lastSyncStatus: String = "Idle"
    @Published public private(set) var lastLatencyMs: Double?
    @Published public private(set) var serverVersion: String?
    @Published public private(set) var offlineQueueCount: Int = 0

    public var statusDescription: String {
        lastSyncStatus
    }

    private let session: URLSession
    private let logger = Logger(subsystem: "dev.funktional.HermesCompanion", category: "DirectHttpSync")
    private let queue = DispatchQueue(label: "com.hermes.directsync", qos: .utility)
    private let fileManager = FileManager.default

    private var queueDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DirectSyncQueue", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15.0
        sessionConfig.timeoutIntervalForResource = 30.0
        sessionConfig.waitsForConnectivity = false
        self.session = URLSession(configuration: sessionConfig)

        refreshQueueCount()
    }

    private func refreshQueueCount() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let files = (try? self.fileManager.contentsOfDirectory(at: self.queueDirectory, includingPropertiesForKeys: nil)) ?? []
            let count = files.filter { $0.pathExtension == "json" }.count
            DispatchQueue.main.async {
                self.offlineQueueCount = count
            }
        }
    }

    // MARK: - Request Builder

    private func buildRequest(
        endpoint: String,
        path: String,
        method: String,
        body: Data? = nil
    ) -> Result<URLRequest, DirectSyncError> {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty, let baseURL = URL(string: trimmedEndpoint) else {
            return .failure(.unconfigured("Endpoint URL is empty or invalid"))
        }

        guard let token = KeychainManager.shared.getToken(), !token.isEmpty else {
            return .failure(.unconfigured("Bearer Token is not set in Keychain"))
        }

        let fullURL = baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        var request = URLRequest(url: fullURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HermesCompanion-iOS/1.0.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return .success(request)
    }

    // MARK: - Connection Handshake Test

    public func testConnection(
        config: TrackingConfiguration,
        completion: @escaping (Bool, String) -> Void
    ) {
        let endpoint = config.directHostEndpoint
        let reqResult = buildRequest(endpoint: endpoint, path: "/api/v1/health", method: "GET")

        guard case .success(let request) = reqResult else {
            if case .failure(let err) = reqResult {
                completion(false, err.localizedDescription)
            }
            return
        }

        let start = Date()
        session.dataTask(with: request) { [weak self] data, response, error in
            let latency = Date().timeIntervalSince(start) * 1000.0

            if let error = error {
                let msg = "Connection failed: \(error.localizedDescription)"
                DispatchQueue.main.async {
                    self?.lastLatencyMs = nil
                    self?.lastSyncStatus = "Offline: \(error.localizedDescription)"
                    completion(false, msg)
                }
                LocationStore.shared.logDiagnostic(
                    title: "Direct Connection Test Failed",
                    details: msg,
                    severity: .error
                )
                return
            }

            guard let http = response as? HTTPURLResponse else {
                completion(false, "Invalid HTTP response from server")
                return
            }

            if http.statusCode == 401 {
                DispatchQueue.main.async {
                    self?.lastSyncStatus = "Unauthorized (Invalid Token)"
                    completion(false, "HTTP 401 Unauthorized: Invalid Bearer Token")
                }
                LocationStore.shared.logDiagnostic(
                    title: "Direct Connection Unauthorized",
                    details: "Bearer Token was rejected by the host.",
                    severity: .error
                )
                return
            }

            guard http.statusCode == 200, let data = data else {
                let msg = "Host responded with HTTP \(http.statusCode)"
                DispatchQueue.main.async {
                    self?.lastSyncStatus = msg
                    completion(false, msg)
                }
                return
            }

            var version = "1.0.0"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ver = json["version"] as? String {
                version = ver
            }

            DispatchQueue.main.async {
                self?.lastLatencyMs = latency
                self?.serverVersion = version
                self?.lastSyncStatus = "Online (Latency: \(Int(latency))ms)"
                LocationStore.shared.logDiagnostic(
                    title: "Direct Connection Verified",
                    details: "Host reachable at \(endpoint) in \(Int(latency))ms (version \(version)).",
                    severity: .success
                )
                completion(true, "Connected in \(Int(latency))ms • Host v\(version)")
            }
        }.resume()
    }

    // MARK: - Telemetry Synchronization

    public func syncLocation(
        records: [LocationRecord],
        latestRecord: LocationRecord?,
        config: TrackingConfiguration,
        completion: ((Result<Int, Error>) -> Void)?
    ) {
        guard config.autoSyncEnabled else {
            completion?(.success(0))
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }

            self.executeWithBackgroundTask(name: "DirectSyncLocation") {
                // Drain any pending items in offline queue first
                self.drainOfflineQueue(config: config)

                let unsynced = records.filter { !$0.synced }
                guard !unsynced.isEmpty || latestRecord != nil else {
                    completion?(.success(0))
                    return
                }

                DispatchQueue.main.async {
                    self.isSyncing = true
                    self.lastSyncStatus = "Pushing location to host..."
                }

                var successCount = 0
                let group = DispatchGroup()

                // 1. Send latest_location.json if we have a fresh fix
                if let newest = latestRecord ?? unsynced.max(by: { $0.timestamp < $1.timestamp }) {
                    group.enter()
                    let payload = newest.toDictionary(deviceName: config.deviceName)
                    self.uploadTelemetry(
                        filename: "latest_location.json",
                        payload: payload,
                        endpoint: config.directHostEndpoint
                    ) { success in
                        if success {
                            successCount += 1
                        }
                        group.leave()
                    }
                }

                // 2. Send rolling location_history.json
                if !records.isEmpty {
                    group.enter()
                    let recent = records.prefix(1000)
                    let recordsPayload = recent.map { $0.toDictionary(deviceName: config.deviceName) }
                    let historyPayload: [String: Any] = [
                        "updated_at": ISO8601DateFormatter().string(from: Date()),
                        "device_name": config.deviceName,
                        "count": recordsPayload.count,
                        "records": recordsPayload
                    ]
                    self.uploadTelemetry(
                        filename: "location_history.json",
                        payload: historyPayload,
                        endpoint: config.directHostEndpoint
                    ) { success in
                        if success {
                            successCount += unsynced.count
                            let ids = Set(unsynced.map { $0.id })
                            LocationStore.shared.markSynced(ids: ids)
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    self.isSyncing = false
                    self.lastSyncDate = Date()
                    self.lastSyncStatus = "Synced via Direct Connection"
                    self.refreshQueueCount()
                    completion?(.success(successCount))
                }
            }
        }
    }

    public func syncHealth(
        snapshot: HealthSnapshot,
        config: TrackingConfiguration,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        guard config.autoSyncEnabled else {
            completion?(.success(()))
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }

            self.executeWithBackgroundTask(name: "DirectSyncHealth") {
                let payload = snapshot.toDictionary()
                self.uploadTelemetry(
                    filename: "latest_health.json",
                    payload: payload,
                    endpoint: config.directHostEndpoint
                ) { success in
                    DispatchQueue.main.async {
                        if success {
                            LocationStore.shared.logDiagnostic(
                                title: "Direct Health Pushed",
                                details: "Pushed Apple Health snapshot directly to host",
                                severity: .success
                            )
                            completion?(.success(()))
                        } else {
                            completion?(.failure(DirectSyncError.networkError("Failed to upload health payload")))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Places Sync

    public func syncPlaces(
        places: [Place],
        completion: ((Result<[Place], Error>) -> Void)?
    ) {
        let config = LocationManager.shared.configuration
        guard config.syncDestination == .direct, !config.directHostEndpoint.isEmpty else {
            completion?(.success(places))
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }

            guard let jsonData = try? JSONEncoder().encode(places),
                  case .success(let request) = self.buildRequest(
                    endpoint: config.directHostEndpoint,
                    path: "/api/v1/places",
                    method: "PUT",
                    body: jsonData
                  ) else {
                completion?(.success(places))
                return
            }

            self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    self.logger.error("Direct places sync failed: \(error.localizedDescription)")
                    completion?(.failure(error))
                    return
                }

                // Also fetch remote places to merge
                self.fetchRemotePlaces(config: config) { remoteResult in
                    switch remoteResult {
                    case .success(let remotePlaces):
                        completion?(.success(remotePlaces))
                    case .failure:
                        completion?(.success(places))
                    }
                }
            }.resume()
        }
    }

    public func fetchRemotePlaces(
        config: TrackingConfiguration,
        completion: @escaping (Result<[Place], Error>) -> Void
    ) {
        guard case .success(let request) = buildRequest(
            endpoint: config.directHostEndpoint,
            path: "/api/v1/places",
            method: "GET"
        ) else {
            completion(.failure(DirectSyncError.unconfigured("Cannot build request")))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data,
                  let places = try? JSONDecoder().decode([Place].self, from: data) else {
                completion(.failure(DirectSyncError.invalidResponse(200)))
                return
            }

            completion(.success(places))
        }.resume()
    }

    // MARK: - Hermes Post / Inbox Messages

    public func sendInboxMessage(
        threadId: String?,
        subject: String?,
        body: String,
        targetProfile: String,
        messageId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let config = LocationManager.shared.configuration
        guard config.syncDestination == .direct, !config.directHostEndpoint.isEmpty else {
            completion(.failure(DirectSyncError.unconfigured("Direct host is not configured")))
            return
        }

        let payload: [String: Any] = [
            "thread_id": threadId ?? "",
            "subject": subject ?? "",
            "body": body,
            "target_profile": targetProfile,
            "message_id": messageId,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              case .success(let request) = buildRequest(
                endpoint: config.directHostEndpoint,
                path: "/api/v1/inbox/messages",
                method: "POST",
                body: jsonData
              ) else {
            completion(.failure(DirectSyncError.encodingError))
            return
        }

        executeWithBackgroundTask(name: "DirectSendInbox") {
            self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    LocationStore.shared.logDiagnostic(
                        title: "Post Message Send Failed",
                        details: error.localizedDescription,
                        severity: .error
                    )
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    completion(.failure(DirectSyncError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 500)))
                    return
                }

                LocationStore.shared.logDiagnostic(
                    title: "Post Letter Sent Direct",
                    details: "Letter \(messageId) delivered to Hermes host",
                    severity: .success
                )
                completion(.success(()))
            }.resume()
        }
    }

    public func fetchPendingInbox(
        completion: @escaping (Result<[DirectInboxThread], Error>) -> Void
    ) {
        let config = LocationManager.shared.configuration
        guard config.syncDestination == .direct, !config.directHostEndpoint.isEmpty else {
            completion(.success([]))
            return
        }

        guard case .success(let request) = buildRequest(
            endpoint: config.directHostEndpoint,
            path: "/api/v1/inbox/pending",
            method: "GET"
        ) else {
            completion(.failure(DirectSyncError.unconfigured("Cannot build request")))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.success([]))
                return
            }

            struct PendingResponse: Codable {
                let status: String
                let count: Int?
                let threads: [DirectInboxThread]
            }

            if let resp = try? JSONDecoder().decode(PendingResponse.self, from: data) {
                completion(.success(resp.threads))
            } else {
                completion(.success([]))
            }
        }.resume()
    }

    // MARK: - Low-Level Telemetry Upload with Offline Queue Fallback

    private func uploadTelemetry(
        filename: String,
        payload: Any,
        endpoint: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else {
            completion(false)
            return
        }

        let reqResult = buildRequest(
            endpoint: endpoint,
            path: "/api/v1/telemetry/\(filename)",
            method: "PUT",
            body: jsonData
        )

        guard case .success(let request) = reqResult else {
            // Cannot construct valid request (e.g. unconfigured or invalid URL); enqueue offline
            enqueueOfflinePayload(filename: filename, data: jsonData)
            completion(false)
            return
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.warning("Upload failed for \(filename): \(error.localizedDescription); caching offline")
                self.enqueueOfflinePayload(filename: filename, data: jsonData)
                DispatchQueue.main.async {
                    self.lastSyncStatus = "Host Offline (Queued)"
                }
                completion(false)
                return
            }

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                self.logger.error("Host returned HTTP status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                self.enqueueOfflinePayload(filename: filename, data: jsonData)
                completion(false)
                return
            }

            self.logger.info("Successfully uploaded \(filename) to host")
            completion(true)
        }.resume()
    }

    // MARK: - Offline Queue Management

    private func enqueueOfflinePayload(filename: String, data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let itemFilename = "\(Int(Date().timeIntervalSince1970 * 1000))_\(filename)"
            let itemURL = self.queueDirectory.appendingPathComponent(itemFilename)
            try? data.write(to: itemURL, options: .atomic)
            self.refreshQueueCount()
            LocationStore.shared.logDiagnostic(
                title: "Direct Sync Queued Offline",
                details: "Stored \(filename) locally; will retry when host reconnects.",
                severity: .warning
            )
        }
    }

    private func drainOfflineQueue(config: TrackingConfiguration) {
        guard !config.directHostEndpoint.isEmpty else { return }

        let files = (try? fileManager.contentsOfDirectory(at: queueDirectory, includingPropertiesForKeys: nil)) ?? []
        let sorted = files.filter { $0.pathExtension == "json" }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })

        for file in sorted {
            guard let data = try? Data(contentsOf: file) else {
                try? fileManager.removeItem(at: file)
                continue
            }

            let components = file.deletingPathExtension().lastPathComponent.split(separator: "_")
            guard components.count >= 2 else {
                try? fileManager.removeItem(at: file)
                continue
            }

            let filename = file.lastPathComponent.components(separatedBy: "_").dropFirst().joined(separator: "_")
            guard case .success(let request) = buildRequest(
                endpoint: config.directHostEndpoint,
                path: "/api/v1/telemetry/\(filename)",
                method: "PUT",
                body: data
            ) else {
                break
            }

            let semaphore = DispatchSemaphore(value: 0)
            var uploadSucceeded = false

            session.dataTask(with: request) { _, response, error in
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    uploadSucceeded = true
                }
                semaphore.signal()
            }.resume()

            _ = semaphore.wait(timeout: .now() + 5.0)

            if uploadSucceeded {
                try? fileManager.removeItem(at: file)
                logger.info("Drained offline queue item \(file.lastPathComponent)")
            } else {
                // Host still offline; stop draining for now
                break
            }
        }
    }

    // MARK: - Background Task Helper

    private func executeWithBackgroundTask<T>(name: String, block: () -> T) -> T {
        let taskId = UIApplication.shared.beginBackgroundTask(withName: name) {}
        defer {
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }
        return block()
    }
}
