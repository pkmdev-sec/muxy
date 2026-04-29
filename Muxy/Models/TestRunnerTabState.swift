import Foundation

@MainActor
@Observable
final class TestRunnerTabState: Identifiable {
    enum Framework: String, Codable {
        case swiftTesting
        case xctest
        case unknown
    }

    static let outputTailLimit = 500

    let id = UUID()
    let projectPath: String
    var commandLine: String
    var framework: Framework
    var root: TestNode
    var isRunning: Bool
    var lastStartedAt: Date?
    var lastFinishedAt: Date?
    var recentOutputLines: [String]
    var lastExitStatus: Int32?

    init(projectPath: String, commandLine: String, framework: Framework = .unknown) {
        self.projectPath = projectPath
        self.commandLine = commandLine
        self.framework = framework
        root = TestNode(name: "", isSuite: true)
        isRunning = false
        recentOutputLines = []
    }

    var displayTitle: String { "Tests" }

    func reset() {
        root = TestNode(name: "", isSuite: true)
        recentOutputLines = []
        lastExitStatus = nil
        lastFinishedAt = nil
    }

    func appendOutput(_ line: String) {
        recentOutputLines.append(line)
        if recentOutputLines.count > Self.outputTailLimit {
            recentOutputLines.removeFirst(recentOutputLines.count - Self.outputTailLimit)
        }
    }
}
