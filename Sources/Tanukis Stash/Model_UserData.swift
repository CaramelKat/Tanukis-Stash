import SwiftUI

struct UserData: Decodable, Hashable {
    static func == (lhs: UserData, rhs: UserData) -> Bool {
        return lhs.id == rhs.id
    }
    
    let id: Int;
    let created_at: String;
    let name: String;
    let level: Int;
    let base_upload_limit: Int;
    let post_upload_count: Int;
    let post_update_count: Int;
    let note_update_count: Int;
    let is_banned: Bool;
    let can_approve_posts: Bool;
    let can_upload_free: Bool;
    let level_string: String;
    let avatar_id: Int;
    let blacklist_users: Bool;
    let description_collapsed_initially: Bool;
    let hide_comments: Bool;
    let show_hidden_comments: Bool;
    let show_post_statistics: Bool;
    let receive_email_notifications: Bool;
    let enable_keyboard_navigation: Bool;
    let enable_privacy_mode: Bool;
    let style_usernames: Bool;
    let enable_auto_complete: Bool;
    let disable_cropped_thumbnails: Bool;
    let enable_safe_mode: Bool;
    let disable_responsive_mode: Bool;
    let no_flagging: Bool;
    let disable_user_dmails: Bool;
    let enable_compact_uploader: Bool;
    let replacements_beta: Bool;
    let forum_notification_dot: Bool;
    let updated_at: String;
    let email: String;
    let last_logged_in_at: String;
    let last_forum_read_at: String;
    let recent_tags: String;
    let comment_threshold: Int;
    let default_image_size: String;
    let favorite_tags: String;
    let blacklisted_tags: String;
    let time_zone: String;
    let per_page: Int;
    let custom_style: String;
    let favorite_count: Int;
    let api_regen_multiplier: Int;
    let api_burst_limit: Int;
    let remaining_api_limit: Int
    let statement_timeout: Int;
    let favorite_limit: Int;
    let tag_query_limit: Int;
    let has_mail: Bool;
    let unread_dmail_count: Int;
}
