import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("LSPClient")
struct LSPClientTests {
    @Test("starts in idle state")
    func idleStart() {
        let client = LSPClient.shared
        client.stop()
        #expect(client.state == .idle)
    }

    @Test("state.isReady reflects the case")
    func isReady() {
        #expect(LSPClient.State.idle.isReady == false)
        #expect(LSPClient.State.starting.isReady == false)
        #expect(LSPClient.State.ready.isReady == true)
        #expect(LSPClient.State.failed("x").isReady == false)
    }
}

@Suite("LSPDiagnostic")
struct LSPDiagnosticTests {
    @Test("severity raw values match LSP spec")
    func severityValues() {
        #expect(LSPDiagnosticSeverity.error.rawValue == 1)
        #expect(LSPDiagnosticSeverity.warning.rawValue == 2)
        #expect(LSPDiagnosticSeverity.information.rawValue == 3)
        #expect(LSPDiagnosticSeverity.hint.rawValue == 4)
    }

    @Test("diagnostic holds file + line + column")
    func diagnosticShape() {
        let d = LSPDiagnostic(
            filePath: "/tmp/a.swift",
            line: 10,
            column: 4,
            severity: .error,
            message: "boom"
        )
        #expect(d.line == 10)
        #expect(d.severity == .error)
    }
}
