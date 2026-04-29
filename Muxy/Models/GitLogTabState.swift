import Foundation
import os

private let gitLogLogger = Logger(subsystem: "app.muxy", category: "GitLogTabState")

@MainActor
@Observable
final class GitLogTabState: Identifiable {
    let id = UUID()
    let projectPath: String
    var commits: [GitCommit] = []
    var graphRows: [GitGraphLayoutRow] = []
    var selectedCommitHash: String?
    var isLoading = false
    var lastError: String?
    var pageSize: Int = 150
    private var loadTask: Task<Void, Never>?

    init(projectPath: String) {
        self.projectPath = projectPath
    }

    var displayTitle: String { "Commit Graph" }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil
        let path = projectPath
        let limit = pageSize
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                let fetched = try await GitRepositoryService().commitLog(repoPath: path, maxCount: limit)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    self.commits = fetched
                    self.graphRows = GitGraphLayout.layout(commits: fetched)
                    if self.selectedCommitHash == nil {
                        self.selectedCommitHash = fetched.first?.hash
                    }
                    self.isLoading = false
                }
            } catch {
                gitLogLogger.error("Failed to load commits: \(error.localizedDescription)")
                await MainActor.run {
                    guard let self else { return }
                    self.lastError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func select(hash: String) {
        selectedCommitHash = hash
    }

    var selectedCommit: GitCommit? {
        guard let hash = selectedCommitHash else { return commits.first }
        return commits.first { $0.hash == hash }
    }
}
