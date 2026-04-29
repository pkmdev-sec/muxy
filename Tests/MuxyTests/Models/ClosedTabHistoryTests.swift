import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("ClosedTabHistory")
struct ClosedTabHistoryTests {
    private func makeRecord(
        projectID: UUID = UUID(),
        tag: String = "t"
    ) -> ClosedTabRecord {
        ClosedTabRecord(
            projectID: projectID,
            worktreeID: UUID(),
            areaID: UUID(),
            payload: .terminal(workingDirectory: "/tmp/\(tag)")
        )
    }

    @Test("push then pop returns the same record")
    func pushPop() {
        let history = ClosedTabHistory()
        let record = makeRecord(tag: "a")
        history.push(record)
        #expect(history.pop()?.id == record.id)
        #expect(history.isEmpty)
    }

    @Test("pop returns most recent first (LIFO)")
    func lifoOrder() {
        let history = ClosedTabHistory()
        let first = makeRecord(tag: "first")
        let second = makeRecord(tag: "second")
        let third = makeRecord(tag: "third")
        history.push(first)
        history.push(second)
        history.push(third)
        #expect(history.pop()?.id == third.id)
        #expect(history.pop()?.id == second.id)
        #expect(history.pop()?.id == first.id)
        #expect(history.pop() == nil)
    }

    @Test("limit evicts oldest entries")
    func limitEvicts() {
        let history = ClosedTabHistory(limit: 3)
        let r1 = makeRecord(tag: "1")
        let r2 = makeRecord(tag: "2")
        let r3 = makeRecord(tag: "3")
        let r4 = makeRecord(tag: "4")
        history.push(r1)
        history.push(r2)
        history.push(r3)
        history.push(r4)
        #expect(history.pop()?.id == r4.id)
        #expect(history.pop()?.id == r3.id)
        #expect(history.pop()?.id == r2.id)
        #expect(history.pop() == nil)
    }

    @Test("clearEntriesForProject removes only matching records")
    func clearByProject() {
        let history = ClosedTabHistory()
        let projectA = UUID()
        let projectB = UUID()
        history.push(makeRecord(projectID: projectA, tag: "a1"))
        history.push(makeRecord(projectID: projectB, tag: "b"))
        history.push(makeRecord(projectID: projectA, tag: "a2"))
        history.clearEntriesForProject(projectA)
        let remaining = history.pop()
        #expect(remaining?.projectID == projectB)
        #expect(history.isEmpty)
    }

    @Test("peek does not remove the record")
    func peekNonDestructive() {
        let history = ClosedTabHistory()
        let r = makeRecord(tag: "p")
        history.push(r)
        #expect(history.peek()?.id == r.id)
        #expect(history.peek()?.id == r.id)
        #expect(history.pop()?.id == r.id)
        #expect(history.isEmpty)
    }
}
