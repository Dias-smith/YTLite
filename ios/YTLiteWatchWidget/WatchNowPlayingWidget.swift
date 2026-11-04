import AppIntents
import SwiftUI
import WidgetKit

struct WatchNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetShared.widgetKind, provider: WatchNowPlayingTimelineProvider()) { entry in
            WatchNowPlayingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black
                }
        }
        .configurationDisplayName("Mixtube")
        .description("Now Playing controls for Mixtube")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

struct WatchNowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchWidgetPlaybackSnapshot
}

struct WatchNowPlayingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchNowPlayingEntry {
        WatchNowPlayingEntry(
            date: Date(),
            snapshot: WatchWidgetPlaybackSnapshot(
                videoId: "placeholder",
                title: "Mixtube",
                artist: "",
                isPlaying: false,
                updatedAt: 0
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchNowPlayingEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchNowPlayingEntry>) -> Void) {
        let entry = makeEntry()
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> WatchNowPlayingEntry {
        WatchNowPlayingEntry(date: Date(), snapshot: WatchWidgetPlaybackSnapshotStore.load())
    }
}

struct WatchNowPlayingWidgetEntryView: View {
    var entry: WatchNowPlayingEntry
    @Environment(\.widgetFamily) private var family

    private static let accent = Color(red: 0.98, green: 0.78, blue: 0.18)

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularBody
        case .accessoryRectangular:
            rectangularBody
        case .accessoryInline:
            inlineBody
        case .accessoryCorner:
            cornerBody
        default:
            rectangularBody
        }
    }

    private var circularBody: some View {
        Button(intent: WatchWidgetTogglePlayIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Self.accent)
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
            Button(intent: WatchWidgetTogglePlayIntent()) {
                Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Self.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private var inlineBody: some View {
        Text(entry.snapshot.hasTrack ? entry.snapshot.title : "Mixtube")
            .lineLimit(1)
    }

    private var cornerBody: some View {
        Button(intent: WatchWidgetTogglePlayIntent()) {
            Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Self.accent)
        }
        .buttonStyle(.plain)
        .widgetLabel {
            Text(entry.snapshot.hasTrack ? entry.snapshot.title : "Mixtube")
                .lineLimit(1)
        }
    }
}

struct WatchWidgetTogglePlayIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Play or pause Mixtube on iPhone")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WatchWidgetCommandQueue.enqueue(.togglePlayPause)
        return .result()
    }
}

struct WatchWidgetPlayNextIntent: AppIntent {
    static var title: LocalizedStringResource = "Next"
    static var description = IntentDescription("Skip to the next track")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WatchWidgetCommandQueue.enqueue(.next)
        return .result()
    }
}
