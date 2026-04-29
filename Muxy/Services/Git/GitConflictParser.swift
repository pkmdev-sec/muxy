import Foundation

enum GitConflictMarker: Equatable {
    case standard
    case diff3
}

struct GitConflictRegion: Equatable {
    let startLineIndex: Int
    let endLineIndex: Int
    let oursLines: [String]
    let theirsLines: [String]
    let baseLines: [String]?
    let oursLabel: String
    let theirsLabel: String
    let marker: GitConflictMarker

    var containsBaseSection: Bool { baseLines != nil }
}

enum GitConflictResolutionChoice: Equatable {
    case keepOurs
    case keepTheirs
    case keepBoth
    case keepBothReversed
    case custom(replacementLines: [String])
}

enum GitConflictParser {
    private static let headPrefix = "<<<<<<<"
    private static let basePrefix = "|||||||"
    private static let middleMarker = "======="
    private static let tailPrefix = ">>>>>>>"

    static func parse(_ contents: String) -> [GitConflictRegion] {
        let lines = splitPreservingTrailingEmpty(contents)
        var regions: [GitConflictRegion] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix(headPrefix) else {
                index += 1
                continue
            }

            guard let region = parseRegion(startingAt: index, lines: lines) else {
                index += 1
                continue
            }
            regions.append(region)
            index = region.endLineIndex + 1
        }

        return regions
    }

    static func applyResolution(
        _ choice: GitConflictResolutionChoice,
        to contents: String,
        region: GitConflictRegion
    ) -> String? {
        var lines = splitPreservingTrailingEmpty(contents)
        guard region.startLineIndex <= region.endLineIndex,
              region.endLineIndex < lines.count
        else { return nil }

        let replacement = replacementLines(for: choice, region: region)
        let range = region.startLineIndex ... region.endLineIndex
        lines.replaceSubrange(range, with: replacement)
        return joinPreservingTrailingEmpty(lines)
    }

    private static func parseRegion(startingAt start: Int, lines: [String]) -> GitConflictRegion? {
        let headLine = lines[start]
        let oursLabel = extractLabel(from: headLine, prefix: headPrefix)

        var cursor = start + 1
        var oursLines: [String] = []
        var baseLines: [String]?
        var theirsLines: [String] = []
        var marker: GitConflictMarker = .standard
        var inOurs = true
        var inBase = false

        while cursor < lines.count {
            let line = lines[cursor]

            if line.hasPrefix(headPrefix) {
                return nil
            }

            if line.hasPrefix(basePrefix) {
                guard inOurs, baseLines == nil else { return nil }
                inOurs = false
                inBase = true
                baseLines = []
                marker = .diff3
                cursor += 1
                continue
            }

            if line == middleMarker {
                guard inOurs || inBase else { return nil }
                inOurs = false
                inBase = false
                cursor += 1
                continue
            }

            if line.hasPrefix(tailPrefix) {
                let theirsLabel = extractLabel(from: line, prefix: tailPrefix)
                return GitConflictRegion(
                    startLineIndex: start,
                    endLineIndex: cursor,
                    oursLines: oursLines,
                    theirsLines: theirsLines,
                    baseLines: baseLines,
                    oursLabel: oursLabel,
                    theirsLabel: theirsLabel,
                    marker: marker
                )
            }

            if inOurs {
                oursLines.append(line)
            } else if inBase {
                baseLines?.append(line)
            } else {
                theirsLines.append(line)
            }
            cursor += 1
        }

        return nil
    }

    private static func extractLabel(from line: String, prefix: String) -> String {
        guard line.count > prefix.count else { return "" }
        let remainder = line.dropFirst(prefix.count)
        return remainder.trimmingCharacters(in: .whitespaces)
    }

    private static func replacementLines(
        for choice: GitConflictResolutionChoice,
        region: GitConflictRegion
    ) -> [String] {
        switch choice {
        case .keepOurs: region.oursLines
        case .keepTheirs: region.theirsLines
        case .keepBoth: region.oursLines + region.theirsLines
        case .keepBothReversed: region.theirsLines + region.oursLines
        case let .custom(replacementLines): replacementLines
        }
    }

    private static func splitPreservingTrailingEmpty(_ contents: String) -> [String] {
        contents.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }).map(String.init)
    }

    private static func joinPreservingTrailingEmpty(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }
}
