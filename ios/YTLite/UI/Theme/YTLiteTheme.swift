import SwiftUI
import UIKit

// MARK: - Color (driven by ThemeStore.activePalette)

enum YTLiteColor {
    private static var p: ThemePalette { ThemeRuntime.activePalette }

    static var accent: Color { p.accent.color }
    static var accentDeep: Color { p.accentDeep.color }
    static var background: Color { p.background.color }
    static var surface: Color { p.surface.color }
    static var surfaceElevated: Color { p.surfaceElevated.color }
    static var surfaceChip: Color { p.surfaceChip.color }
    static var surfaceVariant: Color { p.surfaceVariant.color }
    static var onSurface: Color { p.onSurface.color }
    static var onSurfaceVariant: Color { p.onSurfaceVariant.color }
    static var feedMeta: Color { p.feedMeta.color }
    /// Legacy Google blue — prefer `accent` for primary CTAs.
    static let signInBlue = Color(red: 0.024, green: 0.373, blue: 0.831) // #065FD4
    static var miniPlayer: Color { p.miniPlayer.color }
    static var miniProgress: Color { p.miniProgress.color }
    static var miniProgressTrack: Color { p.miniProgressTrack.color }
    static var miniMeta: Color { p.miniMeta.color }
    static var tabBar: Color { p.tabBar.color }
    static var danger: Color { p.danger.color }
    static var onAccent: Color { p.onAccent.color }
    /// Icons / labels drawn on video, photos, or dimmed media overlays (always light).
    static let onMedia = Color.white
    static let onMediaMuted = Color.white.opacity(0.78)
    static var chromeDivider: Color { p.chromeDivider.color }
    static var searchField: Color { p.searchField.color }
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
    static let feedThumbHorizontal: CGFloat = 12
    static let feedThumbRadius: CGFloat = 12
    static let feedAvatar: CGFloat = 36
    static let feedInfoHorizontal: CGFloat = 12
    static let feedInfoTop: CGFloat = 12
    static let feedInfoBottom: CGFloat = 14
    static let feedAvatarTextGap: CGFloat = 12
    static let feedTitleMetaGap: CGFloat = 8
    static let feedTitleLineSpacing: CGFloat = 4
    static let feedDurationInset: CGFloat = 8
    static let miniThumb: CGFloat = 40
    /// Android `MiniPlayerBarHeight`
    static let miniBarHeight: CGFloat = 56
    /// Android mini media 16:9 slot (height fills bar → width ≈ 99).
    static let miniMediaAspect: CGFloat = 16.0 / 9.0
    static let miniProgressHeight: CGFloat = 2
    static let miniControlSize: CGFloat = 48
    /// Mini player chrome above tab content (bar + progress + hairline divider).
    static var miniPlayerChromeHeight: CGFloat {
        miniBarHeight + miniProgressHeight + 1 / UIScreen.main.scale
    }
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
                .foregroundStyle(selected ? YTLiteColor.onAccent : YTLiteColor.onSurface)
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
            .foregroundStyle(Color.white)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .font(YTLiteType.badge)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Live")
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
            RemoteImage(
                url: url,
                contentMode: contentMode,
                maxPointSize: max(width ?? height, height)
            )
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
    var onTap: (() -> Void)? = nil
    var onMore: (() -> Void)? = nil
    /// Tighter horizontal padding for multi-column grids on iPad.
    var compact: Bool = false

    private var thumbHorizontal: CGFloat {
        compact ? 4 : YTLiteLayout.feedThumbHorizontal
    }

    private var infoHorizontal: CGFloat {
        compact ? 4 : YTLiteLayout.feedInfoHorizontal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: item.thumbnailURL, maxPointSize: 420)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                if let durationText = item.durationText, !durationText.isEmpty {
                    DurationBadge(text: durationText)
                        .padding(YTLiteLayout.feedDurationInset)
                }

                if item.isLive {
                    LiveBadge()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(YTLiteLayout.feedDurationInset)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.feedThumbRadius, style: .continuous))
            .padding(.horizontal, thumbHorizontal)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }

            HStack(alignment: .top, spacing: YTLiteLayout.feedAvatarTextGap) {
                Button {
                    onTap?()
                } label: {
                    HStack(alignment: .top, spacing: YTLiteLayout.feedAvatarTextGap) {
                        feedAvatar

                        VStack(alignment: .leading, spacing: YTLiteLayout.feedTitleMetaGap) {
                            Text(item.title)
                                .font(YTLiteType.feedTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                                .lineLimit(2)
                                .lineSpacing(YTLiteLayout.feedTitleLineSpacing)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(item.feedMetaLine)
                                .font(YTLiteType.feedMeta)
                                .foregroundStyle(YTLiteColor.feedMeta)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    onMore?()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .rotationEffect(.degrees(90))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L("common.more"))
            }
            .padding(.horizontal, infoHorizontal)
            .padding(.top, YTLiteLayout.feedInfoTop)
            .padding(.bottom, YTLiteLayout.feedInfoBottom)
        }
        .background(YTLiteColor.background)
    }

    private var feedAvatar: some View {
        FeedChannelAvatar(
            url: item.channelAvatarURL,
            channelName: item.channelName,
            size: YTLiteLayout.feedAvatar
        )
    }
}

/// Channel avatar with letter fallback when URL is missing or image fails to load.
struct FeedChannelAvatar: View {
    let url: URL?
    let channelName: String
    var size: CGFloat = YTLiteLayout.feedAvatar

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    YTLiteColor.surfaceVariant
                    Text(String(channelName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.39, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        image = nil
        guard let url else { return }
        let maxPx = max(1, Int(size * UIScreen.main.scale))
        if let mem = ImageStore.shared.memoryHit(url, maxPixelSize: maxPx) {
            image = mem
            return
        }
        let loaded = await ImageStore.shared.image(for: url, maxPixelSize: maxPx)
        guard !Task.isCancelled else { return }
        image = loaded
    }
}
