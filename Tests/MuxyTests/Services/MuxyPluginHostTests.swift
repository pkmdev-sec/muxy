import Foundation
import Testing
import JavaScriptCore

@testable import Muxy

@MainActor
@Suite("MuxyPluginHost")
struct MuxyPluginHostTests {
    private func tempPluginDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-plugin-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("PluginCallbackBox retains the JSValue")
    func callbackBoxRetains() {
        let context = JSContext()!
        let value = context.evaluateScript("(function() { return 42; })")
        guard let value else {
            Issue.record("expected JSValue")
            return
        }
        let box = PluginCallbackBox(value)
        #expect(box.value.isObject)
    }

    @Test("manifest fields default sensibly")
    func manifestDefaults() {
        let m = MuxyPluginManifest(id: "p", displayName: "P", sourcePath: "/tmp/p.js", version: "1.0.0")
        #expect(m.id == "p")
        #expect(m.version == "1.0.0")
    }

    @Test("palette command holds plugin id + symbol")
    func paletteCommandShape() {
        let cmd = MuxyPluginPaletteCommand(
            id: "plugin.hello.say",
            title: "Say Hello",
            subtitle: "test",
            symbol: "hand.wave",
            pluginID: "hello"
        )
        #expect(cmd.id.hasPrefix("plugin.hello."))
        #expect(cmd.symbol == "hand.wave")
    }
}
