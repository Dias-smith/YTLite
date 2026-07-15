import SwiftUI

enum YTLiteColor {
    /// Android Orange40
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.0) // #FF6A00
    static let accentDeep = Color(red: 0.769, green: 0.333, blue: 0.0) // #C45500 / primaryContainer
    static let background = Color.black
    static let surface = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
    static let surfaceElevated = Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
    static let surfaceChip = Color(red: 0.129, green: 0.129, blue: 0.129) // #212121
    static let surfaceVariant = Color(red: 0.165, green: 0.165, blue: 0.165) // #2A2A2A
    static let onSurface = Color.white
    static let onSurfaceVariant = Color(red: 0.69, green: 0.69, blue: 0.69) // #B0B0B0 / #AAAAAA
    static let signInBlue = Color(red: 0.024, green: 0.373, blue: 0.831) // #065FD4
    static let miniPlayer = Color(red: 0.094, green: 0.094, blue: 0.094) // #181818
    static let tabBar = Color(red: 0.059, green: 0.059, blue: 0.059)
}

enum YTLiteLayout {
    static let screenPadding: CGFloat = 16
    static let chipRadius: CGFloat = 20
    static let cardRadius: CGFloat = 10
    static let thumbRadius: CGFloat = 8
}

struct YTLiteChip: View {
    let title: String
    var selected: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selected ? YTLiteColor.accent : YTLiteColor.surfaceChip)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct DurationBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct SectionHeaderRow: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(YTLiteColor.accent)
            }
        }
    }
}

struct FeedVideoCard: View {
    let item: VideoItem
    var onMore: (() -> Void)? = nil
    var onDownload: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: item.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        YTLiteColor.surfaceVariant
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.cardRadius))

                if let duration = item.durationText, !duration.isEmpty {
                    DurationBadge(text: duration)
                        .padding(8)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(item.subtitle.isEmpty ? item.channelName : item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let onDownload {
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.to.line")
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                }
                Button(action: { onMore?() }) {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 8)
    }
}
