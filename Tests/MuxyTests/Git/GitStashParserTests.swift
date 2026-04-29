import Foundation
import Testing

@testable import Muxy

@Suite("GitStashParser")
struct GitStashParserTests {
    @Test("parses a single stash entry")
    func singleEntry() {
        let output = "stash@{0}\u{0}abcdef1234567890abcdef1234567890abcdef12\u{0}On main: WIP on main: test change"
        let entries = GitStashParser.parseList(output)
        #expect(entries.count == 1)
        let first = try! #require(entries.first)
        #expect(first.slot == "stash@{0}")
        #expect(first.hash == "abcdef1234567890abcdef1234567890abcdef12")
        #expect(first.message == "On main: WIP on main: test change")
        #expect(first.branchHint == "main")
    }

    @Test("parses multiple stash entries separated by newlines")
    func multipleEntries() {
        let output = """
        stash@{0}\u{0}aaa1\u{0}On main: first
        stash@{1}\u{0}bbb2\u{0}On feature: second
        stash@{2}\u{0}ccc3\u{0}On wip: third
        """
        let entries = GitStashParser.parseList(output)
        #expect(entries.count == 3)
        #expect(entries[0].slot == "stash@{0}")
        #expect(entries[1].branchHint == "feature")
        #expect(entries[2].message == "On wip: third")
    }

    @Test("empty output returns an empty array")
    func emptyOutput() {
        #expect(GitStashParser.parseList("").isEmpty)
    }

    @Test("malformed entry (missing null separator) is skipped")
    func malformedEntry() {
        let output = "garbled text with no nulls\nstash@{0}\u{0}hashhere\u{0}On main: good"
        let entries = GitStashParser.parseList(output)
        #expect(entries.count == 1)
        #expect(entries.first?.slot == "stash@{0}")
    }

    @Test("message with colons inside is preserved intact")
    func colonsInsideMessage() {
        let output = "stash@{0}\u{0}deadbeef\u{0}On main: url: https://example.com fixed"
        let entries = GitStashParser.parseList(output)
        let first = try! #require(entries.first)
        #expect(first.branchHint == "main")
        #expect(first.trailingMessage == "url: https://example.com fixed")
    }

    @Test("message without branch prefix still parses")
    func noBranchPrefix() {
        let output = "stash@{0}\u{0}deadbeef\u{0}WIP on detached HEAD: fix"
        let entries = GitStashParser.parseList(output)
        let first = try! #require(entries.first)
        #expect(first.branchHint == nil)
        #expect(first.message == "WIP on detached HEAD: fix")
    }
}
