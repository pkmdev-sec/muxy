import Foundation
import Testing

@testable import Muxy

@Suite("FileWatchGlob")
struct FileWatchGlobTests {
    @Test("no pattern matches everything")
    func noPattern() {
        #expect(FileWatchGlob.matches(pattern: "", path: "/tmp/x.swift") == true)
    }

    @Test("star matches anything in same segment")
    func starMatches() {
        #expect(FileWatchGlob.matches(pattern: "*.swift", path: "/tmp/foo.swift") == true)
        #expect(FileWatchGlob.matches(pattern: "*.swift", path: "/tmp/foo.txt") == false)
    }

    @Test("case-insensitive matching")
    func caseInsensitive() {
        #expect(FileWatchGlob.matches(pattern: "*.SWIFT", path: "/tmp/foo.swift") == true)
        #expect(FileWatchGlob.matches(pattern: "*.md", path: "/tmp/FOO.MD") == true)
    }

    @Test("comma separates alternatives")
    func commaSeparated() {
        #expect(FileWatchGlob.matches(pattern: "*.swift,*.md", path: "/tmp/x.md") == true)
        #expect(FileWatchGlob.matches(pattern: "*.swift,*.md", path: "/tmp/x.rs") == false)
    }

    @Test("regex metacharacters are escaped")
    func metaEscaped() {
        #expect(FileWatchGlob.matches(pattern: "*.config", path: "/tmp/any.config") == true)
        #expect(FileWatchGlob.matches(pattern: "*.config", path: "/tmp/any-config.txt") == false)
    }
}
