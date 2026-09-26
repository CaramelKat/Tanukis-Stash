//
//  PostView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/4/22.
//

import SwiftUI
import AlertToast
import AttributedText

struct PostPageContent: View {
    @State var post: PostContent;
    @State var search: String;
    @Binding var showImageViewer: Bool;
    var isActive: Bool = true;

    private var tapGesture: some Gesture {
        !["webm", "mp4"].contains(String(post.file.ext))
            ? (TapGesture().onEnded { showImageViewer = true })
            : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let mediaHeight = min(
                geometry.size.height * 0.75,
                geometry.size.width * CGFloat(max(post.file.height, 1)) / CGFloat(max(post.file.width, 1))
            )
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    MediaView(post: post, geometry: geometry, isActive: isActive)
                        .frame(maxWidth: .infinity)
                        .frame(height: mediaHeight)
                        .contentShape(Rectangle())
                        .gesture(tapGesture)
                    VStack(spacing: 0) {
                        VStack {
                            HStack {
                                Text(post.tags.artist.joined(separator: ", "));
                                Spacer();
                            }
                            HStack {
                                Text("\(post.rating) #\(String(post.id)) ⬆️\(post.score.total) ❤️\(post.fav_count)")
                                Spacer()
                            }
                        }
                        .padding(10.0)
                        .background(Color.gray)
                        .cornerRadius(10)
                        RelatedPostsView(post: post, search: search)
                        InfoView(post: post, search: search)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        Spacer().frame(height: 70)
                    }
                    .padding(.top, 10)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
    }
}

@MainActor 
struct PostView: View {
    @State private var showImageViewer: Bool = false;
    @State var posts: [PostContent];
    @State var currentIndex: Int;
    @State var search: String;
    @Environment(\.dismiss) private var dismiss;

    @State private var displayToastType = 0;
    @State private var dismissOffset: CGFloat = 0;
    @State private var dismissOpacity: Double = 1;

    init(posts: [PostContent], currentIndex: Int, search: String) {
        _posts = State(initialValue: posts)
        _currentIndex = State(initialValue: currentIndex)
        _search = State(initialValue: search)
    }

    init(post: PostContent, search: String) {
        self.init(posts: [post], currentIndex: 0, search: search)
    }

    var post: PostContent {
        return posts[currentIndex]
    }

    var body: some View {
        GeometryReader {geometry in
            ZStack(alignment: .bottom) {
                PostPagerView(
                    posts: posts,
                    search: search,
                    currentIndex: $currentIndex,
                    showImageViewer: $showImageViewer,
                    onDismissDrag: { distance, ended in
                        if ended {
                            finishDismissDrag(distance: distance, height: geometry.size.height)
                        } else {
                            dismissOffset = distance
                            dismissOpacity = 1 - min(1, distance / 600)
                        }
                    }
                )

                ActionBar(post: post, search: search, displayToastType: $displayToastType)
                    .id(post.id)
            }
            .offset(y: dismissOffset)
            .opacity(dismissOpacity)
            .toast(isPresenting: Binding<Bool>(get: { displayToastType != 0 }, set: { _ in })) {
                getToast()
            }
            .sheet(isPresented: $showImageViewer, content: {
                            FullscreenImageViewer(post: post)
                        })
            /*.alert(isPresented: Binding<Bool>(get: { displayToastType == 3 }, set: { _ in })) {
                Alert(
                    title: Text("Permission Denied"),
                    message: Text("You have denied access to the photo library. Please enable access in your settings if you want to use this feature."),
                    dismissButton: .default(Text("OK")) {
                        // Action to open the app settings
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString),
                           UIApplication.shared.canOpenURL(settingsURL) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                )
            }*/
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.down")
                }
            }
        }
        .navigationBarTitle("Post", displayMode: .inline)
        .onAppear {
            preloadNeighbors()
        }
        .onChange(of: currentIndex) { _ in
            preloadNeighbors()
        }
    }

    func preloadNeighbors() {
        for i in [currentIndex - 1, currentIndex + 1] {
            if (i >= 0 && i < posts.count) {
                if let urlString = posts[i].file.url {
                    ImageView.preload(urlString)
                }
            }
        }
    }

    func finishDismissDrag(distance: CGFloat, height: CGFloat) {
        if distance > 140 {
            withAnimation(.easeOut(duration: 0.22)) {
                dismissOffset = height
                dismissOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                dismiss()
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                dismissOffset = 0
                dismissOpacity = 1
            }
        }
    }

    func clearToast() {
        // Reset the displayToastType after showing the toast
        let CurrentToastType = displayToastType
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if CurrentToastType == displayToastType {
                // Only clear the toast if the type hasn't changed
                $displayToastType.wrappedValue = 0
            }
        }
    }

    func getToast() -> AlertToast {
        switch displayToastType {
        case 2:
            clearToast()
            return AlertToast(type: .complete(Color.green), title: "Saved!")
        case -1:
            return AlertToast(type: .loading, title: "Saving media...")
        case 1:
            clearToast()
            return AlertToast(type: .error(Color.red), title: "Failed to save")
        case 3:
            clearToast()
            return AlertToast(type: .error(Color.red), title: "Photo library access denied")
        default:
            clearToast()
            return AlertToast(type: .regular, title: "Unknown error \(displayToastType)")
        }
    }
}

final class PostHostingController: UIHostingController<PostPageContent> {
    var dismissPan: UIPanGestureRecognizer?
    private(set) weak var postScrollView: UIScrollView?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard postScrollView == nil, let dismissPan,
              let scrollView = firstScrollView(in: view) else { return }
        scrollView.panGestureRecognizer.require(toFail: dismissPan)
        postScrollView = scrollView
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) { return scrollView }
        }
        return nil
    }
}

struct PostPagerView: UIViewControllerRepresentable {
    var posts: [PostContent]
    var search: String
    @Binding var currentIndex: Int
    @Binding var showImageViewer: Bool
    var onDismissDrag: (CGFloat, Bool) -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let options = [UIPageViewController.OptionsKey.interPageSpacing: 0]
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: options
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator

        if let initialPage = context.coordinator.makePage(at: currentIndex, isActive: true) {
            pageViewController.setViewControllers(
                [initialPage],
                direction: .forward,
                animated: false,
                completion: nil
            )
        }
        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        if let visible = pageViewController.viewControllers?.first,
           context.coordinator.index(of: visible) == currentIndex {
            return
        }
        context.coordinator.syncCurrentPage(in: pageViewController)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PostPagerView
        private var pages: [Int: PostHostingController] = [:]

        init(_ parent: PostPagerView) {
            self.parent = parent
        }

        func makeContent(index: Int, isActive: Bool) -> PostPageContent {
            PostPageContent(
                post: parent.posts[index],
                search: parent.search,
                showImageViewer: parent.$showImageViewer,
                isActive: isActive
            )
        }

        func makePage(at index: Int, isActive: Bool) -> UIHostingController<PostPageContent>? {
            guard index >= 0 && index < parent.posts.count else { return nil }
            if let existing = pages[index] {
                existing.rootView = makeContent(index: index, isActive: isActive)
                return existing
            }
            let hostingController = PostHostingController(rootView: makeContent(index: index, isActive: isActive))
            hostingController.view.backgroundColor = .clear
            let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
            dismissPan.delegate = self
            hostingController.dismissPan = dismissPan
            hostingController.view.addGestureRecognizer(dismissPan)
            pages[index] = hostingController
            return hostingController
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = gestureRecognizer.view,
                let entry = pages.first(where: { $0.value.view === view }),
                let scrollView = entry.value.postScrollView,
                  scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 1,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let post = parent.posts[entry.key]
            let mediaHeight = min(
                view.bounds.height * 0.75,
                view.bounds.width * CGFloat(max(post.file.height, 1)) / CGFloat(max(post.file.width, 1))
            )
            let velocity = pan.velocity(in: view)
            return pan.location(in: view).y <= mediaHeight && velocity.y > abs(velocity.x)
        }

        @objc private func handleDismissPan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let distance = max(0, pan.translation(in: view).y)
            switch pan.state {
            case .changed:
                parent.onDismissDrag(distance, false)
            case .ended:
                parent.onDismissDrag(distance, true)
            case .cancelled, .failed:
                parent.onDismissDrag(0, true)
            default:
                break
            }
        }

        func index(of controller: UIViewController) -> Int? {
            for (index, page) in pages where page === controller {
                return index
            }
            return nil
        }

        func refreshActiveStates(in pageViewController: UIPageViewController) {
            let active = pageViewController.viewControllers?.first.flatMap { index(of: $0) } ?? parent.currentIndex
            parent.currentIndex = active

            evictFarPages(around: active)
            for (index, page) in pages {
                page.rootView = makeContent(index: index, isActive: index == active)
            }
        }

        func evictFarPages(around index: Int) {
            let keep = Set([index - 2, index - 1, index, index + 1, index + 2].filter { $0 >= 0 && $0 < parent.posts.count })
            for (pageIndex, _) in pages where !keep.contains(pageIndex) {
                pages.removeValue(forKey: pageIndex)
            }
        }

        func syncCurrentPage(in pageViewController: UIPageViewController) {
            if let visible = pageViewController.viewControllers?.first,
               let visibleIndex = index(of: visible) {
                if visibleIndex == parent.currentIndex {
                    refreshActiveStates(in: pageViewController)
                    return
                }
            }
            if let target = makePage(at: parent.currentIndex, isActive: true) {
                pageViewController.setViewControllers([target], direction: .forward, animated: false, completion: nil)
            }
            refreshActiveStates(in: pageViewController)
        }

        func setPagingEnabled(_ enabled: Bool, in pageViewController: UIPageViewController) {
            if let scrollView = pageViewController.view.subviews.compactMap({ $0 as? UIScrollView }).first {
                scrollView.isScrollEnabled = enabled
            }
        }

        // MARK: - Data Source

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = index(of: viewController) else { return nil }
            return makePage(at: index - 1, isActive: false)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = index(of: viewController) else { return nil }
            return makePage(at: index + 1, isActive: false)
        }

        // MARK: - Delegate

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed {
                refreshActiveStates(in: pageViewController)
            }
        }
    }
}

struct RelatedPostsView: View {
    @State var post: PostContent;
    @State var search: String;
    @State private var parentPost: PostContent?;

    var body: some View {
        HStack {
            if((post.relationships.parent_id) != nil) {
                NavigationLink(destination: PostView(post: parentPost ?? post, search: search)) {
                    Text("Parent")
                        .foregroundColor(Color.red)
                        .font(.headline)
                }
                .task {
                    await fetchParentPostData(postID: post.relationships.parent_id!);
                }
                //Spacer()
            }
            if(post.relationships.has_active_children) {
                NavigationLink(destination: SearchView(search: "parent:" + String(post.id))) {
                    Text("Children")
                        .foregroundColor(Color.red)
                        .font(.headline)
                }
            }
            if(post.pools.count > 0) {
                //Spacer()
                NavigationLink(destination: SearchView(search: "pool:" + String(post.pools[0]))) {
                    Text("Pool")
                        .foregroundColor(Color.green)
                        .font(.headline)
                }
            }
        }
    }

    func fetchParentPostData(postID: Int) async {
        do {
            let url = "/posts/\(postID).json"
            let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
            if (data) == nil { return; }
            let parsedData = try JSONDecoder().decode(Post.self, from: data!)
            parentPost = parsedData.post;
        } catch {
            print(error);
        }
    }
}

struct InfoView: View {
    @State var post: PostContent;
    @State var search: String;

    var body: some View {
        if (!post.description.isEmpty) {
            AttributedText(descParser(text: .init(post.description)))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        VStack(alignment: .leading) {
            TagGroup(label: "Artist", tags: post.tags.artist, search: search, textColor: Color.yellow)
            TagGroup(label: "Character", tags: post.tags.character, search: search, textColor: Color.green)
            TagGroup(label: "Copyright", tags: post.tags.copyright, search: search, textColor: Color.purple)
            TagGroup(label: "Species", tags: post.tags.species, search: search, textColor: Color.red)
            TagGroup(label: "General", tags: post.tags.general, search: search, textColor: Color.blue)
            if (!post.sources.isEmpty) {
                DisclosureGroup {
                    VStack(alignment: .leading) {
                        ForEach(post.sources, id: \.self) { tag in
                            Text(.init(tag))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } label: {
                    Text("Sources")
                        .font(.title3)
                        .fontWeight(.heavy)
                        .foregroundColor(Color.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
        }
    }
}

struct ActionBar: View {
    @State var post: PostContent;
    @State var search: String;
    @State var favorited: Bool = false;
    @State var our_score: Int = 2;
    @State var score_valid: Bool = false
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    @Binding var displayToastType: Int
    @State private var showComments: Bool = false;

    var buttonSpacing = EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 5);
    
    var body: some View {
        ZStack {
            HStack(spacing: 25) {
                Button(action: {
                    Task.init {
                        our_score = await votePost(postId: post.id, value: 1, no_unvote: false);
                    }
                }) {
                    Image(systemName: our_score == 1 ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                        .font(.title)
                        .foregroundColor(!score_valid ? .gray : .green)
                        .padding(buttonSpacing)
                }.disabled(!score_valid || !AUTHENTICATED)
                Button(action: {
                    Task.init {
                        favorited = favorited ? await unFavoritePost(postId: post.id) : await favoritePost(postId: post.id);
                    }
                }) {
                    Image(systemName: favorited ? "heart.fill" : "heart")
                        .font(.title)
                        .foregroundColor(.red)
                        .padding(buttonSpacing)
                }.disabled(!AUTHENTICATED)
                Button(action: {
                    Task.init {
                        our_score = await votePost(postId: post.id, value: -1, no_unvote: false);
                    }
                }) {
                    Image(systemName: our_score == -1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                        .font(.title)
                        .foregroundColor(!score_valid ? .gray : .orange)
                        .padding(buttonSpacing)
                }.disabled(!score_valid || !AUTHENTICATED)
            }
            HStack() {
                Spacer().frame(width: 10)
                Button(action: {
                    showComments = true
                }) {
                    Image(systemName: "bubble.left")
                        .font(.title)
                        .foregroundColor(.blue)
                        .padding(buttonSpacing)
                }
                Spacer()
            }
            HStack() {
                Spacer()
                Button(action: {
                    Task.init {
                        displayToastType = -1 // Show loading toast
                        saveFile(post: post, showToast: $displayToastType);
                    }
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title)
                        .padding(buttonSpacing)
                }
                ShareLink(item: URL(string: "https://\(UserDefaults.standard.string(forKey: "api_source") ?? "e926.net")/posts/\(post.id)")!) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title)
                        .padding(buttonSpacing)
                }
                Spacer().frame(width: 10)
            }
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showComments, content: {
            CommentsView(post: post)
        })
        .onAppear() {
            favorited = post.is_favorited
        }
        .task {
            await fetchCurrentPostLiked();
            await fetchCurrentPostVote();
        }
    }

    func fetchCurrentPostLiked() async {
        do {
            let url = "/posts/\(post.id).json"
            let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json");
            if (data) == nil { return; }
            let parsedData = try JSONDecoder().decode(Post.self, from: data!)
            favorited = parsedData.post.is_favorited;
        } catch {
            print(error);
        }
    }

    func fetchCurrentPostVote() async {
        our_score = await getVote(postId: post.id);
        print(our_score)
        score_valid = [-1,0,1].contains(our_score);
        print(score_valid)
    }
}

struct TagGroup: View {
    @State var label: String;
    @State var tags: [String];
    @State var search: String;
    @State var textColor: Color;
    
    var body: some View {
        if tags.isEmpty {
            
        } else {
            DisclosureGroup {
                VStack(alignment: .leading) {
                    ForEach(tags, id: \.self) { tag in
                        Tag(tag: tag, search: search, textColor: textColor)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } label: {
                Text(label)
                    .font(.title3)
                    .fontWeight(.heavy)
                    .foregroundColor(Color.primary)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

struct Tag: View {
    @State var tag: String
    @State var search: String
    @State var textColor: Color;
    @State var isActive: Bool = false
    
    var body: some View {
        Menu {
            NavigationLink(destination: SearchView(search: String(tag))) {
                Text("New Search")
            }
            NavigationLink(destination: SearchView(search: String(search + " " + tag))) {
                Text("Add to Current Search")
            }
        } label: {
            Text(tag)
                .font(.body)
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
        } primaryAction: {
            isActive.toggle()
        }
        //.background(
        //    NavigationLink(destination: SearchView(search: String(tag)), isActive: $isActive) {}
        //)
        .navigationDestination(isPresented: $isActive) {
            SearchView(search: String(tag))
        }
    }
}

func descParser(text: String)-> String {
    var newText = text.replacingOccurrences(of: "[b]", with: "<b>");
    newText = newText.replacingOccurrences(of: "[/b]", with: "</b>");
    newText = newText.replacingOccurrences(of: "[u]", with: "<u>");
    newText = newText.replacingOccurrences(of: "[/u]", with: "</u>");
    newText = newText.replacingOccurrences(of: "[quote]", with: "\"");
    newText = newText.replacingOccurrences(of: "[/quote]", with: "\"");
    return newText;
}
