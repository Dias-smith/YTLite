import SwiftUI

struct AppSidebar: View {
    @Binding var selected: AppTab
    var isAuthenticated: Bool

    /// Shorts is iPhone-only — hide on iPad sidebar.
    private var items: [(AppTab, String, String)] {
        [
            (.home, L("tab.home"), "house.fill"),
            (.search, L("tab.search"), "magnifyingglass"),
            (.you, isAuthenticated ? L("tab.youtube") : L("tab.subs"), "play.square.fill"),
            (.library, L("tab.library"), "rectangle.stack.fill"),
        ]
    }

    var body: some View {
        List {
            ForEach(items, id: \.0) { tab, title, icon in
                Button {
                    selected = tab
                } label: {
                    Label(title, systemImage: icon)
                        .foregroundStyle(
                            selected == tab ? YTLiteColor.accent : YTLiteColor.onSurface
                        )
                }
                .listRowBackground(
                    selected == tab
                        ? YTLiteColor.accent.opacity(0.14)
                        : Color.clear
                )
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.surface)
        .navigationTitle("YouLite")
    }
}
