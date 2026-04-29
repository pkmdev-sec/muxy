import Foundation
import Testing

@testable import Muxy

@Suite("GitGraphLayout")
struct GitGraphLayoutTests {
    private func commit(hash: String, parents: [String] = [], subject: String = "") -> GitCommit {
        GitCommit(
            hash: hash,
            shortHash: String(hash.prefix(7)),
            subject: subject,
            authorName: "a",
            authorDate: Date(),
            refs: [],
            parentHashes: parents
        )
    }

    @Test("single commit sits on column 0")
    func single() {
        let rows = GitGraphLayout.layout(commits: [commit(hash: "a")])
        #expect(rows.count == 1)
        #expect(rows[0].column == 0)
        #expect(rows[0].parentColumns.isEmpty)
    }

    @Test("linear history keeps all commits on column 0")
    func linear() {
        let commits = [
            commit(hash: "c", parents: ["b"]),
            commit(hash: "b", parents: ["a"]),
            commit(hash: "a"),
        ]
        let rows = GitGraphLayout.layout(commits: commits)
        #expect(rows.allSatisfy { $0.column == 0 })
    }

    @Test("merge commit introduces parallel column")
    func merge() {
        let commits = [
            commit(hash: "d", parents: ["b", "c"]),
            commit(hash: "c", parents: ["a"]),
            commit(hash: "b", parents: ["a"]),
            commit(hash: "a"),
        ]
        let rows = GitGraphLayout.layout(commits: commits)
        let dRow = rows[0]
        #expect(dRow.column == 0)
        #expect(dRow.parentColumns.count == 2)
        let cRow = rows[1]
        let bRow = rows[2]
        #expect(cRow.column != bRow.column)
        let aRow = rows[3]
        #expect(aRow.column == cRow.parentColumns.first ?? 0 || aRow.column == bRow.parentColumns.first ?? 0)
    }

    @Test("branches running in parallel remain on distinct columns")
    func parallel() {
        let commits = [
            commit(hash: "b", parents: ["a"]),
            commit(hash: "x", parents: ["y"]),
            commit(hash: "a"),
            commit(hash: "y"),
        ]
        let rows = GitGraphLayout.layout(commits: commits)
        #expect(rows[0].column == 0)
        #expect(rows[1].column == 1)
    }
}
