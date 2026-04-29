import Foundation
import os

private let scrollbackLogger = Logger(subsystem: "app.muxy", category: "TerminalScrollbackStore")

struct TerminalScrollbackCheckpoint: Identifiable, Sendable, Equatable {
    let id: UUID
    let paneID: UUID
    let projectID: UUID?
    let label: String
    let seq: UInt64
    let createdAt: Date

    init(
        id: UUID = UUID(),
        paneID: UUID,
        projectID: UUID?,
        label: String,
        seq: UInt64,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.paneID = paneID
        self.projectID = projectID
        self.label = label
        self.seq = seq
        self.createdAt = createdAt
    }
}

@MainActor
@Observable
final class TerminalScrollbackStore {
    static let shared = TerminalScrollbackStore()
    static let defaultCapacityBytes: Int = 4 * 1024 * 1024

    private(set) var checkpoints: [TerminalScrollbackCheckpoint] = []

    @ObservationIgnored private var buffers: [UUID: TerminalRingBuffer] = [:]
    @ObservationIgnored private var subscriptions: [UUID: TerminalOutputSubscription] = [:]
    private let capacity: Int

    init(capacityBytes: Int = TerminalScrollbackStore.defaultCapacityBytes) {
        capacity = capacityBytes
    }

    func ensureSubscribed(paneID: UUID) {
        if subscriptions[paneID] != nil { return }
        if buffers[paneID] == nil {
            buffers[paneID] = TerminalRingBuffer(capacity: capacity)
        }
        let sub = TerminalOutputBus.shared.subscribe(paneID: paneID) { [weak self] data, seq in
            self?.ingest(paneID: paneID, data: data, seq: seq)
        }
        subscriptions[paneID] = sub
    }

    func detach(paneID: UUID) {
        if let sub = subscriptions.removeValue(forKey: paneID) {
            TerminalOutputBus.shared.unsubscribe(sub)
        }
    }

    func bufferSize(paneID: UUID) -> Int {
        buffers[paneID]?.count ?? 0
    }

    func checkpoints(paneID: UUID) -> [TerminalScrollbackCheckpoint] {
        checkpoints.filter { $0.paneID == paneID }
    }

    @discardableResult
    func addCheckpoint(paneID: UUID, label: String, projectID: UUID?) -> TerminalScrollbackCheckpoint? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        ensureSubscribed(paneID: paneID)
        let seq = TerminalOutputBus.shared.currentSeq(paneID: paneID)
        let checkpoint = TerminalScrollbackCheckpoint(
            paneID: paneID,
            projectID: projectID,
            label: trimmed,
            seq: seq
        )
        checkpoints.append(checkpoint)
        return checkpoint
    }

    func removeCheckpoint(id: UUID) {
        checkpoints.removeAll { $0.id == id }
    }

    func clearCheckpoints(paneID: UUID) {
        checkpoints.removeAll { $0.paneID == paneID }
    }

    func clearAll() {
        checkpoints.removeAll()
    }

    func bytesSince(_ checkpoint: TerminalScrollbackCheckpoint) -> Data? {
        guard let buffer = buffers[checkpoint.paneID] else { return nil }
        let currentSeq = TerminalOutputBus.shared.currentSeq(paneID: checkpoint.paneID)
        guard currentSeq > checkpoint.seq else { return Data() }
        let wanted = Int(currentSeq - checkpoint.seq)
        return buffer.tail(count: wanted)
    }

    func bytesBetween(
        _ earlier: TerminalScrollbackCheckpoint,
        _ later: TerminalScrollbackCheckpoint
    ) -> Data? {
        guard earlier.paneID == later.paneID else { return nil }
        guard later.seq > earlier.seq else { return Data() }
        guard let buffer = buffers[earlier.paneID] else { return nil }
        let wantedCount = Int(later.seq - earlier.seq)
        let currentSeq = TerminalOutputBus.shared.currentSeq(paneID: earlier.paneID)
        let trailingOffset = Int(currentSeq &- later.seq)
        return buffer.slice(trailingOffset: trailingOffset, count: wantedCount)
    }

    private func ingest(paneID: UUID, data: Data, seq: UInt64) {
        _ = seq
        let buffer = buffers[paneID, default: TerminalRingBuffer(capacity: capacity)]
        buffer.append(data)
        buffers[paneID] = buffer
    }
}

final class TerminalRingBuffer {
    private let capacity: Int
    private var storage: [UInt8]
    private var writeIndex: Int = 0
    private var filled: Bool = false

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = [UInt8](repeating: 0, count: self.capacity)
    }

    var count: Int {
        filled ? capacity : writeIndex
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var remaining = data.count
            var read = 0
            while remaining > 0 {
                let freeTail = capacity - writeIndex
                let chunk = min(remaining, freeTail)
                storage.withUnsafeMutableBufferPointer { buffer in
                    guard let dst = buffer.baseAddress else { return }
                    (dst + writeIndex).update(from: base + read, count: chunk)
                }
                writeIndex = (writeIndex + chunk) % capacity
                read += chunk
                remaining -= chunk
                if writeIndex == 0 {
                    filled = true
                }
            }
        }
    }

    func tail(count: Int) -> Data {
        let available = self.count
        let take = min(max(0, count), available)
        guard take > 0 else { return Data() }
        var out = Data(count: take)
        out.withUnsafeMutableBytes { (outBuf: UnsafeMutableRawBufferPointer) in
            guard let outBase = outBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            let startOffset = (writeIndex - take + capacity) % capacity
            storage.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                let firstChunk = min(take, capacity - startOffset)
                (outBase).update(from: srcBase + startOffset, count: firstChunk)
                if firstChunk < take {
                    (outBase + firstChunk).update(from: srcBase, count: take - firstChunk)
                }
            }
        }
        return out
    }

    func slice(trailingOffset: Int, count: Int) -> Data? {
        let available = self.count
        let endOffsetFromEnd = max(0, trailingOffset)
        let wanted = max(0, count)
        guard wanted + endOffsetFromEnd <= available else { return nil }
        guard wanted > 0 else { return Data() }
        var out = Data(count: wanted)
        out.withUnsafeMutableBytes { (outBuf: UnsafeMutableRawBufferPointer) in
            guard let outBase = outBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            let endIndex = (writeIndex - endOffsetFromEnd + capacity) % capacity
            let startIndex = (endIndex - wanted + capacity) % capacity
            storage.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                let firstChunk = min(wanted, capacity - startIndex)
                (outBase).update(from: srcBase + startIndex, count: firstChunk)
                if firstChunk < wanted {
                    (outBase + firstChunk).update(from: srcBase, count: wanted - firstChunk)
                }
            }
        }
        return out
    }
}
