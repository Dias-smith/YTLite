import Foundation
import WidgetKit

/// Writes Now Playing into the App Group for the iPhone Home Screen / Lock Screen widget.
enum PhoneWidgetSnapshotBridge {
    static func publish(
        videoId: String?,
        title: String?,
        artist: String?,
        thumbnailURL: URL?,
        isPlaying: Bool
    ) {
        let widgetSnapshot: PhoneWidgetPlaybackSnapshot = {
            guard let videoId, !videoId.isEmpty else { return .empty }
            return PhoneWidgetPlaybackSnapshot(
                videoId: videoId,
                title: title?.isEmpty == false ? (title ?? "Mixtube") : "Mixtube",
                artist: artist ?? "",
                thumbnailURL: thumbnailURL?.absoluteString,
                isPlaying: isPlaying,
                updatedAt: Date().timeIntervalSince1970
            )
        }()
        PhoneWidgetPlaybackSnapshotStore.save(widgetSnapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: PhoneWidgetShared.widgetKind)
    }
}

/// Consumes pending commands written by iPhone Widget App Intents.
@MainActor
final class PhoneWidgetCommandBridge {
    static let shared = PhoneWidgetCommandBridge()

    private weak var playback: PlaybackController?
    private var darwinObserverInstalled = false

    private init() {}

    func start(playback: PlaybackController) {
        self.playback = playback
        installDarwinObserverIfNeeded()
        consumePending()
    }

    func consumePending() {
        guard let command = PhoneWidgetCommandQueue.consume() else { return }
        guard let playback else { return }
        switch command {
        case .togglePlayPause:
            playback.togglePlayPause()
        case .next:
            playback.playNext()
        case .previous:
            playback.playPrevious()
        }
        playback.publishPhoneWidgetSnapshot()
    }

    private func installDarwinObserverIfNeeded() {
        guard !darwinObserverInstalled else { return }
        darwinObserverInstalled = true
        let name = PhoneWidgetShared.darwinNotifyName
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let bridge = Unmanaged<PhoneWidgetCommandBridge>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    bridge.consumePending()
                }
            },
            name,
            nil,
            .deliverImmediately
        )
    }
}
