import SwiftUI

struct MainTabBar: View {
    @Binding var selected: AppTab

    private let items: [(AppTab, String, String)] = [
        (.home, "Home", "house.fill"),
        (.shorts, "Shorts", "play.rectangle.on.rectangle.fill"),
        (.search, "Search", "magnifyingglass"),
        (.you, "Subs", "play.square.fill"),
        (.library, "Library", "rectangle.stack.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { tab, title, icon in
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if selected == tab {
                                Capsule()
                                    .fill(YTLiteColor.accent)
                                    .frame(width: 56, height: 28)
                            }
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(selected == tab ? Color.black.opacity(0.85) : YTLiteColor.onSurfaceVariant)
                        }
                        .frame(height: 28)

                        Text(title)
                            .font(.caption2.weight(selected == tab ? .semibold : .regular))
                            .foregroundStyle(selected == tab ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(YTLiteColor.tabBar)
    }
}
