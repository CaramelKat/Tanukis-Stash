//
//  FullscreenMediaViewer.swift
//  Tanuki's Stash
//
//  Created by Max on 12/19/24.
//  Reworked from the single-post FullscreenImageViewer into a swipeable,
//  slideshow-aware fullscreen pager.
//

import SwiftUI
import UIKit

/// Fullscreen media viewer with swipe navigation.
///
/// Presented from PostView via fullScreenCover. `currentIndex` is shared with
/// the post pager, so:
/// - swiping left/right here also moves the post pager underneath, and
/// - while the slideshow is running, the fullscreen media follows along as
///   the slideshow advances posts.
struct FullscreenMediaViewer: View {
    @Binding var posts: [PostContent]
    @Binding var currentIndex: Int
    @Binding var isSlideshowRunning: Bool
    var onToggleSlideshow: () -> Void
    var onStartSlideshow: () -> Void
    var onVideoEnded: ((Int) -> Void)? = nil
    var onFavoriteChanged: ((Int, Bool) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showSlideshowOptions = false
    @State private var dismissOffset: CGFloat = 0
    @State private var dismissOpacity: Double = 1

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            FullscreenMediaPagerView(
                posts: posts,
                currentIndex: $currentIndex,
                onVideoEnded: onVideoEnded,
                onDismissDrag: { distance, velocity, ended in
                    if ended {
                        finishDismissDrag(distance: distance, velocity: velocity)
                    } else {
                        dismissOffset = distance
                        dismissOpacity = 1 - min(1, distance / 600)
                    }
                }
            )
            .offset(y: dismissOffset)
            .opacity(dismissOpacity)
        }
        .overlay(alignment: .topLeading) {
            circleButton(symbol: "xmark", action: { dismiss() })
                .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            // Slideshow play/pause. Starting opens the options sheet; the
            // slideshow itself only begins from that sheet's Start button.
            circleButton(
                symbol: isSlideshowRunning ? "pause.circle.fill" : "play.circle.fill",
                action: {
                    if isSlideshowRunning {
                        onToggleSlideshow()
                    } else {
                        showSlideshowOptions = true
                    }
                }
            )
            .padding(12)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                // The id keeps the vote bar's state per post; without it the
                // heart "sticks" filled across posts while paging/slideshow.
                FullscreenVoteBar(post: posts[currentIndex], onFavoriteChanged: onFavoriteChanged)
                    .id(posts[currentIndex].id)
                Text("\(currentIndex + 1) / \(posts.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
            }
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showSlideshowOptions) {
            SlideshowOptionsView(onStart: {
                if (!isSlideshowRunning) {
                    onStartSlideshow();
                }
            })
        }
    }

    /// A mostly downward swipe on the media closes the viewer.
    func finishDismissDrag(distance: CGFloat, velocity: CGFloat) {
        if PostDismissPolicy.shouldDismiss(distance: distance, velocity: velocity) {
            withAnimation(.easeOut(duration: 0.22)) {
                dismissOffset = 1000
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

    private func circleButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .padding(12)
                .background(.black.opacity(0.6))
                .clipShape(Circle())
        }
    }
}

/// Upvote / favorite / downvote controls shown at the bottom of the
/// fullscreen media viewer (the ActionBar is not visible there). Owns its
/// state per post — the parent attaches `.id(post.id)` so paging resets it.
/// Follows favorite changes made elsewhere (e.g. the ActionBar) through the
/// post value.
struct FullscreenVoteBar: View {
    var post: PostContent;
    var onFavoriteChanged: ((Int, Bool) -> Void)? = nil;

    @State private var favorited: Bool = false;
    // Start in a valid neutral state so the buttons render colored right
    // away (like the favorite heart); a known/cached vote corrects them
    // shortly after.
    @State private var ourScore: Int = 0;
    @State private var scoreValid: Bool = true;
    @State private var AUTHENTICATED: Bool = UserDefaults.standard.bool(forKey: "AUTHENTICATED");
    @State private var showLoginPrompt: Bool = false;
    /// Bumped whenever the user votes/favorites, so a state fetch that was
    /// still in flight does not clobber the newer user action.
    @State private var stateGeneration: Int = 0;

    var body: some View {
        HStack(spacing: 30) {
            Button(action: { vote(1) }) {
                Image(systemName: ourScore == 1 ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    .font(.title2)
                    .foregroundColor(!scoreValid ? .gray : .green)
            }
            .disabled(AUTHENTICATED && !scoreValid)
            Button(action: { toggleFavorite() }) {
                Image(systemName: favorited ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            Button(action: { vote(-1) }) {
                Image(systemName: ourScore == -1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                    .font(.title2)
                    .foregroundColor(!scoreValid ? .gray : .orange)
            }
            .disabled(AUTHENTICATED && !scoreValid)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.black.opacity(0.55))
        .clipShape(Capsule())
        .alert("You need to log in first", isPresented: $showLoginPrompt) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sign in from Settings with your e621 username and API key to favorite or vote on posts.")
        }
        .task(id: post.id) {
            AUTHENTICATED = UserDefaults.standard.bool(forKey: "AUTHENTICATED")
            // Immediately show what we know, then confirm with the API. The
            // generation guard keeps a slow fetch from overwriting a
            // vote/favorite the user just made.
            favorited = post.is_favorited
            let generation = stateGeneration
            let fetchedFavorited = await fetchPostIsFavorited(postId: post.id)
            if (stateGeneration == generation) {
                favorited = fetchedFavorited
            }
            let fetchedScore = await getVote(postId: post.id)
            if (stateGeneration == generation) {
                ourScore = fetchedScore
                scoreValid = [-1, 0, 1].contains(fetchedScore)
            }
        }
        .onChange(of: post.is_favorited) { _, newValue in
            // Favorite state changed elsewhere (e.g. the ActionBar behind
            // this viewer); follow it.
            favorited = newValue
        }
    }

    func vote(_ value: Int) {
        if (!AUTHENTICATED) {
            showLoginPrompt = true
            return
        }
        stateGeneration += 1
        Task.init {
            ourScore = await votePost(postId: post.id, value: value, no_unvote: false)
            scoreValid = [-1, 0, 1].contains(ourScore)
        }
    }

    func toggleFavorite() {
        if (!AUTHENTICATED) {
            showLoginPrompt = true
            return
        }
        let wasFavorited = favorited
        stateGeneration += 1
        // Optimistic: show the change immediately, revert if the API
        // rejects it.
        favorited = !wasFavorited
        Task.init {
            let success = wasFavorited
                ? await unFavoritePost(postId: post.id)
                : await favoritePost(postId: post.id)
            if (!success) {
                favorited = wasFavorited
            } else {
                onFavoriteChanged?(post.id, !wasFavorited)
            }
        }
    }
}

/// A single page of the fullscreen pager: the post media on a black
/// background. Images and GIFs are zoomable; videos play with the inline
/// player controls (the player's own fullscreen button is hidden because we
/// are already fullscreen).
struct FullscreenMediaPage: View {
    @State var post: PostContent;
    var isActive: Bool = false;
    var onVideoEnded: (() -> Void)? = nil;

    var body: some View {
        GeometryReader { geometry in
            if (["webm", "mp4"].contains(String(post.file.ext))) {
                MediaView(
                    post: post,
                    geometry: geometry,
                    isFullScreen: true,
                    isActive: isActive,
                    onVideoEnded: onVideoEnded
                )
                .frame(minWidth: 0, maxWidth: .greatestFiniteMagnitude, minHeight: 0, maxHeight: .greatestFiniteMagnitude)
            } else {
                ZoomableContainer {
                    MediaView(post: post, geometry: geometry, isFullScreen: true, isActive: isActive)
                        .frame(minWidth: 0, maxWidth: .greatestFiniteMagnitude, minHeight: 0, maxHeight: .greatestFiniteMagnitude)
                }
            }
        }
    }
}

/// UIPageViewController wrapper providing horizontal swipe navigation between
/// posts in the fullscreen viewer. Mirrors the structure of PostPagerView.
struct FullscreenMediaPagerView: UIViewControllerRepresentable {
    var posts: [PostContent]
    @Binding var currentIndex: Int
    var onVideoEnded: ((Int) -> Void)? = nil
    var onDismissDrag: (CGFloat, CGFloat, Bool) -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let options = [UIPageViewController.OptionsKey.interPageSpacing: 0]
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: options
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.view.backgroundColor = .clear

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
            context.coordinator.refreshActiveStates(in: pageViewController)
            return
        }
        context.coordinator.syncCurrentPage(in: pageViewController)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: FullscreenMediaPagerView
        private var pages: [Int: FullscreenMediaHostingController] = [:]

        init(_ parent: FullscreenMediaPagerView) {
            self.parent = parent
        }

        func makePageContent(index: Int, isActive: Bool) -> FullscreenMediaPage {
            let onVideoEnded = parent.onVideoEnded
            return FullscreenMediaPage(
                post: parent.posts[index],
                isActive: isActive,
                onVideoEnded: onVideoEnded == nil ? nil : { onVideoEnded?(index) }
            )
        }

        func makePage(at index: Int, isActive: Bool) -> FullscreenMediaHostingController? {
            guard index >= 0 && index < parent.posts.count else { return nil }
            if let existing = pages[index] {
                existing.rootView = makePageContent(index: index, isActive: isActive)
                return existing
            }
            let hostingController = FullscreenMediaHostingController(rootView: makePageContent(index: index, isActive: isActive))
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
                  let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            // Zoomed images keep their drag-to-pan behaviour.
            if let zoom = entry.value.zoomScrollView, zoom.zoomScale > zoom.minimumZoomScale {
                return false
            }
            // Only mostly downward swipes dismiss; horizontal ones page.
            let velocity = pan.velocity(in: view.window)
            return velocity.y > abs(velocity.x)
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
                page.rootView = makePageContent(index: index, isActive: index == active)
            }
        }

        func evictFarPages(around index: Int) {
            let keep = Set([index - 2, index - 1, index, index + 1, index + 2].filter { $0 >= 0 && $0 < parent.posts.count })
            for (pageIndex, _) in pages where !keep.contains(pageIndex) {
                pages.removeValue(forKey: pageIndex)
            }
        }

        func syncCurrentPage(in pageViewController: UIPageViewController) {
            let visibleIndex = pageViewController.viewControllers?.first.flatMap { index(of: $0) }
            let direction: UIPageViewController.NavigationDirection
            if let visibleIndex, parent.currentIndex < visibleIndex {
                direction = .reverse
            } else {
                direction = .forward
            }
            if let target = makePage(at: parent.currentIndex, isActive: true) {
                pageViewController.setViewControllers([target], direction: direction, animated: false, completion: nil)
            }
            refreshActiveStates(in: pageViewController)
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

/// Hosting controller for one fullscreen page. Owns the swipe-down-to-dismiss
/// pan; the zoom scrollview (images) requires it to fail so that panning a
/// zoomed image still works.
final class FullscreenMediaHostingController: UIHostingController<FullscreenMediaPage> {
    var dismissPan: UIPanGestureRecognizer?
    private(set) weak var zoomScrollView: UIScrollView?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard zoomScrollView == nil, let dismissPan,
              let scrollView = firstScrollView(in: view) else { return }
        scrollView.panGestureRecognizer.require(toFail: dismissPan)
        zoomScrollView = scrollView
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) { return scrollView }
        }
        return nil
    }
}
