import Foundation

enum LSPDiagnosticSeverity: Int, Codable, Sendable, Equatable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

struct LSPDiagnostic: Identifiable, Equatable, Sendable, Hashable {
    let id: UUID
    let filePath: String
    let line: Int
    let column: Int
    let severity: LSPDiagnosticSeverity
    let message: String
    let source: String?

    init(
        id: UUID = UUID(),
        filePath: String,
        line: Int,
        column: Int,
        severity: LSPDiagnosticSeverity,
        message: String,
        source: String? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.source = source
    }
}
