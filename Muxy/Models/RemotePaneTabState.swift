import Foundation

@MainActor
@Observable
final class RemotePaneTabState: Identifiable {
    let id = UUID()
    let remotePaneID: UUID
    let projectPath: String
    let projectName: String
    let peerDeviceName: String
    var isAttached: Bool = false
    var buffer: String = ""
    private static let bufferCharLimit: Int = 200_000

    init(remotePaneID: UUID, projectPath: String, projectName: String, peerDeviceName: String) {
        self.remotePaneID = remotePaneID
        self.projectPath = projectPath
        self.projectName = projectName
        self.peerDeviceName = peerDeviceName
    }

    var displayTitle: String { "\(peerDeviceName) \u{2190} \(projectName)" }

    func appendBytes(_ data: Data) {
        let chunk = ANSIStripper.strip(data)
        buffer.append(chunk)
        if buffer.count > Self.bufferCharLimit {
            let excess = buffer.count - Self.bufferCharLimit
            buffer.removeFirst(excess)
        }
    }

    func clear() {
        buffer = ""
    }
}
