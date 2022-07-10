//
//  PostView.swift
//  Tanuki's Stash
//
//  Created by Jay Poffinbarger on 1/4/22.
//

import SwiftUI
import ImageViewerRemote
import SwiftUIGIF
import AVKit
import Photos

struct PostView: View {
    @State var showImageViewer: Bool = false;
    @State var showSettings = false
    @State var post: PostContent;
    @State var url: String = defaults.string(forKey: "api_source") ?? "e926.net";
    
    var body: some View {
            ScrollView(.vertical) {
                VStack {
                    ImageView(post: post);
                    Spacer();
                    /*Button(action: { showImageViewer = true }) {
                        
                    }*/
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
                    
                    Text(.init(post.description))
                    
                    Spacer()
                    
                    HStack {
                        VStack(alignment:.leading) {
                            Text("Artist")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.artist, id: \.self) { tag in
                                NavigationLink(destination: SearchView(search: String(tag))) {
                                    Text(tag)
                                        .font(.body)
                                        .foregroundColor(Color.yellow)
                                }
                            }
                            
                            Text("Character")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.character, id: \.self) { tag in
                                NavigationLink(destination: SearchView(search: String(tag))) {
                                    Text(tag)
                                        .font(.body)
                                        .foregroundColor(Color.green)
                                }
                            }
                            
                            Text("Copyright")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.copyright, id: \.self) { tag in
                                NavigationLink(destination: SearchView(search: String(tag))) {
                                    Text(tag)
                                        .font(.body)
                                        .foregroundColor(Color.purple)
                                }
                            }
                            
                            Text("Species")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.species, id: \.self) { tag in
                                NavigationLink(destination: SearchView(search: String(tag))) {
                                    Text(tag)
                                        .font(.body)
                                        .foregroundColor(Color.red)
                                }
                            }
                            
                            Text("General")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.general, id: \.self) { tag in
                                NavigationLink(destination: SearchView(search: String(tag))) {
                                    Text(tag)
                                        .font(.body)
                                        .foregroundColor(Color.white)
                                }
                            }
                        }
                        Spacer()
                        VStack(alignment:.trailing) {
                            Text("Post Details")
                                .font(.title3)
                                .fontWeight(.heavy)
                            
                            Text("Author")
                                .font(.headline)
                                .fontWeight(.heavy)
                            Text(String(post.uploader_id))
                                .font(.footnote)
                            
                            if(post.relationships.parent_id != nil) {
                                Text("Parent")
                                    .font(.headline)
                                    .fontWeight(.heavy)
                                Text(String(post.relationships.parent_id!))
                                    .font(.footnote)
                            }
                            
                            if(post.relationships.has_active_children) {
                                Text("Children")
                                    .font(.headline)
                                    .fontWeight(.heavy)
                                ForEach(post.relationships.children, id: \.self) { child in
                                    Text(String(child))
                                        .font(.footnote)
                                }
                            }
                            
                            Text("Sources")
                                .font(.headline)
                                .fontWeight(.heavy)
                            ForEach(post.sources, id: \.self) { tag in
                                Text(.init(tag))
                                    .font(.footnote)
                            }
                            Spacer()
                        }
                    }
                    Spacer()
                    Spacer()
                }
                .padding(10)
            }
            .navigationBarTitle("Post", displayMode: .inline)
            .overlay(ImageViewerRemote(imageURL: self.$url, viewerShown: self.$showImageViewer))
    }
}


struct ImageView: View {
    
    @State var post: PostContent;
    @State private var imageData: Data? = nil
    @State private var mute: Bool = false
    @State private var play: Bool = true
    
    var body: some View {
        if(post.preview.url == nil) {
            Text("😣")
        }
        else if(String(post.file.ext) == "gif" ) {
            if(post.file.url != nil) {
                if let data = imageData {
                    GIFImage(data: data)
                        .scaledToFill()
                    Spacer()
                    Button("Save Image") {
                        var image: UIImage?
                        let urlString = post.file.url
                        
                        let url = NSURL(string: urlString!)! as URL
                        if let imageData: NSData = NSData(contentsOf: url) {
                            image = UIImage(data: imageData as Data)
                            if(image != nil) {
                                writeToPhotoAlbum(image: image!)
                            }
                        }
                    }
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
                VideoPlayer(player: AVPlayer(url: URL(string: post.sample.alternates.original!.urls.last!!)!))
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity)
                Spacer()
                Button("Save Video") {
                    let urlString = post.sample.alternates.original!.urls.last!!
                    print(urlString)
                    downloadVideoLinkAndCreateAsset(urlString);
                }
            }
        }
        else if(String(post.file.ext) != "gif" || String(post.file.ext) != "webm" || String(post.file.ext) != "mp4") {
            if(post.file.url != nil) {
                AsyncImage(url: URL(string: post.file.url!)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity)
                } placeholder: {
                    ZStack {
                        AsyncImage(url: URL(string: post.preview.url!)).opacity(0.25)
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
                Spacer()
                Button("Save Image") {
                    var image: UIImage?
                    let urlString = post.file.url
                    
                    let url = NSURL(string: urlString!)! as URL
                    if let imageData: NSData = NSData(contentsOf: url) {
                        image = UIImage(data: imageData as Data)
                        if(image != nil) {
                            writeToPhotoAlbum(image: image!)
                        }
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
                                        } else {
                                            print(error)
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
}
