import AppKit
import SwiftUI

struct RemotePaneTabView: View {
    let state: RemotePaneTabState
    let focused: Bool
    let onFocus: () -> Void

    @State private var autoScroll = true
    @State private var interactive = false
    private let client = PeerClient.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MuxyTheme.border)
            ZStack {
                content
                if interactive, state.isAttached {
                    RemoteKeystrokeCapture(paneID: state.remotePaneID)
                        .allowsHitTesting(true)
                }
            }
        }
        .background(MuxyTheme.bg)
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .onAppear { attachIfNeeded() }
        .onDisappear { detach() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(state.isAttached ? .green : MuxyTheme.fgMuted)
                .font(.system(size: 12, weight: .semibold))
            Text(state.peerDeviceName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text("\u{2190}")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text(state.projectName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(statusLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .clipShape(Capsule())
            Toggle("Drive", isOn: $interactive)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .help("Send keystrokes to the peer pane")
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
            Button {
                state.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
            .buttonStyle(.plain)
            .help("Clear buffer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusLabel: String {
        state.isAttached ? "Streaming" : "Disconnected"
    }

    private var statusColor: Color {
        state.isAttached ? .green : .red
    }

    @ViewBuilder
    private var content: some View {
        if state.buffer.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for output from \(state.peerDeviceName)\u{2026}")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    Text(state.buffer)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(MuxyTheme.fg)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .id("remote-pane-bottom")
                }
                .onChange(of: state.buffer) { _, _ in
                    guard autoScroll else { return }
                    withAnimation(.linear(duration: 0.05)) {
                        scrollProxy.scrollTo("remote-pane-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func attachIfNeeded() {
        guard client.state.isConnected else {
            state.isAttached = false
            return
        }
        client.subscribeTerminal(paneID: state.remotePaneID) { bytes in
            state.appendBytes(bytes)
        }
        state.isAttached = true
        Task {
            await client.takeOverPane(paneID: state.remotePaneID)
        }
    }

    private func detach() {
        client.unsubscribeTerminal(paneID: state.remotePaneID)
        state.isAttached = false
        Task {
            await client.releasePane(paneID: state.remotePaneID)
        }
    }
}

private struct RemoteKeystrokeCapture: NSViewRepresentable {
    let paneID: UUID

    func makeNSView(context: Context) -> RemoteKeystrokeNSView {
        RemoteKeystrokeNSView(paneID: paneID)
    }

    func updateNSView(_ nsView: RemoteKeystrokeNSView, context: Context) {
        nsView.paneID = paneID
    }
}

private final class RemoteKeystrokeNSView: NSView {
    var paneID: UUID

    init(paneID: UUID) {
        self.paneID = paneID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.characters, !chars.isEmpty else { return }
        let data = Data(chars.utf8)
        let targetPaneID = paneID
        Task { @MainActor in
            await PeerClient.shared.sendInput(paneID: targetPaneID, bytes: data)
        }
    }
}
