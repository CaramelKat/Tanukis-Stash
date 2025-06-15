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

func favoritePost(postId: Int) async -> Bool {
    let url = "/favorites.json?post_id=\(postId)"
    let data = await makeRequest(destination: url, method: "POST", body: nil, contentType: "application/json");
    if (data) == nil { return false; }
    return true;
}

func unFavoritePost(postId: Int) async -> Bool {
    let url = "/favorites/\(postId).json"
    let data = await makeRequest(destination: url, method: "DELETE", body: nil, contentType: "application/json");
    if (data) == nil { return true; }
    return false;
}

func getVote(postId: Int) async -> Int {
    let url = "/posts/\(postId)"
    let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "text/html");
    if (data == nil) { return 0; }
    do {
        let textContent = String(data: data!, encoding: .utf8) ?? ""
        if textContent.contains("post-vote-up-\(postId) score-positive") {
            return 1
        }
        else if textContent.contains("post-vote-down-\(postId) score-negative") {
            return -1
        }
        return 0
    }
}

func votePost(postId: Int, value: Int, no_unvote: Bool) async -> Int {
    let url = "/posts/\(postId)/votes.json"
    let data = await makeRequest(destination: url, method: "POST", body: "score=\(value)&no_unvote=\(no_unvote)".data(using: .utf8), contentType: "application/x-www-form-urlencoded");
    if (data == nil) { return 0; }
    do {
        let json = try JSONDecoder().decode(VoteResponse.self, from: data!);
        //os_log("%{public}@", log: .default, json);
        return json.our_score ?? 0
    }
    catch {
        //os_log("Error decoding vote response: %{public}s", log: .default, error);
        return 0
    }
}

func makeRequest(destination: String, method: String, body: Data?, contentType: String) async -> Data? {
    let domain = UserDefaults.standard.string(forKey: "api_source") ?? "e926.net";
    let API_KEY = UserDefaults.standard.string(forKey: "API_KEY") ?? "";
    let username = UserDefaults.standard.string(forKey: "username") ?? "";
    let AUTH_STRING: String = "\(username):\(API_KEY)".data(using: .utf8)?.base64EncodedString() ?? "";
    let url = URL(string: "https://\(domain)\(destination)")

    var request = URLRequest(url: url!)
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
