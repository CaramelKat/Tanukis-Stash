import SwiftUI

struct CommentContent: Decodable, Identifiable, Hashable {
    let id: Int;
    let created_at: String;
    let creator_id: Int?;
    let creator_name: String;
    let body: String;
    let score: Int;
}