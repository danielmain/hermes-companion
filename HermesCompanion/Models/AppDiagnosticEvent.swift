import Foundation

public enum DiagnosticSeverity: String, Codable {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARN"
    case error = "ERROR"
}

public struct AppDiagnosticEvent: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let title: String
    public let details: String
    public let severity: DiagnosticSeverity

    public init(id: UUID = UUID(), timestamp: Date = Date(), title: String, details: String = "", severity: DiagnosticSeverity = .info) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.details = details
        self.severity = severity
    }
}
