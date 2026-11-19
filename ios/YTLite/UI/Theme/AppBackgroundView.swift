import SwiftUI

/// Shared screen backdrop for Home / Search / Account / Library.
struct AppBackgroundCanvas: View {
    @ObservedObject private var store = AppBackgroundStore.shared
    @ObservedObject private var vip = VipStore.shared

    private var visibleKind: AppBackgroundKind {
        if store.preference.kind == .image, !vip.isVipActive { return .theme }
        return store.preference.kind
    }

    var body: some View {
        let _ = store.revision
        let _ = vip.revision
        ZStack {
            YTLiteColor.background
            switch visibleKind {
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
            FitImageWithBlurredMirror(image: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Fit the photo, and fill letterbox / pillarbox gaps with a blurred mirror of the adjacent edge.
private struct FitImageWithBlurredMirror: View {
    let image: UIImage
    private let blurRadius: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            // Quantize during Duo fold resize so blur layers aren't rebuilt every frame.
            let step: CGFloat = 32
            let size = CGSize(
                width: (geo.size.width / step).rounded() * step,
                height: (geo.size.height / step).rounded() * step
            )
            content(in: size)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .drawingGroup(opaque: true, colorMode: .nonLinear)
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        let imgAspect = max(image.size.width, 1) / max(image.size.height, 1)
        let viewAspect = size.width / max(size.height, 1)

        ZStack {
            YTLiteColor.background
            if abs(imgAspect - viewAspect) < 0.002 {
                sharp(width: size.width, height: size.height)
            } else if imgAspect > viewAspect {
                letterboxed(size: size, imgAspect: imgAspect)
            } else {
                pillarboxed(size: size, imgAspect: imgAspect)
            }
        }
    }

    private func letterboxed(size: CGSize, imgAspect: CGFloat) -> some View {
        let fittedH = size.width / imgAspect
        let barH = max(0, (size.height - fittedH) * 0.5)
        return VStack(spacing: 0) {
            mirrorBand(
                fittedWidth: size.width,
                fittedHeight: fittedH,
                bandWidth: size.width,
                bandHeight: barH,
                scaleX: 1,
                scaleY: -1,
                alignment: .bottom
            )
            sharp(width: size.width, height: fittedH)
            mirrorBand(
                fittedWidth: size.width,
                fittedHeight: fittedH,
                bandWidth: size.width,
                bandHeight: barH,
                scaleX: 1,
                scaleY: -1,
                alignment: .top
            )
        }
    }

    private func pillarboxed(size: CGSize, imgAspect: CGFloat) -> some View {
        let fittedW = size.height * imgAspect
        let barW = max(0, (size.width - fittedW) * 0.5)
        return HStack(spacing: 0) {
            mirrorBand(
                fittedWidth: fittedW,
                fittedHeight: size.height,
                bandWidth: barW,
                bandHeight: size.height,
                scaleX: -1,
                scaleY: 1,
                alignment: .trailing
            )
            sharp(width: fittedW, height: size.height)
            mirrorBand(
                fittedWidth: fittedW,
                fittedHeight: size.height,
                bandWidth: barW,
                bandHeight: size.height,
                scaleX: -1,
                scaleY: 1,
                alignment: .leading
            )
        }
    }

    private func sharp(width: CGFloat, height: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: width, height: height)
    }

    @ViewBuilder
    private func mirrorBand(
        fittedWidth: CGFloat,
        fittedHeight: CGFloat,
        bandWidth: CGFloat,
        bandHeight: CGFloat,
        scaleX: CGFloat,
        scaleY: CGFloat,
        alignment: Alignment
    ) -> some View {
        if bandWidth <= 0.5 || bandHeight <= 0.5 {
            Color.clear.frame(width: max(0, bandWidth), height: max(0, bandHeight))
        } else {
            Image(uiImage: image)
                .resizable()
                .frame(width: fittedWidth, height: fittedHeight)
                .scaleEffect(x: scaleX, y: scaleY)
                // Blur before clip so the mirrored edge softens into the sharp photo.
                .blur(radius: blurRadius)
                .frame(width: bandWidth, height: bandHeight, alignment: alignment)
                .clipped()
        }
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
