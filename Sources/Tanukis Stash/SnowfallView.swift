//
//  SnowfallView.swift
//  Tanuki's Stash
//
//  Subtle animated snowfall for the Christmas theme.
//

import SwiftUI
import Foundation

/// A lightweight, non-interactive snowfall overlay. Each flake's position is
/// derived from the timeline clock, so there is no per-flake animation state
/// and the whole overlay costs a handful of ellipse draws per frame.
struct SnowfallView: View {
    private struct Flake {
        var x: Double          // starting horizontal position, 0...1
        var y: Double          // starting vertical position, 0...1
        var size: Double       // diameter in points
        var speed: Double      // screens per second
        var sway: Double       // side-to-side amplitude in points
        var swaySpeed: Double  // sway cycles per second
        var phase: Double      // starting phase of the sway
        var opacity: Double

        static func random() -> Flake {
            Flake(
                x: .random(in: 0...1),
                y: .random(in: 0...1),
                size: .random(in: 1.6...4.2),
                speed: .random(in: 0.020...0.070),
                sway: .random(in: 8...26),
                swaySpeed: .random(in: 0.30...1.10),
                phase: .random(in: 0...(2 * Double.pi)),
                opacity: .random(in: 0.18...0.55)
            )
        }
    }

    private let flakes: [Flake] = (0..<48).map { _ in .random() }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                for flake in flakes {
                    // Wrapping the vertical position keeps the snow falling
                    // forever without resetting any state.
                    let progress = (flake.y + time * flake.speed)
                        .truncatingRemainder(dividingBy: 1)

                    let x = flake.x * size.width
                        + sin(time * flake.swaySpeed + flake.phase) * flake.sway
                    let y = progress * size.height

                    let rect = CGRect(
                        x: x - flake.size / 2,
                        y: y - flake.size / 2,
                        width: flake.size,
                        height: flake.size
                    )

                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(flake.opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
