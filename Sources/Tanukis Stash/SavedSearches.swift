//
//  SavedSearches.swift
//  Tanuki's Stash
//
//  Named searches the user bookmarks, kept on-device so they can be reopened
//  later. A saved search stores the query itself plus an optional friendly
//  name (the query is used when no name is given).
//

import Foundation

struct SavedSearch: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var query: String

    init(id: UUID = UUID(), name: String, query: String) {
        self.id = id
        self.name = name
        self.query = query
    }
}

enum SavedSearches {
    private static let key = "SAVED_SEARCHES"

    /// Saved searches, newest first.
    static var all: [SavedSearch] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([SavedSearch].self, from: data) else {
            return []
        }
        return items
    }

    /// Saves a query under a friendly name. Saving a query that is already
    /// saved updates its name instead of creating a duplicate.
    static func save(name: String, query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? trimmedQuery : trimmedName

        var items = all
        if let index = items.firstIndex(where: {
            $0.query.caseInsensitiveCompare(trimmedQuery) == .orderedSame
        }) {
            items[index].name = displayName
        } else {
            items.insert(SavedSearch(name: displayName, query: trimmedQuery), at: 0)
        }
        persist(items)
    }

    static func remove(_ id: UUID) {
        persist(all.filter { $0.id != id })
    }

    static func isSaved(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return all.contains { $0.query.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private static func persist(_ items: [SavedSearch]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
