import Foundation

// MARK: - Value Types & Type-Safe Identifiers

public struct ThreadId: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func generate() -> ThreadId {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let datePart = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
        let randPart = UUID().uuidString.prefix(6).lowercased()
        return ThreadId(rawValue: "th_\(datePart)_\(randPart)")
    }
}

public struct MessageId: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func generate() -> MessageId {
        MessageId(rawValue: "msg_\(UUID().uuidString.prefix(8).lowercased())")
    }
}

public enum DispatchSender: String, Codable, Sendable, CaseIterable, Equatable {
    case user
    case agent

    public var displayName: String {
        switch self {
        case .user: return "You"
        case .agent: return "Hermes Agent"
        }
    }
}

public enum DispatchStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pendingAgent = "pending_agent"
    case replied = "replied"
    case archived = "archived"

    public var label: String {
        switch self {
        case .pendingAgent: return "Awaiting Agent"
        case .replied: return "Replied"
        case .archived: return "Archived"
        }
    }
}

// MARK: - Core Domain Models (Pure Immutable Structs)

public struct DispatchThread: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let subject: String
    public let targetProfile: String
    public let status: DispatchStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let messageCount: Int
    public let lastSnippet: String?

    public init(
        id: String,
        subject: String,
        targetProfile: String = "default",
        status: DispatchStatus,
        createdAt: Date,
        updatedAt: Date,
        messageCount: Int,
        lastSnippet: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.targetProfile = targetProfile
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.lastSnippet = lastSnippet
    }

    enum CodingKeys: String, CodingKey {
        case id = "thread_id"
        case subject
        case targetProfile = "target_profile"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messageCount = "message_count"
        case lastSnippet = "last_snippet"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.subject = try container.decode(String.self, forKey: .subject)
        self.targetProfile = try container.decodeIfPresent(String.self, forKey: .targetProfile) ?? "default"
        self.status = try container.decode(DispatchStatus.self, forKey: .status)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.messageCount = try container.decode(Int.self, forKey: .messageCount)
        self.lastSnippet = try container.decodeIfPresent(String.self, forKey: .lastSnippet)
    }

    // Pure functional mutation
    public func with(
        targetProfile: String? = nil,
        status: DispatchStatus? = nil,
        updatedAt: Date? = nil,
        messageCount: Int? = nil,
        lastSnippet: String? = nil
    ) -> DispatchThread {
        DispatchThread(
            id: self.id,
            subject: self.subject,
            targetProfile: targetProfile ?? self.targetProfile,
            status: status ?? self.status,
            createdAt: self.createdAt,
            updatedAt: updatedAt ?? self.updatedAt,
            messageCount: messageCount ?? self.messageCount,
            lastSnippet: lastSnippet ?? self.lastSnippet
        )
    }
}

public struct DispatchMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let threadId: String
    public let sender: DispatchSender
    public let timestamp: Date
    public let body: String

    public init(
        id: String,
        threadId: String,
        sender: DispatchSender,
        timestamp: Date,
        body: String
    ) {
        self.id = id
        self.threadId = threadId
        self.sender = sender
        self.timestamp = timestamp
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case sender
        case timestamp
        case body
    }
}

// MARK: - Pure Formatting & Coders

public enum DispatchFormatters {
    public static let iso8601Zulu: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601Zulu.string(from: date))
        }
        return encoder
    }()

    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            if let date = iso8601Zulu.date(from: dateStr) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date string: \(dateStr)")
        }
        return decoder
    }()
}
