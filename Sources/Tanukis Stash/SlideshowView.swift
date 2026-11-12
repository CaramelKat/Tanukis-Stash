//
//  SlideshowView.swift
//  Tanuki's Stash
//
//  Slideshow settings sheet and plumbing. Types and defaults keys were
//  recovered from the 0.4.6 IPA (SlideshowOptionsView / SlideshowVideoMode,
//  "SLIDESHOW_INTERVAL" / "SLIDESHOW_VIDEO_MODE").
//

import SwiftUI

/// How the slideshow treats video posts. Raw values and descriptions were
/// recovered from the 0.4.6 binary.
enum SlideshowVideoMode: String, CaseIterable, Identifiable {
    case interval
    case playThrough
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interval:    return "Use the same interval"
        case .playThrough: return "Wait for videos"
        case .skip:        return "Skip videos"
        }
    }

    var subtitle: String {
        switch self {
        case .interval:
            return "Videos get the same time on screen as images."
        case .playThrough:
            return "The slideshow waits until the video finishes."
        case .skip:
            return "The slideshow jumps straight past video posts."
        }
    }
}

/// Slideshow settings sheet. Nothing starts until the user presses the big
/// Start button pinned to the bottom of the sheet, so options and interval
/// are picked first.
struct SlideshowOptionsView: View {
    @AppStorage("SLIDESHOW_INTERVAL") private var interval: Double = 5
    @AppStorage("SLIDESHOW_VIDEO_MODE") private var videoMode: SlideshowVideoMode = .interval

    /// Ran when the user presses Start; the owner of the slideshow begins
    /// playing. The sheet dismisses itself afterwards. Dismissing the sheet
    /// any other way leaves the slideshow stopped.
    var onStart: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var intervalText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Slideshow")
                    .font(.title3.bold())
                Text("Pick your pace, then press Start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Interval.
            HStack(spacing: 10) {
                Text("Interval")
                Spacer()
                TextField("5", text: $intervalText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                Text("seconds")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            // How videos are handled.
            VStack(alignment: .leading, spacing: 8) {
                Text("Videos")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(Array(SlideshowVideoMode.allCases.enumerated()), id: \.element.id) { index, mode in
                        if (index > 0) {
                            Divider()
                                .padding(.leading, 16)
                        }
                        Button {
                            videoMode = mode
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title)
                                        .foregroundStyle(.primary)
                                    Text(mode.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                if (videoMode == mode) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                        .padding(.top, 1)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }

            Spacer(minLength: 0)

            // Wide Start button; the slideshow begins here, not when the
            // sheet opens.
            Button {
                // The decimal pad follows the locale, so accept a comma as
                // the decimal separator too.
                if let value = Double(intervalText.replacingOccurrences(of: ",", with: ".")), value > 0 {
                    interval = value
                }
                onStart?()
                dismiss()
            } label: {
                Text("Start")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground))
        // A single, content-sized detent: the sheet never scrolls and never
        // grows into a fullscreen menu.
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
        .onAppear {
            intervalText = String(format: "%g", interval)
        }
    }
}

/// One-shot wrapper around a checked continuation, used by PostView to wait
/// for the end of a video post (slideshow "wait for videos" mode). Safe to
/// resume more than once.
@MainActor
final class SlideshowVideoWaiter {
    private let continuation: CheckedContinuation<Void, Never>
    private var resumed = false

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        guard !resumed else { return }
        resumed = true
        continuation.resume()
    }
}
