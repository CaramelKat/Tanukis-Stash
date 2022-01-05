//
//  ContentView.swift
//  Tanuki's Stash
//
//  Created by Jay Poffinbarger on 1/3/22.
//

import SwiftUI

struct ContentView: View {
    @State var posts = [PostContent]();
    @State var search = ""
    @State var page = 1;
    var limit = 30;
    var vGridLayout = [
        GridItem(.flexible(minimum: 30)),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView(.vertical) {
                LazyVGrid(columns: vGridLayout) {
                    ForEach(posts, id: \.id) { post in
                        if(post.preview.url != nil) {
                            NavigationLink(destination: PostView(post: post)) {
                                ZStack {
                                    AsyncImage(url: URL(string: post.preview.url!)) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(minWidth: 0, maxWidth: .infinity)
                                            .frame(height: 200)
                                            .shadow(color: Color.primary.opacity(0.3), radius: 1)
                                    } placeholder: {
                                        ProgressView()
                                            .frame(minWidth: 0, maxWidth: .infinity)
                                            .frame(height: 200)
                                    }
                                    VStack() {
                                        Spacer()
                                        HStack(alignment: .bottom) {
                                            Text("⬆️\(post.score.total) ❤️\(post.fav_count)")
                                                .font(.callout)
                                                .fontWeight(.bold)
                                                .foregroundColor(Color.white)
                                            Spacer()
                                        }
                                        .padding(10.0)
                                        .background(Color.gray.opacity(0.75))
                                    }
                                }.cornerRadius(10)
                            }
                            .onAppear {
                                Task.init {
                                    if(checkRefresh(post.id)) {
                                        page += 1;
                                        print("ayo")
                                        print(page)
                                        await fetchMoreRecentPosts(page, limit, search);
                                    }
                                }
                            }
                        }
                        else {
                            NavigationLink(destination: PostView(post: post)) {
                                ZStack {
                                    Text("⛔️")
                                        .frame(minWidth: 0, maxWidth: .infinity)
                                        .frame(height: 200)
                                    VStack() {
                                        Spacer()
                                        HStack(alignment: .bottom) {
                                            Text("⬆️\(post.score.total) ❤️\(post.fav_count)")
                                                .font(.callout)
                                                .fontWeight(.bold)
                                                .foregroundColor(Color.white)
                                            Spacer()
                                        }
                                        .padding(10.0)
                                        .background(Color.gray.opacity(0.75))
                                    }
                                }
                            }
                            .onAppear {
                                Task.init {
                                    if(checkRefresh(post.id)) {
                                        page += 1;
                                        print("ayo")
                                        print(page)
                                        await fetchMoreRecentPosts(page, limit, search);
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }.task {
                if($posts.count == 0) {
                    await fetchRecentPosts(1, 28, search)
                }
            }
            .navigationBarTitle("Posts", displayMode: .inline)
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search for tags")
        .onSubmit(of: .search) {
            Task.init {
                page = 1;
                await fetchRecentPosts(page, limit, search)
            }
        }
    }
    
    func checkRefresh(_ id: Int) -> Bool{
        let element = posts.last;
        return element?.id == id;
    }
    
    func fetchRecentPosts(_ page: Int, _ limit: Int, _ tags: String) async {
        do {
            let encoded = tags.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            let userAgent = "Tanukis%20Stash/1.0%20(by%20JayDaBirb%20on%20e621)"
            let url = URL(string: "https://e621.net/posts.json?tags=\(encoded ?? "")&limit=\(limit)&page=\(page)&_client=\(userAgent)")!
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
            let userAgent = "Tanukis%20Stash/1.0%20(by%20JayDaBirb%20on%20e621)"
            let url = URL(string: "https://e621.net/posts.json?tags=\(encoded ?? "")&limit=\(limit)&page=\(page)&_client=\(userAgent)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let parsedData = try JSONDecoder().decode(Posts.self, from: data)
            posts += parsedData.posts;
        } catch {
            print(error);
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
