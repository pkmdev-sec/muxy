import AppKit
import SwiftUI
import MuxyShared

struct ConnectPeerOverlay: View {
    let onDismiss: () -> Void

    @State private var host = ""
    @State private var port = String(PeerClient.defaultPort)
    @State private var deviceName = Host.current().localizedName ?? "This Mac"
    private let client = PeerClient.shared

    var body: some View {
        ZStack {
            MuxyOverlayScrim(onDismiss: onDismiss)
            GlassPanel(
                material: MuxyMaterials.overlayMaterial,
                cornerRadius: 14,
                elevation: .overlay
            ) {
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(MuxyGlass.borderSoft).frame(height: 1)
                    formSection
                    Rectangle().fill(MuxyGlass.borderSoft).frame(height: 1)
                    projectsSection
                }
            }
            .frame(width: 520, height: 460)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(MuxyTheme.accent)
                .font(.system(size: 13, weight: .semibold))
            Text("Connect to Muxy Peer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Spacer()
            statusChip
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(client.state.displayLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(MuxyTheme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
    }

    private var statusColor: Color {
        switch client.state {
        case .idle: MuxyTheme.fgMuted
        case .connecting, .pairing: .yellow
        case .connected: .green
        case .failed: .red
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                fieldLabel("Host")
                TextField("192.168.1.42 or hostname.local", text: $host)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                fieldLabel("Port")
                TextField(String(PeerClient.defaultPort), text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                fieldLabel("This device name")
                TextField("Mac", text: $deviceName)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Spacer()
                if client.state.isConnected {
                    Button("Disconnect") {
                        client.disconnect()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        let resolvedPort = UInt16(port) ?? PeerClient.defaultPort
                        client.connect(
                            host: host.trimmingCharacters(in: .whitespaces),
                            port: resolvedPort,
                            deviceName: deviceName
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return)
                }
            }
        }
        .padding(14)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MuxyTheme.fgMuted)
            .frame(width: 90, alignment: .trailing)
    }

    @ViewBuilder
    private var projectsSection: some View {
        if client.state.isConnected {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Peer projects")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fgMuted)
                    Spacer()
                    Button("Refresh") {
                        Task { await client.refreshProjects() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MuxyTheme.accent)
                }
                if client.remoteProjects.isEmpty {
                    Text("No projects on peer")
                        .font(.system(size: 11))
                        .foregroundStyle(MuxyTheme.fgMuted)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(client.remoteProjects, id: \.id) { project in
                                projectRow(project)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(14)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "lock.shield")
                    .font(.system(size: 24))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Text("Pair with another Muxy")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text("Peer must approve the pairing from their Mac.")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func projectRow(_ project: ProjectDTO) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(MuxyTheme.fgMuted)
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                Text(project.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Stream Pane") {
                streamFirstPane(project: project)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(MuxyTheme.accent.opacity(0.15))
            .foregroundStyle(MuxyTheme.accent)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private func streamFirstPane(project: ProjectDTO) {
        Task {
            guard let workspace = await client.fetchWorkspace(projectID: project.id) else {
                ToastState.shared.show("Peer workspace unavailable")
                return
            }
            guard let (paneID, title) = firstTerminalPane(in: workspace.root) else {
                ToastState.shared.show("No live terminal panes on peer")
                return
            }
            guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
            let peerName: String
            if case let .connected(name, _) = client.state {
                peerName = name
            } else {
                peerName = client.currentHost ?? "peer"
            }
            appDelegate.openRemotePane(
                remotePaneID: paneID,
                projectPath: project.path,
                projectName: project.name,
                paneTitle: title,
                peerDeviceName: peerName
            )
            onDismiss()
        }
    }

    private func firstTerminalPane(in node: SplitNodeDTO) -> (UUID, String)? {
        switch node {
        case let .tabArea(area):
            for tab in area.tabs {
                if tab.kind == .terminal, let paneID = tab.paneID {
                    return (paneID, tab.title)
                }
            }
            return nil
        case let .split(split):
            return firstTerminalPane(in: split.first) ?? firstTerminalPane(in: split.second)
        }
    }
}
