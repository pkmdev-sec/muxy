import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "TextBackingStore")

@MainActor
final class TextBackingStore {
    private(set) var lines: [String] = [""]
    private var pendingTrailingFragment = ""

    var lineCount: Int { lines.count }

    func loadFromText(_ text: String) {
        let split = text.split(separator: "\n", omittingEmptySubsequences: false)
        lines = split.map(String.init)
        pendingTrailingFragment = ""
    }

    func appendText(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        let combined = pendingTrailingFragment + chunk
        let split = combined.split(separator: "\n", omittingEmptySubsequences: false)
        guard !split.isEmpty else { return }

        let mergeFragment = String(split[0])
        if !lines.isEmpty {
            lines[lines.count - 1] += mergeFragment
        } else {
            lines.append(mergeFragment)
        }

        if split.count > 1 {
            for i in 1 ..< split.count - 1 {
                lines.append(String(split[i]))
            }
            pendingTrailingFragment = String(split[split.count - 1])
            lines.append(pendingTrailingFragment)
        } else {
            pendingTrailingFragment = lines.last ?? ""
        }
    }

    func finishLoading() {
        pendingTrailingFragment = ""
    }

    func line(at index: Int) -> String {
        guard index >= 0, index < lines.count else { return "" }
        return lines[index]
    }

    func textForRange(_ range: Range<Int>) -> String {
        let clamped = max(0, range.lowerBound) ..< min(lines.count, range.upperBound)
        guard !clamped.isEmpty else { return "" }
        return lines[clamped].joined(separator: "\n")
    }

    func fullText() -> String {
        lines.joined(separator: "\n")
    }

    func replaceLines(in range: Range<Int>, with newLines: [String]) -> [String] {
        let clamped = max(0, range.lowerBound) ..< min(lines.count, range.upperBound)
        let old = Array(lines[clamped])
        lines.replaceSubrange(clamped, with: newLines)
        return old
    }

    struct SearchMatch {
        let lineIndex: Int
        let range: NSRange
    }

    struct SearchResult {
        let matches: [SearchMatch]
        let invalidRegex: Bool
    }

    func searchDetailed(needle: String, caseSensitive: Bool, useRegex: Bool) -> SearchResult {
        guard !needle.isEmpty else { return SearchResult(matches: [], invalidRegex: false) }
        var matches: [SearchMatch] = []

        if useRegex {
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if !caseSensitive { options.insert(.caseInsensitive) }
            guard let regex = try? NSRegularExpression(pattern: needle, options: options) else {
                return SearchResult(matches: [], invalidRegex: true)
            }

            for (lineIndex, line) in lines.enumerated() {
                let nsLine = line as NSString
                let lineRange = NSRange(location: 0, length: nsLine.length)
                regex.enumerateMatches(in: line, range: lineRange) { match, _, _ in
                    guard let match, match.range.length > 0 else { return }
                    matches.append(SearchMatch(lineIndex: lineIndex, range: match.range))
                }
            }
        } else {
            var options: NSString.CompareOptions = []
            if !caseSensitive { options.insert(.caseInsensitive) }

            for (lineIndex, line) in lines.enumerated() {
                let nsLine = line as NSString
                var searchRange = NSRange(location: 0, length: nsLine.length)
                while searchRange.location < nsLine.length {
                    let found = nsLine.range(of: needle, options: options, range: searchRange)
                    guard found.location != NSNotFound else { break }
                    matches.append(SearchMatch(lineIndex: lineIndex, range: found))
                    searchRange.location = found.location + found.length
                    searchRange.length = nsLine.length - searchRange.location
                }
            }
        }

        return SearchResult(matches: matches, invalidRegex: false)
    }

    func search(needle: String, caseSensitive: Bool, useRegex: Bool) -> [SearchMatch] {
        searchDetailed(needle: needle, caseSensitive: caseSensitive, useRegex: useRegex).matches
    }
}
