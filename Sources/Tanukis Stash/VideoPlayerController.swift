import SwiftUI
import AVKit
 
struct VideoPlayerController: UIViewControllerRepresentable {
    @State private var ENABLE_AIRPLAY = UserDefaults.standard.bool(forKey: "ENABLE_AIRPLAY");
    var videoURL: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: videoURL)
        player.allowsExternalPlayback = ENABLE_AIRPLAY
        let playerViewController = AVPlayerViewController()

        playerViewController.player = player
 
        return playerViewController
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        
    }    
}
 