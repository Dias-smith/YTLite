import Foundation
import UIKit
import WidgetKit

/// Writes Now Playing into the App Group for the iPhone Home Screen / Lock Screen widget.
enum PhoneWidgetSnapshotBridge {
    private static var pendingReload: DispatchWorkItem?
    private static let reloadLock = NSLock()

    static func publish(
        videoId: String?,
        title: String?,
        artist: String?,
        thumbnailURL: URL?,
        artwork: UIImage?,
        isPlaying: Bool,
        reloadImmediately: Bool = false
    ) {
        let widgetSnapshot: PhoneWidgetPlaybackSnapshot = {
            guard let videoId, !videoId.isEmpty else {
                return .empty
            }
            let revision = resolveArtworkRevision(videoId: videoId, artwork: artwork)
            return PhoneWidgetPlaybackSnapshot(
                videoId: videoId,
                title: title?.isEmpty == false ? (title ?? "Mixtube") : "Mixtube",
                artist: artist ?? "",
                thumbnailURL: thumbnailURL?.absoluteString,
                isPlaying: isPlaying,
                updatedAt: Date().timeIntervalSince1970,
                artworkRevision: revision
            )
        }()
        PhoneWidgetPlaybackSnapshotStore.save(widgetSnapshot)
        if reloadImmediately {
            reloadTimelinesNow()
        } else {
            scheduleTimelineReload()
        }
    }

    /// Prefer freshly written cover bytes; otherwise reuse an on-disk cover for this videoId
    /// so title/cover stay paired while a network fetch is still in flight.
    private static func resolveArtworkRevision(videoId: String, artwork: UIImage?) -> Int {
        if let artwork, PhoneWidgetArtworkStore.save(artwork, videoId: videoId) {
            return artworkStamp()
        }
        guard PhoneWidgetArtworkStore.hasFile(videoId: videoId) else { return 0 }
        let prior = PhoneWidgetPlaybackSnapshotStore.load()
        if prior.videoId == videoId, prior.artworkRevision > 0 {
            return prior.artworkRevision
        }
        return artworkStamp()
    }

    private static func artworkStamp() -> Int {
        max(1, Int(Date().timeIntervalSince1970 * 1000) % Int.max)
    }

    /// Coalesce rapid title → cover publishes into one WidgetKit reload.
    private static func scheduleTimelineReload() {
        reloadLock.lock()
        pendingReload?.cancel()
        let work = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: PhoneWidgetShared.widgetKind)
        }
        pendingReload = work
        reloadLock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private static func reloadTimelinesNow() {
        reloadLock.lock()
        pendingReload?.cancel()
        pendingReload = nil
        reloadLock.unlock()
        DispatchQueue.main.async {
            WidgetCenter.shared.reloadTimelines(ofKind: PhoneWidgetShared.widgetKind)
        }
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
        PhoneWidgetIntentDispatcher.handler = { [weak self] command in
            self?.apply(command)
        }
        installDarwinObserverIfNeeded()
        consumePending()
    }

    func consumePending() {
        guard let command = PhoneWidgetCommandQueue.consume() else { return }
        apply(command)
    }

    private func apply(_ command: PhoneWidgetCommand) {
        guard let playback else {
            // Not bound yet — stash for the next start/active cycle.
            PhoneWidgetCommandQueue.enqueue(command)
            return
        }
        switch command {
        case .togglePlayPause:
            // May call `playCurrentQueueItem()` without flipping `isPlaying` immediately;
            // surface sync + a short follow-up cover both the instant and settled states.
            playback.togglePlayPause()
            playback.publishNowPlaying()
            playback.publishPhoneWidgetSnapshot(force: true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                playback.publishPhoneWidgetSnapshot(force: true)
            }
        case .next:
            playback.playNext()
            playback.publishNowPlaying()
            playback.publishPhoneWidgetSnapshot(force: true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                playback.publishPhoneWidgetSnapshot(force: true)
            }
        case .previous:
            playback.playPrevious()
            playback.publishNowPlaying()
            playback.publishPhoneWidgetSnapshot(force: true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                playback.publishPhoneWidgetSnapshot(force: true)
            }
        }
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
