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
    @State private var ENABLE_BLACKLIST: Bool = UserDefaults.standard.bool(forKey: "ENABLE_BLACKLIST");
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    let sources = ["e926.net", "e621.net"];
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account")) {
                    TextField("Username", text: $username).onDisappear() {
                        UserDefaults.standard.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "username");
                    }.disabled(AUTHENTICATED).foregroundColor(AUTHENTICATED ? .gray : .primary);
                    if (!AUTHENTICATED) {
                        TextField("API Key", text: $API_KEY).onDisappear() {
                            UserDefaults.standard.set(API_KEY.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "API_KEY");
                        }.disabled(AUTHENTICATED).foregroundColor(AUTHENTICATED ? .gray : .primary);
                    }
                    LoginButton(AUTHENTICATED: $AUTHENTICATED, username: $username, API_KEY: $API_KEY)
                }

                if (AUTHENTICATED) {
                    Section(header: Text("User Settings")) {
                        UserSettingsView()
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
                    Toggle("Enable Blacklist", isOn: $ENABLE_BLACKLIST)
                        .toggleStyle(.switch)
                        .onChange(of: ENABLE_BLACKLIST, perform: {newValue in
                            UserDefaults.standard.set(newValue, forKey: "ENABLE_BLACKLIST");
                        })
                }

                Section(header: Text("App Information")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                            .foregroundColor(.secondary)
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

struct LoginButton: View {
    @Binding var AUTHENTICATED: Bool
    @Binding var username: String
    @Binding var API_KEY: String
    @State private var ShowAlert: Bool = false;
    @State private var BLACKLIST: String = UserDefaults.standard.string(forKey: "USER_BLACKLIST") ?? "";
    
    var body: some View {
        if (AUTHENTICATED) {
            Button("Logout") {
                AUTHENTICATED = false;
                UserDefaults.standard.set(AUTHENTICATED, forKey: "AUTHENTICATED");
            }.foregroundColor(.red)
        } else {
            Button("Login") {
                Task {
                    UserDefaults.standard.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "username");
                    UserDefaults.standard.set(API_KEY.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "API_KEY");
                    AUTHENTICATED = await login();
                    UserDefaults.standard.set(AUTHENTICATED, forKey: "AUTHENTICATED");
                    if (!AUTHENTICATED) {
                        ShowAlert.toggle()
                    }
                    if (AUTHENTICATED) {
                        // Fetch user data and blacklist if login is successful
                        BLACKLIST = await fetchBlacklist();
                        UserDefaults.standard.set(BLACKLIST.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "USER_BLACKLIST");
                    }
                }
            }
            .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || API_KEY.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .alert(isPresented: $ShowAlert) {
                Alert(
                    title: Text("Login Failed"),
                    message: Text("Check your credentials and try again")
                )
            }
        }
    }
}

struct UserSettingsView: View {
    @State private var BLACKLIST: String = UserDefaults.standard.string(forKey: "USER_BLACKLIST") ?? "";
    @State private var username: String = UserDefaults.standard.string(forKey: "username") ?? "";
    @State private var selection: String = UserDefaults.standard.string(forKey: "api_source") ?? "e621.net";
    
    var body: some View {
        TextField("Blacklist", text: $BLACKLIST,  axis: .vertical)
        .disabled(true)
        .foregroundStyle(.gray)
        .onAppear {
            Task {
                BLACKLIST = await fetchBlacklist();
                UserDefaults.standard.set(BLACKLIST.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "USER_BLACKLIST");
            }
        }
        Link("Edit User Settings", destination: URL(string: "https://\(selection)/users/\(username)/edit?tab=blacklist")!)
    }
}
