import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct PhoneNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PhoneWidgetShared.widgetKind, provider: PhoneNowPlayingTimelineProvider()) { entry in
            PhoneNowPlayingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Mixtube")
        .description("Now Playing controls for Mixtube")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
        // Keep system content margins so controls stay inside the Home Screen corner radius.
        // Full-bleed artwork goes in `containerBackground`, which draws under those margins.
    }
}

struct PhoneNowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: PhoneWidgetPlaybackSnapshot
    let artwork: UIImage?
}

struct PhoneNowPlayingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhoneNowPlayingEntry {
        PhoneNowPlayingEntry(
            date: Date(),
            snapshot: PhoneWidgetPlaybackSnapshot(
                videoId: "placeholder",
                title: "Mixtube",
                artist: "Now Playing",
                thumbnailURL: nil,
                isPlaying: false,
                updatedAt: 0
            ),
            artwork: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PhoneNowPlayingEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhoneNowPlayingEntry>) -> Void) {
        let entry = makeEntry()
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> PhoneNowPlayingEntry {
        let snapshot = PhoneWidgetPlaybackSnapshotStore.load()
        let artwork = snapshot.hasTrack ? PhoneWidgetArtworkStore.load(videoId: snapshot.videoId) : nil
        return PhoneNowPlayingEntry(date: Date(), snapshot: snapshot, artwork: artwork)
    }
}

private enum PhoneWidgetPalette {
    static let accent = Color(red: 0.98, green: 0.78, blue: 0.18)
    static let background = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let onSurface = Color.white
    static let onSurfaceVariant = Color.white.opacity(0.72)
}

/// Avoid system / Liquid Glass chrome morphing a custom `Circle` fill into a warped blob.
private struct WidgetControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct PhoneNowPlayingWidgetEntryView: View {
    var entry: PhoneNowPlayingEntry
    @Environment(\.widgetFamily) private var family

    private var playerURL: URL { URL(string: "ytlite://player")! }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallBody
            case .systemMedium:
                mediumBody
            case .accessoryCircular:
                circularBody
            case .accessoryRectangular:
                rectangularBody
            case .accessoryInline:
                inlineBody
            default:
                mediumBody
            }
        }
    }

    private var smallBody: some View {
        // Three equal columns: previous | open app | next.
        // Title is decorative only — taps are owned by the column hit targets.
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text(entry.snapshot.hasTrack ? entry.snapshot.title : "Mixtube")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PhoneWidgetPalette.onSurface)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                Button(intent: PhoneWidgetPlayPreviousIntent()) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WidgetControlButtonStyle())
                .accessibilityLabel("Previous")

                Link(destination: playerURL) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WidgetControlButtonStyle())
                .accessibilityLabel("Open Mixtube")

                Button(intent: PhoneWidgetPlayNextIntent()) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WidgetControlButtonStyle())
                .accessibilityLabel("Next")
            }
        }
        .containerBackground(for: .widget) {
            smallArtworkBackground
        }
    }

    private var mediumBody: some View {
        HStack(spacing: 14) {
            Link(destination: playerURL) {
                artwork
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(WidgetControlButtonStyle())

            VStack(alignment: .leading, spacing: 6) {
                Link(destination: playerURL) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.snapshot.hasTrack ? entry.snapshot.title : "Mixtube")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(PhoneWidgetPalette.onSurface)
                            .lineLimit(2)
                        Text(
                            entry.snapshot.hasTrack
                                ? (entry.snapshot.artist.isEmpty ? "Now Playing" : entry.snapshot.artist)
                                : "Open to play"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PhoneWidgetPalette.onSurfaceVariant)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(WidgetControlButtonStyle())

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button(intent: PhoneWidgetPlayPreviousIntent()) {
                        sideControlIcon("backward.fill")
                    }
                    .buttonStyle(WidgetControlButtonStyle())

                    playPauseControl(diameter: 34)

                    Button(intent: PhoneWidgetPlayNextIntent()) {
                        sideControlIcon("forward.fill")
                    }
                    .buttonStyle(WidgetControlButtonStyle())

                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            PhoneWidgetPalette.background
        }
    }

    private var circularBody: some View {
        Button(intent: PhoneWidgetTogglePlayIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PhoneWidgetPalette.accent)
                    .offset(x: entry.snapshot.isPlaying ? 0 : 1)
            }
        }
        .buttonStyle(WidgetControlButtonStyle())
        .containerBackground(for: .widget) {
            PhoneWidgetPalette.background
        }
    }

    private var rectangularBody: some View {
        HStack(spacing: 8) {
            Link(destination: playerURL) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snapshot.hasTrack ? entry.snapshot.title : "Mixtube")
                        .font(.headline)
                        .lineLimit(1)
                    Text(
                        entry.snapshot.hasTrack
                            ? (entry.snapshot.artist.isEmpty ? "Now Playing" : entry.snapshot.artist)
                            : "Open to play"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WidgetControlButtonStyle())

            playPauseControl(diameter: 28)
        }
        .containerBackground(for: .widget) {
            PhoneWidgetPalette.background
        }
    }

    private var inlineBody: some View {
        Text(entry.snapshot.hasTrack ? entry.snapshot.title : "Mixtube")
            .lineLimit(1)
    }

    private var smallArtworkBackground: some View {
        ZStack {
            artwork
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let artwork = entry.artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            PhoneWidgetPalette.background
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(PhoneWidgetPalette.onSurfaceVariant)
        }
    }

    private func playPauseControl(diameter: CGFloat) -> some View {
        Button(intent: PhoneWidgetTogglePlayIntent()) {
            ZStack {
                Circle()
                    .fill(PhoneWidgetPalette.accent)
                Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(.black)
                    .offset(x: entry.snapshot.isPlaying ? 0 : diameter * 0.03)
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(WidgetControlButtonStyle())
        .tint(.clear)
        .buttonBorderShape(.circle)
    }

    private func sideControlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PhoneWidgetPalette.onSurface)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.12)))
            .contentShape(Circle())
    }
}
