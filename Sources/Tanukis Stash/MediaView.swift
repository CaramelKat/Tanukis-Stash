import SwiftUI
import SwiftyGif

struct MediaView: View {

    @State var post: PostContent;
    @State var geometry: GeometryProxy;
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
            GIFView(post: post)
            .aspectRatio(contentMode: .fit)
            .background(Color.black.opacity(0.5))
        }
        else if(["webm", "mp4"].contains(fileType)) {
            VideoView(post: post, isActive: isActive, isFullScreen: isFullScreen, onRequestFullscreen: onRequestFullscreen, onVideoEnded: onVideoEnded)
        }
        else if(!["gif", "webm", "mp4"].contains(fileType)) {
            ImageView(post: post)
            .aspectRatio(contentMode: .fit)
        }
        else {
            Text("")
        }
    }
    
}

struct ImageView: View {

    @State var post: PostContent;
    @State private var image: UIImage?;

    nonisolated(unsafe) static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
            } else {
                ZStack {
                    AsyncImage(url: URL(string: post.preview.url!))
                        .opacity(0.25)
                        .scaledToFit()
                    ProgressView()
                }
            }
        }
        .onAppear {
            load()
        }
    }

    static func preload(_ urlString: String) {
        if cache.object(forKey: urlString as NSString) != nil { return }
        DispatchQueue.global().async {
            guard let url = URL(string: urlString),
                  let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else {
                return
            }
            cache.setObject(img, forKey: urlString as NSString)
        }
    }

    func load() {
        guard let urlString = post.file.url else { return }
        if let cached = ImageView.cache.object(forKey: urlString as NSString) {
            image = cached
            return
        }
        DispatchQueue.global().async {
            guard let url = URL(string: urlString),
                  let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else {
                return
            }
            ImageView.cache.setObject(img, forKey: urlString as NSString)
            DispatchQueue.main.async {
                image = img
            }
        }
    }
}

struct GIFView: View {

    @State var post: PostContent;

    var body: some View {
        let url = URL(string: post.file.url!)!
        AnimatedGifView(url: Binding(get: { url }, set: { _ in }))
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
    if let cached = ImageView.cache.object(forKey: urlString as NSString) {
        UIPasteboard.general.image = cached
        showToast.wrappedValue = 5 // Copied
        return
    }
    let data = await Task.detached(priority: .utility) {
        try? Data(contentsOf: url)
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

    @State var post: PostContent;
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
