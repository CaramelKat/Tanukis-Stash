//
//  SettingsView.swift
//  Tanuki's Stash
//
//  Created by Jay Poffinbarger on 1/7/22.
//

import SwiftUI

struct SettingsView: View {
    
    @Environment(\.presentationMode)
    var presentationMode: Binding<PresentationMode>
    @State private var username: String = defaults.string(forKey: "username") ?? "";
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Images Source")) {
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
                
                Section(header: Text("Accounts")) {
                    TextField("Username", text: $username).onDisappear() {
                        defaults.set(username, forKey: "username");
                    }
                }
            }
            .navigationBarTitle("Settings", displayMode: .inline)
            .navigationBarItems(trailing: Button("Dismiss", action: {
                self.presentationMode.wrappedValue.dismiss()
            }))
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
