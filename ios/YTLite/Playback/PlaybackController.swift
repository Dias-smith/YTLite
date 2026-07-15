import Foundation
import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var nowPlaying: NowPlayingItem?
    @Published private(set) var queue: [VideoItem] = []
    @Published private(set) var queueIndex: Int = 0
    @Published private(set) var isPlaying: Bool = false
    @Published var playbackSpeed: Float = 1.0 {
        didSet {
            applySpeed()
            UserDefaults.standard.set(playbackSpeed, forKey: Self.speedKey)
        }
    }
    @Published private(set) var positionSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    @Published private(set) var isBuffering: Bool = false
    @Published var lastError: String?
    @Published private(set) var isFavorite: Bool = false
    @Published private(set) var captionTracks: [CaptionTrack] = []

    static let speedOptions: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 5, 8]
    private static let speedKey = "playback_speed"

    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var extractTask: Task<Void, Never>?

    weak var libraryStore: LibraryStore?
    var onPlaybackStarted: ((NowPlayingItem) -> Void)?

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.speedKey) as? Float
        if let stored, Self.speedOptions.contains(stored) {
            playbackSpeed = stored
        }
        configureAudioSession()
        configureRemoteCommands()
    }

    func play(items: [VideoItem], startAt index: Int = 0) {
        guard !items.isEmpty else { return }
        queue = items
        queueIndex = index.clamped(to: 0...(items.count - 1))
        playCurrentQueueItem()
    }

    func playSearchItem(_ item: SearchVideoItem) {
        play(items: [item], startAt: 0)
    }

    func playNext() {
        guard queueIndex + 1 < queue.count else { return }
        queueIndex += 1
        playCurrentQueueItem()
    }

    func playPrevious() {
        if positionSeconds > 3 {
            seek(to: 0)
            return
        }
        guard queueIndex > 0 else { return }
        queueIndex -= 1
        playCurrentQueueItem()
    }

    func toggleFavorite() {
        guard let item = nowPlaying, let store = libraryStore else { return }
        store.toggleFavorite(
            item: VideoItem(
                videoId: item.videoId,
                title: item.title,
                channelName: item.channelName,
                thumbnailURL: item.thumbnailURL
            )
        )
        isFavorite = store.isFavorite(videoId: item.videoId)
    }

    func refreshFavoriteState() {
        guard let videoId = nowPlaying?.videoId else {
            isFavorite = false
            return
        }
        isFavorite = libraryStore?.isFavorite(videoId: videoId) ?? false
    }

    private func playCurrentQueueItem() {
        let item = queue[queueIndex]
        lastError = nil
        captionTracks = []
        nowPlaying = NowPlayingItem(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: item.thumbnailURL
        )
        refreshFavoriteState()
        isBuffering = true
        extractTask?.cancel()
        extractTask = Task {
            do {
                let playback = try await ExtractorBridge.shared.extractPlayback(videoId: item.videoId)
                guard !Task.isCancelled else { return }
                let playing = NowPlayingItem(
                    videoId: playback.videoId,
                    title: playback.title == playback.videoId ? item.title : playback.title,
                    channelName: playback.channelName.isEmpty ? item.channelName : playback.channelName,
                    thumbnailURL: playback.thumbnailURL ?? item.thumbnailURL
                )
                nowPlaying = playing
                captionTracks = playback.captionTracks
                guard let url = playback.preferredStreamURL(preferVideo: true) else {
                    throw ExtractorBridge.ExtractorError.invalidResponse("no playable url")
                }
                play(url: url)
                libraryStore?.recordPlayback(playing)
                onPlaybackStarted?(playing)
                refreshFavoriteState()
            } catch {
                guard !Task.isCancelled else { return }
                isBuffering = false
                isPlaying = false
                lastError = error.localizedDescription
            }
        }
    }

    func play(url: URL) {
        let avItem = AVPlayerItem(url: url)
        if let player {
            player.replaceCurrentItem(with: avItem)
        } else {
            player = AVPlayer(playerItem: avItem)
            attachTimeObserver()
            attachEndObserver()
        }
        isBuffering = false
        applySpeed()
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: playbackSpeed)
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func stop() {
        extractTask?.cancel()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        isBuffering = false
        nowPlaying = nil
        captionTracks = []
        queue = []
        queueIndex = 0
        positionSeconds = 0
        durationSeconds = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player?.seek(to: time)
    }

    private func applySpeed() {
        guard isPlaying else {
            player?.rate = 0
            return
        }
        player?.playImmediately(atRate: playbackSpeed)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {}
    }

    private func attachTimeObserver() {
        guard let player else { return }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.positionSeconds = time.seconds.isFinite ? time.seconds : 0
                if let duration = player.currentItem?.duration.seconds, duration.isFinite {
                    self.durationSeconds = duration
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func attachEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playNext()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == false { self?.togglePlayPause() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if self?.isPlaying == true { self?.togglePlayPause() }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let nowPlaying else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.channelName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: positionSeconds,
            MPMediaItemPropertyPlaybackDuration: durationSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0,
        ]
    }
}

struct NowPlayingItem: Identifiable, Equatable, Sendable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let channelName: String
    let thumbnailURL: URL?
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
