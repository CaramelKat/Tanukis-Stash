import SwiftUI
import SwiftyGif

struct MediaView: View {

    var post: PostContent;
    var geometry: GeometryProxy;
    var isFullScreen: Bool = false
    var isActive: Bool = true
    /// Fired when the user taps the video player's fullscreen button. Used on
    /// the post page to open the fullscreen media viewer; nil inside the
    /// fullscreen viewer itself (the button is hidden there). Tapping the
    /// video surface itself only toggles the player controls.
    var onRequestFullscreen: (() -> Void)? = nil
    /// Fired when the video post finishes playing (used by the slideshow's
    /// "wait for videos" mode).
    var onVideoEnded: (() -> Void)? = nil

    var fileType: String {
        return String(post.file.ext)
    }
    
    var body: some View {
        if(post.preview.url == nil || post.file.url == nil) {
            Text("Failed to load image data!")
        }
        else if(fileType == "gif") {
            GIFView(post: post, isActive: isActive)
            .aspectRatio(contentMode: .fit)
            .background(Color.black.opacity(0.5))
        }
        else if(["webm", "mp4"].contains(fileType)) {
            VideoView(post: post, isActive: isActive, isFullScreen: isFullScreen, onRequestFullscreen: onRequestFullscreen, onVideoEnded: onVideoEnded)
        }
        else if(!["gif", "webm", "mp4"].contains(fileType)) {
            ImageView(post: post, isFullScreen: isFullScreen, isActive: isActive)
            .aspectRatio(contentMode: .fit)
        }
        else {
            Text("")
        }
    }
    
}

/// Displays a still image. Inline pages use the server's sample (at most a few
/// megapixels) instead of the original file; the fullscreen viewer upgrades
/// only the visible page to the original for zooming. Everything is decoded at
/// roughly display size, so memory stays bounded while paging.
struct ImageView: View {

    var post: PostContent;
    var isFullScreen: Bool = false
    var isActive: Bool = true

    @State private var image: UIImage?;
    @State private var failed: Bool = false;

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                ThumbnailImage(urlString: post.preview.url, maxPixelSize: 700)
                    .opacity(0.3)
                if (!failed) {
                    ProgressView()
                }
            }
        }
        .task(id: loadKey) {
            await load()
        }
    }

    /// Re-runs when the page becomes visible, so the fullscreen upgrade only
    /// happens for the image the user is actually looking at.
    private var loadKey: String {
        "\(post.id)|\(isFullScreen)|\(isActive)"
    }

    private func load() async {
        if (image == nil) {
            guard let baseURL = post.sampleOrFileURL else {
                failed = true
                return
            }
            if let loaded = await ImagePipeline.shared.image(
                for: baseURL,
                maxPixelSize: isFullScreen ? 1800 : 1400
            ) {
                image = loaded
            } else {
                failed = true
                return
            }
        }

        // Original only for the visible fullscreen page. Paging neighbours keep
        // the sample, which saves both bandwidth and tens of megabytes of
        // decoded pixels per page held by the pager.
        guard isFullScreen, isActive,
              let original = post.originalURL,
              original != post.sampleOrFileURL else { return }
        if let full = await ImagePipeline.shared.image(for: original, maxPixelSize: 2400) {
            if (!Task.isCancelled) {
                image = full
            }
        }
    }
}

/// Animated GIF. Only the visible page loads and animates the (potentially
/// large) GIF; neighbours and preloaded pages show the lightweight preview.
struct GIFView: View {

    var post: PostContent;
    var isActive: Bool = true

    var body: some View {
        ZStack {
            ThumbnailImage(urlString: post.preview.url, maxPixelSize: 900)
            if isActive, let urlString = post.file.url, let url = URL(string: urlString) {
                AnimatedGifView(url: Binding(get: { url }, set: { _ in }))
            }
        }
    }
}

/// Copy / Download actions. Shared by the post page's long-press media menu
/// and the ActionBar download button.
struct MediaActionButtons: View {
    @State var post: PostContent;
    @Binding var displayToastType: Int;

    var body: some View {
        Button {
            Task.init {
                await copyPostMedia(post: post, showToast: $displayToastType)
            }
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button {
            Task.init {
                displayToastType = -1 // Show loading toast
                saveFile(post: post, showToast: $displayToastType)
            }
        } label: {
            Label("Download", systemImage: "square.and.arrow.down")
        }
    }
}

/// Copies a post's image (animated GIFs included) to the system clipboard.
@MainActor
func copyPostMedia(post: PostContent, showToast: Binding<Int>) async {
    guard let urlString = post.file.url, let url = URL(string: urlString) else {
        showToast.wrappedValue = 1 // Failed to save
        return
    }
    // Copying wants the untouched original, so it is downloaded directly
    // instead of using the display-sized cache.
    let data = await Task.detached(priority: .userInitiated) { () -> Data? in
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        guard let (data, response) = try? await NetworkSession.shared.data(for: request) else {
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return data
    }.value
    guard let data else {
        showToast.wrappedValue = 1 // Failed to save
        return
    }
    if (String(post.file.ext) == "gif") {
        // Keep the animation when pasting GIFs.
        UIPasteboard.general.setData(data, forPasteboardType: "com.compuserve.gif")
    } else if let image = UIImage(data: data) {
        UIPasteboard.general.image = image
    } else {
        showToast.wrappedValue = 1 // Failed to save
        return
    }
    showToast.wrappedValue = 5 // Copied
}

struct VideoView: View {

    var post: PostContent;
    var isActive: Bool = true
    var isFullScreen: Bool = false
    var onRequestFullscreen: (() -> Void)? = nil
    var onVideoEnded: (() -> Void)? = nil

    var videoLink: URL? {
        return getVideoLink(post: post)
    }

    var body: some View {
        if let link = videoLink {
            VideoPlayerController(videoURL: link, isActive: isActive, isFullScreen: isFullScreen, onRequestFullscreen: onRequestFullscreen, onVideoEnded: onVideoEnded)
                .aspectRatio(CGFloat(max(post.file.width, 1)) / CGFloat(max(post.file.height, 1)), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
        else {
            Text("Video failed to load")
        }
    }
}
