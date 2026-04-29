import Foundation

struct AgentDefinition: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let branchPrefix: String?
    let launchCommand: String
    let worktreeStrategy: WorktreeStrategy?

    enum WorktreeStrategy: String, Codable {
        case newBranch
        case reuseWorktree
    }

    var effectiveBranchPrefix: String {
        let base: String = {
            if let prefix = branchPrefix, !prefix.isEmpty { return prefix }
            return id
        }()
        return base.replacingOccurrences(of: " ", with: "-")
    }

    var effectiveStrategy: WorktreeStrategy {
        worktreeStrategy ?? .newBranch
    }
}
