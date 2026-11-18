//
//  TagManager.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 7/15/22.
//

import Foundation
import SwiftUI
import os.log

let userAgent: String = "Tanukis%20Stash/0.0.5%20(by%20JemTanuki%20on%20e621)";
let log = OSLog.init(subsystem: "dev.jemsoftware.tanukistash", category: "main")

// Thanks Stackoverflow: https://stackoverflow.com/a/45624666
extension URLResponse {

    func getStatusCode() -> Int? {
        if let httpResponse = self as? HTTPURLResponse {
            return httpResponse.statusCode
        }
        return nil
    }
}

func login() async -> Bool {
    let username = UserDefaults.standard.string(forKey: "username") ?? "";
    let API_KEY = UserDefaults.standard.string(forKey: "API_KEY") ?? "";
    if username.isEmpty || API_KEY.isEmpty {
        return false;
    }
    let testFavorites = await fetchRecentPosts(1, 1, "fav:\(username)");
    if testFavorites.isEmpty {
        os_log("Login failed for %{public}s", log: .default, username);
        return false;
    }
    os_log("Login successful for %{public}s", log: .default, username);
    return true;
}

/// Parses the multiline blacklist once per fetch instead of once per post.
/// Each line becomes a set of tags; a post is hidden when it contains every
/// tag on any line.
func blacklistLineSets(_ blacklistedTags: String) -> [Set<String>] {
    blacklistedTags
        .lowercased()
        .split(separator: "\n")
        .map { line in
            Set(line.split(separator: " ").map(String.init))
        }
        .filter { !$0.isEmpty }
}

func areTagsBlacklisted(blacklistLines: [Set<String>], postTags: [String]) -> Bool {
    // Build the post's tag set once, not once per blacklist line.
    let postTagsSet = Set(postTags.lazy.map { $0.lowercased() })
    for line in blacklistLines where line.isSubset(of: postTagsSet) {
        return true
    }
    return false
}

func isPostBlacklisted(_ post: PostContent, blacklistLines: [Set<String>]) -> Bool {
    if (blacklistLines.isEmpty) {
        return false;
    }
    var allPostTags = post.tags.general

    allPostTags.append(contentsOf: post.tags.species)
    allPostTags.append(contentsOf: post.tags.character)
    allPostTags.append(contentsOf: post.tags.copyright)
    allPostTags.append(contentsOf: post.tags.artist)
    allPostTags.append(contentsOf: post.tags.invalid)
    allPostTags.append(contentsOf: post.tags.lore)
    allPostTags.append(contentsOf: post.tags.meta)

    // Get post rating and convert it to a tag
    switch post.rating {
        case "s":
            allPostTags.append("rating:safe")
        case "q":
            allPostTags.append("rating:questionable")
        case "e":
            allPostTags.append("rating:explicit")
        default:
            os_log("Unknown rating %{public}s for post %{public}d", log: .default, post.rating, post.id);
    }

    return areTagsBlacklisted(blacklistLines: blacklistLines, postTags: allPostTags)
}

func fetchUserData() async -> UserData? {
    let username = UserDefaults.standard.string(forKey: "username") ?? "";
    let url = "/users/\(username).json"
    do {
        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
        if (data) == nil { return nil; }
        let userData = try JSONDecoder().decode(UserData.self, from: data!);
        return userData;
    } catch {
        os_log("Error fetching user data: %{public}s", log: .default, error.localizedDescription);
        return nil;
    }
}

func fetchBlacklist() async -> String {
    let authenticated = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    if (!authenticated) {
        os_log("Not authenticated, skipping blacklist update", log: .default);
        return "No Auth";
    }
    let userdata = await fetchUserData();
    if (userdata == nil) {
        os_log("Failed to fetch user data", log: .default);
        return "Bad usrdata";
    }
    let data = userdata!.blacklisted_tags;
    return data;
}

func fetchTags(_ text: String) async -> [String] {
    do {
        let encoded: String? = text.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        let url: String = "/tags/autocomplete.json?search%5Bname_matches%5D=\(encoded!)&expiry=7&_client=\(userAgent)"

        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
        if (data) == nil { return []; }
        let tags: [TagContent] = try JSONDecoder().decode([TagContent].self, from: data!)
        return await processTags(tags);
    } catch {
        //os_log("%{public}s", log: .default, error);
        return [];
    }
}

func processTags(_ tags: [TagContent]) async  -> [String] {
    var tagList = [String]();
    for tag in tags {
        tagList.append(tag.name);
    }
    return tagList
}

func parseSearch(_ searchText: String) -> String {
    if(searchText.contains(" ")) {
        let index = searchText.lastIndex(of: " ");
        if(index != nil) {
            return String(searchText[index!...]).trimmingCharacters(in: .whitespacesAndNewlines);
        }
        else {return "";}
    }
    else { return searchText; }
}

func createTagList(_ search: String) async -> [String] {
    let newSearchText = parseSearch(search);
    if(newSearchText.count >= 3) {
        return await fetchTags(newSearchText);
    }
    return []
}

func getPost(postId: Int) async -> PostContent? {
    let url = "/posts/\(postId).json"
    do {
        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
        if (data) == nil { return nil; }
        let post: Post = try JSONDecoder().decode(Post.self, from: data!);
        // If the blacklist is enabled, check if the post is blacklisted
        return post.post;
    } catch {
        os_log("Error fetching post %{public}d: %{public}s", log: .default, postId, error.localizedDescription);
        return nil;
    }
}

func fetchRecentPosts(_ page: Int, _ limit: Int, _ tags: String) async -> [PostContent] {
    do {
        let username = UserDefaults.standard.string(forKey: "username") ?? "";
        let encoded = tags.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        let url: String;

        if (tags == "fav:\(username)") {
            url = "/favorites.json?limit=\(limit)&page=\(page)"
        } else {
            url = "/posts.json?tags=\(encoded ?? "")&limit=\(limit)&page=\(page)"
        }

        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");

        if (data) == nil { 
            os_log("Failed to fetch posts", log: .default);
            return []; 
        }

        let parsedData: Posts = try JSONDecoder().decode(Posts.self, from: data!)

        // If the blacklist is enabled, filter out blacklisted posts. The
        // blacklist is parsed once here rather than once per post.
        if (UserDefaults.standard.bool(forKey: "ENABLE_BLACKLIST")) {
            let rawBlacklist = UserDefaults.standard.string(forKey: "USER_BLACKLIST") ?? "";
            if (rawBlacklist == "No Auth" || rawBlacklist == "Bad usrdata") {
                return parsedData.posts;
            }
            let lineSets = blacklistLineSets(rawBlacklist);
            return parsedData.posts.filter { !isPostBlacklisted($0, blacklistLines: lineSets) }
        }

        return parsedData.posts;
    } catch {
        os_log("Error! %{public}@", log: .default, String(describing: error));
        return [];
    }
}

// Fetches the precise number of posts matching a search query from the
// server's count endpoint (GET /posts/count.json). Returns nil for an empty
// search or if the request fails, so the UI can hide the count.
func fetchPostCount(search: String) async -> PostSearchCount? {
    let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines);
    if (trimmed.isEmpty) { return nil; }

    let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "";
    let url: String = "/posts/count.json?tags=\(encoded)";

    let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json", noCache: true);
    if (data) == nil { return nil; }

    do {
        return try JSONDecoder().decode(PostSearchCount.self, from: data!);
    } catch {
        os_log("Error fetching post count: %{public}s", log: .default, error.localizedDescription);
        return nil;
    }
}

/// In-memory favorite state per post, seeded from the post data the grid has
/// already downloaded. Opening a post therefore no longer re-fetches the whole
/// post JSON just to learn whether the heart is filled.
@MainActor private var favoriteStateCache: [Int: (value: Bool, at: Date)] = [:]
private let favoriteStateTTL: TimeInterval = 300

@MainActor
func rememberFavoriteState(postId: Int, value: Bool) {
    favoriteStateCache[postId] = (value, Date())
}

@MainActor
private func cachedFavoriteState(postId: Int) -> Bool? {
    guard let cached = favoriteStateCache[postId] else { return nil }
    if Date().timeIntervalSince(cached.at) > favoriteStateTTL {
        favoriteStateCache[postId] = nil
        return nil
    }
    return cached.value
}

@MainActor
func favoritePost(postId: Int) async -> Bool {
    let url = "/favorites.json?post_id=\(postId)"
    let result = await makeStatusRequest(destination: url, method: "POST", body: nil, contentType: "application/json");
    guard let status = result.status else { return false; }
    // 409 = already favorited: the desired state already holds.
    let success = (200..<300).contains(status) || status == 409;
    if (success) { rememberFavoriteState(postId: postId, value: true) }
    return success;
}

@MainActor
func unFavoritePost(postId: Int) async -> Bool {
    let url = "/favorites/\(postId).json"
    let result = await makeStatusRequest(destination: url, method: "DELETE", body: nil, contentType: "application/json");
    guard let status = result.status else { return false; }
    // 404/409 = no favorite to remove: the desired state already holds.
    let success = (200..<300).contains(status) || status == 404 || status == 409;
    if (success) { rememberFavoriteState(postId: postId, value: false) }
    return success;
}

/// Like makeRequest, but also reports the HTTP status code. makeRequest
/// returns response bodies even for error statuses, which makes a successful
/// action indistinguishable from a rejected one.
func makeStatusRequest(destination: String, method: String, body: Data?, contentType: String, noCache: Bool = false) async -> (data: Data?, status: Int?) {
    let domain = UserDefaults.standard.string(forKey: "api_source") ?? "e926.net";
    let API_KEY = UserDefaults.standard.string(forKey: "API_KEY") ?? "";
    let username = UserDefaults.standard.string(forKey: "username") ?? "";
    let AUTH_STRING: String = "\(username):\(API_KEY)".data(using: .utf8)?.base64EncodedString() ?? "";
    guard let url = URL(string: "https://\(domain)\(destination)") else { return (nil, nil); }

    var request = URLRequest(url: url)
    request.timeoutInterval = 25
    if (noCache) {
        // State fetches (favorites, votes) must not be served from the URL
        // cache, or they would report the state from before the last action.
        request.cachePolicy = .reloadIgnoringLocalCacheData
    }
    request.httpMethod = method
    request.addValue(contentType, forHTTPHeaderField: "Content-Type")
    request.addValue(contentType, forHTTPHeaderField: "Accept")
    request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

    if ![API_KEY, username].contains("") {
        request.addValue("Basic \(AUTH_STRING)", forHTTPHeaderField: "Authorization")
    }

    do {
        if (body != nil && method != "GET") {
            request.httpBody = body!;
        }
        let (data, response) = try await NetworkSession.shared.data(for: request);

        os_log("HTTP %{public}s %{public}d https://%{public}s%{public}s", log: .default, method, response.getStatusCode() ?? -1, domain, destination)
        return (data, response.getStatusCode());
    } catch {
        DispatchQueue.main.async {
            os_log("Failed to make request: %{public}s", log: .default, error.localizedDescription);
        }
        return (nil, nil);
    }
}

/// Whether the logged-in user has favorited the given post.
///
/// `seeded` comes from the post data the grid already has, so opening a post
/// is instant and normally needs no request at all. The cache is kept for a
/// few minutes so the post page and the fullscreen viewer share one answer.
@MainActor
func fetchPostIsFavorited(postId: Int, seeded: Bool? = nil) async -> Bool {
    if let cached = cachedFavoriteState(postId: postId) { return cached }
    if let seeded {
        rememberFavoriteState(postId: postId, value: seeded)
        return seeded
    }
    guard UserDefaults.standard.bool(forKey: "AUTHENTICATED") else { return false }
    do {
        let url = "/posts/\(postId).json"
        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json", noCache: true);
        if (data) == nil { return false; }
        let parsedData = try JSONDecoder().decode(Post.self, from: data!)
        rememberFavoriteState(postId: postId, value: parsedData.post.is_favorited)
        return parsedData.post.is_favorited;
    } catch {
        print(error);
        return false;
    }
}

func fetchComments(postId: Int) async -> [CommentContent] {
    do {
        let url: String = "/comments.json?search%5Bpost_id%5D=\(postId)"
        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
        if (data) == nil { return []; }
        let parsedData = try JSONDecoder().decode([CommentContent].self, from: data!)
        return parsedData;
    } catch {
        os_log("Error fetching comments: %{public}s", log: .default, error.localizedDescription);
        return [];
    }
}

// In-memory cache of the logged-in user's vote per post. Populated by
// successful state fetches and by vote responses, so the vote buttons can
// render instantly instead of waiting on a slow fetch.
@MainActor private var ourVoteCache: [Int: Int] = [:]

@MainActor
func getVote(postId: Int) async -> Int {
    if let cached = ourVoteCache[postId] { return cached }
    // Anonymous users cannot vote, so the (large) post HTML fetch would be
    // wasted. Return the neutral state instead.
    guard UserDefaults.standard.bool(forKey: "AUTHENTICATED") else {
        ourVoteCache[postId] = 0
        return 0
    }
    let url = "/posts/\(postId)"
    let result = await makeStatusRequest(destination: url, method: "GET", body: nil, contentType: "text/html", noCache: true);
    // Only cache values from a successful fetch; a failed one (the HTML
    // route is TOS-gated for some clients) would otherwise stick as "no
    // vote" for the rest of the session.
    guard let status = result.status, (200..<300).contains(status), let data = result.data else {
        return ourVoteCache[postId] ?? 0
    }
    let textContent = String(data: data, encoding: .utf8) ?? ""
    var vote = 0
    if textContent.contains("data-vote=\"1\"") {
        vote = 1
    }
    else if textContent.contains("data-vote=\"-1\"") {
        vote = -1
    }
    ourVoteCache[postId] = vote
    return vote
}

@MainActor
func votePost(postId: Int, value: Int, no_unvote: Bool) async -> Int {
    let url = "/posts/\(postId)/votes.json"
    let data = await makeRequest(destination: url, method: "POST", body: "score=\(value)&no_unvote=\(no_unvote)".data(using: .utf8), contentType: "application/x-www-form-urlencoded");
    if (data == nil) { return ourVoteCache[postId] ?? 0; }
    do {
        let json = try JSONDecoder().decode(VoteResponse.self, from: data!);
        let score = json.our_score ?? 0
        ourVoteCache[postId] = score
        return score
    }
    catch {
        return ourVoteCache[postId] ?? 0
    }
}

func makeRequest(destination: String, method: String, body: Data?, contentType: String, noCache: Bool = false) async -> Data? {
    let domain = UserDefaults.standard.string(forKey: "api_source") ?? "e926.net";
    let API_KEY = UserDefaults.standard.string(forKey: "API_KEY") ?? "";
    let username = UserDefaults.standard.string(forKey: "username") ?? "";
    let AUTH_STRING: String = "\(username):\(API_KEY)".data(using: .utf8)?.base64EncodedString() ?? "";
    let url = URL(string: "https://\(domain)\(destination)")

    guard let url else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 25
    if (noCache) {
        // State fetches (favorites, votes) must not be served from the URL
        // cache, or they would report the state from before the last action.
        request.cachePolicy = .reloadIgnoringLocalCacheData
    }
    request.httpMethod = method
    request.addValue(contentType, forHTTPHeaderField: "Content-Type")
    request.addValue(contentType, forHTTPHeaderField: "Accept")
    request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

    if ![API_KEY, username].contains("") {
        request.addValue("Basic \(AUTH_STRING)", forHTTPHeaderField: "Authorization")
    }

    do {
        if (body != nil && method != "GET") {
            request.httpBody = body!
        }
        let (data, response) = try await NetworkSession.shared.data(for: request);
        
        os_log("HTTP %{public}s %{public}d https://%{public}s%{public}s", log: .default, method, response.getStatusCode() ?? -1, domain, destination)
        return data;
    } catch {
        DispatchQueue.main.async {
            os_log("Failed to make request: %{public}s", log: .default, error.localizedDescription);
        }
        return nil
    }
}
