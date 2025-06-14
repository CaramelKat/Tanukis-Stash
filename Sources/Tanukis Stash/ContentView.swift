//
//  ContentView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI
let defaults = UserDefaults.standard

struct ContentView: View {
    
    var body: some View {
        NavigationStack {
            SearchView(search: "");
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
