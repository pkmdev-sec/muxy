import Foundation

struct SwiftTestingParser: TestOutputParser {
    private struct ParsedEnd {
        let name: String
        let status: TestStatus
        let duration: Double?
    }

    private(set) var root: TestNode
    private var suitePath: [String]
    private var activeTestPath: [String]?
    private var pendingFailureMessage: String?

    init() {
        root = TestNode(name: "", isSuite: true)
        suitePath = []
        activeTestPath = nil
    }

    mutating func ingest(line rawLine: String) {
        let line = Self.stripLeading(rawLine)
        if line.isEmpty { return }

        if let suite = Self.matchSuiteStart(line) {
            handleSuiteStart(name: suite)
            return
        }
        if let event = Self.matchSuiteEnd(line) {
            handleSuiteEnd(name: event.name, status: event.status, duration: event.duration)
            return
        }
        if let event = Self.matchTestEnd(line) {
            handleTestEnd(name: event.name, status: event.status, duration: event.duration)
            return
        }
        if let name = Self.matchTestStart(line) {
            handleTestStart(name: name)
            return
        }
        if let name = Self.matchTestSkipped(line) {
            handleTestSkipped(name: name)
            return
        }
        if activeTestPath != nil, let failure = Self.matchFailureLocation(line) {
            attachFailure(failure)
            return
        }
        if Self.matchRunTotals(line) != nil {
            activeTestPath = nil
        }
    }

    private mutating func handleSuiteStart(name: String) {
        activeTestPath = nil
        suitePath.append(name)
        upsertNode(atPath: suitePath, status: .running, isSuite: true)
    }

    private mutating func handleSuiteEnd(name: String, status: TestStatus, duration: Double?) {
        activeTestPath = nil
        let targetPath = resolveExistingPath(for: name, under: suitePath) ?? (suitePath + [name])
        updateNode(atPath: targetPath) { node in
            node.status = status
            node.durationSeconds = duration
            node.isSuite = true
        }
        if suitePath.last == name {
            suitePath.removeLast()
        }
    }

    private mutating func handleTestStart(name: String) {
        let path = suitePath + [name]
        activeTestPath = path
        upsertNode(atPath: path, status: .running, isSuite: false)
    }

    private mutating func handleTestEnd(name: String, status: TestStatus, duration: Double?) {
        let path = resolveExistingPath(for: name, under: suitePath) ?? (suitePath + [name])
        updateNode(atPath: path) { node in
            node.status = status
            node.durationSeconds = duration
        }
        activeTestPath = status == .failed ? path : nil
    }

    private mutating func handleTestSkipped(name: String) {
        let path = suitePath + [name]
        upsertNode(atPath: path, status: .skipped, isSuite: false)
        activeTestPath = nil
    }

    private mutating func attachFailure(_ failure: TestFailure) {
        guard let path = activeTestPath else { return }
        updateNode(atPath: path) { node in
            node.failures.append(failure)
            node.status = .failed
        }
    }

    private func resolveExistingPath(for name: String, under suitePath: [String]) -> [String]? {
        let candidate = suitePath + [name]
        if nodeExists(atPath: candidate) { return candidate }
        if !suitePath.isEmpty, nodeExists(atPath: [name]) { return [name] }
        return nil
    }

    private func nodeExists(atPath path: [String]) -> Bool {
        var current = root
        for component in path {
            guard let next = current.children.first(where: { $0.name == component }) else { return false }
            current = next
        }
        return true
    }

    private mutating func upsertNode(atPath path: [String], status: TestStatus, isSuite: Bool) {
        updateNode(atPath: path, create: true) { node in
            if node.status == .pending || node.status == .running {
                node.status = status
            }
            if isSuite {
                node.isSuite = true
            }
        }
    }

    private mutating func updateNode(
        atPath path: [String],
        create: Bool = true,
        _ mutate: (inout TestNode) -> Void
    ) {
        var trail = root
        applyPath(&trail, remaining: path[...], create: create, mutate: mutate)
        root = trail
    }

    private func applyPath(
        _ node: inout TestNode,
        remaining: ArraySlice<String>,
        create: Bool,
        mutate: (inout TestNode) -> Void
    ) {
        guard let head = remaining.first else {
            mutate(&node)
            return
        }
        let tail = remaining.dropFirst()
        if let index = node.children.firstIndex(where: { $0.name == head }) {
            var child = node.children[index]
            applyPath(&child, remaining: tail, create: create, mutate: mutate)
            node.children[index] = child
            return
        }
        if !create { return }
        var child = TestNode(name: head, status: .pending, isSuite: !tail.isEmpty)
        applyPath(&child, remaining: tail, create: create, mutate: mutate)
        node.children.append(child)
    }

    private static func stripLeading(_ line: String) -> String {
        var result = line[...]
        while let first = result.first {
            if first.isWhitespace {
                result = result.dropFirst()
                continue
            }
            if first.isASCII, first.isLetter {
                break
            }
            if first.isNewline {
                result = result.dropFirst()
                continue
            }
            if Self.isMarkerCharacter(first) {
                result = result.dropFirst()
                continue
            }
            break
        }
        return String(result).trimmingCharacters(in: .whitespaces)
    }

    private static func isMarkerCharacter(_ character: Character) -> Bool {
        let markers: Set<Character> = ["✔", "✘", "◇", "◌", "✱", "􀟈", "􁁛", "􀢄", "•", "-"]
        if markers.contains(character) { return true }
        guard let scalar = character.unicodeScalars.first else { return false }
        if scalar.value >= 0x2600, scalar.value <= 0x27BF { return true }
        if scalar.value >= 0x10000 { return true }
        if scalar.value >= 0xE000, scalar.value <= 0xF8FF { return true }
        return false
    }

    private static let suiteStartRegex = makeRegex("^(?:Test )?Suite [\"'](.+?)[\"'] started\\.?")
    private static let suiteEndRegex = makeRegex(
        "^(?:Test )?Suite [\"'](.+?)[\"'] (passed|failed)(?: after ([\\d.]+) seconds)?"
    )
    private static let testStartRegex = makeRegex("^Test [\"'](.+?)[\"'] started\\.?")
    private static let testEndRegex = makeRegex(
        "^Test [\"'](.+?)[\"'] (passed|failed) after ([\\d.]+) seconds"
    )
    private static let testSkippedRegex = makeRegex("^Test [\"'](.+?)[\"'] skipped")
    private static let runTotalsRegex = makeRegex("^Test run with .* (passed|failed)")
    private static let failureLocationRegex = makeRegex(
        "^([^\\s:]+\\.swift):(\\d+)(?::(\\d+))?:\\s*(.*)$"
    )

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            preconditionFailure("Invalid regex: \(pattern)")
        }
        return regex
    }

    private static func matchSuiteStart(_ line: String) -> String? {
        firstCapture(suiteStartRegex, in: line, index: 1)
    }

    private static func matchSuiteEnd(_ line: String) -> ParsedEnd? {
        guard let match = firstMatch(suiteEndRegex, in: line) else { return nil }
        let name = capture(match, at: 1, in: line) ?? ""
        let statusText = capture(match, at: 2, in: line) ?? "passed"
        let durationText = capture(match, at: 3, in: line)
        return ParsedEnd(
            name: name,
            status: statusText == "failed" ? .failed : .passed,
            duration: durationText.flatMap(Double.init)
        )
    }

    private static func matchTestStart(_ line: String) -> String? {
        firstCapture(testStartRegex, in: line, index: 1)
    }

    private static func matchTestEnd(_ line: String) -> ParsedEnd? {
        guard let match = firstMatch(testEndRegex, in: line) else { return nil }
        let name = capture(match, at: 1, in: line) ?? ""
        let statusText = capture(match, at: 2, in: line) ?? "passed"
        let durationText = capture(match, at: 3, in: line)
        return ParsedEnd(
            name: name,
            status: statusText == "failed" ? .failed : .passed,
            duration: durationText.flatMap(Double.init)
        )
    }

    private static func matchTestSkipped(_ line: String) -> String? {
        firstCapture(testSkippedRegex, in: line, index: 1)
    }

    private static func matchRunTotals(_ line: String) -> String? {
        firstCapture(runTotalsRegex, in: line, index: 1)
    }

    private static func matchFailureLocation(_ line: String) -> TestFailure? {
        guard let match = firstMatch(failureLocationRegex, in: line) else { return nil }
        let path = capture(match, at: 1, in: line) ?? ""
        let lineNumber = capture(match, at: 2, in: line).flatMap(Int.init)
        let column = capture(match, at: 3, in: line).flatMap(Int.init)
        let message = capture(match, at: 4, in: line) ?? line
        return TestFailure(message: message, filePath: path, line: lineNumber, column: column)
    }

    private static func firstMatch(_ regex: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range)
    }

    private static func firstCapture(_ regex: NSRegularExpression, in string: String, index: Int) -> String? {
        guard let match = firstMatch(regex, in: string) else { return nil }
        return capture(match, at: index, in: string)
    }

    private static func capture(_ match: NSTextCheckingResult, at index: Int, in string: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
        return String(string[swiftRange])
    }
}
