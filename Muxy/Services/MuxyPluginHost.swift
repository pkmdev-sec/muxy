import AppKit
import Foundation
import JavaScriptCore
import os

private let pluginLogger = Logger(subsystem: "app.muxy", category: "MuxyPluginHost")

final class PluginCallbackBox: @unchecked Sendable {
    let value: JSValue
    init(_ value: JSValue) { self.value = value }
}

struct FlatCommandRequest: Sendable {
    let pluginID: String
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let callback: PluginCallbackBox?
}

@objc
protocol MuxyPluginJSExports: JSExport {
    func registerCommand(_ definition: [String: Any])
    func log(_ message: String)
    func showToast(_ message: String)
    func postOSNotification(_ title: String, _ body: String)
}

@MainActor
@Observable
final class MuxyPluginHost {
    static let shared = MuxyPluginHost()

    private(set) var loadedPlugins: [MuxyPluginManifest] = []
    private(set) var paletteCommands: [MuxyPluginPaletteCommand] = []

    @ObservationIgnored private var contexts: [String: JSContext] = [:]
    @ObservationIgnored private var callbacksByCommandID: [String: JSValue] = [:]
    @ObservationIgnored private var bridgesByPluginID: [String: MuxyPluginBridge] = [:]

    private init() {}

    static var pluginsDirectory: URL {
        MuxyFileStorage.fileURL(filename: "Plugins").deletingLastPathComponent()
            .appendingPathComponent("Plugins")
    }

    func loadAll() {
        ensureDirectoryExists()
        let directory = Self.pluginsDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        unloadAll()
        for entry in entries where entry.pathExtension == "js" {
            loadPlugin(at: entry)
        }
    }

    func unloadAll() {
        loadedPlugins.removeAll()
        paletteCommands.removeAll()
        contexts.removeAll()
        callbacksByCommandID.removeAll()
        bridgesByPluginID.removeAll()
    }

    func openPluginsDirectoryInFinder() {
        ensureDirectoryExists()
        NSWorkspace.shared.activateFileViewerSelecting([Self.pluginsDirectory])
    }

    func invoke(commandID: String) {
        guard let callback = callbacksByCommandID[commandID] else { return }
        _ = callback.call(withArguments: [])
    }

    private func ensureDirectoryExists() {
        let directory = Self.pluginsDirectory
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func loadPlugin(at url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        let pluginID = url.deletingPathExtension().lastPathComponent
        let context = JSContext()
        guard let context else { return }
        context.exceptionHandler = { _, exception in
            guard let exception else { return }
            pluginLogger.error("Plugin \(pluginID, privacy: .public) error: \(String(describing: exception), privacy: .public)")
        }
        let bridge = MuxyPluginBridge(pluginID: pluginID, host: self)
        bridgesByPluginID[pluginID] = bridge
        context.setObject(bridge, forKeyedSubscript: "muxy" as NSString)
        context.evaluateScript(source)

        let displayName: String = {
            let value = context.objectForKeyedSubscript("MUXY_PLUGIN_NAME")
            if let value, value.isString, let name = value.toString() { return name }
            return pluginID
        }()
        let version: String = {
            let value = context.objectForKeyedSubscript("MUXY_PLUGIN_VERSION")
            if let value, value.isString, let v = value.toString() { return v }
            return "0.0.0"
        }()
        contexts[pluginID] = context
        loadedPlugins.append(MuxyPluginManifest(
            id: pluginID,
            displayName: displayName,
            sourcePath: url.path,
            version: version
        ))
    }

    fileprivate func registerFlatCommand(_ request: FlatCommandRequest) {
        let pluginID = request.pluginID
        let id = request.id
        let title = request.title
        let subtitle = request.subtitle
        let symbol = request.symbol
        let callback = request.callback
        guard !id.isEmpty, !title.isEmpty else { return }
        let fullID = "plugin.\(pluginID).\(id)"
        paletteCommands.removeAll { $0.id == fullID }
        paletteCommands.append(MuxyPluginPaletteCommand(
            id: fullID,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            pluginID: pluginID
        ))
        if let callback {
            callbacksByCommandID[fullID] = callback.value
        }
    }
}

@objc
final class MuxyPluginBridge: NSObject, MuxyPluginJSExports {
    let pluginID: String
    weak var host: MuxyPluginHost?

    init(pluginID: String, host: MuxyPluginHost) {
        self.pluginID = pluginID
        self.host = host
    }

    func registerCommand(_ definition: [String: Any]) {
        let id = (definition["id"] as? String) ?? ""
        let title = (definition["title"] as? String) ?? ""
        let subtitle = definition["subtitle"] as? String
        let symbol = (definition["symbol"] as? String) ?? "puzzlepiece.extension"
        let callbackBox = (definition["run"] as? JSValue).map(PluginCallbackBox.init)
        let pluginID = self.pluginID
        weak var host = self.host
        MainActor.assumeIsolated {
            host?.registerFlatCommand(FlatCommandRequest(
                pluginID: pluginID,
                id: id,
                title: title,
                subtitle: subtitle,
                symbol: symbol,
                callback: callbackBox
            ))
        }
    }

    func log(_ message: String) {
        pluginLogger.log("[\(self.pluginID, privacy: .public)] \(message, privacy: .public)")
    }

    func showToast(_ message: String) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                ToastState.shared.show(message)
            }
        }
    }

    func postOSNotification(_ title: String, _ body: String) {
        DispatchQueue.main.async { [title, body] in
            MainActor.assumeIsolated {
                let notification = NSUserNotification()
                notification.title = title
                notification.informativeText = body
                NSUserNotificationCenter.default.deliver(notification)
            }
        }
    }
}
