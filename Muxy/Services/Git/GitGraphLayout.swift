import Foundation

struct GitGraphLayoutRow: Equatable, Sendable {
    let commitIndex: Int
    let column: Int
    let parentColumns: [Int]
    let activeColumnsAfter: [String?]
}

enum GitGraphLayout {
    static func layout(commits: [GitCommit]) -> [GitGraphLayoutRow] {
        guard !commits.isEmpty else { return [] }
        var rows: [GitGraphLayoutRow] = []
        var columns: [String?] = []

        for (index, commit) in commits.enumerated() {
            let column = reserveColumn(for: commit.hash, in: &columns)
            columns[column] = nil
            let parentColumns = placeParents(
                parents: commit.parentHashes,
                preferredColumn: column,
                columns: &columns
            )
            rows.append(GitGraphLayoutRow(
                commitIndex: index,
                column: column,
                parentColumns: parentColumns,
                activeColumnsAfter: columns
            ))
        }
        return rows
    }

    private static func reserveColumn(for hash: String, in columns: inout [String?]) -> Int {
        if let index = columns.firstIndex(of: hash) {
            return index
        }
        if let firstEmpty = columns.firstIndex(of: nil) {
            columns[firstEmpty] = hash
            return firstEmpty
        }
        columns.append(hash)
        return columns.count - 1
    }

    private static func placeParents(
        parents: [String],
        preferredColumn: Int,
        columns: inout [String?]
    ) -> [Int] {
        var out: [Int] = []
        for (offset, parent) in parents.enumerated() {
            if let existing = columns.firstIndex(of: parent) {
                out.append(existing)
                continue
            }
            if offset == 0 {
                columns[preferredColumn] = parent
                out.append(preferredColumn)
                continue
            }
            if let firstEmpty = columns.firstIndex(of: nil) {
                columns[firstEmpty] = parent
                out.append(firstEmpty)
                continue
            }
            columns.append(parent)
            out.append(columns.count - 1)
        }
        return out
    }
}
