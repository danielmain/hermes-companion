import Foundation
import Combine
import os
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Explicit Error Types

public enum DispatchError: LocalizedError, Equatable, Sendable {
    case directoryCreationFailed(String)
    case serializationFailed(String)
    case writeFailed(String)
    case threadNotFound(String)
    case messageNotFound(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let msg): return "Failed to create directory: \(msg)"
        case .serializationFailed(let msg): return "Serialization error: \(msg)"
        case .writeFailed(let msg): return "Disk write error: \(msg)"
        case .threadNotFound(let id): return "Thread not found: \(id)"
        case .messageNotFound(let id): return "Message not found: \(id)"
        case .readFailed(let msg): return "Read error: \(msg)"
        }
    }
}

// MARK: - Thread & Dispatch Store

public final class DispatchStore: ObservableObject {
    public static let shared = DispatchStore()

    @Published public private(set) var threads: [DispatchThread] = []
    @Published public private(set) var archivedThreads: [DispatchThread] = []
    @Published public private(set) var availableProfiles: [AgentProfile] = [AgentProfile.default]
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.hermes.dispatchstore", qos: .utility)
    private let logger = Logger(subsystem: "com.hermes.HermesCompanion", category: "DispatchStore")

    // MARK: - Performance Cache & Sync Marker Gating

    private struct CachedThreadRecord {
        let modificationDate: Date
        let thread: DispatchThread
    }

    private struct SyncMarkerSignature: Equatable {
        let localModDate: Date?
        let iCloudModDate: Date?
        let updatedAt: String?
    }

    private var threadFileCache: [String: CachedThreadRecord] = [:]
    private var messageCache: [String: [DispatchMessage]] = [:]
    private var lastSyncMarkerSignature: SyncMarkerSignature?
    private var hasCompletedInitialScan: Bool = false

    // MARK: - Directory Locations

    private var localThreadsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("threads", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var localArchiveDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("archive", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var localProfilesURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("profiles.json")
    }

    private var iCloudThreadsDirectory: URL? {
        let containerId = TrackingConfiguration.defaultContainerIdentifier
        let containerURL = fileManager.url(forUbiquityContainerIdentifier: containerId) ?? fileManager.url(forUbiquityContainerIdentifier: nil)
        guard let containerURL = containerURL else { return nil }
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        return documentsURL.appendingPathComponent("threads", isDirectory: true)
    }

    private var iCloudArchiveDirectory: URL? {
        let containerId = TrackingConfiguration.defaultContainerIdentifier
        let containerURL = fileManager.url(forUbiquityContainerIdentifier: containerId) ?? fileManager.url(forUbiquityContainerIdentifier: nil)
        guard let containerURL = containerURL else { return nil }
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        return documentsURL.appendingPathComponent("archive", isDirectory: true)
    }

    private var iCloudProfilesURL: URL? {
        let containerId = TrackingConfiguration.defaultContainerIdentifier
        let containerURL = fileManager.url(forUbiquityContainerIdentifier: containerId) ?? fileManager.url(forUbiquityContainerIdentifier: nil)
        guard let containerURL = containerURL else { return nil }
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        return documentsURL.appendingPathComponent("profiles.json")
    }

    private init() {
        loadProfiles()
        loadThreads()
        loadArchivedThreads()
    }

    // MARK: - Profile Management

    public func loadProfiles() {
        queue.async { [weak self] in
            guard let self = self else { return }
            var profiles: [AgentProfile] = []

            // 1. Try local cache
            if self.fileManager.fileExists(atPath: self.localProfilesURL.path),
               let data = try? Data(contentsOf: self.localProfilesURL),
               let config = try? DispatchFormatters.jsonDecoder.decode(ProfilesConfig.self, from: data) {
                profiles = config.profiles
            }

            // 2. Try iCloud Documents/profiles.json
            if let icloudURL = self.iCloudProfilesURL,
               self.fileManager.fileExists(atPath: icloudURL.path),
               let data = try? Data(contentsOf: icloudURL),
               let config = try? DispatchFormatters.jsonDecoder.decode(ProfilesConfig.self, from: data) {
                profiles = config.profiles
                try? data.write(to: self.localProfilesURL, options: .atomic)
            }

            let resolved = profiles.isEmpty ? [AgentProfile.default] : profiles
            DispatchQueue.main.async {
                self.availableProfiles = resolved
                self.logger.info("Loaded \(resolved.count) agent profiles: \(resolved.map { $0.id }.joined(separator: ", "))")
            }
        }
    }

    public func registerCustomProfile(id: String, name: String? = nil) {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanId.isEmpty else { return }
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "\(cleanId.capitalized) Agent"
        let newProfile = AgentProfile(id: cleanId, name: cleanName, lastActive: Date())

        queue.async { [weak self] in
            guard let self = self else { return }
            var current = self.availableProfiles.filter { $0.id != cleanId }
            current.insert(newProfile, at: 0)
            let config = ProfilesConfig(updatedAt: Date(), profiles: current)
            if let data = try? DispatchFormatters.jsonEncoder.encode(config) {
                try? data.write(to: self.localProfilesURL, options: .atomic)
                if let icloudURL = self.iCloudProfilesURL {
                    try? data.write(to: icloudURL, options: .atomic)
                }
            }
            DispatchQueue.main.async {
                self.availableProfiles = current
            }
        }
    }

    // MARK: - Functional Thread Retrieval & Loading

    private func currentSyncMarkerSignature() -> SyncMarkerSignature {
        var localModDate: Date?
        var iCloudModDate: Date?
        var updatedAt: String?

        let localMarker = localThreadsDirectory.appendingPathComponent(".sync_marker.json")
        if fileManager.fileExists(atPath: localMarker.path) {
            localModDate = (try? fileManager.attributesOfItem(atPath: localMarker.path)[.modificationDate]) as? Date
            if let data = try? Data(contentsOf: localMarker),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                updatedAt = obj["updated_at"] as? String
            }
        }

        if let iCloudDir = iCloudThreadsDirectory {
            let iCloudMarker = iCloudDir.appendingPathComponent(".sync_marker.json")
            if fileManager.fileExists(atPath: iCloudMarker.path) {
                iCloudModDate = (try? fileManager.attributesOfItem(atPath: iCloudMarker.path)[.modificationDate]) as? Date
                if let data = try? Data(contentsOf: iCloudMarker),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let icloudUpdated = obj["updated_at"] as? String {
                    if updatedAt == nil || icloudUpdated > (updatedAt ?? "") {
                        updatedAt = icloudUpdated
                    }
                }
            } else {
                let placeholderMarker = iCloudDir.appendingPathComponent("..sync_marker.json.icloud")
                if fileManager.fileExists(atPath: placeholderMarker.path) {
                    try? fileManager.startDownloadingUbiquitousItem(at: placeholderMarker)
                }
            }
        }

        return SyncMarkerSignature(localModDate: localModDate, iCloudModDate: iCloudModDate, updatedAt: updatedAt)
    }

    private func hasSyncMarkerChanged() -> Bool {
        guard hasCompletedInitialScan, lastSyncMarkerSignature != nil else {
            return true
        }
        let current = currentSyncMarkerSignature()
        return current != lastSyncMarkerSignature
    }

    public func loadThreads(force: Bool = false) {
        loadProfiles()
        queue.async { [weak self] in
            guard let self = self else { return }

            if !force && !self.hasSyncMarkerChanged() {
                self.logger.debug("Sync marker unchanged, skipping O(N) thread directory scan")
                return
            }

            let result = self.scanAllThreads()
            DispatchQueue.main.async {
                switch result {
                case .success(let loaded):
                    let sorted = loaded.sorted(by: { $0.updatedAt > $1.updatedAt })
                    if self.threads != sorted {
                        self.threads = sorted
                    }
                    self.lastSyncDate = Date()
                    self.logger.info("Loaded \(loaded.count) dispatch threads")
                case .failure(let error):
                    self.logger.error("Failed to load threads: \(error.localizedDescription)")
                }
            }
        }
    }

    public func loadArchivedThreads(force: Bool = false) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let result = self.scanArchivedThreads()
            DispatchQueue.main.async {
                switch result {
                case .success(let loaded):
                    let sorted = loaded.sorted(by: { $0.updatedAt > $1.updatedAt })
                    if self.archivedThreads != sorted {
                        self.archivedThreads = sorted
                    }
                    self.logger.info("Loaded \(loaded.count) archived dispatch threads")
                case .failure(let error):
                    self.logger.error("Failed to load archived threads: \(error.localizedDescription)")
                }
            }
        }
    }

    private func scanArchivedThreads() -> Result<[DispatchThread], DispatchError> {
        var threadMap: [String: DispatchThread] = [:]

        let localResults = scanDirectory(localArchiveDirectory)
        for thread in localResults {
            threadMap[thread.id] = thread
        }

        if let iCloudDir = iCloudArchiveDirectory, fileManager.fileExists(atPath: iCloudDir.path) {
            let iCloudResults = scanDirectory(iCloudDir)
            for thread in iCloudResults {
                if let existing = threadMap[thread.id] {
                    if thread.updatedAt > existing.updatedAt {
                        threadMap[thread.id] = thread
                    }
                } else {
                    threadMap[thread.id] = thread
                }
            }
        }

        return .success(Array(threadMap.values))
    }

    private func moveDirectory(from srcURL: URL, to dstURL: URL, isCoordinated: Bool) {
        guard fileManager.fileExists(atPath: srcURL.path) else { return }
        let parentDst = dstURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: parentDst, withIntermediateDirectories: true)

        if isCoordinated {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var error: NSError?
            coordinator.coordinate(writingItemAt: srcURL, options: .forMoving, writingItemAt: dstURL, options: .forReplacing, error: &error) { src, dst in
                do {
                    if self.fileManager.fileExists(atPath: dst.path) {
                        try self.fileManager.removeItem(at: dst)
                    }
                    try self.fileManager.moveItem(at: src, to: dst)
                } catch {
                    self.logger.error("Failed to move coordinated directory from \(src.path) to \(dst.path): \(error.localizedDescription)")
                }
            }
        } else {
            do {
                if fileManager.fileExists(atPath: dstURL.path) {
                    try fileManager.removeItem(at: dstURL)
                }
                try fileManager.moveItem(at: srcURL, to: dstURL)
            } catch {
                logger.error("Failed to move local directory from \(srcURL.path) to \(dstURL.path): \(error.localizedDescription)")
            }
        }
    }

    private func removeDirectory(at url: URL, isCoordinated: Bool) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        if isCoordinated {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var error: NSError?
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &error) { deleteURL in
                do {
                    if self.fileManager.fileExists(atPath: deleteURL.path) {
                        try self.fileManager.removeItem(at: deleteURL)
                    }
                } catch {
                    self.logger.error("Failed to delete coordinated directory at \(deleteURL.path): \(error.localizedDescription)")
                }
            }
            if let err = error {
                logger.error("Coordinator delete error for \(url.path): \(err.localizedDescription)")
            }
        } else {
            do {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            } catch {
                logger.error("Failed to delete local directory at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    private func scanAllThreads() -> Result<[DispatchThread], DispatchError> {
        var threadMap: [String: DispatchThread] = [:]

        // 1. Scan local Application Support directory
        let localResults = scanDirectory(localThreadsDirectory)
        for thread in localResults {
            if thread.status == .archived {
                // Auto-migrate legacy archived thread out of active threads directory
                let src = localThreadsDirectory.appendingPathComponent(thread.id, isDirectory: true)
                let dst = localArchiveDirectory.appendingPathComponent(thread.id, isDirectory: true)
                moveDirectory(from: src, to: dst, isCoordinated: false)
                threadFileCache.removeValue(forKey: src.appendingPathComponent("meta.json").path)
            } else {
                threadMap[thread.id] = thread
            }
        }

        // 2. Scan iCloud Ubiquity container Documents/threads
        if let iCloudDir = iCloudThreadsDirectory, fileManager.fileExists(atPath: iCloudDir.path) {
            let iCloudResults = scanDirectory(iCloudDir)
            for thread in iCloudResults {
                if thread.status == .archived {
                    // Auto-migrate legacy archived thread out of active threads directory
                    if let iCloudArchive = iCloudArchiveDirectory {
                        let src = iCloudDir.appendingPathComponent(thread.id, isDirectory: true)
                        let dst = iCloudArchive.appendingPathComponent(thread.id, isDirectory: true)
                        moveDirectory(from: src, to: dst, isCoordinated: true)
                        threadFileCache.removeValue(forKey: src.appendingPathComponent("meta.json").path)
                    }
                } else {
                    // If local exists, keep the one with newer updatedAt
                    if let existing = threadMap[thread.id] {
                        if thread.updatedAt > existing.updatedAt {
                            threadMap[thread.id] = thread
                        }
                    } else {
                        threadMap[thread.id] = thread
                    }
                }
            }
        }

        self.hasCompletedInitialScan = true
        let currentSig = self.currentSyncMarkerSignature()
        self.lastSyncMarkerSignature = currentSig
        if currentSig.localModDate == nil && currentSig.iCloudModDate == nil {
            self.touchSyncMarker(threadId: "system")
        }

        return .success(Array(threadMap.values))
    }

    private func scanDirectory(_ dir: URL) -> [DispatchThread] {
        guard let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var results: [DispatchThread] = []
        for folderURL in entries {
            let metaURL = folderURL.appendingPathComponent("meta.json")
            if fileManager.isUbiquitousItem(at: metaURL) {
                try? fileManager.startDownloadingUbiquitousItem(at: metaURL)
            }
            let icloudMetaURL = folderURL.appendingPathComponent(".meta.json.icloud")
            let hasPlaceholder = fileManager.fileExists(atPath: icloudMetaURL.path)
            if hasPlaceholder {
                try? fileManager.startDownloadingUbiquitousItem(at: icloudMetaURL)
            }

            guard fileManager.fileExists(atPath: metaURL.path) else {
                if hasPlaceholder, let cached = threadFileCache[metaURL.path] {
                    // Graceful cache fallback: retain thread during CloudDocs background download
                    results.append(cached.thread)
                } else if hasPlaceholder, let fallback = (self.threads.first(where: { $0.id == folderURL.lastPathComponent }) ?? self.archivedThreads.first(where: { $0.id == folderURL.lastPathComponent })) {
                    // Retain from existing published threads if not yet present in file cache
                    threadFileCache[metaURL.path] = CachedThreadRecord(modificationDate: Date.distantPast, thread: fallback)
                    results.append(fallback)
                } else {
                    threadFileCache.removeValue(forKey: metaURL.path)
                }
                continue
            }

            let fileModDate = (try? fileManager.attributesOfItem(atPath: metaURL.path)[.modificationDate]) as? Date ?? Date.distantPast
            if let cached = threadFileCache[metaURL.path], cached.modificationDate == fileModDate {
                results.append(cached.thread)
                continue
            }

            guard let data = try? Data(contentsOf: metaURL),
                  let thread = try? DispatchFormatters.jsonDecoder.decode(DispatchThread.self, from: data) else {
                if let cached = threadFileCache[metaURL.path] {
                    // Graceful fallback if read/decode temporarily fails during ubiquitous sync
                    results.append(cached.thread)
                } else if let fallback = (self.threads.first(where: { $0.id == folderURL.lastPathComponent }) ?? self.archivedThreads.first(where: { $0.id == folderURL.lastPathComponent })) {
                    results.append(fallback)
                }
                continue
            }

            threadFileCache[metaURL.path] = CachedThreadRecord(modificationDate: fileModDate, thread: thread)
            results.append(thread)
        }
        return results
    }

    // MARK: - Thread Creation

    public func createThread(subject: String, initialBody: String, targetProfile: String = "default") -> Result<DispatchThread, DispatchError> {
        executeWithBackgroundTask {
            let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanBody = initialBody.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanProfile = targetProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default" : targetProfile.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanSubject.isEmpty else {
                return .failure(.writeFailed("Subject cannot be empty"))
            }
            guard !cleanBody.isEmpty else {
                return .failure(.writeFailed("Initial message cannot be empty"))
            }

            let threadId = ThreadId.generate().rawValue
            let now = Date()
            let snippet = String(cleanBody.prefix(120))

            let newThread = DispatchThread(
                id: threadId,
                subject: cleanSubject,
                targetProfile: cleanProfile,
                status: .pendingAgent,
                createdAt: now,
                updatedAt: now,
                messageCount: 1,
                lastSnippet: snippet
            )

            let initialMessage = DispatchMessage(
                id: MessageId.generate().rawValue,
                threadId: threadId,
                sender: .user,
                timestamp: now,
                body: cleanBody
            )

            let writeResult = writeThreadAndMessage(thread: newThread, message: initialMessage, sequenceIndex: 1)
            switch writeResult {
            case .success:
                touchSyncMarker(threadId: threadId)
                let updated = (self.threads.filter { $0.id != threadId } + [newThread]).sorted(by: { $0.updatedAt > $1.updatedAt })
                self.threads = updated
                self.logger.info("Created dispatch thread '\(cleanSubject)' (\(threadId))")
                return .success(newThread)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    // MARK: - Sending a Reply

    public func replyToThread(threadId: String, body: String, sender: DispatchSender) -> Result<DispatchMessage, DispatchError> {
        executeWithBackgroundTask {
            let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanBody.isEmpty else {
                return .failure(.writeFailed("Message body cannot be empty"))
            }

            guard let existing = threads.first(where: { $0.id == threadId }) else {
                return .failure(.threadNotFound(threadId))
            }

            let now = Date()
            let nextIndex = existing.messageCount + 1
            let newStatus: DispatchStatus = (sender == .user) ? .pendingAgent : .replied

            let message = DispatchMessage(
                id: MessageId.generate().rawValue,
                threadId: threadId,
                sender: sender,
                timestamp: now,
                body: cleanBody
            )

            let updatedThread = existing.with(
                status: newStatus,
                updatedAt: now,
                messageCount: nextIndex,
                lastSnippet: String(cleanBody.prefix(120)),
                clearError: sender == .user
            )

            let writeResult = writeThreadAndMessage(thread: updatedThread, message: message, sequenceIndex: nextIndex)
            switch writeResult {
            case .success:
                touchSyncMarker(threadId: threadId)
                let updatedList = (self.threads.filter { $0.id != threadId } + [updatedThread]).sorted(by: { $0.updatedAt > $1.updatedAt })
                self.threads = updatedList
                self.logger.info("Appended message \(message.id) to thread \(threadId) by \(sender.rawValue)")
                return .success(message)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    // MARK: - Retry Failed Thread

    public func retryThread(id: String) -> Result<Void, DispatchError> {
        executeWithBackgroundTask {
            guard let existing = threads.first(where: { $0.id == id }) else {
                return .failure(.threadNotFound(id))
            }

            let now = Date()
            let updated = existing.with(status: .pendingAgent, updatedAt: now, clearError: true)
            let writeResult = writeMetadata(updated)
            switch writeResult {
            case .success:
                touchSyncMarker(threadId: id)
                let updatedList = (self.threads.filter { $0.id != id } + [updated]).sorted(by: { $0.updatedAt > $1.updatedAt })
                self.threads = updatedList
                self.logger.info("Retried dispatch thread: \(id)")
                return .success(())
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    // MARK: - Background Task Helper

    private func executeWithBackgroundTask<T>(_ block: () -> T) -> T {
        #if canImport(UIKit)
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "DispatchStoreOperation") {
            // Expiration handler
        }
        defer {
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }
        #endif
        return block()
    }

    // MARK: - Container Upload

    /// Hold a background task while CloudDocs confirms the container file was uploaded.
    ///
    /// A write into the ubiquity container returns as soon as the local file exists; pushing
    /// it to iCloud is bird's job, and iOS is free to suspend the app first. That is where the
    /// minutes went: a letter written at 10:38 reached the Mac at 10:46. Polling
    /// `ubiquitousItemIsUploaded` while a background task is held gives the upload its window.
    /// The wait runs off the main thread, so the UI never blocks.
    private func keepUploading(_ url: URL, timeout: TimeInterval = 25) {
        #if canImport(UIKit)
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "DispatchStoreUpload") {}
        DispatchQueue.global(qos: .utility).async { [logger = self.logger] in
            defer {
                if taskId != .invalid {
                    UIApplication.shared.endBackgroundTask(taskId)
                }
            }
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let values = try? url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey])
                if values?.ubiquitousItemIsUploaded == true {
                    logger.info("Container upload confirmed for \(url.lastPathComponent)")
                    return
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
            logger.error("Container upload for \(url.lastPathComponent) still pending after \(Int(timeout))s; iOS will retry it in the background")
        }
        #else
        _ = url
        #endif
    }

    // MARK: - Loading Messages

    public func loadMessages(for threadId: String) -> Result<[DispatchMessage], DispatchError> {
        let sorted = readMessagesFromDisk(threadId: threadId)
        return .success(sorted)
    }

    public func loadMessagesAsync(for threadId: String, completion: @escaping (Result<[DispatchMessage], DispatchError>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let sorted = self.readMessagesFromDisk(threadId: threadId)
            DispatchQueue.main.async {
                completion(.success(sorted))
            }
        }
    }

    private func readMessagesFromDisk(threadId: String) -> [DispatchMessage] {
        var messages: [DispatchMessage] = []
        let candidateDirs = [
            localThreadsDirectory.appendingPathComponent(threadId, isDirectory: true).appendingPathComponent("messages", isDirectory: true),
            localArchiveDirectory.appendingPathComponent(threadId, isDirectory: true).appendingPathComponent("messages", isDirectory: true),
            iCloudThreadsDirectory?.appendingPathComponent(threadId, isDirectory: true).appendingPathComponent("messages", isDirectory: true),
            iCloudArchiveDirectory?.appendingPathComponent(threadId, isDirectory: true).appendingPathComponent("messages", isDirectory: true)
        ].compactMap { $0 }

        var seenIds = Set<String>()
        var foundPlaceholders = false

        for msgDir in candidateDirs {
            guard fileManager.fileExists(atPath: msgDir.path),
                  let files = try? fileManager.contentsOfDirectory(at: msgDir, includingPropertiesForKeys: nil, options: []) else {
                continue
            }

            for file in files {
                let filename = file.lastPathComponent
                if filename.hasPrefix(".") && filename.hasSuffix(".icloud") {
                    try? fileManager.startDownloadingUbiquitousItem(at: file)
                    foundPlaceholders = true
                    continue
                }

                if file.pathExtension == "json" {
                    if fileManager.isUbiquitousItem(at: file) {
                        try? fileManager.startDownloadingUbiquitousItem(at: file)
                    }
                    guard let data = try? Data(contentsOf: file),
                          let msg = try? DispatchFormatters.jsonDecoder.decode(DispatchMessage.self, from: data) else {
                        foundPlaceholders = true
                        continue
                    }
                    if !seenIds.contains(msg.id) {
                        seenIds.insert(msg.id)
                        messages.append(msg)
                    }
                }
            }
        }

        // Graceful cache fallback: if placeholders are actively syncing and we have cached messages, retain any missing messages
        if let cachedList = messageCache[threadId] {
            for cachedMsg in cachedList {
                if !seenIds.contains(cachedMsg.id) && foundPlaceholders {
                    seenIds.insert(cachedMsg.id)
                    messages.append(cachedMsg)
                }
            }
        }

        let sorted = messages.sorted(by: { $0.timestamp < $1.timestamp })
        if !sorted.isEmpty {
            messageCache[threadId] = sorted
        }
        return sorted
    }

    // MARK: - Archive & Unarchive Threads

    public func archiveThread(id: String) {
        executeWithBackgroundTask {
            guard let existing = (self.threads.first(where: { $0.id == id }) ?? self.archivedThreads.first(where: { $0.id == id })) else { return }
            let updated = existing.with(status: .archived, updatedAt: Date())

            // 1. Move folder from threads/{id} to archive/{id}
            let localSrc = self.localThreadsDirectory.appendingPathComponent(id, isDirectory: true)
            let localDst = self.localArchiveDirectory.appendingPathComponent(id, isDirectory: true)
            self.moveDirectory(from: localSrc, to: localDst, isCoordinated: false)

            if let iCloudThreads = self.iCloudThreadsDirectory, let iCloudArchive = self.iCloudArchiveDirectory {
                let iCloudSrc = iCloudThreads.appendingPathComponent(id, isDirectory: true)
                let iCloudDst = iCloudArchive.appendingPathComponent(id, isDirectory: true)
                self.moveDirectory(from: iCloudSrc, to: iCloudDst, isCoordinated: true)
            }

            // Invalidate cache for old paths
            self.threadFileCache.removeValue(forKey: localSrc.appendingPathComponent("meta.json").path)
            if let iCloudThreads = self.iCloudThreadsDirectory {
                self.threadFileCache.removeValue(forKey: iCloudThreads.appendingPathComponent(id, isDirectory: true).appendingPathComponent("meta.json").path)
            }

            // 2. Write updated metadata into archive destination
            _ = self.writeMetadata(updated)
            self.touchSyncMarker(threadId: id)

            // 3. Update in-memory lists
            self.threads = self.threads.filter { $0.id != id }
            self.archivedThreads = (self.archivedThreads.filter { $0.id != id } + [updated]).sorted(by: { $0.updatedAt > $1.updatedAt })
            self.logger.info("Archived dispatch thread: \(id)")
        }
    }

    public func unarchiveThread(id: String) {
        executeWithBackgroundTask {
            guard let existing = (self.archivedThreads.first(where: { $0.id == id }) ?? self.threads.first(where: { $0.id == id })) else { return }
            let updated = existing.with(status: .replied, updatedAt: Date())

            // 1. Move folder from archive/{id} to threads/{id}
            let localSrc = self.localArchiveDirectory.appendingPathComponent(id, isDirectory: true)
            let localDst = self.localThreadsDirectory.appendingPathComponent(id, isDirectory: true)
            self.moveDirectory(from: localSrc, to: localDst, isCoordinated: false)

            if let iCloudArchive = self.iCloudArchiveDirectory, let iCloudThreads = self.iCloudThreadsDirectory {
                let iCloudSrc = iCloudArchive.appendingPathComponent(id, isDirectory: true)
                let iCloudDst = iCloudThreads.appendingPathComponent(id, isDirectory: true)
                self.moveDirectory(from: iCloudSrc, to: iCloudDst, isCoordinated: true)
            }

            // Invalidate cache for old paths
            self.threadFileCache.removeValue(forKey: localSrc.appendingPathComponent("meta.json").path)
            if let iCloudArchive = self.iCloudArchiveDirectory {
                self.threadFileCache.removeValue(forKey: iCloudArchive.appendingPathComponent(id, isDirectory: true).appendingPathComponent("meta.json").path)
            }

            // 2. Write updated metadata into threads destination
            _ = self.writeMetadata(updated)
            self.touchSyncMarker(threadId: id)

            // 3. Update in-memory lists
            self.archivedThreads = self.archivedThreads.filter { $0.id != id }
            self.threads = (self.threads.filter { $0.id != id } + [updated]).sorted(by: { $0.updatedAt > $1.updatedAt })
            self.logger.info("Unarchived dispatch thread: \(id)")
        }
    }

    // MARK: - Delete Thread

    public func deleteThread(id: String) {
        executeWithBackgroundTask {
            // 1. Remove folder from local threads and archive
            let localThread = self.localThreadsDirectory.appendingPathComponent(id, isDirectory: true)
            let localArchive = self.localArchiveDirectory.appendingPathComponent(id, isDirectory: true)
            self.removeDirectory(at: localThread, isCoordinated: false)
            self.removeDirectory(at: localArchive, isCoordinated: false)

            // 2. Remove folder from iCloud threads and archive using NSFileCoordinator
            if let iCloudThreads = self.iCloudThreadsDirectory {
                let iCloudThread = iCloudThreads.appendingPathComponent(id, isDirectory: true)
                self.removeDirectory(at: iCloudThread, isCoordinated: true)
            }
            if let iCloudArchive = self.iCloudArchiveDirectory {
                let iCloudArch = iCloudArchive.appendingPathComponent(id, isDirectory: true)
                self.removeDirectory(at: iCloudArch, isCoordinated: true)
            }

            // Invalidate cache for paths
            self.threadFileCache.removeValue(forKey: localThread.appendingPathComponent("meta.json").path)
            self.threadFileCache.removeValue(forKey: localArchive.appendingPathComponent("meta.json").path)
            if let iCloudThreads = self.iCloudThreadsDirectory {
                self.threadFileCache.removeValue(forKey: iCloudThreads.appendingPathComponent(id, isDirectory: true).appendingPathComponent("meta.json").path)
            }
            if let iCloudArchive = self.iCloudArchiveDirectory {
                self.threadFileCache.removeValue(forKey: iCloudArchive.appendingPathComponent(id, isDirectory: true).appendingPathComponent("meta.json").path)
            }
            self.messageCache.removeValue(forKey: id)

            // 3. Touch sync marker
            self.touchSyncMarker(threadId: id)

            // 4. Update in-memory lists
            let updateUI = {
                self.threads = self.threads.filter { $0.id != id }
                self.archivedThreads = self.archivedThreads.filter { $0.id != id }
            }
            if Thread.isMainThread {
                updateUI()
            } else {
                DispatchQueue.main.async(execute: updateUI)
            }
            self.logger.info("Deleted dispatch thread: \(id)")
        }
    }

    // MARK: - Low-Level Immutable Disk Writers

    private func coordinatedWrite(data: Data, to url: URL) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                logger.error("Coordinated write failed: \(error.localizedDescription)")
            }
        }
        if let err = coordError {
            logger.error("Coordinator error: \(err.localizedDescription)")
        }
    }

    private func writeThreadAndMessage(thread: DispatchThread, message: DispatchMessage, sequenceIndex: Int) -> Result<Void, DispatchError> {
        // 1. Write metadata
        let metaResult = writeMetadata(thread)
        if case .failure(let err) = metaResult {
            return .failure(err)
        }

        // 2. Write message file
        let datePart = DispatchFormatters.iso8601Zulu.string(from: message.timestamp)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let filename = String(format: "%03d_%@_%@_%@.json", sequenceIndex, message.sender.rawValue, datePart, message.id)

        guard let msgData = try? DispatchFormatters.jsonEncoder.encode(message) else {
            return .failure(.serializationFailed("Failed to encode message"))
        }

        let isArchived = (thread.status == .archived)
        let localBaseDir = isArchived ? localArchiveDirectory : localThreadsDirectory

        // Write locally
        let localMsgDir = localBaseDir.appendingPathComponent(thread.id, isDirectory: true).appendingPathComponent("messages", isDirectory: true)
        try? fileManager.createDirectory(at: localMsgDir, withIntermediateDirectories: true)
        let localMsgURL = localMsgDir.appendingPathComponent(filename)
        try? msgData.write(to: localMsgURL, options: .atomic)

        // Write to iCloud container using NSFileCoordinator to wake up bird immediately
        let iCloudBaseDir = isArchived ? iCloudArchiveDirectory : iCloudThreadsDirectory
        if let iCloudDir = iCloudBaseDir {
            let iCloudMsgDir = iCloudDir.appendingPathComponent(thread.id, isDirectory: true).appendingPathComponent("messages", isDirectory: true)
            try? fileManager.createDirectory(at: iCloudMsgDir, withIntermediateDirectories: true)
            let iCloudMsgURL = iCloudMsgDir.appendingPathComponent(filename)
            coordinatedWrite(data: msgData, to: iCloudMsgURL)
            keepUploading(iCloudMsgURL)
        }

        return .success(())
    }

    private func writeMetadata(_ thread: DispatchThread) -> Result<Void, DispatchError> {
        guard let metaData = try? DispatchFormatters.jsonEncoder.encode(thread) else {
            return .failure(.serializationFailed("Failed to encode thread metadata"))
        }

        let isArchived = (thread.status == .archived)
        let localBaseDir = isArchived ? localArchiveDirectory : localThreadsDirectory

        // Write locally
        let localThreadDir = localBaseDir.appendingPathComponent(thread.id, isDirectory: true)
        try? fileManager.createDirectory(at: localThreadDir, withIntermediateDirectories: true)
        let localMetaURL = localThreadDir.appendingPathComponent("meta.json")
        try? metaData.write(to: localMetaURL, options: .atomic)
        let localModDate = (try? fileManager.attributesOfItem(atPath: localMetaURL.path)[.modificationDate]) as? Date ?? Date()
        threadFileCache[localMetaURL.path] = CachedThreadRecord(modificationDate: localModDate, thread: thread)

        // Write to iCloud container using NSFileCoordinator
        let iCloudBaseDir = isArchived ? iCloudArchiveDirectory : iCloudThreadsDirectory
        if let iCloudDir = iCloudBaseDir {
            let iCloudThreadDir = iCloudDir.appendingPathComponent(thread.id, isDirectory: true)
            try? fileManager.createDirectory(at: iCloudThreadDir, withIntermediateDirectories: true)
            let iCloudMetaURL = iCloudThreadDir.appendingPathComponent("meta.json")
            coordinatedWrite(data: metaData, to: iCloudMetaURL)
            let iCloudModDate = (try? fileManager.attributesOfItem(atPath: iCloudMetaURL.path)[.modificationDate]) as? Date ?? Date()
            threadFileCache[iCloudMetaURL.path] = CachedThreadRecord(modificationDate: iCloudModDate, thread: thread)
            keepUploading(iCloudMetaURL)
        }

        return .success(())
    }

    private func touchSyncMarker(threadId: String) {
        let payload: [String: String] = [
            "updated_at": DispatchFormatters.iso8601Zulu.string(from: Date()),
            "thread_id": threadId
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }

        // Local cache
        let localMarker = localThreadsDirectory.appendingPathComponent(".sync_marker.json")
        try? data.write(to: localMarker, options: .atomic)

        // iCloud Ubiquity Container (triggers macOS launchd WatchPaths immediately via NSFileCoordinator)
        if let iCloudDir = iCloudThreadsDirectory {
            let iCloudMarker = iCloudDir.appendingPathComponent(".sync_marker.json")
            coordinatedWrite(data: data, to: iCloudMarker)
        }

        lastSyncMarkerSignature = currentSyncMarkerSignature()
    }
}
