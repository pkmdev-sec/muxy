import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("BroadcastGroupStore")
struct BroadcastGroupStoreTests {
    private func freshStore() -> BroadcastGroupStore {
        BroadcastGroupStore.shared.clear()
        return BroadcastGroupStore.shared
    }

    @Test("isActive requires at least two panes")
    func isActiveMinimumTwo() {
        let store = freshStore()
        let a = UUID()
        store.add(a)
        #expect(!store.isActive)
        store.add(UUID())
        #expect(store.isActive)
    }

    @Test("toggle adds then removes")
    func toggleRoundTrip() {
        let store = freshStore()
        let id = UUID()
        store.toggle(id)
        #expect(store.isBroadcasting(id))
        store.toggle(id)
        #expect(!store.isBroadcasting(id))
    }

    @Test("receivers excludes the sender and is empty below two panes")
    func receiversExcludeSender() {
        let store = freshStore()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        store.add(a)
        store.add(b)
        store.add(c)
        let fromA = store.receivers(excluding: a)
        #expect(Set(fromA) == [b, c])

        let loneStore = freshStore()
        loneStore.add(a)
        #expect(loneStore.receivers(excluding: a).isEmpty)
    }

    @Test("receivers is empty if sender is not a member")
    func receiversRequireMembership() {
        let store = freshStore()
        let a = UUID()
        let b = UUID()
        store.add(a)
        store.add(b)
        #expect(store.receivers(excluding: UUID()).isEmpty)
    }

    @Test("performReplay suppresses nested fan-out")
    func performReplaySuppresses() {
        let store = freshStore()
        let a = UUID()
        let b = UUID()
        store.add(a)
        store.add(b)
        var outer = store.receivers(excluding: a)
        #expect(outer.count == 1)
        store.performReplay {
            outer = store.receivers(excluding: a)
        }
        #expect(outer.isEmpty)
    }

    @Test("clear empties the group")
    func clearEmpties() {
        let store = freshStore()
        store.add(UUID())
        store.add(UUID())
        store.clear()
        #expect(!store.isActive)
        #expect(store.paneCount == 0)
    }
}
