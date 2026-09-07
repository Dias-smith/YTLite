import SwiftUI

/// Now Playing home — Apple Music–style single screen (artwork, remaining, ±15, ring progress).
struct WatchNowPlayingView: View {
    @EnvironmentObject private var bridge: WatchConnectivityBridge
    @ObservedObject private var playback = WatchPlaybackClient.shared

    @State private var showMore = false
    @State private var showSpeedPicker = false
    @State private var draftVolume: Float = 0.5
    @State private var isAdjustingVolume = false
    @State private var swipeOffset: CGFloat = 0

    private var canControl: Bool { bridge.isReachable }

    private static let accent = Color(red: 0.98, green: 0.78, blue: 0.18)
    /// Prefer horizontal over vertical so vertical TabView paging still works.
    private static let swipeHorizontalDominance: CGFloat = 1.35
    private static let swipeTriggerDistance: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let artSide = min(geo.size.width * 0.72, geo.size.height * 0.40)
            ZStack {
                artworkBackground(size: geo.size)

                Group {
                    if let snapshot = playback.snapshot, snapshot.videoId != nil {
                        playingContent(snapshot, artSide: artSide)
                            .offset(x: swipeOffset)
                    } else {
                        emptyState
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)

                moreButton
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .padding(.top, 22)
                    .padding(.leading, 14)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .gesture(trackSwipeGesture)
        .sheet(isPresented: $showMore) {
            moreSheet
                .onAppear {
                    draftVolume = playback.snapshot?.outputVolume ?? draftVolume
                }
        }
        .sheet(isPresented: $showSpeedPicker) {
            speedPickerSheet
        }
    }

    /// Swipe left → next, swipe right → previous (only when clearly horizontal).
    private var trackSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard canControl, playback.snapshot?.videoId != nil else {
                    swipeOffset = 0
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) * Self.swipeHorizontalDominance else {
                    swipeOffset = 0
                    return
                }
                swipeOffset = dx * 0.28
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let shouldSwitch =
                    canControl
                    && playback.snapshot?.videoId != nil
                    && abs(dx) > abs(dy) * Self.swipeHorizontalDominance
                    && abs(dx) >= Self.swipeTriggerDistance

                withAnimation(.easeOut(duration: 0.18)) {
                    swipeOffset = 0
                }

                guard shouldSwitch else { return }
                if dx < 0 {
                    playback.playNext()
                } else {
                    playback.playPrevious()
                }
            }
    }

    // MARK: - Playing

    private func playingContent(
        _ snapshot: WatchConnectivityProtocol.PlaybackSnapshot,
        artSide: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            WatchArtworkView(urlString: snapshot.thumbnailURL)
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: artSide * 0.12, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            Text(snapshot.title ?? "—")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.horizontal, 10)

            Text(remainingLabel(for: snapshot))
                .font(.caption2.weight(.medium))
                .foregroundStyle(Self.accent)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

            if !canControl {
                Text(WL("watch.phone_required", "Open Mixtube on iPhone"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }

            transportRow(snapshot)
                .padding(.top, 10)

            if let error = playback.lastCommandError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var moreButton: some View {
        Button {
            showMore = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(playback.snapshot?.videoId == nil)
    }

    private func transportRow(_ snapshot: WatchConnectivityProtocol.PlaybackSnapshot) -> some View {
        HStack(spacing: 18) {
            Button {
                playback.seekRelative(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canControl)

            playPauseButton(snapshot)

            Button {
                playback.seekRelative(by: 15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canControl)
        }
        .frame(maxWidth: .infinity)
    }

    private func playPauseButton(_ snapshot: WatchConnectivityProtocol.PlaybackSnapshot) -> some View {
        let progress = progressFraction(for: snapshot)
        return Button {
            playback.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Self.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .offset(x: snapshot.isPlaying ? 0 : 0.5)
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canControl)
    }

    // MARK: - Empty / background

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: canControl ? "music.note" : "iphone.slash")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.7))
            if canControl {
                Text(WL("watch.nothing_playing", "Nothing playing"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(WL("watch.play_on_iphone_hint", "Start playback on iPhone"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Text(WL("watch.phone_required", "Open Mixtube on iPhone"))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private func artworkBackground(size: CGSize) -> some View {
        ZStack {
            Color.black
            if let urlString = playback.snapshot?.thumbnailURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .blur(radius: 26)
                            .opacity(0.9)
                    }
                }
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.28, blue: 0.32),
                        Color(red: 0.08, green: 0.12, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            Color.black.opacity(0.42)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
    }

    // MARK: - Sheets

    private var moreSheet: some View {
        NavigationStack {
            List {
                if let snapshot = playback.snapshot {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(WL("watch.volume", "Volume"))
                                Spacer()
                                Text("\(Int((draftVolume * 100).rounded()))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Slider(
                                    value: Binding(
                                        get: { Double(draftVolume) },
                                        set: { draftVolume = Float($0) }
                                    ),
                                    in: 0...1,
                                    onEditingChanged: { editing in
                                        isAdjustingVolume = editing
                                        if !editing, canControl {
                                            playback.setVolume(draftVolume)
                                        }
                                    }
                                )
                                .disabled(!canControl)
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Button {
                        playback.toggleShuffle()
                    } label: {
                        Label {
                            Text(WL("watch.shuffle", "Shuffle"))
                        } icon: {
                            Image(systemName: "shuffle")
                                .foregroundStyle(snapshot.shuffleEnabled ? Self.accent : .primary)
                        }
                    }
                    .disabled(!canControl)

                    Button {
                        playback.cycleRepeat()
                    } label: {
                        Label {
                            Text(WL("watch.repeat", "Repeat"))
                        } icon: {
                            Image(systemName: repeatSystemImage(snapshot.repeatMode))
                                .foregroundStyle(repeatActive(snapshot.repeatMode) ? Self.accent : .primary)
                        }
                    }
                    .disabled(!canControl)

                    Button {
                        showMore = false
                        showSpeedPicker = true
                    } label: {
                        Label {
                            Text("\(WL("watch.speed", "Speed")) · \(speedLabel(snapshot.speed))")
                        } icon: {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                        }
                    }
                    .disabled(!canControl)

                    Button {
                        playback.playPrevious()
                        showMore = false
                    } label: {
                        Label(WL("watch.previous", "Previous"), systemImage: "backward.fill")
                    }
                    .disabled(!canControl)

                    Button {
                        playback.playNext()
                        showMore = false
                    } label: {
                        Label(WL("watch.next", "Next"), systemImage: "forward.fill")
                    }
                    .disabled(!canControl)
                }
            }
            .navigationTitle(WL("watch.more", "More"))
            .onChange(of: playback.snapshot?.outputVolume) { _, newValue in
                guard !isAdjustingVolume, let newValue else { return }
                draftVolume = newValue
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(WL("watch.done", "Done")) { showMore = false }
                }
            }
        }
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
            .navigationTitle(WL("watch.speed", "Speed"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(WL("watch.done", "Done")) { showSpeedPicker = false }
                }
            }
        }
    }

    // MARK: - Helpers

    private func remainingLabel(for snapshot: WatchConnectivityProtocol.PlaybackSnapshot) -> String {
        let remaining: Double
        if let duration = snapshot.duration, duration > 0 {
            remaining = max(0, duration - snapshot.position)
        } else {
            remaining = 0
        }
        let time = formatTime(remaining)
        return String(format: WL("watch.remaining", "Remaining %@"), time)
    }

    private func progressFraction(for snapshot: WatchConnectivityProtocol.PlaybackSnapshot) -> CGFloat {
        guard let duration = snapshot.duration, duration > 0 else { return 0 }
        return CGFloat(min(max(snapshot.position / duration, 0), 1))
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

// MARK: - Artwork

private struct WatchArtworkView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                                .tint(.white)
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.12)
            Image(systemName: "music.note")
                .font(.title)
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}
