import Foundation

enum TestStatus: String, Codable, Equatable {
    case pending
    case running
    case passed
    case failed
    case skipped
}

struct TestFailure: Codable, Equatable, Identifiable {
    let message: String
    let filePath: String?
    let line: Int?
    let column: Int?

    var id: UUID {
        let key = "\(filePath ?? "")|\(line ?? 0)|\(column ?? 0)|\(message)"
        return TestFailureIDHasher.uuid(from: key)
    }
}

enum TestFailureIDHasher {
    static func uuid(from key: String) -> UUID {
        var bytes: [UInt8] = Array(repeating: 0, count: 16)
        for (index, byte) in Data(key.utf8).enumerated() {
            bytes[index % 16] ^= byte
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct TestNode: Identifiable, Equatable {
    let id: UUID
    let name: String
    var status: TestStatus
    var children: [TestNode]
    var failures: [TestFailure]
    var durationSeconds: Double?
    var isSuite: Bool

    init(
        id: UUID = UUID(),
        name: String,
        status: TestStatus = .pending,
        children: [TestNode] = [],
        failures: [TestFailure] = [],
        durationSeconds: Double? = nil,
        isSuite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.children = children
        self.failures = failures
        self.durationSeconds = durationSeconds
        self.isSuite = isSuite
    }
}

struct TestRunSummary: Equatable {
    let total: Int
    let passed: Int
    let failed: Int
    let skipped: Int
    let durationSeconds: Double?
}

extension TestNode {
    func summary() -> TestRunSummary {
        var total = 0
        var passed = 0
        var failed = 0
        var skipped = 0
        var duration = 0.0
        var hasDuration = false
        walkLeaves { node in
            total += 1
            switch node.status {
            case .passed: passed += 1
            case .failed: failed += 1
            case .skipped: skipped += 1
            default: break
            }
            if let value = node.durationSeconds {
                duration += value
                hasDuration = true
            }
        }
        return TestRunSummary(
            total: total,
            passed: passed,
            failed: failed,
            skipped: skipped,
            durationSeconds: hasDuration ? duration : nil
        )
    }

    func findFailures() -> [(path: [String], failure: TestFailure)] {
        var results: [(path: [String], failure: TestFailure)] = []
        collectFailures(path: [], into: &results)
        return results
    }

    private func walkLeaves(_ visit: (TestNode) -> Void) {
        if children.isEmpty, !isSuite {
            visit(self)
            return
        }
        for child in children {
            child.walkLeaves(visit)
        }
    }

    private func collectFailures(path: [String], into results: inout [(path: [String], failure: TestFailure)]) {
        let nextPath = name.isEmpty ? path : path + [name]
        for failure in failures {
            results.append((path: nextPath, failure: failure))
        }
        for child in children {
            child.collectFailures(path: nextPath, into: &results)
        }
    }
}
