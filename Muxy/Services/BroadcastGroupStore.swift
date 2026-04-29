import Foundation

@MainActor
@Observable
final class BroadcastGroupStore {
    static let shared = BroadcastGroupStore()

    private(set) var activePaneIDs: Set<UUID> = []
    @ObservationIgnored private var replaying = false

    private init() {}

    var isActive: Bool { activePaneIDs.count >= 2 }

    var paneCount: Int { activePaneIDs.count }

    func isBroadcasting(_ paneID: UUID) -> Bool {
        activePaneIDs.contains(paneID)
    }

    func toggle(_ paneID: UUID) {
        if activePaneIDs.contains(paneID) {
            activePaneIDs.remove(paneID)
        } else {
            activePaneIDs.insert(paneID)
        }
    }

    func add(_ paneID: UUID) {
        activePaneIDs.insert(paneID)
    }

    func remove(_ paneID: UUID) {
        activePaneIDs.remove(paneID)
    }

    func clear() {
        activePaneIDs.removeAll()
    }

    func receivers(excluding senderPaneID: UUID) -> [UUID] {
        guard isActive, activePaneIDs.contains(senderPaneID), !replaying else { return [] }
        return Array(activePaneIDs.subtracting([senderPaneID]))
    }

    func performReplay(_ work: () -> Void) {
        guard !replaying else { return }
        replaying = true
        work()
        replaying = false
    }
}
