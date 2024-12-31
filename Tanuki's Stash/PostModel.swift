import SwiftUI

struct Posts: Decodable {
    let posts: [PostContent]
}

struct Post: Decodable {
    let post: PostContent;
}

struct PostContent: Decodable, Hashable {
    static func == (lhs: PostContent, rhs: PostContent) -> Bool {
        return lhs.id == rhs.id
    }
    
    let id: Int;
    let created_at: String;
    let updated_at: String;
    let file: File;
    let preview: Preview;
    let sample: Sample;
    let score: Score;
    let tags: Tags;
    let locked_tags: [String];
    let change_seq: Int;
    let flags: Flags;
    let rating: String;
    let fav_count: Int;
    let sources: [String];
    let pools: [Int];
    let relationships: Relationships;
    let approver_id: Int?;
    let uploader_id: Int;
    let description: String;
    let comment_count: Int;
    var is_favorited: Bool;
    let has_notes: Bool;
    let duration: Float?;
}

struct File: Decodable, Hashable {
    let width: Int;
    let height: Int;
    let ext: String;
    let size: Int;
    let md5: String;
    let url: String?;
}

struct Preview: Decodable, Hashable {
    let width: Int;
    let height: Int;
    let url: String?;
}

struct Sample: Decodable, Hashable {
    let has: Bool;
    let height: Int;
    let width: Int;
    let url: String?;
    let alternates: Alternates;
}

struct Alternates: Decodable, Hashable {
    let original: Alternate?
}

struct Alternate: Decodable, Hashable {
    let type: String;
    let height: Int;
    let width: Int;
    let urls: [String?];
}

struct Score: Decodable, Hashable {
    let up: Int;
    let down: Int;
    let total: Int;
}

struct Tags: Decodable, Hashable {
    let general: [String];
    let species: [String];
    let character: [String];
    let copyright: [String];
    let artist: [String];
    let invalid: [String];
    let lore: [String];
    let meta: [String];
}

struct Flags: Decodable, Hashable {
   let pending: Bool;
   let flagged: Bool;
   let note_locked: Bool;
   let status_locked: Bool;
   let rating_locked: Bool;
   let deleted: Bool;
}

struct Relationships: Decodable, Hashable {
    let parent_id: Int?;
    let has_children: Bool;
    let has_active_children: Bool;
    let children: [Int];
}

struct VoteResponse: Decodable, Hashable {
    let score: Int?;
    let up: Int?;
    let down: Int?;
    let our_score: Int?;
    let success: Bool?;
    let message: String?;
    let code: String?;
}
