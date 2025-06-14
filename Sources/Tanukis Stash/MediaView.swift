import SwiftUI
import SwiftyGif

struct MediaView: View {

    @State var post: PostContent;
    @State var geometry: GeometryProxy;
    var isFullScreen: Bool = false

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

    var body: some View {
        AsyncImage(url: URL(string: post.file.url!)) { image in
            image
                .resizable()
        } 
        placeholder: {
            ZStack {
                AsyncImage(url: URL(string: post.preview.url!))
                    .opacity(0.25)
                    .scaledToFit()
                ProgressView()
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

    var videoLink: URL? {
        return getVideoLink(post: post)
    }

    var body: some View {
        if (videoLink != nil) {
            VideoPlayerController(videoURL: videoLink!)
        }
        else {
            Text("Video failed to load")
        }
        
    }
}
