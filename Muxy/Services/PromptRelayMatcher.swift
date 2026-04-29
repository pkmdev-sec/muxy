import Foundation

struct PromptRelayMatch: Equatable, Sendable {
    let target: String
    let body: String
    let replyChannel: String?
}

final class PromptRelayMatcher: @unchecked Sendable {
    private var buffer: String = ""
    private let maxBufferBytes: Int = 32 * 1024

    func ingest(_ data: Data) -> [PromptRelayMatch] {
        guard let chunk = String(data: data, encoding: .utf8) else { return [] }
        buffer += chunk
        if buffer.count > maxBufferBytes {
            buffer = String(buffer.suffix(maxBufferBytes))
        }
        return drainMatches()
    }

    func reset() {
        buffer = ""
    }

    private func drainMatches() -> [PromptRelayMatch] {
        var results: [PromptRelayMatch] = []
        while let match = extractFirstMatch() {
            results.append(match.payload)
            buffer.removeSubrange(match.range)
        }
        return results
    }

    private struct ExtractedMatch {
        let payload: PromptRelayMatch
        let range: Range<String.Index>
    }

    private func extractFirstMatch() -> ExtractedMatch? {
        let openTag = "<muxy:ask"
        let closeTag = "</muxy:ask>"
        guard let openStart = buffer.range(of: openTag) else { return nil }
        guard let openEnd = buffer.range(of: ">", range: openStart.upperBound ..< buffer.endIndex) else { return nil }
        guard let closeRange = buffer.range(of: closeTag, range: openEnd.upperBound ..< buffer.endIndex) else {
            return nil
        }
        let attributeSegment = String(buffer[openStart.upperBound ..< openEnd.lowerBound])
        let body = String(buffer[openEnd.upperBound ..< closeRange.lowerBound])
        let attributes = parseAttributes(attributeSegment)
        guard let target = attributes["target"], !target.isEmpty else {
            return ExtractedMatch(
                payload: PromptRelayMatch(target: "", body: body, replyChannel: nil),
                range: openStart.lowerBound ..< closeRange.upperBound
            )
        }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExtractedMatch(
            payload: PromptRelayMatch(
                target: target,
                body: trimmedBody,
                replyChannel: attributes["reply"]
            ),
            range: openStart.lowerBound ..< closeRange.upperBound
        )
    }

    private func parseAttributes(_ segment: String) -> [String: String] {
        var results: [String: String] = [:]
        var index = segment.startIndex
        while index < segment.endIndex {
            while index < segment.endIndex, segment[index].isWhitespace {
                index = segment.index(after: index)
            }
            guard index < segment.endIndex else { break }
            let nameStart = index
            while index < segment.endIndex, segment[index] != "=", !segment[index].isWhitespace {
                index = segment.index(after: index)
            }
            let name = String(segment[nameStart ..< index]).trimmingCharacters(in: .whitespaces)
            guard index < segment.endIndex, segment[index] == "=" else { break }
            index = segment.index(after: index)
            guard index < segment.endIndex, segment[index] == "\"" else { break }
            index = segment.index(after: index)
            let valueStart = index
            while index < segment.endIndex, segment[index] != "\"" {
                index = segment.index(after: index)
            }
            let value = String(segment[valueStart ..< index])
            if !name.isEmpty {
                results[name] = value
            }
            if index < segment.endIndex {
                index = segment.index(after: index)
            }
        }
        return results
    }
}
