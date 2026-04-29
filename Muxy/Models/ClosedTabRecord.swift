import Foundation

struct ClosedTabRecord: Identifiable, Sendable {
    enum Payload: Sendable {
        case terminal(workingDirectory: String)
        case editor(filePath: String)
        case vcs
    }

    let id = UUID()
    let projectID: UUID
    let worktreeID: UUID
    let areaID: UUID
    let payload: Payload
    let customTitle: String?
    let colorID: String?
    let isPinned: Bool
    let closedAt: Date

    init(
        projectID: UUID,
        worktreeID: UUID,
        areaID: UUID,
        payload: Payload,
        customTitle: String? = nil,
        colorID: String? = nil,
        isPinned: Bool = false,
        closedAt: Date = Date()
    ) {
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.areaID = areaID
        self.payload = payload
        self.customTitle = customTitle
        self.colorID = colorID
        self.isPinned = isPinned
        self.closedAt = closedAt
    }
}

@MainActor
final class ClosedTabHistory {
    private let limit: Int
    private var records: [ClosedTabRecord] = []

    init(limit: Int = 20) {
        self.limit = limit
    }

    var isEmpty: Bool { records.isEmpty }

    func push(_ record: ClosedTabRecord) {
        records.append(record)
        if records.count > limit {
            records.removeFirst(records.count - limit)
        }
    }

    func pop() -> ClosedTabRecord? {
        records.popLast()
    }

    func peek() -> ClosedTabRecord? {
        records.last
    }

    func clear() {
        records.removeAll()
    }

    func clearEntriesForProject(_ projectID: UUID) {
        records.removeAll { $0.projectID == projectID }
    }
}
