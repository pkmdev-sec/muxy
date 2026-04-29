import Foundation
import os

private let lspLogger = Logger(subsystem: "app.muxy", category: "LSPClient")

@MainActor
@Observable
final class LSPClient {
    static let shared = LSPClient()

    enum State: Equatable {
        case idle
        case starting
        case ready
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    private(set) var state: State = .idle
    private(set) var diagnosticsByFile: [String: [LSPDiagnostic]] = [:]

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdin: Pipe?
    @ObservationIgnored private var stdout: Pipe?
    @ObservationIgnored private var readerTask: Task<Void, Never>?
    @ObservationIgnored private var nextRequestID: Int = 1
    @ObservationIgnored private var readBuffer = Data()
    @ObservationIgnored private(set) var rootURL: URL?

    private init() {}

    func start(rootPath: String) {
        if case .ready = state, rootURL?.path == rootPath { return }
        stop()
        state = .starting
        rootURL = URL(fileURLWithPath: rootPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sourcekit-lsp"]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        self.process = process
        self.stdin = stdinPipe
        self.stdout = stdoutPipe

        do {
            try process.run()
        } catch {
            lspLogger.error("Failed to launch sourcekit-lsp: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            return
        }

        startReader()
        sendInitialize(rootPath: rootPath)
    }

    func stop() {
        readerTask?.cancel()
        readerTask = nil
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        diagnosticsByFile.removeAll()
        state = .idle
        rootURL = nil
        readBuffer.removeAll()
    }

    func diagnostics(for filePath: String) -> [LSPDiagnostic] {
        diagnosticsByFile[filePath] ?? []
    }

    func allDiagnostics() -> [LSPDiagnostic] {
        diagnosticsByFile.values.flatMap { $0 }.sorted { lhs, rhs in
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.column < rhs.column
        }
    }

    func totalCount(severity: LSPDiagnosticSeverity) -> Int {
        diagnosticsByFile.values.flatMap { $0 }.count { $0.severity == severity }
    }

    func openDocument(path: String, text: String) {
        guard state.isReady else { return }
        let uri = "file://\(path)"
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": [
                "textDocument": [
                    "uri": uri,
                    "languageId": "swift",
                    "version": 1,
                    "text": text,
                ],
            ],
        ]
        sendRaw(message)
    }

    func changeDocument(path: String, version: Int, text: String) {
        guard state.isReady else { return }
        let uri = "file://\(path)"
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "textDocument/didChange",
            "params": [
                "textDocument": [
                    "uri": uri,
                    "version": version,
                ],
                "contentChanges": [
                    ["text": text],
                ],
            ],
        ]
        sendRaw(message)
    }

    private func sendInitialize(rootPath: String) {
        let id = nextRequestID
        nextRequestID += 1
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "initialize",
            "params": [
                "processId": ProcessInfo.processInfo.processIdentifier,
                "rootUri": "file://\(rootPath)",
                "capabilities": [
                    "textDocument": [
                        "publishDiagnostics": [:],
                    ],
                ],
            ],
        ]
        sendRaw(message)
        let initialized: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:],
        ]
        sendRaw(initialized)
        state = .ready
    }

    private func sendRaw(_ message: [String: Any]) {
        guard let stdin else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: []) else { return }
        var header = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
        header.append(data)
        stdin.fileHandleForWriting.write(header)
    }

    private func startReader() {
        guard let stdout else { return }
        let handle = stdout.fileHandleForReading
        readerTask = Task { [weak self] in
            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continue
                }
                await self?.ingest(chunk)
            }
        }
    }

    private func ingest(_ chunk: Data) {
        readBuffer.append(chunk)
        while let frame = extractFrame() {
            decodeFrame(frame)
        }
    }

    private func extractFrame() -> Data? {
        guard let headerEndRange = readBuffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = readBuffer.subdata(in: 0 ..< headerEndRange.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8) else {
            readBuffer.removeSubrange(0 ..< headerEndRange.upperBound)
            return nil
        }
        var contentLength: Int = 0
        for line in header.split(separator: "\r\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "Content-Length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerEndRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard readBuffer.count >= bodyEnd else { return nil }
        let body = readBuffer.subdata(in: bodyStart ..< bodyEnd)
        readBuffer.removeSubrange(0 ..< bodyEnd)
        return body
    }

    private func decodeFrame(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let method = object["method"] as? String else { return }
        if method == "textDocument/publishDiagnostics" {
            handlePublishDiagnostics(params: object["params"] as? [String: Any] ?? [:])
        }
    }

    private func handlePublishDiagnostics(params: [String: Any]) {
        guard let uri = params["uri"] as? String else { return }
        let path = uri.hasPrefix("file://") ? String(uri.dropFirst("file://".count)) : uri
        let rawDiagnostics = (params["diagnostics"] as? [[String: Any]]) ?? []
        var decoded: [LSPDiagnostic] = []
        for raw in rawDiagnostics {
            guard let range = raw["range"] as? [String: Any],
                  let start = range["start"] as? [String: Any],
                  let line = start["line"] as? Int,
                  let character = start["character"] as? Int,
                  let message = raw["message"] as? String else { continue }
            let severityValue = (raw["severity"] as? Int) ?? 1
            let severity = LSPDiagnosticSeverity(rawValue: severityValue) ?? .error
            decoded.append(LSPDiagnostic(
                filePath: path,
                line: line + 1,
                column: character + 1,
                severity: severity,
                message: message,
                source: raw["source"] as? String
            ))
        }
        diagnosticsByFile[path] = decoded
    }
}
