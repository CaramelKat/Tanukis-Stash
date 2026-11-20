//
//  SavedSearchesView.swift
//  Tanuki's Stash
//
//  Lists the user's bookmarked searches. Tapping one runs it and returns to
//  the search screen; swiping left deletes it.
//

import SwiftUI

struct SavedSearchesView: View {
    @Environment(\.dismiss) private var dismiss

    let currentQuery: String
    let onRun: (String) -> Void

    @State private var searches: [SavedSearch] = SavedSearches.all
    @State private var showNamePrompt = false
    @State private var name = ""

    private var trimmedQuery: String {
        currentQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            Section {
                if trimmedQuery.isEmpty {
                    Text("Run a search first, then come back here to save it.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else if SavedSearches.isSaved(trimmedQuery) {
                    Label("This search is already saved.", systemImage: "bookmark.fill")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text(trimmedQuery)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        name = trimmedQuery
                        showNamePrompt = true
                    } label: {
                        Label("Save Current Search", systemImage: "bookmark")
                    }
                    Text(trimmedQuery)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Current Search")
            }

            Section {
                if searches.isEmpty {
                    Text("No saved searches yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(searches) { saved in
                        Button {
                            onRun(saved.query)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(saved.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                if saved.name.caseInsensitiveCompare(saved.query) != .orderedSame {
                                    Text(saved.query)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            SavedSearches.remove(searches[index].id)
                        }
                        searches = SavedSearches.all
                    }
                }
            } header: {
                Text("Saved")
            } footer: {
                if !searches.isEmpty {
                    Text("Tap a search to run it again. Swipe left to delete.")
                }
            }
        }
        .navigationTitle("Saved Searches")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Save Search", isPresented: $showNamePrompt) {
            TextField("Name", text: $name)
            Button("Save") {
                SavedSearches.save(name: name, query: trimmedQuery)
                searches = SavedSearches.all
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Give this search a name so you can find it later.")
        }
    }
}
