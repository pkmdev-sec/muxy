import Foundation

struct NumstatEntry {
    let additions: Int?
    let deletions: Int?
    let isBinary: Bool
}

struct GitStatusFile: Identifiable, Hashable {
    let path: String
    let oldPath: String?
    let xStatus: Character
    let yStatus: Character
    let additions: Int?
    let deletions: Int?
    let isBinary: Bool

    var id: String { path }

    var isStaged: Bool {
        let staged: Set<Character> = ["A", "M", "D", "R", "C"]
        return staged.contains(xStatus)
    }

    var isUnstaged: Bool {
        let unstaged: Set<Character> = ["M", "D", "?"]
        return unstaged.contains(yStatus) || (xStatus == "?" && yStatus == "?")
    }

    var isConflicted: Bool {
        xStatus == "U" || yStatus == "U"
            || (xStatus == "A" && yStatus == "A")
            || (xStatus == "D" && yStatus == "D")
    }

    var statusText: String {
        switch (xStatus, yStatus) {
        case ("A", _),
             (_, "A"):
            "A"
        case ("D", _),
             (_, "D"):
            "D"
        case ("R", _),
             (_, "R"):
            "R"
        case ("C", _),
             (_, "C"):
            "C"
        case ("M", _),
             (_, "M"):
            "M"
        case ("U", _),
             (_, "U"):
            "U"
        default:
            "?"
        }
    }

    var stagedStatusText: String {
        String(xStatus)
    }

    var unstagedStatusText: String {
        if xStatus == "?", yStatus == "?" {
            return "U"
        }
        return String(yStatus)
    }
}

struct GitCommit: Identifiable {
    let hash: String
    let shortHash: String
    let subject: String
    let authorName: String
    let authorDate: Date
    let refs: [GitRef]
    let parentHashes: [String]

    var id: String { hash }
    var isMerge: Bool { parentHashes.count > 1 }
}

struct GitRef {
    enum Kind {
        case localBranch
        case remoteBranch
        case tag
        case head
    }

    let name: String
    let kind: Kind
}

struct DiffDisplayRow: Identifiable {
    enum Kind {
        case hunk
        case context
        case addition
        case deletion
        case collapsed
    }

    enum Source {
        case staged
        case unstaged
        case untracked
    }

    let id = UUID()
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let oldText: String?
    let newText: String?
    let text: String
    let hunkIndex: Int?
    let source: Source?

    init(
        kind: Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        oldText: String?,
        newText: String?,
        text: String,
        hunkIndex: Int? = nil,
        source: Source? = nil
    ) {
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.oldText = oldText
        self.newText = newText
        self.text = text
        self.hunkIndex = hunkIndex
        self.source = source
    }
}
