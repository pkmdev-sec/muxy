import Foundation
import os

struct CodableFileStoreOptions {
    var prettyPrinted: Bool = false
    var sortedKeys: Bool = false
    var filePermissions: Int?

    static let standard = Self()
    static let pretty = Self(prettyPrinted: true)
    static let prettySorted = Self(prettyPrinted: true, sortedKeys: true)
}

struct CodableFileStore<Value: Codable> {
    let fileURL: URL
    let options: CodableFileStoreOptions

    init(fileURL: URL, options: CodableFileStoreOptions = .standard) {
        self.fileURL = fileURL
        self.options = options
    }

    func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = []
        if options.prettyPrinted { formatting.insert(.prettyPrinted) }
        if options.sortedKeys { formatting.insert(.sortedKeys) }
        encoder.outputFormatting = formatting

        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)

        if let permissions = options.filePermissions {
            try FileManager.default.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: fileURL.path
            )
        }
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

private let codableFileStoreQueue = DispatchQueue(
    label: "app.muxy.codable-file-store",
    qos: .utility,
    attributes: .concurrent
)

extension CodableFileStore where Value: Sendable {
    func saveAsync(_ value: Value) {
        let options = self.options
        let url = self.fileURL
        codableFileStoreQueue.async {
            Self.writeSync(value, to: url, options: options)
        }
    }

    static func writeSync(_ value: Value, to url: URL, options: CodableFileStoreOptions) {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = []
        if options.prettyPrinted { formatting.insert(.prettyPrinted) }
        if options.sortedKeys { formatting.insert(.sortedKeys) }
        encoder.outputFormatting = formatting

        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)

            if let permissions = options.filePermissions {
                try FileManager.default.setAttributes(
                    [.posixPermissions: permissions],
                    ofItemAtPath: url.path
                )
            }
        } catch {
            let logger = Logger(subsystem: "app.muxy", category: "CodableFileStore")
            logger.error("Async save failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
