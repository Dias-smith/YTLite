import SwiftUI

/// Root tab host for music import (Import Hub + nested imported list).
struct ImportTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ImportHubView()
        }
        .ytLiteContentWidth(enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass))
    }
}
