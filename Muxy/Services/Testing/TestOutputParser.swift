import Foundation

protocol TestOutputParser: Sendable {
    mutating func ingest(line: String)
    mutating func ingest(data: Data)
    var root: TestNode { get }
    var summary: TestRunSummary { get }
}

extension TestOutputParser {
    mutating func ingest(data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            ingest(line: String(line))
        }
    }

    var summary: TestRunSummary { root.summary() }
}
