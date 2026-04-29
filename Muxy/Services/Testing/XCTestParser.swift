import Foundation

struct XCTestParser: TestOutputParser {
    private(set) var root: TestNode
    private var activeSuite: String?
    private var activeTest: String?

    init() {
        root = TestNode(name: "", isSuite: true)
    }

    mutating func ingest(line rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return }

        if let parsed = Self.matchTestCase(line) {
            handleTestCase(parsed)
            return
        }
        if activeTest != nil, let failure = Self.matchFailure(line) {
            attachFailure(failure)
        }
    }

    private mutating func handleTestCase(_ event: TestCaseEvent) {
        ensureSuite(event.suite)
        let path = [event.suite, event.test]
        switch event.status {
        case .started:
            activeTest = event.test
            upsert(atPath: path, status: .running, isSuite: false, duration: nil)
        case .passed:
            activeTest = nil
            upsert(atPath: path, status: .passed, isSuite: false, duration: event.duration)
        case .failed:
            activeTest = event.test
            upsert(atPath: path, status: .failed, isSuite: false, duration: event.duration)
        case .skipped:
            activeTest = nil
            upsert(atPath: path, status: .skipped, isSuite: false, duration: event.duration)
        }
    }

    private mutating func ensureSuite(_ suite: String) {
        activeSuite = suite
        upsert(atPath: [suite], status: .running, isSuite: true, duration: nil)
    }

    private mutating func attachFailure(_ failure: TestFailure) {
        guard let suite = activeSuite, let test = activeTest else { return }
        updateNode(atPath: [suite, test]) { node in
            node.failures.append(failure)
            node.status = .failed
        }
    }

    private mutating func upsert(atPath path: [String], status: TestStatus, isSuite: Bool, duration: Double?) {
        updateNode(atPath: path) { node in
            if node.status == .pending || node.status == .running || status == .failed {
                node.status = status
            }
            if isSuite { node.isSuite = true }
            if let duration { node.durationSeconds = duration }
        }
    }

    private mutating func updateNode(atPath path: [String], _ mutate: (inout TestNode) -> Void) {
        var trail = root
        applyPath(&trail, remaining: path[...], mutate: mutate)
        root = trail
    }

    private func applyPath(
        _ node: inout TestNode,
        remaining: ArraySlice<String>,
        mutate: (inout TestNode) -> Void
    ) {
        guard let head = remaining.first else {
            mutate(&node)
            return
        }
        let tail = remaining.dropFirst()
        if let index = node.children.firstIndex(where: { $0.name == head }) {
            var child = node.children[index]
            applyPath(&child, remaining: tail, mutate: mutate)
            node.children[index] = child
            return
        }
        var child = TestNode(name: head, status: .pending, isSuite: !tail.isEmpty)
        applyPath(&child, remaining: tail, mutate: mutate)
        node.children.append(child)
    }

    private struct TestCaseEvent {
        enum Status { case started, passed, failed, skipped }
        let suite: String
        let test: String
        let status: Status
        let duration: Double?
    }

    private static let testCaseRegex = makeRegex(
        "^Test Case '-?\\[([^\\s\\]]+)\\s+([^\\s\\]]+)\\]'\\s+(started|passed|failed|skipped)(?:\\s+\\(([\\d.]+) seconds\\))?"
    )
    private static let failureRegex = makeRegex(
        "^(\\/[^:]+\\.swift):(\\d+):\\s*error:\\s*(.*)$"
    )

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("Invalid regex: \(pattern)")
        }
        return regex
    }

    private static func matchTestCase(_ line: String) -> TestCaseEvent? {
        guard let match = firstMatch(testCaseRegex, in: line) else { return nil }
        let rawSuite = capture(match, at: 1, in: line) ?? ""
        let suite = rawSuite.split(separator: ".").last.map(String.init) ?? rawSuite
        let test = capture(match, at: 2, in: line) ?? ""
        let statusText = capture(match, at: 3, in: line) ?? "started"
        let duration = capture(match, at: 4, in: line).flatMap(Double.init)
        let status: TestCaseEvent.Status = switch statusText {
        case "passed": .passed
        case "failed": .failed
        case "skipped": .skipped
        default: .started
        }
        return TestCaseEvent(suite: suite, test: test, status: status, duration: duration)
    }

    private static func matchFailure(_ line: String) -> TestFailure? {
        guard let match = firstMatch(failureRegex, in: line) else { return nil }
        let path = capture(match, at: 1, in: line) ?? ""
        let lineNumber = capture(match, at: 2, in: line).flatMap(Int.init)
        let message = capture(match, at: 3, in: line) ?? line
        return TestFailure(message: message, filePath: path, line: lineNumber, column: nil)
    }

    private static func firstMatch(_ regex: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range)
    }

    private static func capture(_ match: NSTextCheckingResult, at index: Int, in string: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
        return String(string[swiftRange])
    }
}
