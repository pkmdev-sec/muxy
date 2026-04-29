import Foundation
import Testing

@testable import Muxy

@Suite("ProjectSearchService parsers")
struct ProjectSearchServiceTests {
    @Test("git-grep line with filename, line, column, text")
    func parsesGitGrepLine() {
        let line = "Muxy/Services/Foo.swift:42:7:    let needle = foo()"
        let result = ProjectSearchServiceTestHooks.parseGitGrepLine(line, projectPath: "/tmp/project")
        let unwrapped = try! #require(result)
        #expect(unwrapped.relativePath == "Muxy/Services/Foo.swift")
        #expect(unwrapped.absolutePath == "/tmp/project/Muxy/Services/Foo.swift")
        #expect(unwrapped.lineNumber == 42)
        #expect(unwrapped.columnNumber == 7)
        #expect(unwrapped.matchText == "    let needle = foo()")
    }

    @Test("git-grep line with colons inside match text")
    func preservesColonsInMatchText() {
        let line = "src/a.swift:5:1:let url = \"http://example.com\""
        let result = ProjectSearchServiceTestHooks.parseGitGrepLine(line)
        let unwrapped = try! #require(result)
        #expect(unwrapped.matchText == "let url = \"http://example.com\"")
    }

    @Test("malformed git-grep line returns nil")
    func malformedReturnsNil() {
        #expect(ProjectSearchServiceTestHooks.parseGitGrepLine("not a grep line") == nil)
        #expect(ProjectSearchServiceTestHooks.parseGitGrepLine("only:one:part") == nil)
    }

    @Test("grep line strips the project prefix into relative path")
    func grepStripsPrefix() {
        let result = ProjectSearchServiceTestHooks.parseGrepLine(
            "/tmp/project/src/foo.swift:10:    hit()",
            projectPath: "/tmp/project"
        )
        let unwrapped = try! #require(result)
        #expect(unwrapped.relativePath == "src/foo.swift")
        #expect(unwrapped.lineNumber == 10)
        #expect(unwrapped.columnNumber == 1)
        #expect(unwrapped.absolutePath == "/tmp/project/src/foo.swift")
    }

    @Test("grep line outside project prefix keeps absolute path unchanged")
    func grepOutsidePrefix() {
        let result = ProjectSearchServiceTestHooks.parseGrepLine(
            "/other/place/foo.swift:3:hit",
            projectPath: "/tmp/project"
        )
        let unwrapped = try! #require(result)
        #expect(unwrapped.relativePath == "/other/place/foo.swift")
    }
}
