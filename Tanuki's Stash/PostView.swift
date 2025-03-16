//
//  PostView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/4/22.
//

import SwiftUI
import ImageViewerRemote
import SwiftUIGIF
import AVKit
import Photos
import AlertToast
import AttributedText

struct PostView: View {
    @State private var showImageViewer: Bool = false;
    @State private var showToast: Bool = false;
    @State private var showLoadingToast: Bool = false
    @State private var showFailToast: Bool = false;
    @State var showSettings = false;
    @State var post: PostContent;
    @State var search: String;
    @State var url: String = "";
    @State private var parentPost: PostContent?;
    @State var favorited: Bool = false;
    @State var our_score: Int = 2;
    @State var score_valid: Bool = false
    @State private var authorizationStatus = PHAuthorizationStatus.notDetermined
    
    var buttonSpacing = EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 5);
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical) {
                VStack {
                    ImageView(post: post)
                        .onTapGesture {
                            showImageViewer = true
                        }
                        .sheet(isPresented: $showImageViewer, content: {
                            FullscreenImageViewer(post: post)
                        })
                    Spacer();
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
                            Spacer()
                        }
                        if(post.relationships.has_active_children) {
                            NavigationLink(destination: SearchView(search: "parent:" + String(post.id))) {
                                Text("Children")
                                    .foregroundColor(Color.red)
                                    .font(.headline)
                            }
                        }
                        if(post.pools.count > 0) {
                            Spacer()
                            NavigationLink(destination: SearchView(search: "pool:" + String(post.pools[0]))) {
                                Text("Pool")
                                    .foregroundColor(Color.green)
                                    .font(.headline)
                            }
                        }
                    }
                    if (!post.description.isEmpty) {
                        Spacer()
                        AttributedText(descParser(text: .init(post.description)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        TagGroup(label: "Artist", tags: post.tags.artist, search: search, textColor: Color.yellow)
                        TagGroup(label: "Character", tags: post.tags.character, search: search, textColor: Color.green)
                        TagGroup(label: "Copyright", tags: post.tags.copyright, search: search, textColor: Color.purple)
                        TagGroup(label: "Species", tags: post.tags.species, search: search, textColor: Color.red)
                        TagGroup(label: "General", tags: post.tags.general, search: search, textColor: Color.blue)
                        if (!post.sources.isEmpty) {
                            Text("Sources")
                                .font(.headline)
                                .fontWeight(.heavy)
                            ForEach(post.sources, id: \.self) { tag in
                                Text(.init(tag))
                                    .font(.footnote)
                                    .multilineTextAlignment(.leading)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, maxHeight: 10)
                            }
                        }
                        Spacer()
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(ImageViewerRemote(imageURL: self.$url, viewerShown: self.$showImageViewer))
            }
            .navigationBarTitle("Post", displayMode: .inline)
            .toast(isPresenting: $showToast){
                AlertToast(type: .complete(Color.green), title: "Saved!")
            }
            .toast(isPresenting: $showLoadingToast){
                AlertToast(type: .loading, title: "Saving media...")
            }
            .alert(isPresented: $showFailToast) {
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
            }
            .task {
                await fetchCurrentPostLiked();
                await fetchCurrentPostVote();
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 30, trailing: 0))
            VStack{
                HStack() {
                    Spacer().frame(width: 10)
                    Button(action: {
                        Task.init {
                            favorited = favorited ? await unFavoritePost(postId: post.id) : await favoritePost(postId: post.id);
                        }
                    }) {
                        Image(systemName: favorited ? "heart.fill" : "heart")
                            .font(.title)
                            .foregroundColor(.red)
                            .padding(buttonSpacing)
                    }
                    Button(action: {
                        Task.init {
                            our_score = await votePost(postId: post.id, value: 1, no_unvote: false);
                        }
                    }) {
                        Image(systemName: our_score == 1 ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                            .font(.title)
                            .foregroundColor(.green)
                            .padding(buttonSpacing)
                    }.disabled(!score_valid)
                    Button(action: {
                        Task.init {
                            our_score = await votePost(postId: post.id, value: -1, no_unvote: false);
                        }
                    }) {
                        Image(systemName: our_score == -1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                            .font(.title)
                            .foregroundColor(.orange)
                            .padding(buttonSpacing)
                    }.disabled(!score_valid)
                    Spacer()
                    Button(action: {
                        Task.init {
                            saveFile()
                        }
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title)
                            .padding(buttonSpacing)
                    }
                    ShareLink(item: URL(string: "https://\(source)/posts/\(post.id)")!) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title)
                            .padding(buttonSpacing)
                    }
                    Spacer().frame(width: 10)
                }
                .background(.ultraThinMaterial)
                .onAppear() {
                    favorited = post.is_favorited
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 30)
        }
    }
    func fetchParentPostData(postID: Int) async {
        do {
            let url = "https://\(source)/posts/\(postID).json"
            let data = await makeRequest(url: url, method: "GET", body: nil, contentType: "application/json");
            if (data) == nil { return; }
            let parsedData = try JSONDecoder().decode(Post.self, from: data!)
            parentPost = parsedData.post;
        } catch {
            print(error);
        }
    }
    
    func fetchCurrentPostLiked() async {
        do {
            let url = "https://\(source)/posts/\(post.id).json"
            let data = await makeRequest(url: url, method: "GET", body: nil, contentType: "application/json");
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
    
    func writeToPhotoAlbum(image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, nil, nil)
    }
    
    func downloadVideoLinkAndCreateAsset(_ videoLink: String) {

            // use guard to make sure you have a valid url
            guard let videoURL = URL(string: videoLink) else { return }

            guard let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

            // check if the file already exist at the destination folder if you don't want to download it twice
            if !FileManager.default.fileExists(atPath: documentsDirectoryURL.appendingPathComponent(videoURL.lastPathComponent).path) {

                // set up your download task
                URLSession.shared.downloadTask(with: videoURL) { (location, response, error) -> Void in

                    // use guard to unwrap your optional url
                    guard let location = location else { return }

                    // create a deatination url with the server response suggested file name
                    let destinationURL = documentsDirectoryURL.appendingPathComponent(response?.suggestedFilename ?? videoURL.lastPathComponent)

                    do {

                        try FileManager.default.moveItem(at: location, to: destinationURL)

                        PHPhotoLibrary.requestAuthorization({ (authorizationStatus: PHAuthorizationStatus) -> Void in

                            // check if user authorized access photos for your app
                            if authorizationStatus == .authorized {
                                PHPhotoLibrary.shared().performChanges({
                                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: destinationURL)}) { completed, error in
                                        if completed {
                                            print("Video asset created")
                                            showLoadingToast.toggle()
                                            showToast.toggle()
                                        } else {
                                            print(error as Any)
                                            showLoadingToast.toggle()
                                            showToast.toggle()
                                        }
                                }
                            }
                        })

                    } catch { print(error) }

                }.resume()

            } else {
                print("File already exists at destination url")
            }

        }
    
    func saveFile() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            authorizationStatus = status
            if status == .denied {
                showFailToast.toggle()
            }
        }
        if (authorizationStatus != .authorized) {
            return
        }
        if (String(post.file.ext) == "gif") {
            showLoadingToast.toggle()
            var image: UIImage?
            let urlString = post.file.url
            
            let url = URL(string: urlString!)
            
            DispatchQueue.global().async {
                let data = try? Data(contentsOf: url!) //make sure your image in this url does exist, otherwise unwrap in a if let check / try-catch
                DispatchQueue.main.async {
                    image = UIImage(data: data!)
                    if(image != nil) {
                        writeToPhotoAlbum(image: image!)
                        showLoadingToast.toggle()
                        showToast.toggle()
                    }
                }
            }
        }
        else if (String(post.file.ext) == "webm") {
            showLoadingToast.toggle()
            let urlString = post.sample.alternates.original!.urls.last!!
            // This takes too long, yeet it to the other thread
            Task.init {
                downloadVideoLinkAndCreateAsset(urlString);
            }
        }
        else if (!["gif", "webm", "mp4"].contains(String(post.file.ext))) {
            showLoadingToast.toggle()
            var image: UIImage?
            let urlString = post.file.url
            
            let url = URL(string: urlString!)
            
            DispatchQueue.global().async {
                let data = try? Data(contentsOf: url!) //make sure your image in this url does exist, otherwise unwrap in a if let check / try-catch
                DispatchQueue.main.async {
                    image = UIImage(data: data!)
                    if(image != nil) {
                        writeToPhotoAlbum(image: image!)
                        showLoadingToast.toggle()
                        showToast.toggle()
                    }
                }
            }
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

struct ImageView: View {
    
    @State var post: PostContent;
    @State private var ENABLE_AIRPLAY = defaults.bool(forKey: "ENABLE_AIRPLAY");
    var isFullScreen: Bool = false
    @State private var imageData: Data? = nil
    @State private var mute: Bool = false
    @State private var play: Bool = true
    
    var body: some View {
        if(post.preview.url == nil) {
            Text("😣")
        }
        else if(String(post.file.ext) == "gif") {
            if(post.file.url != nil) {
                if let data = imageData {
                    GIFImage(data: data)
                        .scaledToFit()
                }
                else {
                    ProgressView()
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .onAppear(perform: loadGif)
                }
            }
        }
        else if(String(post.file.ext) == "webm") {
            if(post.sample.alternates.original != nil) {
                let player = prepVideoPlayer(post: post);
                VideoPlayer(player: player)
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        else if(!["gif", "webm", "mp4"].contains(String(post.file.ext))) {
            if(post.file.url != nil) {
                AsyncImage(url: URL(string: post.file.url!)) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(minWidth: 0, maxWidth: .infinity)
                } placeholder: {
                    ZStack {
                        AsyncImage(url: URL(string: post.preview.url!)).opacity(0.25)
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
            }
            
        }
        else {
            Text("😣")
        }
    }
    
    func loadGif() {
        let task = URLSession.shared.dataTask(with: URL(string: post.file.url!)!) { data, response, error in
            imageData = data
        }
        task.resume()
    }
    
    func prepVideoPlayer(post: PostContent) -> AVPlayer {
        let url = URL(string: post.sample.alternates.original!.urls.last!!)!
        var player = AVPlayer(url: url);
        player.allowsExternalPlayback = ENABLE_AIRPLAY;
        return player
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
