//
//  SettingsView.swift
//  Tanuki's Stash
//
//  Created by Jay Poffinbarger on 1/7/22.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Button(action: {
                defaults.set("e621.net", forKey: "api_source");
            }) {
                Text("e621.net")
            }
            Button(action: {
                defaults.set("e926.net", forKey: "api_source");
            }) {
                Text("e926.net")
            }
        }
        .navigationBarTitle("Settings", displayMode: .inline)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
