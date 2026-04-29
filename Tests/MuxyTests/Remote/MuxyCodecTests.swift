import Foundation
import MuxyShared
import Testing

@Suite("MuxyCodec")
struct MuxyCodecTests {
    @Test("request round-trip preserves id, method and params")
    func requestRoundTrip() throws {
        let projectID = UUID()
        let original = MuxyMessage.request(
            MuxyRequest(
                id: "req-1",
                method: .selectProject,
                params: .selectProject(SelectProjectParams(projectID: projectID))
            )
        )

        let data = try MuxyCodec.encode(original)
        let decoded = try MuxyCodec.decode(data)

        guard case let .request(request) = decoded else {
            Issue.record("expected .request case, got \(decoded)")
            return
        }
        #expect(request.id == "req-1")
        #expect(request.method == .selectProject)
        guard case let .selectProject(params) = request.params else {
            Issue.record("expected selectProject params")
            return
        }
        #expect(params.projectID == projectID)
    }

    @Test("response round-trip preserves ok result")
    func responseRoundTripOk() throws {
        let original = MuxyMessage.response(MuxyResponse(id: "r1", result: .ok))
        let data = try MuxyCodec.encode(original)
        let decoded = try MuxyCodec.decode(data)

        guard case let .response(response) = decoded else {
            Issue.record("expected .response case")
            return
        }
        #expect(response.id == "r1")
        #expect(response.error == nil)
        guard case .ok = response.result else {
            Issue.record("expected .ok result")
            return
        }
    }

    @Test("response round-trip preserves error")
    func responseRoundTripError() throws {
        let original = MuxyMessage.response(
            MuxyResponse(id: "r2", error: .invalidParams)
        )
        let data = try MuxyCodec.encode(original)
        let decoded = try MuxyCodec.decode(data)

        guard case let .response(response) = decoded,
              let error = response.error
        else {
            Issue.record("expected response with error")
            return
        }
        #expect(error.code == 400)
        #expect(response.result == nil)
    }

    @Test("event round-trip preserves payload")
    func eventRoundTrip() throws {
        let paneID = UUID()
        let deviceID = UUID()
        let original = MuxyMessage.event(
            MuxyEvent(
                event: .paneOwnershipChanged,
                data: .paneOwnership(
                    PaneOwnershipEventDTO(
                        paneID: paneID,
                        owner: .remote(deviceID: deviceID, deviceName: "iPhone")
                    )
                )
            )
        )

        let data = try MuxyCodec.encode(original)
        let decoded = try MuxyCodec.decode(data)

        guard case let .event(event) = decoded,
              case let .paneOwnership(dto) = event.data
        else {
            Issue.record("expected pane ownership event")
            return
        }
        #expect(event.event == .paneOwnershipChanged)
        #expect(dto.paneID == paneID)
        #expect(dto.owner == .remote(deviceID: deviceID, deviceName: "iPhone"))
    }

    @Test("unknown param type rejects decoding")
    func unknownParamTypeFails() {
        let json = #"{"type":"request","payload":{"id":"x","method":"selectProject","params":{"type":"bogus","value":{}}}}"#
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            _ = try MuxyCodec.decode(data)
        }
    }

    @Test("terminal cells payload preserves cells array")
    func terminalCellsRoundTrip() throws {
        let paneID = UUID()
        let cells = (0 ..< 4).map {
            TerminalCellDTO(codepoint: UInt32($0) + 65, fg: 0xFF_FFFF, bg: 0, flags: 0)
        }
        let payload = TerminalCellsDTO(
            paneID: paneID,
            cols: 2,
            rows: 2,
            cursorX: 1,
            cursorY: 1,
            cursorVisible: true,
            defaultFg: 0xFF_FFFF,
            defaultBg: 0,
            cells: cells
        )

        let data = try MuxyCodec.encode(.response(MuxyResponse(id: "c1", result: .terminalCells(payload))))
        let decoded = try MuxyCodec.decode(data)

        guard case let .response(response) = decoded,
              case let .terminalCells(roundTripped) = response.result
        else {
            Issue.record("expected terminalCells response")
            return
        }
        #expect(roundTripped.paneID == paneID)
        #expect(roundTripped.cells.count == 4)
        #expect(roundTripped.cells.first?.codepoint == 65)
    }

    @Test("new encoders include protocolVersion on all envelopes")
    func protocolVersionIsEmitted() throws {
        let request = MuxyMessage.request(MuxyRequest(id: "p1", method: .listProjects))
        let response = MuxyMessage.response(MuxyResponse(id: "p2", result: .ok))
        let event = MuxyMessage.event(
            MuxyEvent(event: .paneOwnershipChanged, data: .paneOwnership(
                PaneOwnershipEventDTO(paneID: UUID(), owner: .mac(deviceName: "MacBook"))
            ))
        )
        for message in [request, response, event] {
            let data = try MuxyCodec.encode(message)
            let json = try #require(String(data: data, encoding: .utf8))
            #expect(json.contains("\"protocolVersion\":1"))
        }
    }

    @Test("old payloads without protocolVersion still decode")
    func legacyPayloadsDecodeWithoutProtocolVersion() throws {
        let legacy = #"{"type":"request","payload":{"id":"x","method":"listProjects"}}"#
        let data = Data(legacy.utf8)
        let decoded = try MuxyCodec.decode(data)
        guard case let .request(request) = decoded else {
            Issue.record("expected .request")
            return
        }
        #expect(request.id == "x")
        #expect(request.method == .listProjects)
        #expect(request.protocolVersion == nil)
    }

    @Test("terminal output event preserves seq field")
    func terminalOutputSeqRoundTrip() throws {
        let paneID = UUID()
        let dto = TerminalOutputEventDTO(paneID: paneID, bytes: Data([0x68, 0x69]), seq: 42)
        let message = MuxyMessage.event(MuxyEvent(event: .terminalOutput, data: .terminalOutput(dto)))
        let data = try MuxyCodec.encode(message)
        let decoded = try MuxyCodec.decode(data)
        guard case let .event(event) = decoded,
              case let .terminalOutput(roundTripped) = event.data
        else {
            Issue.record("expected terminalOutput event")
            return
        }
        #expect(roundTripped.paneID == paneID)
        #expect(roundTripped.seq == 42)
    }

    @Test("terminal output event without seq decodes as nil")
    func terminalOutputSeqDefaultsNil() throws {
        let json = #"{"type":"event","payload":{"protocolVersion":1,"event":"terminalOutput","data":{"type":"terminalOutput","value":{"paneID":"\#(UUID().uuidString)","bytes":"aGk="}}}}"#
        let data = Data(json.utf8)
        let decoded = try MuxyCodec.decode(data)
        guard case let .event(event) = decoded,
              case let .terminalOutput(dto) = event.data
        else {
            Issue.record("expected terminalOutput event")
            return
        }
        #expect(dto.seq == nil)
        #expect(dto.bytes == Data([0x68, 0x69]))
    }
}
