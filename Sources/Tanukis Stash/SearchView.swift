//
//  ContentView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

struct SearchView: View {
    @State var posts = [PostContent]();
    @State var searchSuggestions = [String]();
    @State var search: String;
    @State var page = 1;
    @State var source = defaults.string(forKey: "api_source") ?? "e926.net";
    @State var showSettings = false
    
    var limit = 75;
    var vGridLayout = [
        GridItem(.flexible(minimum: 75)),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: vGridLayout) {
                ForEach(Array(posts.enumerated()), id: \.element) { i, post in
                    PostPreviewFrame(post: post, search: search)
                    .onAppear {
                        if (i == posts.count - 9) {
                            Task.init {
                                page += 1;
                                posts += await fetchMoreRecentPosts(page, limit, search);
                            }
                        }
                    }
                }
            }
            .padding(10)
        }.task {
            if($posts.count == 0) {
                posts = await fetchRecentPosts(1, 28, search)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SearchView(search: String("fav:\(defaults.string(forKey: "username") ?? "default")"))) {
                    Image(systemName: "heart").imageScale(.large)
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    self.showSettings = true
                }) {
                    Image(systemName: "person.crop.circle").imageScale(.large)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Posts")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for tags") {
            //List {
                ForEach(searchSuggestions, id: \.self) { tag in
                    Button(action: {
                        updateSearch(tag);
                    }) {
                        Text(tag);
                    }
                }
            //}
        }
        .textInputAutocapitalization(.never)
        .onChange(of: search) { newQuery in
            Task.init { if(search.count >= 3) {
                Task.init {
                    searchSuggestions = await createTagList(search);
               }
           } }
                   }
        .onSubmit(of: .search) {
            posts = [];
            Task.init {
                page = 1;
                posts = await fetchRecentPosts(page, limit, search)
                searchSuggestions.removeAll();
            }
        }
        .onChange(of: showSettings, perform: {showSettings in
            updateSettings();
        })
        .sheet(isPresented: $showSettings, content: {
            SettingsView()
        })
        .refreshable {
            page = 1;
            posts = await fetchRecentPosts(page, limit, search)
        }
    }
    
    func checkRefresh(_ id: Int) -> Bool{
        if(posts.count > 25) {
            let element = posts[posts.count - 25];
            return element.id == id;
        }
        else {
            let element = posts.last;
            return element?.id == id;
        }
    }
    
    func updateSearch(_ tag: String) {
        if(search.contains(" ")) {
            let index = search.lastIndex(of: " ");
            if(index != nil) {
                search = String(search[...index!].trimmingCharacters(in: .whitespaces) + " " + tag);
            }
        }
        else { search = tag; }
    }
    
    func updateSettings() {
        showSettings = !showSettings;
        if(showSettings) {
            source = defaults.string(forKey: "api_source") ?? "e926.net";
            if(posts.count == 0) {
                posts = [];
                Task.init {
                    page = 1;
                    posts = await fetchRecentPosts(page, limit, search)
                    searchSuggestions.removeAll();
                }
            }
        }
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct PostPreviewFrame: View {
    @State var post: PostContent;
    @State var search: String;
    
    var body: some View {
        
        NavigationLink(destination: PostView(post: post, search: search)) {
            ZStack {
                if(post.preview.url != nil) {
                    AsyncImage(url: URL(string: post.preview.url!)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .clipped()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 150)
                            .shadow(color: Color.primary.opacity(0.3), radius: 1)
                    } placeholder: {
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(width: 100, height: 150)
                    }
                }
                else {
                    Text("Deleted")
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 150)
                        .background(Color.gray.opacity(0.90))
                }
                VStack() {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Text("⬆️\(post.score.total) ❤️\(post.fav_count)")
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(Color.white)
                        Spacer()
                    }
                    .padding(5.0)
                    .background(Color.gray.opacity(0.50))
                }
            }.cornerRadius(10)
            .padding(0.1)
        }
    }
}
