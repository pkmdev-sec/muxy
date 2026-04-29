import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("TerminalOutputBus.subscribe/dispatch")
struct TerminalOutputBusTests {
    @Test("subscribers receive dispatched bytes with monotonic seq")
    func dispatchesBytes() {
        let bus = TerminalOutputBus.shared
        let paneID = UUID()
        var received: [(Data, UInt64)] = []
        let sub = bus.subscribe(paneID: paneID) { data, seq in
            received.append((data, seq))
        }
        bus.testingInject(paneID: paneID, bytes: Data([0x41, 0x42]))
        bus.testingInject(paneID: paneID, bytes: Data([0x43]))
        bus.unsubscribe(sub)
        #expect(received.count == 2)
        #expect(received[0].1 == 2)
        #expect(received[1].1 == 3)
    }

    @Test("unsubscribe removes handler")
    func unsubscribes() {
        let bus = TerminalOutputBus.shared
        let paneID = UUID()
        var count = 0
        let sub = bus.subscribe(paneID: paneID) { _, _ in count += 1 }
        bus.testingInject(paneID: paneID, bytes: Data([0x01]))
        bus.unsubscribe(sub)
        bus.testingInject(paneID: paneID, bytes: Data([0x02]))
        #expect(count == 1)
    }

    @Test("multiple subscribers all receive each byte batch")
    func multipleSubscribers() {
        let bus = TerminalOutputBus.shared
        let paneID = UUID()
        var a = 0
        var b = 0
        let s1 = bus.subscribe(paneID: paneID) { _, _ in a += 1 }
        let s2 = bus.subscribe(paneID: paneID) { _, _ in b += 1 }
        bus.testingInject(paneID: paneID, bytes: Data([0x10]))
        bus.unsubscribe(s1)
        bus.unsubscribe(s2)
        #expect(a == 1)
        #expect(b == 1)
    }

    @Test("currentSeq reflects cumulative bytes")
    func currentSeq() {
        let bus = TerminalOutputBus.shared
        let paneID = UUID()
        _ = bus.subscribe(paneID: paneID) { _, _ in }
        bus.testingInject(paneID: paneID, bytes: Data([0x1, 0x2, 0x3]))
        #expect(bus.currentSeq(paneID: paneID) >= 3)
    }
}

@MainActor
@Suite("TerminalScrollbackStore")
struct TerminalScrollbackStoreTests {
    @Test("addCheckpoint creates entry tied to current seq")
    func addCheckpoint() {
        let store = TerminalScrollbackStore.shared
        store.clearAll()
        let paneID = UUID()
        store.ensureSubscribed(paneID: paneID)
        TerminalOutputBus.shared.testingInject(paneID: paneID, bytes: Data([0x1, 0x2, 0x3, 0x4, 0x5]))
        let checkpoint = store.addCheckpoint(paneID: paneID, label: "First", projectID: nil)
        #expect(checkpoint != nil)
        #expect(checkpoint?.seq == 5)
        #expect(store.checkpoints(paneID: paneID).count == 1)
    }

    @Test("addCheckpoint rejects empty labels")
    func emptyLabelRejected() {
        let store = TerminalScrollbackStore.shared
        store.clearAll()
        let paneID = UUID()
        let result = store.addCheckpoint(paneID: paneID, label: "   ", projectID: nil)
        #expect(result == nil)
        #expect(store.checkpoints.isEmpty)
    }

    @Test("bytesSince returns data written after checkpoint")
    func bytesSince() {
        let store = TerminalScrollbackStore.shared
        store.clearAll()
        let paneID = UUID()
        store.ensureSubscribed(paneID: paneID)
        TerminalOutputBus.shared.testingInject(paneID: paneID, bytes: Data("before-".utf8))
        guard let cp = store.addCheckpoint(paneID: paneID, label: "M", projectID: nil) else {
            Issue.record("checkpoint should have created")
            return
        }
        TerminalOutputBus.shared.testingInject(paneID: paneID, bytes: Data("after".utf8))
        let since = store.bytesSince(cp)
        #expect(since == Data("after".utf8))
    }

    @Test("bytesBetween returns middle slice")
    func bytesBetween() {
        let store = TerminalScrollbackStore.shared
        store.clearAll()
        let paneID = UUID()
        store.ensureSubscribed(paneID: paneID)
        TerminalOutputBus.shared.testingInject(paneID: paneID, bytes: Data("one-".utf8))
        guard let a = store.addCheckpoint(paneID: paneID, label: "A", projectID: nil) else { return }
        TerminalOutputBus.shared.testingInject(paneID: paneID, bytes: Data("middle".utf8))
        guard let b = store.addCheckpoint(paneID: paneID, label: "B", projectID: nil) else { return }
        TerminalOutputBus.shared.testingInject(paneID: paneID, bytes: Data("-end".utf8))
        let slice = store.bytesBetween(a, b)
        #expect(slice == Data("middle".utf8))
    }

    @Test("clearCheckpoints removes pane-specific entries")
    func clearPane() {
        let store = TerminalScrollbackStore.shared
        store.clearAll()
        let p1 = UUID()
        let p2 = UUID()
        store.ensureSubscribed(paneID: p1)
        store.ensureSubscribed(paneID: p2)
        _ = store.addCheckpoint(paneID: p1, label: "x", projectID: nil)
        _ = store.addCheckpoint(paneID: p2, label: "y", projectID: nil)
        store.clearCheckpoints(paneID: p1)
        #expect(store.checkpoints(paneID: p1).isEmpty)
        #expect(store.checkpoints(paneID: p2).count == 1)
    }
}

@Suite("TerminalRingBuffer")
struct TerminalRingBufferTests {
    @Test("append then tail returns written bytes when under capacity")
    func underCapacity() {
        let buf = TerminalRingBuffer(capacity: 64)
        buf.append(Data([1, 2, 3, 4]))
        #expect(buf.tail(count: 4) == Data([1, 2, 3, 4]))
        #expect(buf.count == 4)
    }

    @Test("wraparound preserves most recent bytes")
    func wraparound() {
        let buf = TerminalRingBuffer(capacity: 4)
        buf.append(Data([1, 2, 3, 4, 5, 6]))
        #expect(buf.count == 4)
        #expect(buf.tail(count: 4) == Data([3, 4, 5, 6]))
    }

    @Test("slice with trailing offset returns middle region")
    func sliceMiddle() {
        let buf = TerminalRingBuffer(capacity: 16)
        buf.append(Data([1, 2, 3, 4, 5, 6, 7, 8]))
        let slice = buf.slice(trailingOffset: 2, count: 3)
        #expect(slice == Data([4, 5, 6]))
    }

    @Test("slice out of range returns nil")
    func sliceOutOfRange() {
        let buf = TerminalRingBuffer(capacity: 8)
        buf.append(Data([1, 2, 3]))
        let slice = buf.slice(trailingOffset: 0, count: 99)
        #expect(slice == nil)
    }
}
