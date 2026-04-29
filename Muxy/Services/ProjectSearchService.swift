import Foundation

struct ProjectSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let relativePath: String
    let absolutePath: String
    let lineNumber: Int
    let columnNumber: Int
    let matchText: String
}

enum ProjectSearchService {
    static let maxResults = 200
    private static let prunedDirectoryNames: [String] = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        "__pycache__", ".venv", "venv", "dist", ".next", ".nuxt",
        "target", "Pods", ".swiftpm", ".idea", ".vscode",
        "vendor", "coverage", ".cache", ".parcel-cache",
    ]

    static func search(query: String, in projectPath: String) async -> [ProjectSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }

        if await isGitRepository(projectPath: projectPath) {
            return await runGitGrep(query: trimmed, projectPath: projectPath)
        }
        return await runGrep(query: trimmed, projectPath: projectPath)
    }

    private static func isGitRepository(projectPath: String) async -> Bool {
        let dotGit = (projectPath as NSString).appendingPathComponent(".git")
        return FileManager.default.fileExists(atPath: dotGit)
    }

    private static func runGitGrep(query: String, projectPath: String) async -> [ProjectSearchResult] {
        let arguments = [
            "git", "-C", projectPath, "grep",
            "--line-number", "--column", "-I",
            "--no-color", "--untracked",
            "--fixed-strings", "-e", query,
        ]
        return await run(
            executable: "/usr/bin/env",
            arguments: arguments,
            projectPath: projectPath,
            parser: { parseGitGrepLine($0, projectPath: projectPath) }
        )
    }

    private static func runGrep(query: String, projectPath: String) async -> [ProjectSearchResult] {
        var arguments: [String] = ["grep", "-rIn", "--line-buffered", "--color=never"]
        for name in prunedDirectoryNames {
            arguments.append("--exclude-dir=\(name)")
        }
        arguments.append("--fixed-strings")
        arguments.append("-e")
        arguments.append(query)
        arguments.append(projectPath)
        return await run(
            executable: "/usr/bin/env",
            arguments: arguments,
            projectPath: projectPath,
            parser: { parseGrepLine($0, projectPath: projectPath) }
        )
    }

    private static func run(
        executable: String,
        arguments: [String],
        projectPath: String,
        parser: @escaping @Sendable (String) -> ProjectSearchResult?
    ) async -> [ProjectSearchResult] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let box = ResultsBox(parser: parser, projectPath: projectPath)
            let handle = stdoutPipe.fileHandleForReading

            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if data.isEmpty { return }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                if box.append(chunk: chunk) {
                    if process.isRunning { process.terminate() }
                }
            }

            process.terminationHandler = { _ in
                handle.readabilityHandler = nil
                if let remaining = try? handle.readToEnd(), let chunk = String(data: remaining, encoding: .utf8) {
                    _ = box.append(chunk: chunk)
                }
                continuation.resume(returning: box.take())
            }

            do {
                try process.run()
            } catch {
                handle.readabilityHandler = nil
                continuation.resume(returning: [])
            }
        }
    }

    private static func parseGitGrepLine(_ line: String, projectPath: String) -> ProjectSearchResult? {
        let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let relativePath = String(parts[0])
        guard let lineNumber = Int(parts[1]), let columnNumber = Int(parts[2]) else { return nil }
        let matchText = String(parts[3])
        let absolute = absolutePath(of: relativePath, projectPath: projectPath)
        return ProjectSearchResult(
            id: "\(relativePath):\(lineNumber):\(columnNumber)",
            relativePath: relativePath,
            absolutePath: absolute,
            lineNumber: lineNumber,
            columnNumber: columnNumber,
            matchText: matchText
        )
    }

    private static func absolutePath(of relative: String, projectPath: String) -> String {
        if relative.hasPrefix("/") { return relative }
        let base = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
        return base + relative
    }

    private static func parseGrepLine(_ line: String, projectPath: String) -> ProjectSearchResult? {
        let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let absolute = String(parts[0])
        guard let lineNumber = Int(parts[1]) else { return nil }
        let matchText = String(parts[2])
        let relative = relativePath(of: absolute, projectPath: projectPath)
        return ProjectSearchResult(
            id: "\(relative):\(lineNumber)",
            relativePath: relative,
            absolutePath: absolute,
            lineNumber: lineNumber,
            columnNumber: 1,
            matchText: matchText
        )
    }

    private static func relativePath(of absolute: String, projectPath: String) -> String {
        let prefix = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
        if absolute.hasPrefix(prefix) {
            return String(absolute.dropFirst(prefix.count))
        }
        return absolute
    }
}

private final class ResultsBox: @unchecked Sendable {
    private var buffer = ""
    private var results: [ProjectSearchResult] = []
    private let parser: @Sendable (String) -> ProjectSearchResult?
    private let projectPath: String

    init(parser: @escaping @Sendable (String) -> ProjectSearchResult?, projectPath: String) {
        self.parser = parser
        self.projectPath = projectPath
    }

    func append(chunk: String) -> Bool {
        buffer += chunk
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound])
            buffer.removeSubrange(buffer.startIndex ..< newlineRange.upperBound)
            if let result = parser(line) {
                results.append(result)
                if results.count >= ProjectSearchService.maxResults {
                    return true
                }
            }
        }
        return false
    }

    func take() -> [ProjectSearchResult] {
        if !buffer.isEmpty, let result = parser(buffer) {
            results.append(result)
        }
        return results
    }
}


enum ProjectSearchServiceTestHooks {
    static func parseGitGrepLine(_ line: String, projectPath: String = "") -> ProjectSearchResult? {
        ProjectSearchService.parseGitGrepLineForTesting(line, projectPath: projectPath)
    }

    static func parseGrepLine(_ line: String, projectPath: String) -> ProjectSearchResult? {
        ProjectSearchService.parseGrepLineForTesting(line, projectPath: projectPath)
    }
}

extension ProjectSearchService {
    static func parseGitGrepLineForTesting(_ line: String, projectPath: String = "") -> ProjectSearchResult? {
        parseGitGrepLine(line, projectPath: projectPath)
    }

    static func parseGrepLineForTesting(_ line: String, projectPath: String) -> ProjectSearchResult? {
        parseGrepLine(line, projectPath: projectPath)
    }
}
