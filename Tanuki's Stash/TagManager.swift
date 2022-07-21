//
//  TagManager.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 7/15/22.
//

import Foundation
import SwiftUI

var source = defaults.string(forKey: "api_source") ?? "e926.net";
var tagList = [String]();

func fetchTags(_ text: String) async {
    do {
        let userAgent = "Tanukis%20Stash/1.0%20(by%20JayDaBirb%20on%20e621)"
        let url = URL(string: "https://\(source)/tags/autocomplete.json?search%5Bname_matches%5D=\(text)&expiry=7&_client=\(userAgent)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        //print(url);
        let parsedData = try JSONDecoder().decode([TagContent].self, from: data)
        let tags = parsedData;
        //print(tags);
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
