import SwiftUI
import SwiftyGif

struct MediaView: View {

    @State var post: PostContent;
    @State var geometry: GeometryProxy;
    var isFullScreen: Bool = false
    var isActive: Bool = true

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
            VideoView(post: post)
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

struct VideoView: View {

    @State var post: PostContent;
    var isActive: Bool = true

    var videoLink: URL? {
        return getVideoLink(post: post)
    }

    var body: some View {
        if let link = videoLink {
            VideoPlayerController(videoURL: link, isActive: isActive)
                .aspectRatio(CGFloat(max(post.file.width, 1)) / CGFloat(max(post.file.height, 1)), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
        else {
            Text("Video failed to load")
        }
    }
}
