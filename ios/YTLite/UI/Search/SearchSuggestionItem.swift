import Foundation

struct SearchSuggestionItem: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let isFromHistory: Bool
}

enum SearchSuggestionMerger {
    /// Mirrors Android `SearchResultParser.parseQuerySuggestions`.
    static func merge(
        query: String,
        history: [String],
        remote: [String],
        maxCount: Int = 12
    ) -> [SearchSuggestionItem] {
        var ordered: [SearchSuggestionItem] = []
        var seen = Set<String>()

        func key(for text: String) -> String { "query:\(text.lowercased())" }

        for historyItem in history where historyItem.localizedCaseInsensitiveContains(query) {
            if ordered.count >= 5 { break }
            let k = key(for: historyItem)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            ordered.append(
                SearchSuggestionItem(id: k, text: historyItem, isFromHistory: true)
            )
        }

        for text in remote {
            if ordered.count >= maxCount { break }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let k = key(for: trimmed)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            ordered.append(
                SearchSuggestionItem(id: k, text: trimmed, isFromHistory: false)
            )
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let k = key(for: q)
            if !seen.contains(k) {
                let fromHistory = history.contains { $0.caseInsensitiveCompare(q) == .orderedSame }
                ordered.append(
                    SearchSuggestionItem(id: k, text: q, isFromHistory: fromHistory)
                )
            }
        }

        return ordered
    }
}
