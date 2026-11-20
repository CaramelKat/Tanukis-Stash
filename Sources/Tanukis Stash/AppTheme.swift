//
//  AppTheme.swift
//  Tanuki's Stash
//
//  App-wide appearance themes: Light, Dark (the default) and Christmas.
//

import SwiftUI

/// App-wide color themes. The choice is stored in UserDefaults under
/// "APP_THEME"; Dark is the default, matching the app's previous look.
enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case christmas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:     return "Light"
        case .dark:      return "Dark"
        case .christmas: return "Christmas"
        }
    }

    var subtitle: String {
        switch self {
        case .light:     return "Bright and clean"
        case .dark:      return "Easy on the eyes — the default"
        case .christmas: return "Festive red, green and snowfall"
        }
    }

    var symbol: String {
        switch self {
        case .light:     return "sun.max.fill"
        case .dark:      return "moon.stars.fill"
        case .christmas: return "snowflake"
        }
    }

    /// The interface style each theme forces. Christmas builds on the dark
    /// scheme with festive accents.
    var colorScheme: ColorScheme {
        switch self {
        case .light:            return .light
        case .dark, .christmas: return .dark
        }
    }

    /// Tint used for buttons, links, toggles and other controls.
    var accent: Color {
        switch self {
        case .light, .dark: return .blue
        case .christmas:    return Color(red: 0.87, green: 0.16, blue: 0.20)
        }
    }

    /// Backdrop drawn behind the app's content. Only Christmas overrides the
    /// system background; Light and Dark keep their native ones.
    @ViewBuilder
    var backgroundView: some View {
        switch self {
        case .light, .dark:
            Color.clear
        case .christmas:
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.13, blue: 0.09),
                    Color(red: 0.015, green: 0.035, blue: 0.025)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Gradient swatch shown next to the theme's name in Settings.
    var swatch: LinearGradient {
        switch self {
        case .light:
            return LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.00),
                    Color(red: 0.72, green: 0.83, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.25, blue: 0.31),
                    Color(red: 0.04, green: 0.04, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .christmas:
            return LinearGradient(
                colors: [
                    Color(red: 0.86, green: 0.13, blue: 0.18),
                    Color(red: 0.06, green: 0.42, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Symbol color drawn on top of the swatch.
    var swatchSymbolColor: Color {
        switch self {
        case .light:            return Color(red: 0.95, green: 0.62, blue: 0.10)
        case .dark, .christmas: return .white
        }
    }

    var showsSnow: Bool { self == .christmas }
}
