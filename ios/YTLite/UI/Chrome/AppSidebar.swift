import SwiftUI
import UIKit

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
        var rows: [(AppTab, String, String)] = [
            (.home, L("tab.home"), "house.fill"),
            (.search, L("tab.search"), "magnifyingglass"),
            (.library, L("tab.library"), "rectangle.stack.fill"),
            (.importMusic, L("tab.import"), "square.and.arrow.down"),
        ]
        #if targetEnvironment(macCatalyst)
        rows.append((.sendToIPhone, L("import.source.mac_send"), "iphone"))
        #endif
        rows.append((.you, youTabTitle, "play.square.fill"))
        #if targetEnvironment(macCatalyst)
        rows.append((.settings, L("settings.title"), "gearshape"))
        #endif
        return rows
    }

    var body: some View {
        List {
            ForEach(items, id: \.0) { tab, title, icon in
                Button {
                    #if targetEnvironment(macCatalyst)
                    let switching = selected != tab
                    selected = tab
                    // The detail column keeps a pushed page until its navigation stack is popped.
                    if switching {
                        DispatchQueue.main.async {
                            MacDetailNavigation.popToRoot(animated: false)
                        }
                    } else {
                        MacDetailNavigation.popToRoot(animated: true)
                    }
                    #else
                    selected = tab
                    #endif
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

#if targetEnvironment(macCatalyst)
/// Pops the detail column back to the section root. The sidebar column is left alone.
enum MacDetailNavigation {
    static func popToRoot(animated: Bool) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                if !popSecondary(of: window.rootViewController, animated: animated) {
                    popStacks(in: window.rootViewController, animated: animated)
                }
            }
        }
    }

    /// Returns whether a split view's detail column was found.
    private static func popSecondary(of vc: UIViewController?, animated: Bool) -> Bool {
        guard let vc else { return false }
        if let split = vc as? UISplitViewController {
            popStacks(in: split.viewController(for: .secondary), animated: animated)
            return true
        }
        for child in vc.children where popSecondary(of: child, animated: animated) {
            return true
        }
        return false
    }

    /// Inner stacks first, so a page pushed inside the detail root is cleared.
    private static func popStacks(in vc: UIViewController?, animated: Bool) {
        guard let vc else { return }
        for child in vc.children {
            popStacks(in: child, animated: animated)
        }
        guard let nav = vc as? UINavigationController, nav.viewControllers.count > 1 else { return }
        nav.popToRootViewController(animated: animated)
    }
}
#endif
