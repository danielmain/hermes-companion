import Foundation

// MARK: - Agent Profile Model (Pure Value Type)

public struct AgentProfile: Identifiable, Codable, Equatable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let lastActive: Date?

    public init(id: String, name: String, lastActive: Date? = nil) {
        self.id = id
        self.name = name
        self.lastActive = lastActive
    }

    public static let `default` = AgentProfile(id: "default", name: "Default Agent")

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case lastActive = "last_active"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? id.capitalized
        if let dateStr = try container.decodeIfPresent(String.self, forKey: .lastActive) {
            self.lastActive = DispatchFormatters.iso8601Zulu.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr)
        } else {
            self.lastActive = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        if let lastActive = lastActive {
            try container.encode(DispatchFormatters.iso8601Zulu.string(from: lastActive), forKey: .lastActive)
        }
    }
}

// MARK: - Profiles Configuration File

public struct ProfilesConfig: Codable, Equatable, Sendable {
    public let updatedAt: Date
    public let profiles: [AgentProfile]

    public init(updatedAt: Date, profiles: [AgentProfile]) {
        self.updatedAt = updatedAt
        self.profiles = profiles
    }

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case profiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let dateStr = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            self.updatedAt = DispatchFormatters.iso8601Zulu.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr) ?? Date()
        } else {
            self.updatedAt = Date()
        }
        let list = try container.decodeIfPresent([AgentProfile].self, forKey: .profiles) ?? []
        self.profiles = list.isEmpty ? [AgentProfile.default] : list
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(DispatchFormatters.iso8601Zulu.string(from: updatedAt), forKey: .updatedAt)
        try container.encode(profiles, forKey: .profiles)
    }
}
