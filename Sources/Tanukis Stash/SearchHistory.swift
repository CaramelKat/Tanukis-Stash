//
//  SearchHistory.swift
//  Tanuki's Stash
//
//  Remembers the last submitted query (so the app reopens on it) and keeps a
//  short list of recent queries for the search suggestions.
//

import Foundation

enum SearchHistory {
    private static let lastKey = "LAST_SEARCH"
    private static let recentKey = "RECENT_SEARCHES"
    private static let maxRecent = 8

    /// The query the app opens with on launch. Empty means the default feed.
    static var lastSearch: String {
        UserDefaults.standard.string(forKey: lastKey) ?? ""
    }

    /// Submitted queries, newest first.
    static var recent: [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    /// Saves a submitted query as the most recent one. An empty query clears
    /// the saved query (the app then opens on the default feed) but is not
    /// added to the history.
    static func record(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: lastKey)
        guard !trimmed.isEmpty else { return }

        // Move an existing entry to the top instead of duplicating it.
        var items = recent.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        if items.count > maxRecent {
            items.removeLast(items.count - maxRecent)
        }
        UserDefaults.standard.set(items, forKey: recentKey)
    }

    static func clearRecent() {
        UserDefaults.standard.removeObject(forKey: recentKey)
    }
}
