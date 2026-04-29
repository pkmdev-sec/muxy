import Foundation

struct GitStashEntry: Identifiable, Equatable, Sendable {
    let slot: String
    let hash: String
    let message: String

    var id: String { slot }

    var branchHint: String? {
        let prefix = "On "
        guard message.hasPrefix(prefix) else { return nil }
        let trimmed = message.dropFirst(prefix.count)
        guard let separator = trimmed.firstIndex(of: ":") else { return nil }
        return String(trimmed[..<separator])
    }

    var trailingMessage: String {
        if let prefixRange = message.range(of: "^On [^:]+: ", options: .regularExpression) {
            return String(message[prefixRange.upperBound...])
        }
        if let colonIdx = message.firstIndex(of: ":") {
            return String(message[message.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        }
        return message
    }
}

enum GitStashParser {
    static func parseList(_ output: String) -> [GitStashEntry] {
        guard !output.isEmpty else { return [] }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        var entries: [GitStashEntry] = []
        for line in lines {
            let components = line.split(separator: "\0", maxSplits: 2, omittingEmptySubsequences: false)
            guard components.count == 3 else { continue }
            let slot = String(components[0])
            let hash = String(components[1])
            let message = String(components[2])
            guard !slot.isEmpty else { continue }
            entries.append(GitStashEntry(slot: slot, hash: hash, message: message))
        }
        return entries
    }
}
