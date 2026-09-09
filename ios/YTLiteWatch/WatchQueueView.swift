import SwiftUI

/// Queue list: play index, remove, play next, move to end.
/// Disconnected: last mirror browsable read-only with open-phone CTA (mutations blocked).
struct WatchQueueView: View {
    @EnvironmentObject private var bridge: WatchConnectivityBridge
    @EnvironmentObject private var playback: WatchPlaybackClient

    private var canControl: Bool { bridge.isReachable }

    var body: some View {
        NavigationStack {
            Group {
                if let queue = playback.queue, !queue.items.isEmpty {
                    List {
                        Section {
                            if canControl {
                                EmptyView()
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(WL("watch.phone_required", "Open Mixtube on iPhone"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                    Text(WL("watch.queue_readonly_hint", "Connect iPhone to control the queue"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .listRowBackground(Color.clear)
                            }
                        }

                        ForEach(Array(queue.items.enumerated()), id: \.offset) { index, item in
                            queueRow(item, index: index, currentIndex: queue.currentIndex)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if canControl {
                                        Button(role: .destructive) {
                                            playback.removeFromQueue(videoIds: [item.videoId])
                                        } label: {
                                            Label(WL("watch.remove", "Remove"), systemImage: "trash")
                                        }
                                    }
                                }
                                .contextMenu {
                                    if canControl {
                                        Button {
                                            playback.playQueueIndex(index)
                                        } label: {
                                            Label(WL("watch.play", "Play"), systemImage: "play.fill")
                                        }
                                        Button {
                                            playback.playNextInQueue(videoId: item.videoId)
                                        } label: {
                                            Label(WL("watch.play_next", "Play next"), systemImage: "text.line.first.and.arrowtriangle.forward")
                                        }
                                        Button {
                                            playback.appendOrMoveToEnd(videoId: item.videoId)
                                        } label: {
                                            Label(WL("watch.add_to_end", "Add to end"), systemImage: "text.append")
                                        }
                                        Button(role: .destructive) {
                                            playback.removeFromQueue(videoIds: [item.videoId])
                                        } label: {
                                            Label(WL("watch.remove", "Remove"), systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label(
                            WL("watch.queue_empty", "Queue empty"),
                            systemImage: "list.bullet"
                        )
                    } description: {
                        Text(
                            canControl
                                ? WL("watch.queue_empty_hint", "Play something on iPhone")
                                : WL("watch.phone_required", "Open Mixtube on iPhone")
                        )
                    }
                }
            }
            .navigationTitle(WL("watch.queue", "Queue"))
            .onAppear {
                if canControl {
                    playback.requestSnapshot()
                }
            }
        }
    }

    private func queueRow(
        _ item: WatchConnectivityProtocol.QueueTrackDTO,
        index: Int,
        currentIndex: Int
    ) -> some View {
        let isCurrent = index == currentIndex
        return Button {
            guard canControl else { return }
            playback.playQueueIndex(index)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "music.note")
                    .font(.caption2)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Text(item.artist)
                            .lineLimit(1)
                        if let duration = item.durationText, !duration.isEmpty {
                            Text("·")
                            Text(duration)
                        }
                        if item.isLive {
                            Text("LIVE")
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .opacity(canControl ? 1 : 0.85)
        }
        .buttonStyle(.plain)
    }
}
