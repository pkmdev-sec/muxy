import Foundation
import Testing

@testable import Muxy

@Suite("SwiftTestingParser")
struct SwiftTestingParserTests {
    @Test("empty input produces empty root")
    func emptyInput() {
        var parser = SwiftTestingParser()
        parser.ingest(line: "")
        parser.ingest(line: "   ")
        #expect(parser.root.children.isEmpty)
        #expect(parser.summary.total == 0)
    }

    @Test("parses passing suite with passing test")
    func passingSuite() {
        var parser = SwiftTestingParser()
        parser.ingest(line: "Test Suite \"MuxyCodec\" started.")
        parser.ingest(line: "Test \"round trip\" started.")
        parser.ingest(line: "Test \"round trip\" passed after 0.001 seconds")
        parser.ingest(line: "Suite \"MuxyCodec\" passed after 0.002 seconds")

        let summary = parser.summary
        #expect(summary.total == 1)
        #expect(summary.passed == 1)
        #expect(summary.failed == 0)
        let suite = parser.root.children.first
        #expect(suite?.name == "MuxyCodec")
        #expect(suite?.isSuite == true)
        #expect(suite?.durationSeconds == 0.002)
        #expect(suite?.children.first?.status == .passed)
        #expect(suite?.children.first?.durationSeconds == 0.001)
    }

    @Test("parses failing test and captures following file:line")
    func failingTestCapturesLocation() {
        var parser = SwiftTestingParser()
        parser.ingest(line: "Test Suite \"FooSuite\" started.")
        parser.ingest(line: "Test \"broken\" started.")
        parser.ingest(line: "Test \"broken\" failed after 0.003 seconds with 1 issue")
        parser.ingest(line: "Sources/FooTests.swift:42:5: Expectation failed: 1 == 2")
        parser.ingest(line: "Suite \"FooSuite\" failed after 0.005 seconds")

        let failures = parser.root.findFailures()
        #expect(parser.summary.failed == 1)
        #expect(failures.count == 1)
        #expect(failures.first?.failure.filePath == "Sources/FooTests.swift")
        #expect(failures.first?.failure.line == 42)
        #expect(failures.first?.failure.column == 5)
    }

    @Test("nests suites under parent suite")
    func nestedSuites() {
        var parser = SwiftTestingParser()
        parser.ingest(line: "Test Suite \"Outer\" started.")
        parser.ingest(line: "Test Suite \"Inner\" started.")
        parser.ingest(line: "Test \"leaf\" started.")
        parser.ingest(line: "Test \"leaf\" passed after 0.010 seconds")
        parser.ingest(line: "Suite \"Inner\" passed after 0.010 seconds")
        parser.ingest(line: "Suite \"Outer\" passed after 0.020 seconds")

        let outer = parser.root.children.first
        #expect(outer?.name == "Outer")
        let inner = outer?.children.first
        #expect(inner?.name == "Inner")
        #expect(inner?.isSuite == true)
        #expect(inner?.children.first?.name == "leaf")
        #expect(inner?.children.first?.status == .passed)
    }

    @Test("handles ASCII markers with the same result")
    func asciiMarkers() {
        var parser = SwiftTestingParser()
        parser.ingest(line: "◇ Test Suite \"AsciiSuite\" started.")
        parser.ingest(line: "◇ Test \"alpha\" started.")
        parser.ingest(line: "✔ Test \"alpha\" passed after 0.001 seconds")
        parser.ingest(line: "✔ Suite \"AsciiSuite\" passed after 0.002 seconds")

        #expect(parser.summary.passed == 1)
        #expect(parser.root.children.first?.name == "AsciiSuite")
    }

    @Test("mid-run interrupt leaves running nodes intact")
    func midRunInterrupt() {
        var parser = SwiftTestingParser()
        parser.ingest(line: "Test Suite \"Partial\" started.")
        parser.ingest(line: "Test \"pending\" started.")

        let suite = parser.root.children.first
        #expect(suite?.status == .running)
        #expect(suite?.children.first?.status == .running)
        #expect(parser.summary.passed == 0)
        #expect(parser.summary.failed == 0)
    }

    @Test("summary sums durations across leaves")
    func durationSummed() {
        var parser = SwiftTestingParser()
        parser.ingest(line: "Test Suite \"S\" started.")
        parser.ingest(line: "Test \"a\" started.")
        parser.ingest(line: "Test \"a\" passed after 0.250 seconds")
        parser.ingest(line: "Test \"b\" started.")
        parser.ingest(line: "Test \"b\" passed after 0.750 seconds")
        parser.ingest(line: "Suite \"S\" passed after 1.000 seconds")

        let summary = parser.summary
        #expect(summary.total == 2)
        #expect(summary.durationSeconds.map { ($0 - 1.0) < 0.0001 } == true)
    }
}
