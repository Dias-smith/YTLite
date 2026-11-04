import Foundation
import WidgetKit

/// Writes Now Playing into the Watch App Group for WidgetKit complications / Smart Stack.
enum WatchWidgetSnapshotBridge {
    static func publish(from snapshot: WatchConnectivityProtocol.PlaybackSnapshot?) {
        let widgetSnapshot: WatchWidgetPlaybackSnapshot = {
            guard let snapshot, let videoId = snapshot.videoId, !videoId.isEmpty else {
                return .empty
            }
            return WatchWidgetPlaybackSnapshot(
                videoId: videoId,
                title: snapshot.title ?? "Mixtube",
                artist: snapshot.artist ?? "",
                isPlaying: snapshot.isPlaying,
                updatedAt: snapshot.updatedAt ?? Date().timeIntervalSince1970
            )
        }()
        WatchWidgetPlaybackSnapshotStore.save(widgetSnapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetShared.widgetKind)
    }
}

/// Consumes pending commands written by the Watch Widget App Intents.
@MainActor
final class WatchWidgetCommandBridge {
    static let shared = WatchWidgetCommandBridge()

    private weak var client: WatchPlaybackClient?
    private var timer: Timer?

    private init() {}

    func start(client: WatchPlaybackClient) {
        self.client = client
        consumePending()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.consumePending()
            }
        }
    }

    func consumePending() {
        guard let command = WatchWidgetCommandQueue.consume() else { return }
        guard let client else { return }
        switch command {
        case .togglePlayPause:
            client.togglePlayPause()
        case .next:
            client.playNext()
        case .openApp:
            client.syncWithPhone(bootstrap: true)
        }
    }
}
