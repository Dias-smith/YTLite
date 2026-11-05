import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct PhoneNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PhoneWidgetShared.widgetKind, provider: PhoneNowPlayingTimelineProvider()) { entry in
            PhoneNowPlayingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    PhoneWidgetPalette.background
                }
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
        .contentMarginsDisabled()
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

struct PhoneNowPlayingWidgetEntryView: View {
    var entry: PhoneNowPlayingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
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

    private var smallBody: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)
                Text(entry.snapshot.hasTrack ? entry.snapshot.title : "Mixtube")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PhoneWidgetPalette.onSurface)
                    .lineLimit(2)
                HStack {
                    Spacer(minLength: 0)
                    Button(intent: PhoneWidgetTogglePlayIntent()) {
                        Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(PhoneWidgetPalette.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .widgetURL(URL(string: "ytlite://player"))
    }

    private var mediumBody: some View {
        HStack(spacing: 14) {
            artwork
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button(intent: PhoneWidgetPlayPreviousIntent()) {
                        controlIcon("backward.fill")
                    }
                    .buttonStyle(.plain)
                    Button(intent: PhoneWidgetTogglePlayIntent()) {
                        Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(PhoneWidgetPalette.accent))
                    }
                    .buttonStyle(.plain)
                    Button(intent: PhoneWidgetPlayNextIntent()) {
                        controlIcon("forward.fill")
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 4)
            Spacer(minLength: 0)
        }
        .padding(14)
        .widgetURL(URL(string: "ytlite://player"))
    }

    private var circularBody: some View {
        Button(intent: PhoneWidgetTogglePlayIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PhoneWidgetPalette.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private var rectangularBody: some View {
        HStack(spacing: 8) {
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
            Spacer(minLength: 0)
            Button(intent: PhoneWidgetTogglePlayIntent()) {
                Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(PhoneWidgetPalette.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private var inlineBody: some View {
        Text(entry.snapshot.hasTrack ? entry.snapshot.title : "Mixtube")
            .lineLimit(1)
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

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(PhoneWidgetPalette.onSurface)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.12)))
    }
}
