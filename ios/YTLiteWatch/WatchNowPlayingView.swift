import SwiftUI

/// Now Playing remote: seek, shuffle, repeat, speed + transport.
struct WatchNowPlayingView: View {
    @EnvironmentObject private var bridge: WatchConnectivityBridge
    @ObservedObject private var playback = WatchPlaybackClient.shared

    @State private var scrubPosition: Double?
    @State private var isScrubbing = false
    @State private var showSpeedPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    connectivityBanner

                    if let snapshot = playback.snapshot, snapshot.videoId != nil {
                        nowPlayingCard(snapshot)
                        seekSection(snapshot, enabled: bridge.isReachable)
                        transportControls(enabled: bridge.isReachable)
                        modeControls(snapshot, enabled: bridge.isReachable)
                        volumeHint(snapshot)
                    } else {
                        emptyState
                    }

                    if let error = playback.lastCommandError ?? bridge.lastErrorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .navigationTitle("Mixtube")
            .sheet(isPresented: $showSpeedPicker) {
                speedPickerSheet
            }
        }
    }

    @ViewBuilder
    private var connectivityBanner: some View {
        if !bridge.isReachable {
            VStack(alignment: .leading, spacing: 4) {
                Text(WL("watch.phone_required", "Open Mixtube on iPhone"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(WL("watch.controls_blocked", "Controls unavailable until Mixtube is open on iPhone"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: bridge.isReachable ? "music.note" : "iphone.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            if bridge.isReachable {
                Text(WL("watch.nothing_playing", "Nothing playing"))
                    .font(.headline)
                Text(WL("watch.play_on_iphone_hint", "Start playback on iPhone"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(WL("watch.phone_required", "Open Mixtube on iPhone"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(WL("watch.controls_blocked", "Controls unavailable until Mixtube is open on iPhone"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func nowPlayingCard(_ snapshot: WatchConnectivityProtocol.PlaybackSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.title ?? "—")
                .font(.headline)
                .lineLimit(2)
            Text(snapshot.artist ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if snapshot.isExtracting {
                Label(
                    String(localized: "watch.extracting", defaultValue: "Loading…"),
                    systemImage: "ellipsis"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let error = snapshot.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func seekSection(
        _ snapshot: WatchConnectivityProtocol.PlaybackSnapshot,
        enabled: Bool
    ) -> some View {
        let duration = snapshot.duration ?? 0
        let displayed = isScrubbing ? (scrubPosition ?? snapshot.position) : snapshot.position

        VStack(spacing: 4) {
            HStack {
                Text(formatTime(displayed))
                    .font(.caption2.monospacedDigit())
                Spacer()
                Text(duration > 0 ? formatTime(duration) : "--:--")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if snapshot.isSeekable, duration > 0 {
                Slider(
                    value: Binding(
                        get: { displayed },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...duration,
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if editing {
                            scrubPosition = displayed
                        } else if let target = scrubPosition, enabled {
                            playback.seek(to: target)
                            scrubPosition = nil
                        } else {
                            scrubPosition = nil
                        }
                    }
                )
                .disabled(!enabled)

                HStack {
                    Button {
                        playback.seekRelative(by: -15)
                    } label: {
                        Label("-15", systemImage: "gobackward.15")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!enabled)

                    Spacer()

                    Button {
                        playback.seekRelative(by: 30)
                    } label: {
                        Label("+30", systemImage: "goforward.30")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!enabled)
                }
                .buttonStyle(.plain)
                .font(.body)
            }
        }
    }

    private func transportControls(enabled: Bool) -> some View {
        HStack(spacing: 16) {
            Button {
                playback.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
            }
            .disabled(!enabled)

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: (playback.snapshot?.isPlaying == true) ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .disabled(!enabled)

            Button {
                playback.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
            }
            .disabled(!enabled)
        }
        .buttonStyle(.plain)
    }

    private func modeControls(
        _ snapshot: WatchConnectivityProtocol.PlaybackSnapshot,
        enabled: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Button {
                playback.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(snapshot.shuffleEnabled ? Color.accentColor : Color.primary)
            }
            .disabled(!enabled)

            Button {
                playback.cycleRepeat()
            } label: {
                Image(systemName: repeatSystemImage(snapshot.repeatMode))
                    .foregroundStyle(repeatActive(snapshot.repeatMode) ? Color.accentColor : Color.primary)
            }
            .disabled(!enabled)

            Button {
                showSpeedPicker = true
            } label: {
                Text(speedLabel(snapshot.speed))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2), in: Capsule())
            }
            .disabled(!enabled)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func volumeHint(_ snapshot: WatchConnectivityProtocol.PlaybackSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.caption2)
            if let volume = snapshot.outputVolume {
                Text("\(Int((volume * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
            }
            Text(String(localized: "watch.volume_crown_hint", defaultValue: "Crown for volume"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speedPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(WatchConnectivityProtocol.PlaybackSnapshot.speedOptions, id: \.self) { speed in
                    Button {
                        playback.setSpeed(speed)
                        showSpeedPicker = false
                    } label: {
                        HStack {
                            Text(speedLabel(speed))
                            Spacer()
                            if abs((playback.snapshot?.speed ?? 1) - speed) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "watch.speed", defaultValue: "Speed"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "watch.done", defaultValue: "Done")) {
                        showSpeedPicker = false
                    }
                }
            }
        }
    }

    private func repeatSystemImage(_ raw: String) -> String {
        switch raw {
        case "ONE": return "repeat.1"
        default: return "repeat"
        }
    }

    private func repeatActive(_ raw: String) -> Bool {
        raw != "OFF"
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed.rounded() == speed {
            return String(format: "%.1fx", speed)
        }
        return String(format: "%gx", speed)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
