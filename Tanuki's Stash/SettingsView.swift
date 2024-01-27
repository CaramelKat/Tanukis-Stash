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
    @State private var selection: String = defaults.string(forKey: "api_source") ?? "e621.net";
    let sources = ["e621.net", "e926.net"];
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Images Source")) {
                    Picker("API Source", selection: $selection) {
                            ForEach(sources, id: \.self) {
                                Text($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selection, perform: {newValue in
                            defaults.set(newValue, forKey: "api_source");
                        })
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
