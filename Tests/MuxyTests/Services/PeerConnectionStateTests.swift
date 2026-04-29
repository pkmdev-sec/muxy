import Foundation
import Testing

@testable import Muxy

@Suite("PeerConnectionState")
struct PeerConnectionStateTests {
    @Test("idle state is not connected")
    func idleNotConnected() {
        let state: PeerConnectionState = .idle
        #expect(state.isConnected == false)
        #expect(state.displayLabel == "Disconnected")
    }

    @Test("connecting state is not connected yet")
    func connectingState() {
        let state: PeerConnectionState = .connecting
        #expect(state.isConnected == false)
        #expect(state.displayLabel.hasPrefix("Connecting"))
    }

    @Test("pairing state is not connected yet")
    func pairingState() {
        let state: PeerConnectionState = .pairing
        #expect(state.isConnected == false)
        #expect(state.displayLabel.hasPrefix("Pairing"))
    }

    @Test("connected state exposes name")
    func connectedState() {
        let id = UUID()
        let state: PeerConnectionState = .connected(deviceName: "Desktop", clientID: id)
        #expect(state.isConnected == true)
        #expect(state.displayLabel == "Connected: Desktop")
    }

    @Test("failed state surfaces message")
    func failedState() {
        let state: PeerConnectionState = .failed(message: "timeout")
        #expect(state.isConnected == false)
        #expect(state.displayLabel == "Failed: timeout")
    }
}
