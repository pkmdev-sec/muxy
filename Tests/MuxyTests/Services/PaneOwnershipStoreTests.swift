import Foundation
import MuxyShared
import Testing

@testable import Muxy

@Suite("PaneOwnershipStore")
@MainActor
struct PaneOwnershipStoreTests {
    @Test("remove purges owner and reverse index for a remote pane")
    func removePurgesRemoteEntry() {
        let store = PaneOwnershipStore.shared
        let clientID = UUID()
        let paneID = UUID()
        var events: [(UUID, PaneOwnerDTO)] = []
        let previousHandler = store.onOwnershipChanged
        store.onOwnershipChanged = { events.append(($0, $1)) }
        defer { store.onOwnershipChanged = previousHandler }

        store.registerDevice(clientID: clientID, name: "iPhone")
        store.assign(paneID: paneID, to: clientID)
        #expect(store.remoteOwner(for: paneID) == clientID)

        store.remove(paneID: paneID)

        #expect(store.isOwnedByMac(paneID))
        #expect(store.remoteOwner(for: paneID) == nil)
        #expect(events.last?.0 == paneID)
        if case .mac = events.last?.1 { } else {
            Issue.record("expected final event to be mac ownership")
        }
    }

    @Test("remove is a no-op for panes never assigned to a remote")
    func removeIsNoopForMacPane() {
        let store = PaneOwnershipStore.shared
        let paneID = UUID()
        var fired = false
        let previousHandler = store.onOwnershipChanged
        store.onOwnershipChanged = { _, _ in fired = true }
        defer { store.onOwnershipChanged = previousHandler }

        store.remove(paneID: paneID)

        #expect(!fired)
        #expect(store.isOwnedByMac(paneID))
    }
}
