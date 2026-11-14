import SwiftUI

/// Root tab host for music import (Library-style chrome).
struct ImportTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ImportHubView(isTabRoot: true)
        }
        .ytLiteContentWidth(enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass))
    }
}
