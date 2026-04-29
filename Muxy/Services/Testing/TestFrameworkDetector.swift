import Foundation

struct TestFrameworkDetection: Equatable {
    let framework: TestRunnerTabState.Framework
    let commandLine: String
}

enum TestFrameworkDetector {
    static func detect(projectPath: String) -> TestFrameworkDetection {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)

        if fileManager.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
            return TestFrameworkDetection(framework: .swiftTesting, commandLine: "swift test")
        }

        if hasXcodeProject(in: root) {
            return TestFrameworkDetection(framework: .xctest, commandLine: "xcodebuild test")
        }

        return TestFrameworkDetection(framework: .unknown, commandLine: "swift test")
    }

    private static func hasXcodeProject(in directory: URL) -> Bool {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return entries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") })
    }
}
