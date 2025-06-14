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
    @State private var username: String = UserDefaults.standard.string(forKey: "username") ?? "";
    @State private var selection: String = UserDefaults.standard.string(forKey: "api_source") ?? "e621.net";
    @State private var API_KEY: String = UserDefaults.standard.string(forKey: "API_KEY") ?? "";
    @State private var ENABLE_AIRPLAY: Bool = UserDefaults.standard.bool(forKey: "ENABLE_AIRPLAY");
    let sources = ["e926.net", "e621.net"];
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Accounts")) {
                    TextField("Username", text: $username).onDisappear() {
                        UserDefaults.standard.set(username, forKey: "username");
                    }
                    TextField("API Key", text: $API_KEY).onDisappear() {
                        UserDefaults.standard.set(API_KEY, forKey: "API_KEY");
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
                        UserDefaults.standard.set(newValue, forKey: "api_source");
                    })
                    Toggle("Enable AirPlay", isOn: $ENABLE_AIRPLAY)
                        .toggleStyle(.switch)
                        .onChange(of: ENABLE_AIRPLAY, perform: {newValue in
                            UserDefaults.standard.set(newValue, forKey: "ENABLE_AIRPLAY");
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
