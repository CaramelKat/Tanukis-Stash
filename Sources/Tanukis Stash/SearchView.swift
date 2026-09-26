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
    @State var showSettings = false;
    @State var selectedPost: PostSelection?;
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    @Environment(\.dismiss) private var dismiss;
    @Environment(\.dismissSearch) private var dismissSearch;

    let fuckSearchableViewModel = SearchableViewModel();
    var isTopView: Bool = false

    @State var infoText: String = ""

    var limit = 75;
    var vGridLayout = [
        GridItem(.flexible(minimum: 75)),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var loadingText = "Loading posts...";
    var noPostsFoundText = "No posts found";

    init(search: String, isTopView: Bool = false) {
        self.search = search;
        self.isTopView = isTopView; 
    }

    var body: some View {
        ScrollView(.vertical) {
            if(posts.count == 0) {
                ProgressView(infoText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LazyVGrid(columns: vGridLayout) {
                ForEach(Array(posts.enumerated()), id: \.element) { i, post in
                    PostPreviewFrame(post: post, search: search, selectedPost: $selectedPost, index: i)
                    .onAppear {
                        if (i == posts.count - 9) {
                            Task.init {
                                await getPosts(append: true);
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .task({
            if (posts.count == 0) {
                await getPosts(append: false);
            }
        })
        .toolbar {
            if (AUTHENTICATED) {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SearchView(search: String("fav:\(UserDefaults.standard.string(forKey: "username") ?? "default")"))) {
                        Image(systemName: "heart").imageScale(.large)
                    }
                }
            }
            if (isTopView) {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        self.showSettings = true
                    }) {
                        Image(systemName: "person.crop.circle").imageScale(.large)
                    }
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
        .onChange(of: search) {
            Task.init { 
                if(search.count >= 3) {
                    Task.init {
                        searchSuggestions = await createTagList(search);
                    }
                } 
           }
        }
        .onSubmit(of: .search) {
            posts = [];
            Task.init {
                await getPosts(append: false);
                searchSuggestions.removeAll();
                dismissSearch()
            }
        }
        .onChange(of: showSettings) {
            updateSettings();
        }
        .sheet(isPresented: $showSettings, content: {
            SettingsView()
        })
        .fullScreenCover(item: $selectedPost, content: { selection in
            NavigationStack {
                PostView(posts: posts, currentIndex: selection.index, search: search)
            }
        })
        .refreshable {
            page = 1;
            posts = await fetchRecentPosts(page, limit, search)
        }
    }
    
    func getPosts(append: Bool) async {
        infoText = loadingText;
        if(append) {
            page += 1;
            posts += await fetchRecentPosts(page, limit, search)
        } else {
            page = 1;
            posts = await fetchRecentPosts(page, limit, search)
        }
        
        if (posts.count == 0) {
            infoText = noPostsFoundText
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
        AUTHENTICATED = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
        
        if(showSettings) {
            if(posts.count == 0) {
                posts = [];
                Task.init {
                    await getPosts(append: false);
                    searchSuggestions.removeAll();
                    dismiss()
                    dismissSearch()
                }
            }
        }
    }
}

class SearchableViewModel: ObservableObject {
    var dismissClosure: () -> Void = { print("Not Set") }
}

struct SearchableViewPassthrough: ViewModifier {
    @Environment(\.isSearching) var isSearching
    @Environment(\.dismissSearch) var dismissSearch
    let viewModel: SearchableViewModel

    func body(content: Content) -> some View {
        content
        .onAppear {
            viewModel.dismissClosure = { dismissSearch() }
        }
    }
}

struct PostSelection: Identifiable {
    let index: Int;
    var id: Int { index }
}

struct PostPreviewFrame: View {
    @State var post: PostContent;
    @State var search: String;
    @Binding var selectedPost: PostSelection?;
    var index: Int;
    
    var body: some View {
        
        Button(action: { selectedPost = PostSelection(index: index) }) {
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
                if(post.isAnimated) {
                    HStack(spacing: 3) {
                        Image(systemName: "film")
                        Text(post.file.ext.uppercased())
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(4)
                }
                VStack() {
                    Spacer()
                    HStack(alignment: .bottom) {
                        Text("⬆️\(post.score.total.formatted(.number.notation(.compactName))) ❤️\(post.fav_count.formatted(.number.notation(.compactName)))")
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
        .buttonStyle(.plain)
    }
}
