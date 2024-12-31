//
//  FullscreenImageViewer.swift
//  Tanuki's Stash
//
//  Created by Max on 12/19/24.
//

import SwiftUI

public struct FullscreenImageViewer: View {
    @Environment(\.presentationMode)
    var presentationMode: Binding<PresentationMode>
    @State var post: PostContent
    
    public var body: some View {
        ZoomableContainer {
            ImageView(post: post, isFullScreen: true)
                .frame(minWidth: 0, maxWidth: .greatestFiniteMagnitude, minHeight: 0, maxHeight: .greatestFiniteMagnitude)
        }
        .navigationBarItems(trailing: Button("Dismiss", action: {
            self.presentationMode.wrappedValue.dismiss()
        }))
    }
}
