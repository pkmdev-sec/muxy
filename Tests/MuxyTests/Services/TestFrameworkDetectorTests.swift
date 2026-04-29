import Foundation
import Testing

@testable import Muxy

@Suite("TestFrameworkDetector")
struct TestFrameworkDetectorTests {
    @Test("detects Swift Package as swiftTesting")
    func detectsSwiftPackage() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "// swift-tools-version: 6.0\n".write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let detection = TestFrameworkDetector.detect(projectPath: root.path)
        #expect(detection.framework == .swiftTesting)
        #expect(detection.commandLine == "swift test")
    }

    @Test("detects Xcode project as xctest")
    func detectsXcodeProject() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("App.xcodeproj"),
            withIntermediateDirectories: true
        )

        let detection = TestFrameworkDetector.detect(projectPath: root.path)
        #expect(detection.framework == .xctest)
        #expect(detection.commandLine == "xcodebuild test")
    }

    @Test("plain directory is unknown")
    func plainDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "hi".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let detection = TestFrameworkDetector.detect(projectPath: root.path)
        #expect(detection.framework == .unknown)
        #expect(detection.commandLine == "swift test")
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("muxy-detector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
