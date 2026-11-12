//
//  TanukisStashApp.swift
//  Tanuki's Stash
//
//  Created by Jemma Poffinbarger on 1/3/22.
//

import SwiftUI

@main
struct TanukisStashApp: App {
    /// App-wide appearance theme (Light, Dark or Christmas).
    @AppStorage("APP_THEME") private var themeRaw: String = AppTheme.dark.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .dark
    }

    init() {
        // Defaults for settings read with UserDefaults.standard.bool (which
        // returns false for unset keys).
        UserDefaults.standard.register(defaults: [
            "VIDEO_AUTOPLAY": true,
            "VIDEO_LOOP": true,
            "VIDEO_MUTED_DEFAULT": false,
            "APP_THEME": AppTheme.dark.rawValue
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Theme backdrop (only Christmas paints one).
                .background {
                    theme.backgroundView
                        .ignoresSafeArea()
                }
                .tint(theme.accent)
                .preferredColorScheme(theme.colorScheme)
                // Gentle snowfall over the browsing UI during Christmas.
                // Sheets and the fullscreen viewer present above this, so
                // media viewing stays unobstructed.
                .overlay {
                    if theme.showsSnow {
                        SnowfallView()
                            .ignoresSafeArea()
                    }
                }
        }
    }
}
