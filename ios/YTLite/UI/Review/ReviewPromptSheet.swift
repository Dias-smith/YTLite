import SwiftUI

/// Custom pre-prompt before StoreKit / feedback mailto.
struct ReviewPromptSheet: View {
    @EnvironmentObject private var review: ReviewPromptCoordinator

    var body: some View {
        VStack(spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: L("review.enjoy_title"))

            Text(L("review.enjoy_body"))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.bottom, YTLiteLayout.stackLoose)

            VStack(spacing: YTLiteLayout.stackDefault) {
                YTLiteSheetPrimaryButton(title: L("review.love_it")) {
                    review.loveIt()
                }
                YTLiteSheetSecondaryButton(title: L("review.not_really")) {
                    review.notReally()
                }
                Button(L("review.later")) {
                    review.later()
                }
                .font(YTLiteType.labelEmphasized)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .padding(.vertical, YTLiteLayout.stackTight)
            }
            .padding(.bottom, 28)
        }
        .background(YTLiteColor.surfaceElevated.ignoresSafeArea())
    }
}
