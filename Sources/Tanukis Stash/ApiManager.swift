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

func areTagsBlacklisted(blacklistedArray: [String], postTags: [String]) -> Bool {
    for tag in blacklistedArray {
         // Each line in the blacklist can contain multiple tags separated by spaces, if post contains all of them, it is blacklisted
        let blacklistLineTags = tag.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let blacklistLineTagsSet = Set(blacklistLineTags)
        let postTagsSet = Set(postTags.map { $0.lowercased() })
        // Check if the post tags contain all the blacklisted tags in this line
        if blacklistLineTagsSet.isSubset(of: postTagsSet) {
            os_log("Post is blacklisted due to tags: %{public}s", log: .default, tag);
            return true;
        }
    }
    return false

}

func isPostBlacklisted(_ post: PostContent) async -> Bool {
    let blacklistedTags = UserDefaults.standard.string(forKey: "USER_BLACKLIST") ?? "";
    if (blacklistedTags == "No Auth" || blacklistedTags == "Bad usrdata") {
        return false;
    }
    // Split the blacklisted tags into an array
    let blacklistedArray = blacklistedTags.lowercased().split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
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

    return areTagsBlacklisted(blacklistedArray: blacklistedArray, postTags: allPostTags)
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

        // If the blacklist is enabled, filter out blacklisted posts
        if (UserDefaults.standard.bool(forKey: "ENABLE_BLACKLIST")) {
            var filteredPosts = [PostContent]()
            for post in parsedData.posts {
                if !(await isPostBlacklisted(post)) {
                    filteredPosts.append(post)
                }
            }
            return filteredPosts
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

func favoritePost(postId: Int) async -> Bool {
    let url = "/favorites.json?post_id=\(postId)"
    let result = await makeStatusRequest(destination: url, method: "POST", body: nil, contentType: "application/json");
    guard let status = result.status else { return false; }
    // 409 = already favorited: the desired state already holds.
    return (200..<300).contains(status) || status == 409;
}

func unFavoritePost(postId: Int) async -> Bool {
    let url = "/favorites/\(postId).json"
    let result = await makeStatusRequest(destination: url, method: "DELETE", body: nil, contentType: "application/json");
    guard let status = result.status else { return false; }
    // 404/409 = no favorite to remove: the desired state already holds.
    return (200..<300).contains(status) || status == 404 || status == 409;
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
    if (noCache) {
        // State fetches (favorites, votes) must not be served from the URL
        // cache, or they would report the state from before the last action.
        request.cachePolicy = .reloadIgnoringLocalCacheData
    }
    request.httpMethod = method
    request.addValue(contentType, forHTTPHeaderField: "Content-Type")
    request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

    if ![API_KEY, username].contains("") {
        request.addValue("Basic \(AUTH_STRING)", forHTTPHeaderField: "Authorization")
    }

    do {
        if (body != nil && method != "GET") {
            request.httpBody = body!;
        }
        let (data, response) = try await URLSession.shared.data(for: request);

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
@MainActor
func fetchPostIsFavorited(postId: Int) async -> Bool {
    do {
        let url = "/posts/\(postId).json"
        let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json", noCache: true);
        if (data) == nil { return false; }
        let parsedData = try JSONDecoder().decode(Post.self, from: data!)
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

    var request = URLRequest(url: url!)
    if (noCache) {
        // State fetches (favorites, votes) must not be served from the URL
        // cache, or they would report the state from before the last action.
        request.cachePolicy = .reloadIgnoringLocalCacheData
    }
    request.httpMethod = method
    request.addValue(contentType, forHTTPHeaderField: "Content-Type")
    request.addValue(userAgent, forHTTPHeaderField: "User-Agent")

    if ![API_KEY, username].contains("") {
        request.addValue("Basic \(AUTH_STRING)", forHTTPHeaderField: "Authorization")
    }

    do {
        if (body != nil && method != "GET") {
            request.httpBody = body!
        }
        let (data, response) = try await URLSession.shared.data(for: request);
        
        os_log("HTTP %{public}s %{public}d https://%{public}s%{public}s", log: .default, method, response.getStatusCode() ?? -1, domain, destination)
        return data;
    } catch {
        DispatchQueue.main.async {
            os_log("Failed to make request: %{public}s", log: .default, error.localizedDescription);
        }
        return nil
    }
}
