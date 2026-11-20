import SwiftUI

/// Response of GET /posts.json.
///
/// The API returns a bare `[...]` array in v2 and the old `{"posts": [...]}`
/// envelope in v1. Requests ask for v2 now, but both shapes are decoded so
/// cached responses and the remaining v1-capable window keep working.
struct Posts: Decodable {
    let posts: [PostContent]

    private enum CodingKeys: String, CodingKey { case posts }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let posts = try? container.decode([PostContent].self) {
            self.posts = posts
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.posts = try container.decode([PostContent].self, forKey: .posts)
    }
}

/// Response of GET /posts/<id>.json. Accepts both the legacy `{"post": {...}}`
/// envelope and the bare object used by the v2 format.
struct Post: Decodable {
    let post: PostContent;

    private enum CodingKeys: String, CodingKey { case post }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let post = try? container.decode(PostContent.self) {
            self.post = post
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.post = try container.decode(PostContent.self, forKey: .post)
    }
}

// Response of GET /posts/count.json — the precise number of posts matching a
// tag query. `capped` means the query has more posts than the server is
// willing to count, so `count` is a lower bound.
struct PostSearchCount: Decodable {
    let count: Int;
    let capped: Bool;
}

struct PostContent: Decodable, Hashable {
    static func == (lhs: PostContent, rhs: PostContent) -> Bool {
        return lhs.id == rhs.id
    }

    /// Identity is the post id. Without this, SwiftUI/text diffing would hash
    /// every tag array on every grid update.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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

    private enum CodingKeys: String, CodingKey {
        case id, created_at, updated_at
        case file, preview, sample, score, tags, locked_tags, change_seq
        case flags, rating, fav_count, sources, pools, relationships
        case approver_id, uploader_id, description, comment_count
        case is_favorited, has_notes, duration
        // v2 groups these fields into nested objects.
        case files, stats, has
    }

    /// Decodes both the legacy shape and the v2 shape that became the default
    /// on 2026-11-18. v2 moves file data into `files`, scores into `stats`
    /// and relationship/note flags into `has`; mapping them back here keeps
    /// the rest of the app unchanged.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        created_at = try container.decode(String.self, forKey: .created_at)
        updated_at = try container.decode(String.self, forKey: .updated_at)
        locked_tags = try container.decode([String].self, forKey: .locked_tags)
        change_seq = try container.decode(Int.self, forKey: .change_seq)
        flags = try container.decode(Flags.self, forKey: .flags)
        rating = try container.decode(String.self, forKey: .rating)
        sources = try container.decode([String].self, forKey: .sources)
        pools = try container.decode([Int].self, forKey: .pools)
        approver_id = try container.decodeIfPresent(Int.self, forKey: .approver_id)
        uploader_id = try container.decode(Int.self, forKey: .uploader_id)
        description = try container.decode(String.self, forKey: .description)
        // Both formats group tags by category (v2 via mode=extended).
        tags = try container.decode(Tags.self, forKey: .tags)

        if let files = try container.decodeIfPresent(V2Files.self, forKey: .files) {
            let has = try container.decodeIfPresent(V2Has.self, forKey: .has)
            let stats = try container.decode(V2Stats.self, forKey: .stats)
            let relationship = try container.decode(V2Relationships.self, forKey: .relationships)

            file = files.file
            preview = files.preview
            sample = files.sample(hasSample: has?.sample ?? files.meta.has_sample ?? false)
            duration = files.meta.duration
            score = stats.score
            fav_count = stats.fav_count
            comment_count = stats.comment_count
            is_favorited = stats.is_favorited
            relationships = Relationships(
                parent_id: relationship.parent_id,
                has_children: has?.children ?? false,
                has_active_children: has?.active_children ?? false,
                children: relationship.children ?? []
            )
            has_notes = has?.notes ?? false
        } else {
            file = try container.decode(File.self, forKey: .file)
            preview = try container.decode(Preview.self, forKey: .preview)
            sample = try container.decode(Sample.self, forKey: .sample)
            duration = try container.decodeIfPresent(Float.self, forKey: .duration)
            score = try container.decode(Score.self, forKey: .score)
            fav_count = try container.decode(Int.self, forKey: .fav_count)
            comment_count = try container.decode(Int.self, forKey: .comment_count)
            is_favorited = try container.decodeIfPresent(Bool.self, forKey: .is_favorited) ?? false
            relationships = try container.decode(Relationships.self, forKey: .relationships)
            has_notes = try container.decode(Bool.self, forKey: .has_notes)
        }
    }

    var isAnimated: Bool {
        return ["gif", "webm", "mp4"].contains(file.ext) || tags.general.contains("animated");
    }

    /// The medium-size file shown on screen: the server's sample when it
    /// exists (a few megapixels at most), otherwise the original.
    var sampleOrFileURL: URL? {
        URL(string: sample.url ?? file.url ?? "")
    }

    /// The untouched original file, used for zooming and downloads.
    var originalURL: URL? {
        URL(string: file.url ?? "")
    }
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
    let alternates: Alternates?;
}

struct Alternates: Decodable, Hashable {
    let original: Alternate?
    let variants: Variants?
}

struct Variants: Decodable, Hashable {
    let mp4: Alternate?;
}

struct Alternate: Decodable, Hashable {
    let type: String?;
    let height: Int?;
    let width: Int?;
    let url: String?;
    let urls: [String]?;
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

/// The v2 post format nests file data under `files`. Only the values the app
/// uses are modelled; unknown keys are ignored by Codable.
private struct V2Files: Decodable {
    struct Meta: Decodable {
        let md5: String
        let ext: String
        let size: Int
        let duration: Float?
        let has_sample: Bool?
    }

    struct Original: Decodable {
        let width: Int
        let height: Int
        let url: String?
    }

    struct Image: Decodable {
        let width: Int?
        let height: Int?
        let jpg: String?
        let webp: String?
    }

    struct Video: Decodable {
        struct File: Decodable {
            let type: String?
            let width: Int?
            let height: Int?
            let url: String?
        }

        struct Variants: Decodable {
            let mp4: File?
        }

        let original: File?
        let variants: Variants?
    }

    let meta: Meta
    let original: Original
    let previewImage: Image?
    let sampleImage: Image?
    let video: Video?

    private enum CodingKeys: String, CodingKey {
        case meta, original, video
        case previewImage = "preview"
        case sampleImage = "sample"
    }

    var file: File {
        File(
            width: original.width,
            height: original.height,
            ext: meta.ext,
            size: meta.size,
            md5: meta.md5,
            url: original.url
        )
    }

    var preview: Preview {
        Preview(
            width: previewImage?.width ?? original.width,
            height: previewImage?.height ?? original.height,
            url: previewImage?.jpg ?? previewImage?.webp
        )
    }

    func sample(hasSample: Bool) -> Sample {
        let alternates: Alternates? = video.map { video in
            Alternates(
                original: video.original.map { Alternate($0) },
                variants: video.variants.map { Variants(mp4: $0.mp4.map { Alternate($0) }) }
            )
        }
        return Sample(
            has: hasSample,
            height: sampleImage?.height ?? original.height,
            width: sampleImage?.width ?? original.width,
            url: sampleImage?.jpg ?? sampleImage?.webp,
            alternates: alternates
        )
    }
}

private extension Alternate {
    /// Adapts a v2 video file so downloads and playback can keep using the
    /// legacy `sample.alternates.variants.mp4` path.
    init(_ file: V2Files.Video.File) {
        self.init(
            type: file.type,
            height: file.height,
            width: file.width,
            url: file.url,
            urls: nil
        )
    }
}

private struct V2Stats: Decodable {
    let score: Score
    let fav_count: Int
    let is_favorited: Bool
    let comment_count: Int
}

private struct V2Has: Decodable {
    let parent: Bool?
    let children: Bool?
    let active_children: Bool?
    let notes: Bool?
    let sample: Bool?
}

private struct V2Relationships: Decodable {
    let parent_id: Int?
    let children: [Int]?
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
