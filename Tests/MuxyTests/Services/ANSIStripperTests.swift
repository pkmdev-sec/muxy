import Foundation
import Testing

@testable import Muxy

@Suite("ANSIStripper")
struct ANSIStripperTests {
    @Test("plain ascii passes through unchanged")
    func plainAscii() {
        let out = ANSIStripper.strip(Data("hello world".utf8))
        #expect(out == "hello world")
    }

    @Test("CSI color codes are removed")
    func csiColorCodes() {
        let raw = "\u{1B}[31mred\u{1B}[0m normal"
        let out = ANSIStripper.strip(Data(raw.utf8))
        #expect(out == "red normal")
    }

    @Test("OSC sequences are removed")
    func oscSequences() {
        let raw = "before\u{1B}]0;Terminal Title\u{07}after"
        let out = ANSIStripper.strip(Data(raw.utf8))
        #expect(out == "beforeafter")
    }

    @Test("cursor movement codes are removed")
    func cursorCodes() {
        let raw = "abc\u{1B}[2Jxyz"
        let out = ANSIStripper.strip(Data(raw.utf8))
        #expect(out == "abcxyz")
    }

    @Test("carriage returns are dropped")
    func carriageReturns() {
        let raw = "line1\r\nline2"
        let out = ANSIStripper.strip(Data(raw.utf8))
        #expect(out == "line1\nline2")
    }

    @Test("bell characters are dropped")
    func bellChars() {
        let raw = "beep\u{07}done"
        let out = ANSIStripper.strip(Data(raw.utf8))
        #expect(out == "beepdone")
    }

    @Test("24-bit truecolor sequences are stripped")
    func trueColor() {
        let raw = "\u{1B}[38;2;255;128;0morange\u{1B}[0m"
        let out = ANSIStripper.strip(Data(raw.utf8))
        #expect(out == "orange")
    }
}

@MainActor
@Suite("RemotePaneTabState")
struct RemotePaneTabStateTests {
    @Test("appending bytes strips and accumulates into buffer")
    func appendStrips() {
        let state = RemotePaneTabState(
            remotePaneID: UUID(),
            projectPath: "/tmp/p",
            projectName: "Proj",
            peerDeviceName: "Peer"
        )
        state.appendBytes(Data("\u{1B}[31mhi\u{1B}[0m".utf8))
        state.appendBytes(Data("\nthere".utf8))
        #expect(state.buffer == "hi\nthere")
    }

    @Test("clear resets the buffer")
    func clear() {
        let state = RemotePaneTabState(
            remotePaneID: UUID(),
            projectPath: "/tmp/p",
            projectName: "Proj",
            peerDeviceName: "Peer"
        )
        state.appendBytes(Data("hello".utf8))
        state.clear()
        #expect(state.buffer.isEmpty)
    }

    @Test("display title includes peer and project names")
    func title() {
        let state = RemotePaneTabState(
            remotePaneID: UUID(),
            projectPath: "/tmp/p",
            projectName: "Alpha",
            peerDeviceName: "Desktop"
        )
        #expect(state.displayTitle.contains("Desktop"))
        #expect(state.displayTitle.contains("Alpha"))
    }
}
