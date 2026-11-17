import SwiftUI

struct CommentsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State var post: PostContent
    @State private var comments: [CommentContent] = []
    @State private var loaded: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if loaded {
                    if comments.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 42))
                                .foregroundColor(.secondary)
                            Text("No comments on this post yet.")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(comments) { comment in
                                    CommentRow(comment: comment)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                } else {
                    ProgressView("Loading comments...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(comments.isEmpty ? "Comments" : "Comments (\(comments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .task {
            await load()
        }
    }

    func load() async {
        guard !loaded else { return }
        // Oldest first reads naturally as a conversation.
        comments = await fetchComments(postId: post.id)
            .sorted { $0.created_at < $1.created_at }
        loaded = true
    }
}

struct CommentRow: View {
    var comment: CommentContent

    @Environment(\.openURL) private var openURL

    private var initial: String {
        String(comment.creator_name.prefix(1)).uppercased()
    }

    /// A stable color per commenter, so the same person is recognisable at a
    /// glance while scrolling.
    private var avatarColor: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .red]
        var hash: UInt = 5381
        for scalar in comment.creator_name.unicodeScalars {
            hash = (hash &* 33) &+ UInt(scalar.value)
        }
        return palette[Int(hash % UInt(palette.count))]
    }

    /// A leading `@name` mention, optionally after a quoted block. e621 has no
    /// parent-comment field, so this is the reliable way to spot a reply.
    private var replyHandle: String? {
        var body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let quoted = body.range(
            of: #"(?s)^\s*\[quote(?:=[^\]]*)?\].*?\[/quote\]\s*"#,
            options: .regularExpression
        ) {
            body = String(body[quoted.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard body.hasPrefix("@") else { return nil }
        let handle = body.dropFirst().prefix { character in
            character.isLetter || character.isNumber || character == "_" || character == "-" || character == "."
        }
        return handle.isEmpty ? nil : String(handle)
    }

    private var scoreColor: Color {
        if comment.score > 0 { return .green }
        if comment.score < 0 { return .orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 9) {
                NavigationLink(destination: SearchView(search: "fav:\(comment.creator_name)")) {
                    HStack(alignment: .center, spacing: 9) {
                        Text(initial)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(avatarColor.gradient, in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(comment.creator_name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            Text(commentDate(comment.created_at))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(comment.creator_name)'s favorites")
                .contextMenu {
                    if let id = comment.creator_id,
                       let url = URL(string: "https://\(apiHost)/users/\(id)") {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open Profile in Browser", systemImage: "safari")
                        }
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 3) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 9))
                    Text("\(comment.score)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundColor(scoreColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(scoreColor.opacity(comment.score == 0 ? 0 : 0.12))
                )
            }

            if let replyHandle {
                HStack(spacing: 5) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption2)
                    Text("Replying to")
                    NavigationLink(destination: SearchView(search: "fav:\(replyHandle)")) {
                        Text("@\(replyHandle)")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
            }

            // Full BBCode rendering, including distinct quote panels.
            DTextView(text: comment.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private var apiHost: String {
        UserDefaults.standard.string(forKey: "api_source") ?? "e926.net"
    }
}

/// "2026-11-17T12:34:56.789Z" -> "Nov 17, 2026"
func commentDate(_ raw: String) -> String {
    let cleaned = raw.replacingOccurrences(
        of: #"\.\d+"#,
        with: "",
        options: .regularExpression
    )
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    guard let date = iso.date(from: cleaned) else {
        return datePrefix(raw)
    }
    let display = DateFormatter()
    display.dateStyle = .medium
    display.timeStyle = .none
    return display.string(from: date)
}

func datePrefix(_ raw: String) -> String {
    let parts = raw.split(separator: "T")
    return parts.first.map(String.init) ?? raw
}
