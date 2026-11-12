import SwiftUI

struct MainTabBar: View {
    @Binding var selected: AppTab
    var isAuthenticated: Bool = false
    /// Horizontal bottom bar (compact) or vertical side bar (Duo vertical chrome).
    var axis: Axis = .horizontal
    /// Hairline facing content: `.top` for bottom bar; `.trailing`/`.leading` for side bar.
    var separatorAlignment: Alignment = .top
    @Environment(\.displayScale) private var displayScale

    private var items: [(AppTab, String, String)] {
        [
            (.home, L("tab.home"), "house.fill"),
            (.search, L("tab.search"), "magnifyingglass"),
            (.library, L("tab.library"), "rectangle.stack.fill"),
            // Android: guest "Subs" → authenticated "catalog"
            (.you, isAuthenticated ? L("tab.account") : L("tab.subs"), "play.square.fill"),
        ]
    }

    var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 0) {
                    ForEach(items, id: \.0) { tab, title, icon in
                        tabButton(tab: tab, title: title, icon: icon)
                    }
                }
                .padding(.top, YTLiteLayout.stackDefault)
                .padding(.bottom, YTLiteLayout.stackTight)
            } else {
                VStack(spacing: YTLiteLayout.stackLoose) {
                    ForEach(items, id: \.0) { tab, title, icon in
                        tabButton(tab: tab, title: title, icon: icon)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, YTLiteLayout.stackLoose)
                .padding(.horizontal, YTLiteLayout.stackTight)
                .frame(maxHeight: .infinity)
            }
        }
        .background {
            YTLiteColor.tabBar
                .ignoresSafeArea(edges: axis == .horizontal ? .bottom : [])
        }
        .overlay(alignment: separatorAlignment) {
            Rectangle()
                .fill(YTLiteColor.chromeDivider)
                .frame(
                    width: axis == .horizontal ? nil : YTLiteLayout.hairlineHeight(displayScale: displayScale),
                    height: axis == .horizontal ? YTLiteLayout.hairlineHeight(displayScale: displayScale) : nil
                )
        }
    }

    private func tabButton(tab: AppTab, title: String, icon: String) -> some View {
        Button {
            selected = tab
        } label: {
            VStack(spacing: YTLiteLayout.stackTight) {
                ZStack {
                    if selected == tab {
                        Capsule()
                            .fill(YTLiteColor.accent)
                            .frame(width: 56, height: 28)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            selected == tab
                                ? YTLiteColor.onAccent
                                : YTLiteColor.onSurfaceVariant
                        )
                }
                .frame(height: 28)

                Text(title)
                    .font(selected == tab ? YTLiteType.tabLabelSelected : YTLiteType.tabLabel)
                    .foregroundStyle(
                        selected == tab
                            ? YTLiteColor.accent
                            : YTLiteColor.onSurfaceVariant
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
