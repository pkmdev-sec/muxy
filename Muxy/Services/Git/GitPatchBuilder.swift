import Foundation

enum GitPatchBuilder {
    static func buildPatch(from rawPatch: String, selectingHunkIndices indices: Set<Int>) -> String? {
        guard !indices.isEmpty else { return nil }

        let normalized = rawPatch.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }).map(String.init)
        guard !lines.isEmpty else { return nil }

        var output: [String] = []
        var inSelectedHunk = false
        var encounteredHunk = false
        var hunkCounter = -1
        var currentFileHeader: [String] = []
        var fileHeaderEmitted = false
        var lastLineWasNewlineMarker = false

        for line in lines {
            if isFileHeaderStart(line) {
                currentFileHeader = [line]
                fileHeaderEmitted = false
                encounteredHunk = false
                inSelectedHunk = false
                continue
            }

            if encounteredHunk == false, isFileHeaderContinuation(line) {
                currentFileHeader.append(line)
                continue
            }

            if line.hasPrefix("@@") {
                encounteredHunk = true
                hunkCounter += 1
                if indices.contains(hunkCounter) {
                    if !fileHeaderEmitted {
                        output.append(contentsOf: currentFileHeader)
                        fileHeaderEmitted = true
                    }
                    output.append(line)
                    inSelectedHunk = true
                    lastLineWasNewlineMarker = false
                } else {
                    inSelectedHunk = false
                }
                continue
            }

            guard inSelectedHunk else { continue }

            if line.hasPrefix("\\ ") {
                if lastLineWasNewlineMarker == false {
                    output.append(line)
                    lastLineWasNewlineMarker = true
                }
                continue
            }

            if line.hasPrefix(" ") || line.hasPrefix("+") || line.hasPrefix("-") {
                output.append(line)
                lastLineWasNewlineMarker = false
                continue
            }

            if line.isEmpty {
                output.append(line)
                lastLineWasNewlineMarker = false
            }
        }

        guard !output.isEmpty else { return nil }
        return output.joined(separator: "\n") + "\n"
    }

    struct LineSelection: Hashable, Sendable {
        let hunkIndex: Int
        let bodyLineIndex: Int
    }

    static func buildPatch(from rawPatch: String, selectingLines selection: Set<LineSelection>) -> String? {
        guard !selection.isEmpty else { return nil }

        let normalized = rawPatch.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }).map(String.init)
        guard !lines.isEmpty else { return nil }

        let selectionsByHunk = Dictionary(grouping: selection, by: { $0.hunkIndex })

        var output: [String] = []
        var currentFileHeader: [String] = []
        var fileHeaderEmitted = false
        var encounteredHunk = false
        var hunkCounter = -1
        var bodyBuffer: [(raw: String, kind: BodyKind)] = []
        var currentHunkHeader: (oldStart: Int, newStart: Int)?
        var collectingHunk = false

        func flushCurrentHunk() {
            defer {
                bodyBuffer = []
                currentHunkHeader = nil
                collectingHunk = false
            }
            guard let header = currentHunkHeader else { return }
            let selectedBodyLines = selectionsByHunk[hunkCounter]?.map(\.bodyLineIndex).map { $0 } ?? []
            let selectedSet = Set(selectedBodyLines)
            guard !selectedSet.isEmpty else { return }

            var emittedBody: [String] = []
            var lastEmittedKind: BodyKind = .context

            for (index, entry) in bodyBuffer.enumerated() {
                switch entry.kind {
                case .context:
                    emittedBody.append(entry.raw)
                    lastEmittedKind = .context
                case .deletion:
                    if selectedSet.contains(index) {
                        emittedBody.append(entry.raw)
                        lastEmittedKind = .deletion
                    } else {
                        let content = String(entry.raw.dropFirst())
                        emittedBody.append(" " + content)
                        lastEmittedKind = .context
                    }
                case .addition:
                    if selectedSet.contains(index) {
                        emittedBody.append(entry.raw)
                        lastEmittedKind = .addition
                    }
                case .newlineMarker:
                    switch lastEmittedKind {
                    case .context, .deletion, .addition:
                        emittedBody.append(entry.raw)
                    default:
                        break
                    }
                }
            }

            let oldCount = emittedBody.reduce(into: 0) { count, line in
                if line.hasPrefix("-") || line.hasPrefix(" ") { count += 1 }
            }
            let newCount = emittedBody.reduce(into: 0) { count, line in
                if line.hasPrefix("+") || line.hasPrefix(" ") { count += 1 }
            }

            guard oldCount > 0 || newCount > 0 else { return }

            if !fileHeaderEmitted {
                output.append(contentsOf: currentFileHeader)
                fileHeaderEmitted = true
            }
            output.append("@@ -\(header.oldStart),\(oldCount) +\(header.newStart),\(newCount) @@")
            output.append(contentsOf: emittedBody)
        }

        for line in lines {
            if isFileHeaderStart(line) {
                flushCurrentHunk()
                currentFileHeader = [line]
                fileHeaderEmitted = false
                encounteredHunk = false
                continue
            }
            if !encounteredHunk, isFileHeaderContinuation(line) {
                currentFileHeader.append(line)
                continue
            }
            if line.hasPrefix("@@") {
                flushCurrentHunk()
                encounteredHunk = true
                hunkCounter += 1
                let header = GitDiffParser.parseHunkHeader(line)
                currentHunkHeader = (oldStart: header.0, newStart: header.1)
                collectingHunk = true
                continue
            }
            guard collectingHunk else { continue }
            if line.hasPrefix("\\ ") {
                bodyBuffer.append((raw: line, kind: .newlineMarker))
                continue
            }
            if line.hasPrefix("+") {
                bodyBuffer.append((raw: line, kind: .addition))
                continue
            }
            if line.hasPrefix("-") {
                bodyBuffer.append((raw: line, kind: .deletion))
                continue
            }
            if line.hasPrefix(" ") {
                bodyBuffer.append((raw: line, kind: .context))
                continue
            }
            if line.isEmpty {
                bodyBuffer.append((raw: line, kind: .context))
            }
        }
        flushCurrentHunk()

        guard !output.isEmpty else { return nil }
        return output.joined(separator: "\n") + "\n"
    }

    private enum BodyKind {
        case context
        case addition
        case deletion
        case newlineMarker
    }

    private static func isFileHeaderStart(_ line: String) -> Bool {
        line.hasPrefix("diff --git ")
    }

    private static func isFileHeaderContinuation(_ line: String) -> Bool {
        line.hasPrefix("index ")
            || line.hasPrefix("--- ")
            || line.hasPrefix("+++ ")
            || line.hasPrefix("new file mode ")
            || line.hasPrefix("deleted file mode ")
            || line.hasPrefix("old mode ")
            || line.hasPrefix("new mode ")
            || line.hasPrefix("similarity index ")
            || line.hasPrefix("dissimilarity index ")
            || line.hasPrefix("rename from ")
            || line.hasPrefix("rename to ")
            || line.hasPrefix("copy from ")
            || line.hasPrefix("copy to ")
            || line.hasPrefix("Binary files ")
    }
}
