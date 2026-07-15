import SwiftUI

// MARK: - Color (Android-aligned)

enum YTLiteColor {
    /// Android Orange40
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.0) // #FF6A00
    static let accentDeep = Color(red: 0.769, green: 0.333, blue: 0.0) // #C45500
    static let background = Color.black
    static let surface = Color(red: 0.051, green: 0.051, blue: 0.051) // #0D0D0D
    static let surfaceElevated = Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E
    static let surfaceChip = Color(red: 0.129, green: 0.129, blue: 0.129) // #212121
    static let surfaceVariant = Color(red: 0.165, green: 0.165, blue: 0.165) // #2A2A2A
    static let onSurface = Color.white
    static let onSurfaceVariant = Color(red: 0.69, green: 0.69, blue: 0.69) // #B0B0B0
    /// Feed meta gray matching YouTube card (~#AAAAAA)
    static let feedMeta = Color(red: 0.667, green: 0.667, blue: 0.667)
    static let signInBlue = Color(red: 0.024, green: 0.373, blue: 0.831) // #065FD4
    static let miniPlayer = Color(red: 0.094, green: 0.094, blue: 0.094) // #181818
    static let tabBar = Color(red: 0.059, green: 0.059, blue: 0.059)
    static let danger = Color.red
    static let onAccent = Color.black.opacity(0.85)
}

// MARK: - Typography (SF semantic tokens)

enum YTLiteType {
    /// Library / Subs page headers (~22)
    static let pageTitle = Font.title2.bold()
    /// Section headers e.g. "Recent searches" (~17 semibold)
    static let sectionTitle = Font.headline
    /// List / card primary titles (~15 semibold)
    static let rowTitle = Font.subheadline.weight(.semibold)
    /// Compact row title when slightly lighter weight is needed
    static let rowTitleMedium = Font.subheadline.weight(.medium)
    /// Body copy (~15 regular)
    static let body = Font.subheadline
    /// Secondary meta: channel, views (~12)
    static let meta = Font.system(size: 12, weight: .regular)
    /// Home feed large-card title (YouTube-like ~14 semibold)
    static let feedTitle = Font.system(size: 14, weight: .semibold)
    /// Home feed meta under title (~12)
    static let feedMeta = Font.system(size: 12, weight: .regular)
    /// Chip / filter / inline button label
    static let label = Font.subheadline
    /// Chip selected emphasis
    static let labelEmphasized = Font.subheadline.weight(.semibold)
    /// Bottom tab labels
    static let tabLabel = Font.caption2
    static let tabLabelSelected = Font.caption2.weight(.semibold)
    /// Duration badge
    static let badge = Font.caption2.weight(.semibold)
    /// Caption-sized action text under icons
    static let iconCaption = Font.caption2
    /// Empty-state / hero supporting
    static let emptyTitle = Font.title3.weight(.bold)
}

// MARK: - Layout

enum YTLiteLayout {
    static let screenPadding: CGFloat = 16
    static let rowVertical: CGFloat = 8
    static let sectionGap: CGFloat = 24
    static let stackTight: CGFloat = 4
    static let stackDefault: CGFloat = 8
    static let stackLoose: CGFloat = 12
    static let chipHorizontal: CGFloat = 14
    static let chipVertical: CGFloat = 8
    static let chipRadius: CGFloat = 20
    static let cardRadius: CGFloat = 10
    static let thumbRadius: CGFloat = 8
    static let searchThumbWidth: CGFloat = 112
    static let searchThumbHeight: CGFloat = 63
    static let feedThumbHeight: CGFloat = 200
    static let feedAvatar: CGFloat = 36
    static let feedInfoHorizontal: CGFloat = 12
    static let feedInfoTop: CGFloat = 10
    static let feedInfoBottom: CGFloat = 12
    static let feedAvatarTextGap: CGFloat = 12
    static let feedTitleMetaGap: CGFloat = 4
    static let feedDurationInset: CGFloat = 8
    static let miniThumb: CGFloat = 40
    static let channelAvatar: CGFloat = 56
}

// MARK: - Shared components

struct YTLiteChip: View {
    let title: String
    var selected: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(selected ? YTLiteType.labelEmphasized : YTLiteType.label)
                .foregroundStyle(YTLiteColor.onSurface)
                .padding(.horizontal, YTLiteLayout.chipHorizontal)
                .padding(.vertical, YTLiteLayout.chipVertical)
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
            .font(YTLiteType.badge)
            .foregroundStyle(YTLiteColor.onSurface)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Shared video cover with optional duration badge at bottom-trailing.
struct VideoThumbnail: View {
    let url: URL?
    var durationText: String? = nil
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = YTLiteLayout.thumbRadius
    var badgePadding: CGFloat = 4
    var contentMode: ContentMode = .fill

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RemoteImage(url: url, contentMode: contentMode)
                .frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : width)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            if let durationText, !durationText.isEmpty {
                DurationBadge(text: durationText)
                    .padding(badgePadding)
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : width)
    }
}

struct SectionHeaderRow: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(YTLiteType.sectionTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.accent)
            }
        }
    }
}

struct FeedVideoCard: View {
    let item: VideoItem
    var onMore: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: item.thumbnailURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                if let durationText = item.durationText, !durationText.isEmpty {
                    DurationBadge(text: durationText)
                        .padding(YTLiteLayout.feedDurationInset)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()

            HStack(alignment: .top, spacing: YTLiteLayout.feedAvatarTextGap) {
                feedAvatar

                VStack(alignment: .leading, spacing: YTLiteLayout.feedTitleMetaGap) {
                    Text(item.title)
                        .font(YTLiteType.feedTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(item.feedMetaLine)
                        .font(YTLiteType.feedMeta)
                        .foregroundStyle(YTLiteColor.feedMeta)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: { onMore?() }) {
                    Image(systemName: "ellipsis.vertical")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(width: 36, height: 36, alignment: .top)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, YTLiteLayout.feedInfoHorizontal)
            .padding(.top, YTLiteLayout.feedInfoTop)
            .padding(.bottom, YTLiteLayout.feedInfoBottom)
        }
        .background(YTLiteColor.background)
    }

    @ViewBuilder
    private var feedAvatar: some View {
        Group {
            if let url = item.channelAvatarURL {
                RemoteImage(url: url)
            } else {
                ZStack {
                    YTLiteColor.surfaceVariant
                    Text(String(item.channelName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                }
            }
        }
        .frame(width: YTLiteLayout.feedAvatar, height: YTLiteLayout.feedAvatar)
        .clipShape(Circle())
    }
}
