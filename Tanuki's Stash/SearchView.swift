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
                ForEach(posts, id: \.id) { post in
                    if(post.preview.url != nil) {
                        NavigationLink(destination: PostView(post: post, search: search)) {
                            ZStack {
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
                        .onAppear {
                            Task.init {
                                if(checkRefresh(post.id)) {
                                    page += 1;
                                    await fetchMoreRecentPosts(page, limit, search);
                                }
                            }
                        }
                    }
                    else {
                        NavigationLink(destination: PostView(post: post, search: search)) {
                            ZStack {
                                Text("Deleted")
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .frame(height: 150)
                                    .background(Color.gray.opacity(0.90))
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
                        .onAppear {
                            Task.init {
                                if(checkRefresh(post.id)) {
                                    page += 1;
                                    await fetchMoreRecentPosts(page, limit, search);
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
        }.task {
            source = defaults.string(forKey: "api_source") ?? "e621.net";
            if($posts.count == 0) {
                await fetchRecentPosts(1, 28, search)
            }
        }
        .navigationBarTitle("Posts", displayMode: .inline)
        .navigationBarItems(trailing: Button(action: {
        }) {
            NavigationLink(destination: SearchView(search: String("fav:\(defaults.string(forKey: "username") ?? "default")"))) {
                Image(systemName: "heart").imageScale(.large)
            }
        })
        .navigationBarItems(leading: Button(action: {
            self.showSettings = true
        }) {
            Image(systemName: "person.crop.circle").imageScale(.large)
        })
        .sheet(isPresented: $showSettings, content: {
            SettingsView()
        })
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
        .onChange(of: search) { newQuery in
            Task.init { if(search.count >= 3) {
                Task.init {
                    searchSuggestions = await createTagList(search);
               }
           } }
                   }
        .onSubmit(of: .search) {
            Task.init {
                page = 1;
                await fetchRecentPosts(page, limit, search)
                searchSuggestions.removeAll();
            }
        }
        .onChange(of: showSettings, perform: {showSettings in
            if(!showSettings && (source != defaults.string(forKey: "api_source"))) {
                source = defaults.string(forKey: "api_source") ?? "e926.net";
                Task.init {
                    page = 1;
                    await fetchRecentPosts(page, limit, search)
                    searchSuggestions.removeAll();
                }
            }
        })
        .refreshable {
            page = 1;
            await fetchRecentPosts(page, limit, search)
        }
    }
    
    func refreshData() async {
        // do work to asyncronously refresh your data here
        try? await Task.sleep(nanoseconds: 3_000_000_000)
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
    
    func fetchRecentPosts(_ page: Int, _ limit: Int, _ tags: String) async {
        do {
            let encoded = tags.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            let userAgent = "Tanukis%20Stash/1.0%20(by%20JemTanuki%20on%20e621)"
            let url = URL(string: "https://\(source)/posts.json?tags=\(encoded ?? "")&limit=\(limit)&page=\(page)&_client=\(userAgent)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let parsedData = try JSONDecoder().decode(Posts.self, from: data)
            posts = parsedData.posts;
        } catch {
            print(error);
        }
    }
    
    func fetchMoreRecentPosts(_ page: Int, _ limit: Int, _ tags: String) async {
        do {
            let encoded = tags.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            let userAgent = "Tanukis%20Stash/1.0%20(by%20JemTanuki%20on%20e621)"
            let url = URL(string: "https://\(source)/posts.json?tags=\(encoded ?? "")&limit=\(limit)&page=\(page)&_client=\(userAgent)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let parsedData = try JSONDecoder().decode(Posts.self, from: data)
            posts += parsedData.posts;
        } catch {
            print(error);
        }
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
