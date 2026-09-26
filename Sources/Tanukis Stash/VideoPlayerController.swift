import SwiftUI
import AVKit

struct VideoPlayerController: View {
    var videoURL: URL
    var isActive: Bool = true
    @StateObject private var holder = PlayerHolder()
    @State private var showFullscreenPlayer = false

    var body: some View {
        InlinePlayerViewRepresentable(
            player: holder.player,
            videoURL: videoURL,
            isActive: isActive,
            onFullscreen: { showFullscreenPlayer = true }
        )
        .fullScreenCover(isPresented: $showFullscreenPlayer) {
            FullscreenVideoPlayer(player: holder.player)
                .ignoresSafeArea()
                .background(Color.black)
                .overlay(alignment: .topLeading) {
                    Button(action: {
                        showFullscreenPlayer = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(12)
                }
        }
        .onChange(of: showFullscreenPlayer) { _, dismissed in
            if (!dismissed) {
                holder.player.pause()
            }
        }
    }
}

final class PlayerHolder: ObservableObject {
    let player = AVPlayer()
}

struct FullscreenVideoPlayer: UIViewControllerRepresentable {
    var player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerViewController = AVPlayerViewController()
        playerViewController.showsPlaybackControls = true
        playerViewController.player = player
        player.play()
        return playerViewController
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if (uiViewController.player !== player) {
            uiViewController.player = player
            uiViewController.player?.play()
        }
    }
}

struct InlinePlayerViewRepresentable: UIViewRepresentable {
    var player: AVPlayer
    var videoURL: URL
    var isActive: Bool
    var onFullscreen: () -> Void

    func makeUIView(context: Context) -> InlinePlayerView {
        let view = InlinePlayerView(player: player)
        view.videoURL = videoURL
        view.onFullscreen = onFullscreen
        return view
    }

    func updateUIView(_ uiView: InlinePlayerView, context: Context) {
        if (uiView.videoURL != videoURL) {
            uiView.videoURL = videoURL
        }
        uiView.onFullscreen = onFullscreen
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
    private var displayLink: CADisplayLink?
    private var hideTimer: Timer?
    private var loadedURL: URL?
    private var lastPlaying: Bool = false
    private var isShuttingDown = false

    var videoURL: URL? {
        didSet { load() }
    }
    var onFullscreen: (() -> Void)?

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

    deinit {
        shutdown()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func setActive(_ active: Bool) {
        if (!active && player.timeControlStatus == .playing) {
            player.pause()
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
        player.replaceCurrentItem(with: nil)
    }

    private func load() {
        guard let url = videoURL, loadedURL != url, !isShuttingDown else { return }
        loadedURL = url
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
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
        NSLayoutConstraint.activate([
            controlsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlsView.heightAnchor.constraint(equalToConstant: 56)
        ])

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor)
        ])

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
        } else {
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

    @objc private func toggleMute() {
        player.isMuted.toggle()
        setSymbol(on: btnMute, player.isMuted ? "speaker.slash.fill" : "speaker.fill", pointSize: 22)
        restartHideTimer()
    }

    @objc private func openFullscreen() {
        player.pause()
        updatePlayState()
        hideControls()
        onFullscreen?()
    }

    @objc private func playbackEnded() {
        lastPlaying = false
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