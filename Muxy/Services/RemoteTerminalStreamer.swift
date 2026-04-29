import Foundation
import GhosttyKit
import MuxyServer
import MuxyShared

@MainActor
final class RemoteTerminalStreamer {
    static let shared = RemoteTerminalStreamer()

    weak var server: MuxyRemoteServer?

    private var subscriptionsByPane: [UUID: TerminalOutputSubscription] = [:]

    private init() {}

    func attach(paneID: UUID) {
        if subscriptionsByPane[paneID] != nil { return }
        let subscription = TerminalOutputBus.shared.subscribe(paneID: paneID) { [weak self] bytes, seq in
            self?.forward(paneID: paneID, bytes: bytes, seq: seq)
        }
        subscriptionsByPane[paneID] = subscription
    }

    func detach(paneID: UUID) {
        if let subscription = subscriptionsByPane.removeValue(forKey: paneID) {
            TerminalOutputBus.shared.unsubscribe(subscription)
        }
    }

    fileprivate func forward(paneID: UUID, bytes: Data, seq: UInt64) {
        guard let clientID = PaneOwnershipStore.shared.remoteOwner(for: paneID) else { return }
        let event = MuxyEvent(
            event: .terminalOutput,
            data: .terminalOutput(TerminalOutputEventDTO(paneID: paneID, bytes: bytes, seq: seq))
        )
        server?.send(event, to: clientID)
    }
}
