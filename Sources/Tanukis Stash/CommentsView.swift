import SwiftUI
import AttributedText

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
                        Text("No comments on this post yet.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(comments) { comment in
                            CommentRow(comment: comment)
                        }
                        .listStyle(.plain)
                    }
                } else {
                    ProgressView("Loading comments...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Comments")
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
        comments = await fetchComments(postId: post.id)
        loaded = true
    }
}

struct CommentRow: View {
    var comment: CommentContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(comment.creator_name)
                    .font(.headline)
                Spacer()
                Text(datePrefix(comment.created_at))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            AttributedText(descParser(text: .init(comment.body)))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("\(comment.score)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

func datePrefix(_ raw: String) -> String {
    let parts = raw.split(separator: "T")
    return parts.first.map(String.init) ?? raw
}