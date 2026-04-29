import Foundation
import Testing

@testable import Muxy

@Suite("ProjectReplaceService")
struct ProjectReplaceServiceTests {
    @Test("rewriteContents replaces every occurrence and reports the count")
    func replacesEveryOccurrence() {
        let input = "alpha beta alpha gamma alpha"
        let (output, count) = ProjectReplaceService.rewriteContents(input, query: "alpha", replacement: "ALPHA")
        #expect(output == "ALPHA beta ALPHA gamma ALPHA")
        #expect(count == 3)
    }

    @Test("rewriteContents returns zero count when the query is absent")
    func absentQueryNoopsCleanly() {
        let input = "nothing to see here"
        let (output, count) = ProjectReplaceService.rewriteContents(input, query: "alpha", replacement: "ALPHA")
        #expect(output == input)
        #expect(count == 0)
    }

    @Test("rewriteContents handles empty replacement (deletion)")
    func emptyReplacementDeletes() {
        let input = "foo bar foo"
        let (output, count) = ProjectReplaceService.rewriteContents(input, query: "foo ", replacement: "")
        #expect(output == "bar foo")
        #expect(count == 1)
    }

    @Test("rewriteContents treats query as literal (no regex)")
    func treatsLiteralNotRegex() {
        let input = "use .* everywhere"
        let (output, count) = ProjectReplaceService.rewriteContents(input, query: ".*", replacement: "X")
        #expect(output == "use X everywhere")
        #expect(count == 1)
    }

    @Test("rewriteContents preserves overlapping-match semantics of String.range(of:)")
    func nonOverlappingMatches() {
        let input = "aaaa"
        let (output, count) = ProjectReplaceService.rewriteContents(input, query: "aa", replacement: "b")
        #expect(output == "bb")
        #expect(count == 2)
    }

    @Test("rewriteContents on empty query returns input unchanged")
    func emptyQueryReturnsUnchanged() {
        let input = "alpha"
        let (output, count) = ProjectReplaceService.rewriteContents(input, query: "", replacement: "X")
        #expect(output == input)
        #expect(count == 0)
    }

    @Test("replace writes to disk and reports accurate counts")
    func replaceOnDisk() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("muxy-replace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileA = tempDir.appendingPathComponent("a.txt")
        let fileB = tempDir.appendingPathComponent("b.txt")
        try "hello world hello".write(to: fileA, atomically: true, encoding: .utf8)
        try "goodbye".write(to: fileB, atomically: true, encoding: .utf8)

        let results = [
            ProjectSearchResult(
                id: "a:1",
                relativePath: "a.txt",
                absolutePath: fileA.path,
                lineNumber: 1,
                columnNumber: 1,
                matchText: "hello world hello"
            ),
            ProjectSearchResult(
                id: "b:1",
                relativePath: "b.txt",
                absolutePath: fileB.path,
                lineNumber: 1,
                columnNumber: 1,
                matchText: "goodbye"
            ),
        ]

        let outcome = await ProjectReplaceService.replace(
            query: "hello",
            replacement: "HI",
            in: results
        )

        #expect(outcome.filesChanged == 1)
        #expect(outcome.occurrencesReplaced == 2)
        #expect(outcome.failures.isEmpty)

        let updatedA = try String(contentsOf: fileA, encoding: .utf8)
        let updatedB = try String(contentsOf: fileB, encoding: .utf8)
        #expect(updatedA == "HI world HI")
        #expect(updatedB == "goodbye")
    }

    @Test("replace records failures for unreadable paths")
    func replaceRecordsFailure() async throws {
        let missingPath = "/tmp/muxy-does-not-exist-\(UUID().uuidString)/x.txt"
        let results = [
            ProjectSearchResult(
                id: "x:1",
                relativePath: "x.txt",
                absolutePath: missingPath,
                lineNumber: 1,
                columnNumber: 1,
                matchText: "anything"
            ),
        ]

        let outcome = await ProjectReplaceService.replace(
            query: "any",
            replacement: "new",
            in: results
        )

        #expect(outcome.filesChanged == 0)
        #expect(outcome.occurrencesReplaced == 0)
        #expect(outcome.failures == [missingPath])
    }
}
