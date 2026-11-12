import SwiftUI
import AVKit

struct VideoPlayerController: View {
    var videoURL: URL
    var isActive: Bool = true
    var isFullScreen: Bool = false
    /// Fired when the user taps the player's "go fullscreen" button. On the
    /// post page this opens the shared fullscreen media viewer (the same one
    /// images use). Inside that viewer the button is hidden, so nil is fine.
    var onRequestFullscreen: (() -> Void)? = nil
    /// Called when the video plays through to its end (slideshow support).
    var onVideoEnded: (() -> Void)? = nil
    @StateObject private var holder = PlayerHolder()

    var body: some View {
        InlinePlayerViewRepresentable(
            player: holder.player,
            videoURL: videoURL,
            isActive: isActive,
            isFullscreen: isFullScreen,
            autoPlayWhenActive: isFullScreen && UserDefaults.standard.bool(forKey: "VIDEO_AUTOPLAY"),
            onFullscreen: { onRequestFullscreen?() },
            onVideoEnded: onVideoEnded
        )
    }
}

final class PlayerHolder: ObservableObject {
    let player = AVPlayer()
}

/// Remembers where a video was last playing so another copy of the player
/// (e.g. the fullscreen viewer's) can resume from the same position.
/// Keyed by the video file URL.
@MainActor
enum VideoPlaybackRegistry {
    private static var times: [String: Double] = [:]

    static func record(url: URL?, time: Double) {
        guard let url else { return }
        times[url.absoluteString] = time
    }

    static func consume(url: URL?) -> Double? {
        guard let url else { return nil }
        return times.removeValue(forKey: url.absoluteString)
    }
}

struct InlinePlayerViewRepresentable: UIViewRepresentable {
    var player: AVPlayer
    var videoURL: URL
    var isActive: Bool
    var isFullscreen: Bool = false
    var autoPlayWhenActive: Bool = false
    var onFullscreen: () -> Void
    var onVideoEnded: (() -> Void)? = nil

    func makeUIView(context: Context) -> InlinePlayerView {
        let view = InlinePlayerView(player: player)
        view.videoURL = videoURL
        view.onFullscreen = onFullscreen
        view.onVideoEnded = onVideoEnded
        view.autoPlayWhenActive = autoPlayWhenActive
        view.setFullscreen(isFullscreen)
        return view
    }

    func updateUIView(_ uiView: InlinePlayerView, context: Context) {
        if (uiView.videoURL != videoURL) {
            uiView.videoURL = videoURL
        }
        uiView.onFullscreen = onFullscreen
        uiView.onVideoEnded = onVideoEnded
        uiView.autoPlayWhenActive = autoPlayWhenActive
        uiView.setFullscreen(isFullscreen)
        uiView.setActive(isActive)
    }

    static func dismantleUIView(_ uiView: InlinePlayerView, coordinator: ()) {
        uiView.shutdown()
    }
}

final class InlinePlayerView: UIView {
    private let player: AVPlayer
    private let playerLayer = AVPlayerLayer()
    private let centerPlayButton = UIButton(type: .system)
    private let controlsView = UIView()
    private let btnPlay = UIButton(type: .system)
    private let btnBack = UIButton(type: .system)
    private let btnFwd = UIButton(type: .system)
    private let btnMute = UIButton(type: .system)
    private let btnFull = UIButton(type: .system)
    private let timeLabel = UILabel()
    // Fullscreen-only scrubber row: elapsed, slider, duration.
    private let sliderRow = UIStackView()
    private let progressSlider = UISlider()
    private let elapsedLabel = UILabel()
    private let durationLabel = UILabel()
    private var controlsHeightConstraint: NSLayoutConstraint!
    private var displayLink: CADisplayLink?
    private var hideTimer: Timer?
    private var loadedURL: URL?
    private var lastPlaying: Bool = false
    private var isShuttingDown = false

    var videoURL: URL? {
        didSet { load() }
    }
    var onFullscreen: (() -> Void)?
    /// Invoked when playback reaches the end of the item (slideshow support).
    var onVideoEnded: (() -> Void)?
    /// When true (fullscreen media viewer), playback starts automatically as
    /// soon as the page becomes active.
    var autoPlayWhenActive = false
    private var isFullscreenState = false
    /// Set when the user explicitly pauses, so SwiftUI re-renders (which call
    /// setActive) do not override the pause with autoplay.
    private var userPaused = false

    init(player: AVPlayer) {
        self.player = player
        super.init(frame: .zero)
        backgroundColor = .black
        player.automaticallyWaitsToMinimizeStalling = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.player = player
        layer.addSublayer(playerLayer)
        setupCenterPlayButton()
        setupControls()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        addGestureRecognizer(tap)

        addTickTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackEnded),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    /// Hides the "go fullscreen" button when the player is already fullscreen,
    /// and swaps the compact time label for a full scrubber row.
    func setFullscreen(_ fullscreen: Bool) {
        guard isFullscreenState != fullscreen else { return }
        isFullscreenState = fullscreen
        btnFull.isHidden = fullscreen
        sliderRow.isHidden = !fullscreen
        timeLabel.isHidden = fullscreen
        controlsHeightConstraint.constant = fullscreen ? 92 : 56
    }

    func setActive(_ active: Bool) {
        if (!active) {
            if (player.timeControlStatus == .playing) {
                player.pause()
                updatePlayState()
            }
        } else if (autoPlayWhenActive && !userPaused && loadedURL != nil && player.timeControlStatus != .playing) {
            // Restart from the beginning if this item already finished.
            if let duration = player.currentItem?.duration, duration.seconds.isFinite,
               player.currentTime() >= duration {
                player.seek(to: .zero)
            }
            player.play()
            updatePlayState()
        }
    }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        displayLink?.invalidate()
        displayLink = nil
        hideTimer?.invalidate()
        hideTimer = nil
        NotificationCenter.default.removeObserver(self)
        player.pause()
        recordPlaybackPosition()
        player.replaceCurrentItem(with: nil)
    }

    private func load() {
        guard let url = videoURL, loadedURL != url, !isShuttingDown else { return }
        loadedURL = url
        userPaused = false
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = UserDefaults.standard.bool(forKey: "VIDEO_MUTED_DEFAULT")
        setSymbol(on: btnMute, player.isMuted ? "speaker.slash.fill" : "speaker.fill", pointSize: 22)
        // Resume where this video was last playing (e.g. the inline player's
        // position when the user opened the fullscreen viewer).
        if let start = VideoPlaybackRegistry.consume(url: url), start > 0 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        updatePlayState()
        updateTimeLabel()
    }

    // MARK: - Layout

    private func setupCenterPlayButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 72, weight: .regular)
        centerPlayButton.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: config), for: .normal)
        centerPlayButton.tintColor = UIColor.white.withAlphaComponent(0.85)
        centerPlayButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(centerPlayButton)
        NSLayoutConstraint.activate([
            centerPlayButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerPlayButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerPlayButton.widthAnchor.constraint(equalToConstant: 84),
            centerPlayButton.heightAnchor.constraint(equalToConstant: 84)
        ])
        centerPlayButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        centerPlayButton.isHidden = true
    }

    private func setupControls() {
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        controlsView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        addSubview(controlsView)
        controlsHeightConstraint = controlsView.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([
            controlsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlsHeightConstraint
        ])

        // Rows container: the scrubber row (fullscreen only) above the
        // button row.
        let rows = UIStackView()
        rows.axis = .vertical
        rows.alignment = .fill
        rows.distribution = .fill
        rows.spacing = 2
        rows.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 12),
            rows.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -12),
            rows.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 4),
            rows.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: -4)
        ])

        // Scrubber row (hidden unless fullscreen).
        sliderRow.axis = .horizontal
        sliderRow.alignment = .center
        sliderRow.distribution = .fill
        sliderRow.spacing = 10
        sliderRow.isHidden = true
        rows.addArrangedSubview(sliderRow)

        elapsedLabel.textColor = .white
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        elapsedLabel.text = "0:00"
        elapsedLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.textColor = .white
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        durationLabel.text = "0:00"
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        progressSlider.minimumTrackTintColor = .white
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.35)
        progressSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        sliderRow.addArrangedSubview(elapsedLabel)
        sliderRow.addArrangedSubview(progressSlider)
        sliderRow.addArrangedSubview(durationLabel)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        rows.addArrangedSubview(stack)

        timeLabel.textColor = .white
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeLabel.text = "0:00/0:00"
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        configure(btnBack, symbol: "gobackward.10")
        configure(btnPlay, symbol: "play.fill", isPlay: true)
        configure(btnFwd, symbol: "goforward.10")
        configure(btnMute, symbol: "speaker.fill")
        configure(btnFull, symbol: "arrow.up.left.and.arrow.down.right")

        stack.addArrangedSubview(timeLabel)
        stack.addArrangedSubview(btnBack)
        stack.addArrangedSubview(btnPlay)
        stack.addArrangedSubview(btnFwd)
        stack.addArrangedSubview(btnMute)
        stack.addArrangedSubview(btnFull)

        btnBack.addTarget(self, action: #selector(seekBack), for: .touchUpInside)
        btnPlay.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        btnFwd.addTarget(self, action: #selector(seekFwd), for: .touchUpInside)
        btnMute.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)
        btnFull.addTarget(self, action: #selector(openFullscreen), for: .touchUpInside)
    }

    private func configure(_ button: UIButton, symbol: String, isPlay: Bool = false) {
        let pointSize: CGFloat = isPlay ? 30 : 22
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func setSymbol(on button: UIButton, _ symbol: String, pointSize: CGFloat) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
    }

    // MARK: - Controls visibility

    private func showControls() {
        UIView.animate(withDuration: 0.2) {
            self.controlsView.alpha = 1
        }
        restartHideTimer()
    }

    private func hideControls() {
        hideTimer?.invalidate()
        hideTimer = nil
        UIView.animate(withDuration: 0.25) {
            self.controlsView.alpha = 0
        }
    }

    private func restartHideTimer() {
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: 4.0, target: self, selector: #selector(autoHideControls), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    @objc private func autoHideControls() {
        hideTimer = nil
        if (player.timeControlStatus == .playing) {
            UIView.animate(withDuration: 0.25) {
                self.controlsView.alpha = 0
            }
        }
    }

    @objc private func handleTap() {
        if (controlsView.alpha > 0.5) {
            hideControls()
        } else {
            showControls()
        }
    }

    // MARK: - Timers

    private func addTickTimer() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        updatePlayState()
        updateTimeLabel()
    }

    // MARK: - Playback state

    private func updatePlayState() {
        let isPlaying = player.timeControlStatus == .playing
        if (isPlaying != lastPlaying) {
            lastPlaying = isPlaying
            setSymbol(on: btnPlay, isPlaying ? "pause.fill" : "play.fill", pointSize: 30)
            UIView.animate(withDuration: 0.15) {
                self.centerPlayButton.alpha = isPlaying ? 0 : 1
            } completion: { _ in
                self.centerPlayButton.isHidden = isPlaying
            }
            if (isPlaying) {
                restartHideTimer()
            } else {
                showControls()
            }
        }
    }

    private func updateTimeLabel() {
        let time = player.currentTime()
        let duration = player.currentItem?.duration
        let total = (duration?.seconds.isFinite ?? false) ? duration!.seconds : 0
        let current = time.isNumeric ? time.seconds : 0
        timeLabel.text = "\(formatTime(current))/\(formatTime(total))"
        if (isFullscreenState) {
            elapsedLabel.text = formatTime(current)
            durationLabel.text = formatTime(total)
            if (total > 0) {
                progressSlider.maximumValue = Float(total)
                if (!progressSlider.isTracking) {
                    progressSlider.value = min(Float(current), Float(total))
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        if (seconds.isNaN || seconds.isInfinite || seconds < 0) { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if (h > 0) {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Actions

    @objc private func togglePlay() {
        if (player.timeControlStatus == .playing) {
            player.pause()
            userPaused = true
        } else {
            userPaused = false
            let item = player.currentItem
            if let duration = item?.duration, duration.seconds.isFinite {
                if (player.currentTime() >= duration) {
                    player.seek(to: .zero)
                }
            }
            player.play()
        }
        updatePlayState()
        restartHideTimer()
    }

    @objc private func seekBack() {
        seek(by: -10)
    }

    @objc private func seekFwd() {
        seek(by: 10)
    }

    private func seek(by seconds: Double) {
        let time = player.currentTime()
        guard time.isNumeric, let duration = player.currentItem?.duration, duration.seconds.isFinite else { return }
        let target = min(max(time.seconds + seconds, 0), duration.seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        updateTimeLabel()
        restartHideTimer()
    }

    @objc private func sliderChanged() {
        let target = Double(progressSlider.value)
        if let duration = player.currentItem?.duration, duration.seconds.isFinite, duration.seconds > 0 {
            player.seek(to: CMTime(seconds: min(max(target, 0), duration.seconds), preferredTimescale: 600))
        } else {
            player.seek(to: CMTime(seconds: max(target, 0), preferredTimescale: 600))
        }
        updateTimeLabel()
        restartHideTimer()
    }

    @objc private func toggleMute() {
        player.isMuted.toggle()
        setSymbol(on: btnMute, player.isMuted ? "speaker.slash.fill" : "speaker.fill", pointSize: 22)
        restartHideTimer()
    }

    @objc private func openFullscreen() {
        // The fullscreen button opens the shared fullscreen media viewer; stop
        // this inline player so audio does not double up with the fullscreen
        // copy. userPaused keeps later re-renders from restarting it.
        if (player.timeControlStatus == .playing) {
            player.pause()
            userPaused = true
            updatePlayState()
        }
        // Hand the current playback position to the fullscreen copy so it
        // continues from here.
        recordPlaybackPosition()
        hideControls()
        onFullscreen?()
    }

    /// Stores the current position for whichever player loads this video next.
    private func recordPlaybackPosition() {
        let time = player.currentTime().seconds
        guard time.isFinite, time > 0.5 else { return }
        if let duration = player.currentItem?.duration, duration.seconds.isFinite, time >= duration.seconds - 0.25 {
            return // at/near the end; nothing worth resuming
        }
        VideoPlaybackRegistry.record(url: loadedURL, time: time)
    }

    @objc private func playbackEnded() {
        // Tell the slideshow (if running) that this video finished; a looped
        // video still counts as finished for "wait for videos" mode.
        onVideoEnded?()
        if (UserDefaults.standard.bool(forKey: "VIDEO_LOOP") && !isShuttingDown) {
            // Videos loop by default: restart from the beginning.
            player.seek(to: .zero)
            player.play()
            return
        }
        lastPlaying = false
        userPaused = false
        setSymbol(on: btnPlay, "play.fill", pointSize: 30)
        UIView.animate(withDuration: 0.15) {
            self.centerPlayButton.alpha = 1
        } completion: { _ in
            self.centerPlayButton.isHidden = false
        }
        showControls()
        updateTimeLabel()
    }
}

extension InlinePlayerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if (controlsView.bounds.contains(touch.location(in: controlsView))) { return false }
        if (centerPlayButton.bounds.contains(touch.location(in: centerPlayButton))) { return false }
        return true
    }
}