//
//  ContentView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

struct ContentView: View {

    var body: some View {
        NavigationStack {
            SearchView(search: "", isTopView: true)
        }.task {
            UserDefaults.standard.set(await login(), forKey: "AUTHENTICATED");
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
