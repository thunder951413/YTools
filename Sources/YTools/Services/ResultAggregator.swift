import Foundation

struct AggregatedResults {
    let results: [LauncherResult]
    let selectedIndex: Int
}

/// Owns result ranking and privacy-preserving usage learning.
@MainActor
final class ResultAggregator {
    private let usage: UsageRankingStore

    init(usage: UsageRankingStore = UsageRankingStore()) {
        self.usage = usage
    }

    func aggregate(
        background: [LauncherResult],
        spotlight: [LauncherResult],
        query: String,
        previousResults: [LauncherResult],
        selectedIndex: Int
    ) -> AggregatedResults {
        let selectedID = previousResults.indices.contains(selectedIndex)
            ? previousResults[selectedIndex].id
            : nil
        let results = (background + spotlight)
            .map { result in
                result.withScore(result.score + usage.boost(for: result.id, query: query))
            }
            .sorted {
                if $0.score == $1.score { return $0.title < $1.title }
                return $0.score > $1.score
            }
        let nextIndex: Int
        if let selectedID, let retained = results.firstIndex(where: { $0.id == selectedID }) {
            nextIndex = retained
        } else {
            nextIndex = results.isEmpty ? 0 : min(selectedIndex, results.count - 1)
        }
        return AggregatedResults(results: results, selectedIndex: nextIndex)
    }

    func record(_ result: LauncherResult, query: String) {
        usage.record(result.id, query: query)
    }

    func clearLearning() {
        usage.clear()
    }
}
