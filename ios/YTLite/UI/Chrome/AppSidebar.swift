import SwiftUI

struct AppSidebar: View {
    @Binding var selected: AppTab
    var isAuthenticated: Bool

    private var items: [(AppTab, String, String)] {
        [
            (.home, L("tab.home"), "house.fill"),
            (.search, L("tab.search"), "magnifyingglass"),
            (.library, L("tab.library"), "rectangle.stack.fill"),
            (.you, isAuthenticated ? L("tab.account") : L("tab.subs"), "play.square.fill"),
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
        .navigationTitle("Mixtube")
    }
}
