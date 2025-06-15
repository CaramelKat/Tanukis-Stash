//
//  ContentView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

struct ContentView: View {

    init() {
        Task.init {
            let loginStatus = await login();
            UserDefaults.standard.set(loginStatus, forKey: "AUTHENTICATED");
            if (loginStatus) {
                UserDefaults.standard.set(await fetchBlacklist().trimmingCharacters(in: .whitespacesAndNewlines), forKey: "USER_BLACKLIST");
            }
        }
    }

    var body: some View {
        NavigationStack {
            SearchView(search: "", isTopView: true)
        }
    }
}
