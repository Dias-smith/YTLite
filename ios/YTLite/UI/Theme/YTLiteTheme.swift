import SwiftUI
import UIKit

// MARK: - Color (Android-aligned, adaptive light/dark)

enum YTLiteColor {
    /// Android Orange40 — brand accent (same in both schemes)
    static let accent = Color(red: 1.0, green: 0.416, blue: 0.0) // #FF6A00
    static let accentDeep = Color(red: 0.769, green: 0.333, blue: 0.0) // #C45500

    static let background = adaptive(light: UIColor.white, dark: UIColor.black)
    static let surface = adaptive(
        light: UIColor(white: 0.96, alpha: 1), // #F5F5F5
        dark: UIColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1) // #0D0D0D
    )
    static let surfaceElevated = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1) // #1E1E1E
    )
    static let surfaceChip = adaptive(
        light: UIColor(white: 0.91, alpha: 1), // #E8E8E8
        dark: UIColor(red: 0.129, green: 0.129, blue: 0.129, alpha: 1) // #212121
    )
    static let surfaceVariant = adaptive(
        light: UIColor(white: 0.94, alpha: 1), // #F0F0F0
        dark: UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1) // #2A2A2A
    )
    static let onSurface = adaptive(
        light: UIColor(white: 0.102, alpha: 1), // #1A1A1A
        dark: UIColor.white
    )
    static let onSurfaceVariant = adaptive(
        light: UIColor(white: 0.42, alpha: 1), // #6B6B6B
        dark: UIColor(red: 0.69, green: 0.69, blue: 0.69, alpha: 1) // #B0B0B0
    )
    /// Feed meta gray matching YouTube card
    static let feedMeta = adaptive(
        light: UIColor(white: 0.459, alpha: 1), // #757575
        dark: UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1) // #AAAAAA
    )
    static let signInBlue = Color(red: 0.024, green: 0.373, blue: 0.831) // #065FD4
    static let miniPlayer = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 0.129, green: 0.129, blue: 0.129, alpha: 1) // #212121
    )
    /// Mini player progress fill (Android ProgressBlue)
    static let miniProgress = Color(red: 0.243, green: 0.651, blue: 1.0) // #3EA6FF
    static let miniProgressTrack = adaptive(
        light: UIColor(white: 0.82, alpha: 1),
        dark: UIColor(red: 0.259, green: 0.259, blue: 0.259, alpha: 1) // #424242
    )
    /// Channel meta in mini player
    static let miniMeta = adaptive(
        light: UIColor(white: 0.459, alpha: 1),
        dark: UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1)
    )
    static let tabBar = adaptive(
        light: UIColor.white,
        dark: UIColor(red: 0.059, green: 0.059, blue: 0.059, alpha: 1)
    )
    static let danger = Color.red
    static let onAccent = Color.black.opacity(0.85)
    /// Hairline divider for light chrome (tab bar / mini player)
    static let chromeDivider = adaptive(
        light: UIColor(white: 0.85, alpha: 1),
        dark: UIColor(white: 1, alpha: 0.08)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
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
            .foregroundStyle(Color.white)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
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
    var onTap: (() -> Void)? = nil
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
            .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.feedThumbRadius, style: .continuous))
            .padding(.horizontal, YTLiteLayout.feedThumbHorizontal)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }

            HStack(alignment: .top, spacing: YTLiteLayout.feedAvatarTextGap) {
                feedAvatar
                    .onTapGesture { onTap?() }

                HStack(alignment: .center, spacing: 4) {
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
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?() }

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
                    .accessibilityLabel("More")
                }
            }
            .padding(.horizontal, YTLiteLayout.feedInfoHorizontal)
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
        if let mem = ImageStore.shared.memoryHit(url) {
            image = mem
            return
        }
        image = await ImageStore.shared.image(for: url)
    }
}
