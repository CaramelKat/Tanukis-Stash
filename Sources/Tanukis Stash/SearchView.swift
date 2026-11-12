//
//  ContentView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

// Reports the grid's vertical scroll offset within its scroll view. Used as
// the iOS 17 fallback for scroll tracking (iOS 18+ uses the native
// scroll-geometry API in GridScrollTracker instead).
private struct GridScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// Tracks the grid's scroll offset. Uses the native scroll-geometry API on
// iOS 18+, and falls back to the preference-key probe inside the scroll
// content on iOS 17.
private struct GridScrollTracker: ViewModifier {
    let onChange: (CGFloat) -> Void;

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Resting at the top = 0, scrolling down goes negative — the
                // same semantics the preference-key probe reports.
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, newValue in
                onChange(newValue)
            }
        } else {
            content.onPreferenceChange(GridScrollOffsetKey.self) { onChange($0) }
        }
    }
}

struct SearchView: View {
    @State var posts = [PostContent]();
    @State var searchSuggestions = [String]();
    @State var search: String;
    @State var page = 1;
    @State var showSettings = false;
    @State var selectedPost: PostSelection?;
    @State var currentPostIndex: Int = 0;
    @State var lastFollowedRow: Int = -1;
    @State var isLoadingMore: Bool = false;
    @State var resultCount: PostSearchCount? = nil;
    // Floating search bar (slides in when the user flicks up while scrolled
    // deep in the grid) and the scroll-offset tracking that drives it.
    @State private var showFloatingSearch = false;
    @FocusState private var floatingSearchFocused: Bool;
    @State private var restScrollOffset: CGFloat? = nil;
    @State private var prevScrollOffset: CGFloat? = nil;
    // Total points scrolled in one direction since the direction last
    // changed. Accumulating (instead of judging each frame's delta alone)
    // means a slow, small upward drag shows the bar just like a fast flick.
    @State private var upAccum: CGFloat = 0;
    @State private var downAccum: CGFloat = 0;
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    // Submitted queries, newest first, shown while the search field is empty.
    @State private var recentSearches: [String] = SearchHistory.recent;
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
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // Scroll-offset probe: drives the floating search bar.
                GeometryReader { geo in
                    Color.clear.preference(key: GridScrollOffsetKey.self, value: geo.frame(in: .named("gridScroll")).minY)
                }
                .frame(height: 0)
                .id("gridTopAnchor")
                if(posts.count == 0) {
                    ProgressView(infoText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                LazyVGrid(columns: vGridLayout) {
                    ForEach(Array(posts.enumerated()), id: \.element) { i, post in
                        PostPreviewFrame(post: post, search: search, selectedPost: $selectedPost, index: i)
                        .id(i)
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
                .onChange(of: currentPostIndex) { _, newIndex in
                    followPost(index: newIndex, proxy: proxy)
                }
            }
            .coordinateSpace(name: "gridScroll")
            // Scroll tracking for the floating search bar: native scroll
            // geometry on iOS 18+, preference-key probe on iOS 17.
            .modifier(GridScrollTracker(onChange: handleScrollOffset))
            // Floating search bar: slides in over the grid when the user
            // scrolls up while scrolled deep, so running a new search never
            // requires scrolling all the way back to the top.
            .overlay(alignment: .top) {
                floatingSearchBar(proxy: proxy)
            }
            .animation(.easeOut(duration: 0.18), value: showFloatingSearch)
            // Precise number of posts the current search matches, pinned
            // above the grid.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let resultCount {
                    Text(resultCount.capped
                         ? "\(resultCount.count.formatted())+ posts"
                         : "\(resultCount.count.formatted()) posts")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
            .refreshable {
                page = 1;
                posts = await fetchRecentPosts(page, limit, search)
                await refreshResultCount();
            }
            .task({
                recentSearches = SearchHistory.recent;
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
                // Remembered queries, shown before typing anything.
                if (search.isEmpty && !recentSearches.isEmpty) {
                    Section("Recent") {
                        ForEach(recentSearches, id: \.self) { query in
                            Button {
                                runRecentSearch(query);
                            } label: {
                                Label(query, systemImage: "clock.arrow.circlepath");
                            }
                        }
                        Button(role: .destructive) {
                            clearRecentSearches();
                        } label: {
                            Label("Clear Recent Searches", systemImage: "trash");
                        }
                    }
                }
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
                resultCount = nil;
                recordSearch();
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
                    PostView(posts: posts, currentIndex: selection.index, search: search, onIndexChanged: { index in
                        currentPostIndex = index;
                    })
                }
            })
            .onChange(of: selectedPost) { _, selection in
                guard let selection else { return }
                currentPostIndex = selection.index;
                lastFollowedRow = selection.index / max(vGridLayout.count, 1);
                loadMoreIfNeeded(near: selection.index);
            }
        }
    }
    
    func getPosts(append: Bool) async {
        infoText = loadingText;
        if(append) {
            if (isLoadingMore) { return }
            isLoadingMore = true;
            page += 1;
            posts += await fetchRecentPosts(page, limit, search)
            isLoadingMore = false;
        } else {
            page = 1;
            posts = await fetchRecentPosts(page, limit, search)
            await refreshResultCount();
        }
        
        if (posts.count == 0) {
            infoText = noPostsFoundText
        }
    }

    // Keeps the posts grid in sync with the post the user is viewing, so the
    // grid scrolls along and keeps loading new pages of posts.
    func followPost(index: Int, proxy: ScrollViewProxy) {
        loadMoreIfNeeded(near: index);

        let row = index / max(vGridLayout.count, 1);
        if (row == lastFollowedRow) { return }
        lastFollowedRow = row;
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(index, anchor: .center);
        }
    }

    // Fetches the next page once the user gets close to the end of the loaded posts.
    func loadMoreIfNeeded(near index: Int) {
        if (posts.count == 0 || isLoadingMore) { return }
        if (index >= posts.count - 10) {
            Task.init {
                await getPosts(append: true);
            }
        }
    }
    
    // MARK: Floating search bar

    // Shows/hides the floating search bar based on the grid's scroll offset.
    // Movement is accumulated per direction instead of judging each frame's
    // delta alone, so a slow, small upward drag shows the bar just like a
    // fast flick does.
    private func handleScrollOffset(_ offset: CGFloat) {
        guard let rest = restScrollOffset else {
            // First sample: remember where "resting at the top" is.
            restScrollOffset = offset;
            prevScrollOffset = offset;
            return;
        }
        // The content sits below its resting offset (pull-to-refresh rubber
        // banding, or the count bar appearing): re-baseline instead of
        // reading it as an upward scroll.
        if (offset > rest + 1) {
            restScrollOffset = offset;
            prevScrollOffset = offset;
            upAccum = 0;
            downAccum = 0;
            return;
        }
        let delta = offset - (prevScrollOffset ?? offset);
        prevScrollOffset = offset;

        // While the fullscreen post viewer is open the grid auto-follows the
        // visible post; that is not a user scroll gesture.
        if (selectedPost != nil) {
            upAccum = 0;
            downAccum = 0;
            return;
        }
        // Keep the bar up (and the keyboard open) while the user is typing.
        if (floatingSearchFocused) {
            upAccum = 0;
            downAccum = 0;
            return;
        }

        if (offset > rest - 110) {
            // Close enough to the top that the real search bar is visible.
            showFloatingSearch = false;
            upAccum = 0;
            downAccum = 0;
            return;
        }

        // Accumulate movement in the current scroll direction; a change of
        // direction resets the opposite accumulator, so only sustained
        // movement in one direction can cross a threshold.
        if (delta > 0) {
            upAccum += delta;
            downAccum = 0;
            if (!showFloatingSearch && upAccum > 22) {
                showFloatingSearch = true;
                upAccum = 0;
            }
        } else if (delta < 0) {
            downAccum -= delta;
            upAccum = 0;
            if (showFloatingSearch && downAccum > 18) {
                showFloatingSearch = false;
                downAccum = 0;
            }
        }
    }

    // The floating search bar itself, drawn over the top of the grid.
    @ViewBuilder
    private func floatingSearchBar(proxy: ScrollViewProxy) -> some View {
        if (showFloatingSearch) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .onTapGesture { floatingSearchFocused = true }
                    TextField("Search for tags", text: $search)
                        .focused($floatingSearchFocused)
                        .submitLabel(.search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            submitFloatingSearch(proxy: proxy)
                        }
                    if (!search.isEmpty) {
                        Button {
                            search = "";
                            searchSuggestions.removeAll();
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: Color.black.opacity(0.2), radius: 5, y: 2)

                // Recent queries (when empty) and live tag suggestions while
                // typing, same as the main search bar.
                if (floatingSearchFocused && (!searchSuggestions.isEmpty || (search.isEmpty && !recentSearches.isEmpty))) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if (search.isEmpty) {
                                Text("Recent")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                                ForEach(Array(recentSearches.prefix(10)), id: \.self) { query in
                                    Button {
                                        search = query;
                                        submitFloatingSearch(proxy: proxy);
                                    } label: {
                                        Label(query, systemImage: "clock.arrow.circlepath")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            ForEach(Array(searchSuggestions.prefix(10)), id: \.self) { tag in
                                Button {
                                    updateSearch(tag);
                                } label: {
                                    Text(tag)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 232)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color.black.opacity(0.2), radius: 5, y: 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, resultCount != nil ? 36 : 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // Runs the query typed into the floating search bar.
    private func submitFloatingSearch(proxy: ScrollViewProxy) {
        floatingSearchFocused = false;
        showFloatingSearch = false;
        searchSuggestions.removeAll();
        posts = [];
        resultCount = nil;
        recordSearch();
        // Re-baseline the scroll tracking for the fresh, shorter content.
        restScrollOffset = nil;
        prevScrollOffset = nil;
        upAccum = 0;
        downAccum = 0;
        Task.init {
            await getPosts(append: false);
        }
        proxy.scrollTo("gridTopAnchor", anchor: .top);
    }

    // MARK: - Search history

    /// Saves a submitted query (only from the top-level search, so pushed tag
    /// and favorites searches don't overwrite what the app reopens on).
    func recordSearch() {
        guard isTopView else { return }
        SearchHistory.record(search);
        recentSearches = SearchHistory.recent;
    }

    /// Runs one of the remembered queries tapped in the suggestions.
    func runRecentSearch(_ query: String) {
        search = query;
        searchSuggestions.removeAll();
        posts = [];
        resultCount = nil;
        recordSearch();
        Task.init {
            await getPosts(append: false);
        }
        dismissSearch();
    }

    func clearRecentSearches() {
        SearchHistory.clearRecent();
        recentSearches = [];
    }

    // Fetches the precise number of posts matching the current search for
    // the count bar.
    func refreshResultCount() async {
        let fetched = await fetchPostCount(search: search);
        // A zero count while posts are on screen means the count endpoint
        // cannot handle this query (some metatags) — hide the bar instead of
        // showing a wrong number.
        if (fetched?.count == 0 && !posts.isEmpty) {
            resultCount = nil;
        } else {
            resultCount = fetched;
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

struct PostSelection: Identifiable, Equatable {
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
            .contentShape(Rectangle())
            .padding(0.1)
        }
        .buttonStyle(.plain)
    }
}
