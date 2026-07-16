import SwiftUI
import UIKit

struct MainTabBar: View {
    @Binding var selected: AppTab
    var isAuthenticated: Bool = false

    private var items: [(AppTab, String, String)] {
        [
            (.home, L("tab.home"), "house.fill"),
            (.shorts, L("tab.shorts"), "play.rectangle.on.rectangle.fill"),
            (.search, L("tab.search"), "magnifyingglass"),
            // Android: guest "Subs" → authenticated "YouTube"
            (.you, isAuthenticated ? L("tab.youtube") : L("tab.subs"), "play.square.fill"),
            (.library, L("tab.library"), "rectangle.stack.fill"),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { tab, title, icon in
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
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, YTLiteLayout.stackDefault)
        .padding(.bottom, YTLiteLayout.stackTight)
        .background(YTLiteColor.tabBar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(YTLiteColor.chromeDivider)
                .frame(height: 1 / UIScreen.main.scale)
        }
    }
}
