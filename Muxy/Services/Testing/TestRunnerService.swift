import Foundation
import os

private let testRunnerLogger = Logger(subsystem: "app.muxy", category: "TestRunnerService")

@MainActor
final class TestRunnerService {
    static let shared = TestRunnerService()

    private var processesByState: [ObjectIdentifier: Process] = [:]

    func run(state: TestRunnerTabState) async {
        if state.isRunning { return }
        state.reset()
        state.isRunning = true
        state.lastStartedAt = Date()

        let framework = state.framework
        let command = state.commandLine
        let projectPath = state.projectPath
        let stateID = ObjectIdentifier(state)

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        processesByState[stateID] = process

        let stream = AsyncStream<String> { continuation in
            Self.attachReader(pipe: stdout, continuation: continuation)
            Self.attachReader(pipe: stderr, continuation: continuation)
            process.terminationHandler = { _ in
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            testRunnerLogger.error("Failed to launch tests: \(error.localizedDescription, privacy: .public)")
            state.isRunning = false
            state.lastExitStatus = -1
            state.lastFinishedAt = Date()
            processesByState.removeValue(forKey: stateID)
            return
        }

        var parser = makeParser(for: framework)
        for await chunk in stream {
            for rawLine in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(rawLine)
                if !line.isEmpty {
                    state.appendOutput(line)
                    parser.ingest(line: line)
                }
            }
            state.root = parser.root
        }

        process.waitUntilExit()
        state.root = parser.root
        state.lastExitStatus = process.terminationStatus
        state.lastFinishedAt = Date()
        state.isRunning = false
        processesByState.removeValue(forKey: stateID)
    }

    func cancel(state: TestRunnerTabState) {
        let stateID = ObjectIdentifier(state)
        guard let process = processesByState[stateID], process.isRunning else { return }
        process.interrupt()
    }

    private func makeParser(for framework: TestRunnerTabState.Framework) -> any TestOutputParser {
        switch framework {
        case .swiftTesting: SwiftTestingParser()
        case .xctest: XCTestParser()
        case .unknown: SwiftTestingParser()
        }
    }

    private static func attachReader(pipe: Pipe, continuation: AsyncStream<String>.Continuation) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                continuation.yield(text)
            }
        }
    }
}
