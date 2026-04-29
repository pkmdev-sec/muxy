import Foundation

struct MuxyPluginManifest: Equatable {
    let id: String
    let displayName: String
    let sourcePath: String
    let version: String
}

struct MuxyPluginPaletteCommand: Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let pluginID: String
}
