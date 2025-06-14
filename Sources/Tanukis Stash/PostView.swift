//
//  PostView.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/4/22.
//

import SwiftUI
import AlertToast
import AttributedText

@MainActor 
struct PostView: View {
    @State private var showImageViewer: Bool = false;
    @State var post: PostContent;
    @State var search: String;
    @State var url: String = "";

    @State private var displayToastType = 0;

    private var tapGesture: some Gesture {
        !["webm", "mp4"].contains(String(post.file.ext)) ? (TapGesture().onEnded { showImageViewer = true }) : nil
    }
    
    var body: some View {
        GeometryReader {geometry in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical) {
                    VStack {
                        MediaView(post: post, geometry: geometry).gesture(tapGesture)
                            .frame(
                                width: geometry.size.width,
                                height: calculateImageHeight(geometry: geometry)
                            )
                            .padding(EdgeInsets(top: 0, leading: -10, bottom: 0, trailing: -10))
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationBarTitle("Post", displayMode: .inline)
                .sheet(isPresented: $showImageViewer, content: {
                                FullscreenImageViewer(post: post)
                            })
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 30, trailing: 0))
                ActionBar(post: post, search: search, displayToastType: $displayToastType)
                    .frame(maxWidth: .infinity, maxHeight: 30)
            }
            .toast(isPresenting: Binding<Bool>(get: { displayToastType != 0 }, set: { _ in })) {
                getToast()
            }
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
    }

    func calculateImageHeight(geometry: GeometryProxy) -> CGFloat {
        return CGFloat(CGFloat(post.file.height) * (CGFloat(geometry.size.width) / CGFloat(post.file.width)))
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
        default:
            clearToast()
            return AlertToast(type: .regular, title: "FUck")
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
    @Binding var displayToastType: Int

    var buttonSpacing = EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 5);
    
    var body: some View {
        VStack {
            HStack() {
                Spacer().frame(width: 15)
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
                        .foregroundColor(!score_valid ? .gray : .green)
                        .padding(buttonSpacing)
                }.disabled(!score_valid)
                Button(action: {
                    Task.init {
                        our_score = await votePost(postId: post.id, value: -1, no_unvote: false);
                    }
                }) {
                    Image(systemName: our_score == -1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                        .font(.title)
                        .foregroundColor(!score_valid ? .gray : .orange)
                        .padding(buttonSpacing)
                }.disabled(!score_valid)
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
            .background(.ultraThinMaterial)
            .onAppear() {
                favorited = post.is_favorited
            }
            .task {
                await fetchCurrentPostLiked();
                await fetchCurrentPostVote();
            }
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
