//
//  SettingsView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/7/22.
//

import SwiftUI

struct SettingsView: View {
    
    @Environment(\.presentationMode)
    var presentationMode: Binding<PresentationMode>
    @State private var username: String = defaults.string(forKey: "username") ?? "";
    @State private var selection: String = defaults.string(forKey: "api_source") ?? "e621.net";
    @State private var API_KEY: String = defaults.string(forKey: "API_KEY") ?? "";
    @State private var ENABLE_AIRPLAY: Bool = defaults.bool(forKey: "ENABLE_AIRPLAY");
    let sources = ["e621.net", "e926.net"];
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Accounts")) {
                    TextField("Username", text: $username).onDisappear() {
                        defaults.set(username, forKey: "username");
                    }
                    TextField("API Key", text: $API_KEY).onDisappear() {
                        defaults.set(API_KEY, forKey: "API_KEY");
                    }
                }
                
                Section(header: Text("App Settings")) {
                    Picker("API Source", selection: $selection) {
                        ForEach(sources, id: \.self) {
                            Text($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selection, perform: {newValue in
                        defaults.set(newValue, forKey: "api_source");
                    })
                    Toggle("Enable AirPlay", isOn: $ENABLE_AIRPLAY)
                        .toggleStyle(.switch)
                        .onChange(of: ENABLE_AIRPLAY, perform: {newValue in
                            defaults.set(newValue, forKey: "ENABLE_AIRPLAY");
                        })
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
