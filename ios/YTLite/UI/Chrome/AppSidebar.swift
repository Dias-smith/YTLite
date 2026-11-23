import SwiftUI

struct AppSidebar: View {
    @Binding var selected: AppTab
    var isAuthenticated: Bool

    private var youTabTitle: String {
        #if targetEnvironment(macCatalyst)
        // Mac DMG build is account/sign-in oriented — never label this tab "Subs".
        L("tab.account")
        #else
        isAuthenticated ? L("tab.account") : L("tab.subs")
        #endif
    }

    private var items: [(AppTab, String, String)] {
        [
            (.home, L("tab.home"), "house.fill"),
            (.search, L("tab.search"), "magnifyingglass"),
            (.library, L("tab.library"), "rectangle.stack.fill"),
            (.importMusic, L("tab.import"), "square.and.arrow.down"),
            (.you, youTabTitle, "play.square.fill"),
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
