import Foundation
import GhosttyKit
import os

private let terminalOutputBusLogger = Logger(subsystem: "app.muxy", category: "TerminalOutputBus")

struct TerminalOutputSubscription: Sendable, Identifiable {
    let id: UUID
    let paneID: UUID
}

@MainActor
@Observable
final class TerminalOutputBus {
    static let shared = TerminalOutputBus()

    typealias Handler = @MainActor (Data, UInt64) -> Void

    @ObservationIgnored private var paneByToken: [Int: UUID] = [:]
    @ObservationIgnored private var tokenByPane: [UUID: Int] = [:]
    @ObservationIgnored private var nextToken: Int = 1
    @ObservationIgnored private var subscribersByPane: [UUID: [(UUID, Handler)]] = [:]
    @ObservationIgnored private var seqByPane: [UUID: UInt64] = [:]

    private init() {}

    func attach(paneID: UUID, surface: ghostty_surface_t) {
        if tokenByPane[paneID] != nil { return }
        let token = nextToken
        nextToken += 1
        tokenByPane[paneID] = token
        paneByToken[token] = paneID
        ghostty_surface_set_data_callback(
            surface,
            terminalOutputBusDataCallback,
            UnsafeMutableRawPointer(bitPattern: UInt(token))
        )
    }

    func detach(paneID: UUID, surface: ghostty_surface_t) {
        ghostty_surface_set_data_callback(surface, nil, nil)
        if let token = tokenByPane.removeValue(forKey: paneID) {
            paneByToken.removeValue(forKey: token)
        }
    }

    func subscribe(
        paneID: UUID,
        handler: @escaping Handler
    ) -> TerminalOutputSubscription {
        let id = UUID()
        subscribersByPane[paneID, default: []].append((id, handler))
        return TerminalOutputSubscription(id: id, paneID: paneID)
    }

    func unsubscribe(_ subscription: TerminalOutputSubscription) {
        guard var list = subscribersByPane[subscription.paneID] else { return }
        list.removeAll { $0.0 == subscription.id }
        if list.isEmpty {
            subscribersByPane.removeValue(forKey: subscription.paneID)
            return
        }
        subscribersByPane[subscription.paneID] = list
    }

    func currentSeq(paneID: UUID) -> UInt64 {
        seqByPane[paneID] ?? 0
    }

    func testingInject(paneID: UUID, bytes: Data) {
        dispatch(paneID: paneID, bytes: bytes)
    }

        fileprivate func pane(for token: Int) -> UUID? {
        paneByToken[token]
    }

    fileprivate func dispatch(paneID: UUID, bytes: Data) {
        guard !bytes.isEmpty else { return }
        let nextSeq = (seqByPane[paneID] ?? 0) &+ UInt64(bytes.count)
        seqByPane[paneID] = nextSeq
        guard let subscribers = subscribersByPane[paneID] else { return }
        for (_, handler) in subscribers {
            handler(bytes, nextSeq)
        }
    }
}

private typealias TerminalOutputBusDataCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<UInt8>?,
    UInt
) -> Void

private final class TerminalOutputBurstCoalescer: @unchecked Sendable {
    static let shared = TerminalOutputBurstCoalescer()
    private let lock = NSLock()
    private var pendingByToken: [Int: Data] = [:]
    private var flushScheduled = false

    func enqueue(token: Int, bytes: UnsafePointer<UInt8>, len: Int) {
        lock.lock()
        var existing = pendingByToken[token] ?? Data()
        existing.append(bytes, count: len)
        pendingByToken[token] = existing
        let shouldSchedule = !flushScheduled
        if shouldSchedule {
            flushScheduled = true
        }
        lock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        lock.lock()
        let snapshot = pendingByToken
        pendingByToken.removeAll(keepingCapacity: true)
        flushScheduled = false
        lock.unlock()
        MainActor.assumeIsolated {
            for (token, bytes) in snapshot {
                guard let paneID = TerminalOutputBus.shared.pane(for: token) else { continue }
                TerminalOutputBus.shared.dispatch(paneID: paneID, bytes: bytes)
            }
        }
    }
}

private let terminalOutputBusDataCallback: TerminalOutputBusDataCallback = { userdata, ptr, len in
    guard let userdata, let ptr, len > 0 else { return }
    let token = Int(bitPattern: userdata)
    TerminalOutputBurstCoalescer.shared.enqueue(token: token, bytes: ptr, len: Int(len))
}
