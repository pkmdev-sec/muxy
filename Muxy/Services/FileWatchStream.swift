import CoreServices
import Foundation

final class FileWatchStream: @unchecked Sendable {
    struct Event: Sendable, Equatable {
        let paths: [String]
    }

    typealias Handler = @Sendable (Event) -> Void

    private let queue = DispatchQueue(label: "app.muxy.file-watch", qos: .utility)
    private var stream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private var pendingPaths: [String] = []
    private let handler: Handler
    private let glob: String?
    private let debounceSeconds: Double

    init?(
        rootPath: String,
        glob: String? = nil,
        debounceSeconds: Double = 0.25,
        handler: @escaping Handler
    ) {
        guard FileManager.default.fileExists(atPath: rootPath) else { return nil }
        self.handler = handler
        self.glob = glob
        self.debounceSeconds = debounceSeconds

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [rootPath] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            FileWatchStream.eventCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceSeconds,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        debounceWork?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    static let eventCallback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, _, _ in
        guard let clientInfo, numEvents > 0 else { return }
        let watcher = Unmanaged<FileWatchStream>.fromOpaque(clientInfo).takeUnretainedValue()
        guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
        watcher.ingest(paths: paths)
    }

    private func ingest(paths: [String]) {
        let filtered = paths.filter { matches(glob: glob, path: $0) }
        guard !filtered.isEmpty else { return }
        pendingPaths.append(contentsOf: filtered)
        scheduleFlush()
    }

    private func scheduleFlush() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.pendingPaths.isEmpty else { return }
            let batch = Array(Set(self.pendingPaths))
            self.pendingPaths.removeAll()
            self.handler(Event(paths: batch))
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
    }

    private func matches(glob: String?, path: String) -> Bool {
        guard let glob, !glob.isEmpty else { return true }
        return FileWatchGlob.matches(pattern: glob, path: path)
    }
}

enum FileWatchGlob {
    static func matches(pattern: String, path: String) -> Bool {
        let lowerPath = path.lowercased()
        let segments = pattern
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return true }
        for segment in segments where matchesSingle(pattern: segment, path: lowerPath) {
            return true
        }
        return false
    }

    private static func matchesSingle(pattern: String, path: String) -> Bool {
        let needleRegex = convertGlobToRegex(pattern)
        guard let regex = try? NSRegularExpression(pattern: needleRegex, options: [.anchorsMatchLines]) else { return false }
        let range = NSRange(location: 0, length: (path as NSString).length)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }

    private static func convertGlobToRegex(_ pattern: String) -> String {
        var regex = ""
        for char in pattern {
            switch char {
            case "*": regex += "[^/]*"
            case "?": regex += "[^/]"
            case ".", "(", ")", "+", "|", "^", "$", "[", "]", "{", "}", "\\":
                regex += "\\" + String(char)
            default: regex.append(char)
            }
        }
        return regex
    }
}
