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

struct PostView: View {
    @State var showImageViewer: Bool = false;
    @State var post: PostContent;
    @State var url: String = "";
    
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
                                Text(tag)
                                    .font(.body)
                                    .foregroundColor(Color.yellow)
                            }
                            
                            Text("Character")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.character, id: \.self) { tag in
                                Text(tag)
                                    .font(.body)
                                    .foregroundColor(Color.green)
                            }
                            
                            Text("Copyright")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.copyright, id: \.self) { tag in
                                Text(tag)
                                    .font(.body)
                                    .foregroundColor(Color.purple)
                            }
                            
                            Text("Species")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.species, id: \.self) { tag in
                                Text(tag)
                                    .font(.body)
                                    .foregroundColor(Color.red)
                            }
                            
                            Text("General")
                                .font(.title3)
                                .fontWeight(.heavy)
                            ForEach(post.tags.general, id: \.self) { tag in
                                Text(tag)
                                    .font(.body)
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
}
