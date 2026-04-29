import Foundation

struct ProjectReplaceOutcome: Equatable, Sendable {
    let filesChanged: Int
    let occurrencesReplaced: Int
    let failures: [String]
}

enum ProjectReplaceService {
    static func replace(
        query: String,
        replacement: String,
        in results: [ProjectSearchResult]
    ) async -> ProjectReplaceOutcome {
        guard !query.isEmpty else {
            return ProjectReplaceOutcome(filesChanged: 0, occurrencesReplaced: 0, failures: [])
        }

        let groupedByFile = Dictionary(grouping: results, by: { $0.absolutePath })

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = performReplace(
                    query: query,
                    replacement: replacement,
                    groupedByFile: groupedByFile
                )
                continuation.resume(returning: outcome)
            }
        }
    }

    static func rewriteContents(_ contents: String, query: String, replacement: String) -> (String, Int) {
        guard !query.isEmpty, contents.contains(query) else { return (contents, 0) }
        var occurrences = 0
        var cursor = contents.startIndex
        var output = ""
        while let range = contents.range(of: query, range: cursor ..< contents.endIndex) {
            output += contents[cursor ..< range.lowerBound]
            output += replacement
            occurrences += 1
            cursor = range.upperBound
        }
        output += contents[cursor ..< contents.endIndex]
        return (output, occurrences)
    }

    private static func performReplace(
        query: String,
        replacement: String,
        groupedByFile: [String: [ProjectSearchResult]]
    ) -> ProjectReplaceOutcome {
        var filesChanged = 0
        var occurrencesReplaced = 0
        var failures: [String] = []

        for absolutePath in groupedByFile.keys.sorted() {
            do {
                let contents = try String(contentsOfFile: absolutePath, encoding: .utf8)
                let (rewritten, count) = rewriteContents(contents, query: query, replacement: replacement)
                guard count > 0, rewritten != contents else { continue }
                try rewritten.write(toFile: absolutePath, atomically: true, encoding: .utf8)
                filesChanged += 1
                occurrencesReplaced += count
            } catch {
                failures.append(absolutePath)
            }
        }

        return ProjectReplaceOutcome(
            filesChanged: filesChanged,
            occurrencesReplaced: occurrencesReplaced,
            failures: failures
        )
    }
}
