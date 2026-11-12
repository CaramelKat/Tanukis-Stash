//
//  PostView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/4/22.
//

import SwiftUI
import UIKit
import AlertToast
import AttributedText

struct PostPageContent: View {
    @State var post: PostContent;
    @State var search: String;
    @Binding var showImageViewer: Bool;
    @Binding var displayToastType: Int;
    var isActive: Bool = true;
    var onVideoEnded: (() -> Void)? = nil;

    // Tapping an image or GIF opens the fullscreen viewer. Videos open it via
    // the player's fullscreen button instead; tapping a video surface toggles
    // the player controls.
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
                    MediaView(
                        post: post,
                        geometry: geometry,
                        isActive: isActive,
                        onRequestFullscreen: { showImageViewer = true },
                        onVideoEnded: onVideoEnded
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: mediaHeight)
                    .contentShape(Rectangle())
                    .gesture(tapGesture)
                    // Hold on a picture/GIF for the copy/download menu.
                    .contextMenu {
                        if (!["webm", "mp4"].contains(String(post.file.ext))) {
                            MediaActionButtons(post: post, displayToastType: $displayToastType)
                        }
                    }
                    VStack(spacing: 0) {
                        VStack {
                            HStack {
                                Text(post.tags.artist.joined(separator: ", "));
                                Spacer();
                            }
                            HStack {
                                Text("\(post.rating) #\(String(post.id)) ⬆️\(post.score.total) ❤️\(post.fav_count) 💬\(post.comment_count)")
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
    var onIndexChanged: ((Int) -> Void)? = nil;
    @Environment(\.dismiss) private var dismiss;

    @State private var displayToastType = 0;
    @State private var dismissOffset: CGFloat = 0;
    @State private var dismissOpacity: Double = 1;

    // Slideshow (reconstructed from the 0.4.6 binary and extended)
    @AppStorage("SLIDESHOW_INTERVAL") private var slideshowInterval: Double = 5;
    @AppStorage("SLIDESHOW_VIDEO_MODE") private var slideshowVideoMode: SlideshowVideoMode = .interval;
    @State private var isSlideshowRunning: Bool = false;
    @State private var showSlideshowOptions: Bool = false;
    @State private var slideshowTask: Task<Void, Never>? = nil;
    @State private var isLoadingMorePosts: Bool = false;
    @State private var videoEndWaiters: [SlideshowVideoWaiter] = [];

    init(posts: [PostContent], currentIndex: Int, search: String, onIndexChanged: ((Int) -> Void)? = nil) {
        _posts = State(initialValue: posts)
        _currentIndex = State(initialValue: currentIndex)
        _search = State(initialValue: search)
        self.onIndexChanged = onIndexChanged
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
                    displayToastType: $displayToastType,
                    onDismissDrag: { distance, velocity, ended in
                        if ended {
                            finishDismissDrag(distance: distance, velocity: velocity, height: geometry.size.height)
                        } else {
                            dismissOffset = distance
                            dismissOpacity = 1 - min(1, distance / 600)
                        }
                    },
                    onVideoEnded: { index in handleVideoEnded(index) }
                )

                ActionBar(
                    post: post,
                    search: search,
                    displayToastType: $displayToastType,
                    isSlideshowRunning: $isSlideshowRunning,
                    onToggleSlideshow: { toggleSlideshow() },
                    onFavoriteChanged: { postID, newValue in updateFavoriteState(postID: postID, isFavorited: newValue) }
                )
                    .id(post.id)
            }
            .offset(y: dismissOffset)
            .opacity(dismissOpacity)
            .toast(isPresenting: Binding<Bool>(get: { displayToastType != 0 }, set: { _ in })) {
                getToast()
            }
            // Fullscreen media viewer. currentIndex is shared with the post
            // pager, so swiping inside the viewer navigates posts and the
            // slideshow keeps advancing the fullscreen media.
            .fullScreenCover(isPresented: $showImageViewer, content: {
                FullscreenMediaViewer(
                    posts: $posts,
                    currentIndex: $currentIndex,
                    isSlideshowRunning: $isSlideshowRunning,
                    onToggleSlideshow: { toggleSlideshow() },
                    onStartSlideshow: { startSlideshow() },
                    onVideoEnded: { index in handleVideoEnded(index) },
                    onFavoriteChanged: { postID, newValue in updateFavoriteState(postID: postID, isFavorited: newValue) }
                )
            })
            .sheet(isPresented: $showSlideshowOptions, content: {
                // The slideshow only starts once the user presses Start in
                // the sheet, after picking the interval and video options.
                SlideshowOptionsView(onStart: {
                    if (!isSlideshowRunning) {
                        startSlideshow();
                    }
                })
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
        .onChange(of: currentIndex) { _, newIndex in
            preloadNeighbors()
            onIndexChanged?(newIndex)
            ensureMorePosts()
        }
        .onDisappear {
            // Stops the slideshow (if running) and lets the screen sleep again.
            // Skip while the fullscreen viewer is presented: on some iOS
            // versions onDisappear also fires when a fullScreenCover appears.
            if (!showImageViewer) {
                stopSlideshow()
            }
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

    /// Writes a post's favorite state back into the posts array so every view
    /// (post page, fullscreen viewer, revisited pages) agrees on it.
    func updateFavoriteState(postID: Int, isFavorited: Bool) {
        if let index = posts.firstIndex(where: { $0.id == postID }) {
            posts[index].is_favorited = isFavorited
        }
    }

    // MARK: - Slideshow

    func toggleSlideshow() {
        if isSlideshowRunning {
            stopSlideshow()
        } else {
            // Don't start right away: the user picks the interval and video
            // options first, then presses Start in the sheet.
            showSlideshowOptions = true
        }
    }

    func startSlideshow() {
        isSlideshowRunning = true
        // Keep the screen awake while the slideshow is running.
        UIApplication.shared.isIdleTimerDisabled = true
        slideshowTask = Task {
            await runSlideshowStep()
        }
    }

    func stopSlideshow() {
        isSlideshowRunning = false
        slideshowTask?.cancel()
        slideshowTask = nil
        resumeVideoEndWaiters()
        // The slideshow is off; the phone is allowed to fall asleep again.
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func runSlideshowStep() async {
        slideshowLoop: while isSlideshowRunning && !Task.isCancelled {
            guard currentIndex >= 0, currentIndex < posts.count else { break }

            let currentPost = posts[currentIndex]
            let isVideo = isVideoPost(currentPost)

            if isVideo {
                switch slideshowVideoMode {
                case .skip:
                    await advanceSlideshow(skipVideos: true)
                    continue slideshowLoop
                case .playThrough:
                    // Wait for the video to actually finish, with a duration
                    // based timeout as a fallback.
                    let timeout = currentPost.duration.map { Double($0) + 2 } ?? 30
                    await awaitVideoEnd(timeout: max(timeout, 5))
                    guard isSlideshowRunning && !Task.isCancelled else { break slideshowLoop }
                    await advanceSlideshow(skipVideos: false)
                    continue slideshowLoop
                case .interval:
                    await slideshowSleep(seconds: slideshowInterval)
                }
            } else {
                await slideshowSleep(seconds: slideshowInterval)
            }

            guard isSlideshowRunning && !Task.isCancelled else { break }
            await advanceSlideshow(skipVideos: slideshowVideoMode == .skip)
        }
    }

    func advanceSlideshow(skipVideos: Bool) async {
        var next = currentIndex + 1

        if skipVideos {
            while next < posts.count && isVideoPost(posts[next]) {
                next += 1
            }
        }

        if next >= posts.count {
            await loadMorePosts()
            if skipVideos {
                while next < posts.count && isVideoPost(posts[next]) {
                    next += 1
                }
            }
            guard next < posts.count else {
                stopSlideshow()
                return
            }
        }

        currentIndex = next
    }

    func isVideoPost(_ post: PostContent) -> Bool {
        return ["webm", "mp4"].contains(String(post.file.ext))
    }

    func slideshowSleep(seconds: Double) async {
        try? await Task.sleep(for: .seconds(max(seconds, 0.1)))
    }

    /// Wakes up when the video at the current index finishes playing, or after
    /// `timeout` seconds, whichever comes first.
    func awaitVideoEnd(timeout: Double) async {
        await withCheckedContinuation { continuation in
            let waiter = SlideshowVideoWaiter(continuation)
            videoEndWaiters.append(waiter)
            Task {
                try? await Task.sleep(for: .seconds(max(timeout, 1)))
                waiter.resume()
            }
        }
    }

    /// Called by the video player when a post's video finishes playing.
    func handleVideoEnded(_ index: Int) {
        guard isSlideshowRunning, index == currentIndex else { return }
        resumeVideoEndWaiters()
    }

    func resumeVideoEndWaiters() {
        let waiters = videoEndWaiters
        videoEndWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    // MARK: - Infinite loading (used by the slideshow and the post pager)

    /// Fetches more posts once the pager gets close to the end of the
    /// currently loaded set.
    func ensureMorePosts() {
        guard !isLoadingMorePosts, currentIndex >= posts.count - 3 else { return }
        Task {
            await loadMorePosts()
        }
    }

    func loadMorePosts() async {
        guard !isLoadingMorePosts else { return }
        isLoadingMorePosts = true
        defer { isLoadingMorePosts = false }

        let limit = 75
        // posts.count / limit + 1 is the next page this pager has not seen.
        // Blacklist filtering can make pages smaller, so retry one page
        // further if a fetch comes back with only already-known posts.
        var page = (posts.count / limit) + 1
        for _ in 0..<3 {
            let fetched = await fetchRecentPosts(page, limit, search)
            let knownIDs = Set(posts.map { $0.id })
            let fresh = fetched.filter { !knownIDs.contains($0.id) }
            if !fresh.isEmpty {
                posts += fresh
                return
            }
            if fetched.isEmpty { return }
            page += 1
        }
    }

    func finishDismissDrag(distance: CGFloat, velocity: CGFloat, height: CGFloat) {
        if PostDismissPolicy.shouldDismiss(distance: distance, velocity: velocity) {
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
        case 4:
            clearToast()
            return AlertToast(type: .error(Color.red), title: "Failed to save")
        case 5:
            clearToast()
            return AlertToast(type: .complete(Color.green), title: "Copied!")
        default:
            clearToast()
            return AlertToast(type: .regular, title: "Unknown error \(displayToastType)")
        }
    }
}

enum PostDismissPolicy {
    static func shouldBegin(offset: CGFloat, top: CGFloat, velocity: CGPoint) -> Bool {
        offset <= top + 8 && velocity.y > abs(velocity.x)
    }

    static func shouldDismiss(distance: CGFloat, velocity: CGFloat) -> Bool {
        velocity > -300 && (distance >= 80 || (distance >= 20 && velocity >= 650))
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
    @Binding var displayToastType: Int
    var onDismissDrag: (CGFloat, CGFloat, Bool) -> Void
    var onVideoEnded: ((Int) -> Void)? = nil

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
            let onVideoEnded = parent.onVideoEnded
            return PostPageContent(
                post: parent.posts[index],
                search: parent.search,
                showImageViewer: parent.$showImageViewer,
                displayToastType: parent.$displayToastType,
                isActive: isActive,
                onVideoEnded: onVideoEnded == nil ? nil : { onVideoEnded?(index) }
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
            dismissPan.maximumNumberOfTouches = 1
            hostingController.dismissPan = dismissPan
            hostingController.view.addGestureRecognizer(dismissPan)
            pages[index] = hostingController
            return hostingController
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = gestureRecognizer.view,
                let entry = pages.first(where: { $0.value.view === view }),
                let scrollView = entry.value.postScrollView,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            return PostDismissPolicy.shouldBegin(
                offset: scrollView.contentOffset.y,
                top: -scrollView.adjustedContentInset.top,
                velocity: pan.velocity(in: view.window)
            )
        }

        @objc private func handleDismissPan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let distance = max(0, pan.translation(in: view.window).y)
            let velocity = pan.velocity(in: view.window).y
            switch pan.state {
            case .changed:
                parent.onDismissDrag(distance, velocity, false)
            case .ended:
                parent.onDismissDrag(distance, velocity, true)
            case .cancelled, .failed:
                parent.onDismissDrag(0, 0, true)
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
        Text(formatPostDate(post.created_at))
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        if (!post.description.isEmpty) {
            DTextView(text: post.description)
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
    var post: PostContent;
    @State var search: String;
    @State var favorited: Bool = false;
    // Start in a valid neutral state so the buttons render colored right
    // away (like the favorite heart); a known/cached vote corrects them
    // shortly after. 2/invalid meant "gray until the fetch lands".
    @State var our_score: Int = 0;
    @State var score_valid: Bool = true
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    @Binding var displayToastType: Int
    @Binding var isSlideshowRunning: Bool
    var onToggleSlideshow: () -> Void
    /// Reports (post id, new favorite state) so the owning view can keep the
    /// post data in sync — the post page and the fullscreen viewer then agree,
    /// and revisiting a page later shows the right state.
    var onFavoriteChanged: ((Int, Bool) -> Void)? = nil
    @State private var showComments: Bool = false;
    @State private var showLoginPrompt: Bool = false;
    /// Bumped whenever the user votes/favorites, so a state fetch that was
    /// still in flight does not clobber the newer user action.
    @State private var stateGeneration: Int = 0;

    var buttonSpacing = EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 5);
    
    var body: some View {
        ZStack {
            HStack(spacing: 25) {
                Button(action: { vote(1) }) {
                    Image(systemName: our_score == 1 ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                        .font(.title)
                        .foregroundColor(!score_valid ? .gray : .green)
                        .padding(buttonSpacing)
                }.disabled(AUTHENTICATED && !score_valid)
                Button(action: { toggleFavorite() }) {
                    Image(systemName: favorited ? "heart.fill" : "heart")
                        .font(.title)
                        .foregroundColor(.red)
                        .padding(buttonSpacing)
                }
                Button(action: { vote(-1) }) {
                    Image(systemName: our_score == -1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                        .font(.title)
                        .foregroundColor(!score_valid ? .gray : .orange)
                        .padding(buttonSpacing)
                }.disabled(AUTHENTICATED && !score_valid)
            }
            HStack(spacing: 12) {
                Spacer().frame(width: 10)
                Button(action: {
                    showComments = true
                }) {
                    Image(systemName: "bubble.left")
                        .font(.title)
                        .foregroundColor(.blue)
                        .padding(buttonSpacing)
                }
                // Slideshow play/pause. Starting opens the slideshow options
                // sheet; the slideshow begins from its Start button.
                Button(action: onToggleSlideshow) {
                    Image(systemName: isSlideshowRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(isSlideshowRunning ? .green : .blue)
                        .padding(buttonSpacing)
                }
                Spacer()
            }
            HStack() {
                Spacer()
                // Same copy/download menu as long-pressing the media.
                Menu {
                    MediaActionButtons(post: post, displayToastType: $displayToastType)
                } label: {
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
        .alert("You need to log in first", isPresented: $showLoginPrompt) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sign in from Settings with your e621 username and API key to favorite or vote on posts.")
        }
        .onAppear() {
            favorited = post.is_favorited
            AUTHENTICATED = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
        }
        .task(id: post.id) {
            // Fresh state per post. The generation guard keeps a slow fetch
            // from overwriting a vote/favorite the user just made.
            let generation = stateGeneration
            await fetchCurrentPostLiked(generation: generation);
            await fetchCurrentPostVote(generation: generation);
        }
        .onChange(of: post.is_favorited) { _, newValue in
            // The favorite state changed somewhere else (e.g. favoriting in
            // the fullscreen viewer); follow it so this heart matches.
            favorited = newValue
        }
    }

    func vote(_ value: Int) {
        if (!AUTHENTICATED) {
            showLoginPrompt = true;
            return;
        }
        stateGeneration += 1;
        Task.init {
            our_score = await votePost(postId: post.id, value: value, no_unvote: false);
            score_valid = [-1, 0, 1].contains(our_score);
        }
    }

    func toggleFavorite() {
        if (!AUTHENTICATED) {
            showLoginPrompt = true;
            return;
        }
        let wasFavorited = favorited;
        stateGeneration += 1;
        // Optimistic: show the change immediately, revert if the API
        // rejects it.
        favorited = !wasFavorited;
        Task.init {
            let success = wasFavorited
                ? await unFavoritePost(postId: post.id)
                : await favoritePost(postId: post.id);
            if (!success) {
                favorited = wasFavorited;
            } else {
                onFavoriteChanged?(post.id, !wasFavorited);
            }
        }
    }

    func fetchCurrentPostLiked(generation: Int) async {
        do {
            let url = "/posts/\(post.id).json"
            let data = await makeRequest(destination: url, method: "GET", body: nil, contentType: "application/json", noCache: true);
            if (data) == nil { return; }
            let parsedData = try JSONDecoder().decode(Post.self, from: data!)
            if (stateGeneration == generation) {
                favorited = parsedData.post.is_favorited;
            }
        } catch {
            print(error);
        }
    }

    func fetchCurrentPostVote(generation: Int) async {
        let fetchedScore = await getVote(postId: post.id);
        if (stateGeneration == generation) {
            our_score = fetchedScore;
            score_valid = [-1, 0, 1].contains(fetchedScore);
        }
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

// Formats a post's ISO-8601 created_at string into a human readable local date.
func formatPostDate(_ isoDate: String) -> String {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let noFraction = ISO8601DateFormatter()
    noFraction.formatOptions = [.withInternetDateTime]

    guard let date = withFraction.date(from: isoDate) ?? noFraction.date(from: isoDate) else {
        return isoDate
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return "Posted on \(formatter.string(from: date))"
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
