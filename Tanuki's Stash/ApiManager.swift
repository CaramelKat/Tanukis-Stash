//
//  TagManager.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 7/15/22.
//

import Foundation
import SwiftUI

var source = defaults.string(forKey: "api_source") ?? "e926.net";
var API_KEY = defaults.string(forKey: "API_KEY") ?? "";
var username = defaults.string(forKey: "username") ?? "";
var tagList = [String]();
let userAgent: String = "Tanukis%20Stash/0.0.5%20(by%20JemTanuki%20on%20e621)";
let AUTH_STRING: String = "\(username):\(API_KEY)".data(using: .utf8)?.base64EncodedString() ?? "";

func fetchTags(_ text: String) async {
    do {
        let url = URL(string: "https://\(source)/tags/autocomplete.json?search%5Bname_matches%5D=\(text)&expiry=7&_client=\(userAgent)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let parsedData = try JSONDecoder().decode([TagContent].self, from: data)
        let tags = parsedData;
        await processTags(tags);
    } catch {
        print(error);
    }
}

func processTags(_ tags: [TagContent]) async {
    for tag in tags {
        tagList.append(tag.name);
    }
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
    tagList.removeAll();
    let newSearchText = parseSearch(search);
    if(newSearchText.count >= 3) {
        await fetchTags(newSearchText);
    }
    return tagList;
}

func fetchRecentPosts(_ page: Int, _ limit: Int, _ tags: String) async -> [PostContent] {
    do {
        let encoded = tags.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        let url = "https://\(source)/posts.json?tags=\(encoded ?? "")&limit=\(limit)&page=\(page)"
        let data = await makeRequest(url: url, method: "GET", body: nil, contentType: "application/json");
        if (data) == nil { return []; }
        let parsedData = try JSONDecoder().decode(Posts.self, from: data!)
        return parsedData.posts;
    } catch {
        print(error);
        return [];
    }
}

func fetchMoreRecentPosts(_ page: Int, _ limit: Int, _ tags: String) async -> [PostContent] {
    do {
        let encoded = tags.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        let url = "https://\(source)/posts.json?tags=\(encoded ?? "")&limit=\(limit)&page=\(page)"
        let data = await makeRequest(url: url, method: "GET", body: nil, contentType: "application/json");
        if (data) == nil { return []; }
        let parsedData = try JSONDecoder().decode(Posts.self, from: data!)
        return parsedData.posts;
    } catch {
        print(error);
        return [];
    }
}

func favoritePost(postId: Int) async -> Bool {
    let url = "https://\(source)/favorites.json?post_id=\(postId)"
    let data = await makeRequest(url: url, method: "POST", body: nil, contentType: "application/json");
    if (data) == nil { return false; }
    return true;
}

func unFavoritePost(postId: Int) async -> Bool {
    let url = "https://\(source)/favorites/\(postId).json"
    let data = await makeRequest(url: url, method: "DELETE", body: nil, contentType: "application/json");
    if (data) == nil { return true; }
    return false;
}

func votePost(postId: Int, value: Int, no_unvote: Bool) async -> Int {
    let url = "https://\(source)/posts/\(postId)/votes.json"
    let data = await makeRequest(url: url, method: "POST", body: "score=\(value)&no_unvote=\(no_unvote)".data(using: .utf8), contentType: "application/x-www-form-urlencoded");
    if (data == nil) { return 0; }
    do {
        let json = try JSONDecoder().decode(VoteResponse.self, from: data!);
        return json.our_score ?? 0
    }
    catch {
        print("Error decoding vote response: \(error)")
        return 0
    }
}

func makeRequest(url: String, method: String, body: Data?, contentType: String) async -> Data? {
    let url = URL(string: url)
    var request = URLRequest(url: url!)
    request.httpMethod = method
    request.addValue(contentType, forHTTPHeaderField: "Content-Type")
    request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
    if ![API_KEY, username].contains("") {
        request.addValue("Basic \(AUTH_STRING)", forHTTPHeaderField: "Authorization")
    }
    print("Making request to \(url!)")
    print("Method: \(method)")
    print("Body: \(body?.debugDescription ?? "")")
    do {
        if (body != nil) {
            request.httpBody = body!
        }
        let (data, response) = try await URLSession.shared.data(for: request);
        return data;
        
    } catch {
        DispatchQueue.main.async {
            print("Failed to make request")
        }
        return nil
    }
}
