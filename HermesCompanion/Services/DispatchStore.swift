import Foundation
import Combine
import os

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
    @Published public private(set) var availableProfiles: [AgentProfile] = [AgentProfile.default]
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.hermes.dispatchstore", qos: .utility)
    private let logger = Logger(subsystem: "com.hermes.HermesCompanion", category: "DispatchStore")

    // MARK: - Directory Locations

    private var localThreadsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("threads", isDirectory: true)
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

    // MARK: - Functional Thread Retrieval & Loading

    public func loadThreads() {
        loadProfiles()
        queue.async { [weak self] in
            guard let self = self else { return }
            let result = self.scanAllThreads()
            DispatchQueue.main.async {
                switch result {
                case .success(let loaded):
                    self.threads = loaded.sorted(by: { $0.updatedAt > $1.updatedAt })
                    self.lastSyncDate = Date()
                    self.logger.info("Loaded \(loaded.count) dispatch threads")
                case .failure(let error):
                    self.logger.error("Failed to load threads: \(error.localizedDescription)")
                }
            }
        }
    }

    private func scanAllThreads() -> Result<[DispatchThread], DispatchError> {
        var threadMap: [String: DispatchThread] = [:]

        // 1. Scan local Application Support directory
        let localResults = scanDirectory(localThreadsDirectory)
        for thread in localResults {
            threadMap[thread.id] = thread
        }

        // 2. Scan iCloud Ubiquity container Documents/threads
        if let iCloudDir = iCloudThreadsDirectory, fileManager.fileExists(atPath: iCloudDir.path) {
            let iCloudResults = scanDirectory(iCloudDir)
            for thread in iCloudResults {
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

        return .success(Array(threadMap.values))
    }

    private func scanDirectory(_ dir: URL) -> [DispatchThread] {
        guard let entries = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        return entries.compactMap { folderURL -> DispatchThread? in
            let metaURL = folderURL.appendingPathComponent("meta.json")
            guard fileManager.fileExists(atPath: metaURL.path),
                  let data = try? Data(contentsOf: metaURL),
                  let thread = try? DispatchFormatters.jsonDecoder.decode(DispatchThread.self, from: data) else {
                return nil
            }
            return thread
        }
    }

    // MARK: - Thread Creation

    public func createThread(subject: String, initialBody: String, targetProfile: String = "default") -> Result<DispatchThread, DispatchError> {
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
            let updated = (self.threads.filter { $0.id != threadId } + [newThread]).sorted(by: { $0.updatedAt > $1.updatedAt })
            self.threads = updated
            self.logger.info("Created dispatch thread '\(cleanSubject)' (\(threadId))")
            return .success(newThread)
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Sending a Reply

    public func replyToThread(threadId: String, body: String, sender: DispatchSender) -> Result<DispatchMessage, DispatchError> {
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
            lastSnippet: String(cleanBody.prefix(120))
        )

        let writeResult = writeThreadAndMessage(thread: updatedThread, message: message, sequenceIndex: nextIndex)
        switch writeResult {
        case .success:
            let updatedList = (self.threads.filter { $0.id != threadId } + [updatedThread]).sorted(by: { $0.updatedAt > $1.updatedAt })
            self.threads = updatedList
            self.logger.info("Appended message \(message.id) to thread \(threadId) by \(sender.rawValue)")
            return .success(message)
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Loading Messages

    public func loadMessages(for threadId: String) -> Result<[DispatchMessage], DispatchError> {
        var messages: [DispatchMessage] = []
        let candidateDirs = [
            localThreadsDirectory.appendingPathComponent(threadId, isDirectory: true).appendingPathComponent("messages", isDirectory: true),
            iCloudThreadsDirectory?.appendingPathComponent(threadId, isDirectory: true).appendingPathComponent("messages", isDirectory: true)
        ].compactMap { $0 }

        var seenIds = Set<String>()

        for msgDir in candidateDirs {
            guard fileManager.fileExists(atPath: msgDir.path),
                  let files = try? fileManager.contentsOfDirectory(at: msgDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }

            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let msg = try? DispatchFormatters.jsonDecoder.decode(DispatchMessage.self, from: data) else {
                    continue
                }
                if !seenIds.contains(msg.id) {
                    seenIds.insert(msg.id)
                    messages.append(msg)
                }
            }
        }

        let sorted = messages.sorted(by: { $0.timestamp < $1.timestamp })
        return .success(sorted)
    }

    // MARK: - Archive Thread

    public func archiveThread(id: String) {
        guard let existing = threads.first(where: { $0.id == id }) else { return }
        let updated = existing.with(status: .archived, updatedAt: Date())
        _ = writeMetadata(updated)
        let updatedList = (self.threads.filter { $0.id != id } + [updated]).sorted(by: { $0.updatedAt > $1.updatedAt })
        self.threads = updatedList
        logger.info("Archived dispatch thread: \(id)")
    }

    // MARK: - Low-Level Immutable Disk Writers

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

        // Write locally
        let localMsgDir = localThreadsDirectory.appendingPathComponent(thread.id, isDirectory: true).appendingPathComponent("messages", isDirectory: true)
        try? fileManager.createDirectory(at: localMsgDir, withIntermediateDirectories: true)
        let localMsgURL = localMsgDir.appendingPathComponent(filename)
        try? msgData.write(to: localMsgURL, options: .atomic)

        // Write to iCloud container
        if let iCloudDir = iCloudThreadsDirectory {
            let iCloudMsgDir = iCloudDir.appendingPathComponent(thread.id, isDirectory: true).appendingPathComponent("messages", isDirectory: true)
            try? fileManager.createDirectory(at: iCloudMsgDir, withIntermediateDirectories: true)
            let iCloudMsgURL = iCloudMsgDir.appendingPathComponent(filename)
            try? msgData.write(to: iCloudMsgURL, options: .atomic)
        }

        return .success(())
    }

    private func writeMetadata(_ thread: DispatchThread) -> Result<Void, DispatchError> {
        guard let metaData = try? DispatchFormatters.jsonEncoder.encode(thread) else {
            return .failure(.serializationFailed("Failed to encode thread metadata"))
        }

        // Write locally
        let localThreadDir = localThreadsDirectory.appendingPathComponent(thread.id, isDirectory: true)
        try? fileManager.createDirectory(at: localThreadDir, withIntermediateDirectories: true)
        let localMetaURL = localThreadDir.appendingPathComponent("meta.json")
        try? metaData.write(to: localMetaURL, options: .atomic)

        // Write to iCloud container
        if let iCloudDir = iCloudThreadsDirectory {
            let iCloudThreadDir = iCloudDir.appendingPathComponent(thread.id, isDirectory: true)
            try? fileManager.createDirectory(at: iCloudThreadDir, withIntermediateDirectories: true)
            let iCloudMetaURL = iCloudThreadDir.appendingPathComponent("meta.json")
            try? metaData.write(to: iCloudMetaURL, options: .atomic)
        }

        return .success(())
    }
}
