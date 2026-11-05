import SwiftUI

/// Shared screen backdrop for Home / Search / Account / Library.
struct AppBackgroundCanvas: View {
    @ObservedObject private var store = AppBackgroundStore.shared

    var body: some View {
        let _ = store.revision
        ZStack {
            YTLiteColor.background
            switch store.preference.kind {
            case .theme:
                EmptyView()
            case .color:
                store.preference.color.color
            case .image:
                if let image = store.image {
                    imageLayer(image, mode: store.preference.imageMode)
                    // Keep on-surface text readable over arbitrary photos.
                    YTLiteColor.background.opacity(0.72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func imageLayer(_ image: UIImage, mode: AppBackgroundImageMode) -> some View {
        switch mode {
        case .fill:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        case .fit:
            ZStack {
                YTLiteColor.background
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .stretch:
            Image(uiImage: image)
                .resizable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tile:
            Rectangle()
                .fill(
                    ImagePaint(
                        image: Image(uiImage: image),
                        scale: tileScale(for: image)
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tileScale(for image: UIImage) -> CGFloat {
        // Keep tiles readable on Retina without becoming tiny stamps.
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return 1 }
        return min(1, 220 / longest)
    }
}

private struct AppBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            AppBackgroundCanvas()
                .ignoresSafeArea()
        }
    }
}

extension View {
    /// Theme / solid / photo backdrop used by main browsing tabs.
    func ytLiteAppBackground() -> some View {
        modifier(AppBackgroundModifier())
    }
}
