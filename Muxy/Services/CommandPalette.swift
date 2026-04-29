import Foundation

enum PaletteCommandGroup: String, Codable, CaseIterable, Sendable {
    case action
    case navigation
    case theme
    case ai
    case settings

    var displayName: String {
        switch self {
        case .action: "Action"
        case .navigation: "Navigation"
        case .theme: "Theme"
        case .ai: "AI Usage"
        case .settings: "Settings"
        }
    }

    var sortWeight: Int {
        switch self {
        case .action: 0
        case .navigation: 1
        case .theme: 2
        case .ai: 3
        case .settings: 4
        }
    }
}

struct PaletteCommand: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let group: PaletteCommandGroup
    let shortcut: KeyCombo?
    let run: @MainActor @Sendable () -> Void
}

@MainActor
protocol PaletteCommandSource {
    func commands() -> [PaletteCommand]
}

struct PaletteCommandMatch: Identifiable, Sendable {
    let command: PaletteCommand
    let score: Int
    let titleRanges: [Range<String.Index>]
    var id: String { command.id }
}

enum PaletteFuzzyMatcher {
    static func score(query: String, candidate: PaletteCommand) -> PaletteCommandMatch? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return PaletteCommandMatch(command: candidate, score: 0, titleRanges: [])
        }

        if let (titleScore, ranges) = fuzzy(query: trimmed, in: candidate.title) {
            return PaletteCommandMatch(
                command: candidate,
                score: titleScore + 1000,
                titleRanges: ranges
            )
        }

        if let subtitle = candidate.subtitle,
           let (subtitleScore, _) = fuzzy(query: trimmed, in: subtitle)
        {
            return PaletteCommandMatch(command: candidate, score: subtitleScore, titleRanges: [])
        }

        return nil
    }

    private static func fuzzy(query: String, in text: String) -> (Int, [Range<String.Index>])? {
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()

        if let range = lowerText.range(of: lowerQuery) {
            let startOffset = lowerText.distance(from: lowerText.startIndex, to: range.lowerBound)
            let lengthBonus = max(0, 50 - text.count)
            var score = 500 - startOffset + lengthBonus
            if startOffset == 0 || lowerText[lowerText.index(before: range.lowerBound)] == " " {
                score += 200
            }
            let mapped = mapRange(from: lowerText, to: text, range: range)
            return (score, [mapped])
        }

        var queryIndex = lowerQuery.startIndex
        var ranges: [Range<String.Index>] = []
        var score = 0
        var previousIndex: String.Index?
        var rangeStart: String.Index?

        for index in lowerText.indices {
            guard queryIndex < lowerQuery.endIndex else { break }
            if lowerText[index] == lowerQuery[queryIndex] {
                score += 10
                if let previous = previousIndex,
                   lowerText.index(after: previous) == index
                {
                    score += 15
                } else {
                    if let start = rangeStart, let end = previousIndex {
                        ranges.append(start ..< lowerText.index(after: end))
                    }
                    rangeStart = index
                }
                if index == lowerText.startIndex {
                    score += 100
                } else if lowerText[lowerText.index(before: index)] == " " {
                    score += 50
                }
                previousIndex = index
                queryIndex = lowerQuery.index(after: queryIndex)
            }
        }

        guard queryIndex == lowerQuery.endIndex else { return nil }

        if let start = rangeStart, let end = previousIndex {
            ranges.append(start ..< lowerText.index(after: end))
        }

        let mappedRanges = ranges.map { mapRange(from: lowerText, to: text, range: $0) }
        return (score - text.count, mappedRanges)
    }

    private static func mapRange(
        from lower: String,
        to original: String,
        range: Range<String.Index>
    ) -> Range<String.Index> {
        let lowerStartOffset = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let lowerEndOffset = lower.distance(from: lower.startIndex, to: range.upperBound)
        let start = original.index(original.startIndex, offsetBy: lowerStartOffset)
        let end = original.index(original.startIndex, offsetBy: lowerEndOffset)
        return start ..< end
    }
}

@MainActor
final class PaletteRecentsStore {
    static let shared = PaletteRecentsStore()

    private let key = "muxy.palette.recents"
    private let limit = 12

    func recent() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func bump(_ id: String) {
        var recents = recent().filter { $0 != id }
        recents.insert(id, at: 0)
        if recents.count > limit {
            recents = Array(recents.prefix(limit))
        }
        UserDefaults.standard.set(recents, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@MainActor
struct CommandPalette {
    let sources: [PaletteCommandSource]
    private let recents: PaletteRecentsStore

    init(sources: [PaletteCommandSource], recents: PaletteRecentsStore = .shared) {
        self.sources = sources
        self.recents = recents
    }

    func matches(for query: String) -> [PaletteCommandMatch] {
        var seen: Set<String> = []
        var commands: [PaletteCommand] = []
        for source in sources {
            for command in source.commands() where !seen.contains(command.id) {
                seen.insert(command.id)
                commands.append(command)
            }
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return emptyQueryRanking(commands)
        }

        let matched = commands.compactMap { PaletteFuzzyMatcher.score(query: trimmed, candidate: $0) }
        return matched.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.command.group != rhs.command.group {
                return lhs.command.group.sortWeight < rhs.command.group.sortWeight
            }
            return lhs.command.title.localizedCompare(rhs.command.title) == .orderedAscending
        }
    }

    private func emptyQueryRanking(_ commands: [PaletteCommand]) -> [PaletteCommandMatch] {
        let recentIDs = recents.recent()
        let recentRank = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($0.element, $0.offset) })

        let sorted = commands.sorted { lhs, rhs in
            let lRecent = recentRank[lhs.id]
            let rRecent = recentRank[rhs.id]
            switch (lRecent, rRecent) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                if lhs.group != rhs.group {
                    return lhs.group.sortWeight < rhs.group.sortWeight
                }
                return lhs.title.localizedCompare(rhs.title) == .orderedAscending
            }
        }

        return sorted.map { PaletteCommandMatch(command: $0, score: 0, titleRanges: []) }
    }

    func run(_ command: PaletteCommand) {
        recents.bump(command.id)
        command.run()
    }
}
