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
        selectedIndex: Int,
        preserveOrder: Bool = false
    ) -> AggregatedResults {
        let selectedID = previousResults.indices.contains(selectedIndex)
            ? previousResults[selectedIndex].id
            : nil
        let combined = background + spotlight
        let results: [LauncherResult]
        if preserveOrder {
            results = combined
        } else {
            let queryHash = usage.normalizedQueryHash(for: query)
            let now = Date()
            results = combined
                .map { result -> (result: LauncherResult, tieCount: Int) in
                    let stats = usage.boostAndCount(for: result.id, queryHash: queryHash, now: now)
                    return (
                        result.withScore(result.score + stats.boost),
                        result.moduleID == "applications" ? stats.count : 0
                    )
                }
                .sorted {
                    if $0.result.score != $1.result.score { return $0.result.score > $1.result.score }
                    if $0.tieCount != $1.tieCount { return $0.tieCount > $1.tieCount }
                    return $0.result.title.localizedStandardCompare($1.result.title) == .orderedAscending
                }
                .map(\.result)
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
