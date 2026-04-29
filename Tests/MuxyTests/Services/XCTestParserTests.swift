import Foundation
import Testing

@testable import Muxy

@Suite("XCTestParser")
struct XCTestParserTests {
    @Test("parses a passing case grouped by suite")
    func parsesPassingCase() {
        var parser = XCTestParser()
        parser.ingest(line: "Test Case '-[MuxyTests.FooTests testBar]' started.")
        parser.ingest(line: "Test Case '-[MuxyTests.FooTests testBar]' passed (0.002 seconds).")

        let suite = parser.root.children.first
        #expect(suite?.name == "FooTests")
        #expect(suite?.isSuite == true)
        let test = suite?.children.first
        #expect(test?.name == "testBar")
        #expect(test?.status == .passed)
        #expect(test?.durationSeconds == 0.002)
    }

    @Test("captures failure file and line")
    func capturesFailure() {
        var parser = XCTestParser()
        parser.ingest(line: "Test Case '-[MuxyTests.FooTests testBaz]' started.")
        parser.ingest(line: "/tmp/Sources/Foo.swift:42: error: -[MuxyTests.FooTests testBaz] : XCTAssertEqual failed: 1 != 2")
        parser.ingest(line: "Test Case '-[MuxyTests.FooTests testBaz]' failed (0.004 seconds).")

        let test = parser.root.children.first?.children.first
        #expect(test?.status == .failed)
        #expect(test?.failures.count == 1)
        #expect(test?.failures.first?.filePath == "/tmp/Sources/Foo.swift")
        #expect(test?.failures.first?.line == 42)
    }

    @Test("nests multiple suites side-by-side")
    func multipleSuites() {
        var parser = XCTestParser()
        parser.ingest(line: "Test Case '-[MuxyTests.FooTests testA]' started.")
        parser.ingest(line: "Test Case '-[MuxyTests.FooTests testA]' passed (0.001 seconds).")
        parser.ingest(line: "Test Case '-[MuxyTests.BarTests testB]' started.")
        parser.ingest(line: "Test Case '-[MuxyTests.BarTests testB]' passed (0.001 seconds).")

        #expect(parser.root.children.count == 2)
        let names = Set(parser.root.children.map(\.name))
        #expect(names == ["FooTests", "BarTests"])
        #expect(parser.summary.passed == 2)
    }

    @Test("empty input produces empty tree and summary")
    func emptyInput() {
        var parser = XCTestParser()
        parser.ingest(line: "** TEST SUCCEEDED **")
        #expect(parser.root.children.isEmpty)
        #expect(parser.summary.total == 0)
    }
}
