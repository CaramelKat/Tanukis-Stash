//
//  AudioSession.swift
//  Tanuki's Stash
//
//  Keeps media audio playing even when the iPhone's ring/silent switch is on.
//

import AVFoundation

enum AudioSession {
    /// Uses the `.playback` category, which ignores the ring/silent switch
    /// (the default category would be silenced by it). The session itself is
    /// activated automatically by AVPlayer when a video starts, so simply
    /// opening the app does not interrupt other audio.
    static func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
}
