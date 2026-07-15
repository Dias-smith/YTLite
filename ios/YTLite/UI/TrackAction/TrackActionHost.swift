import SwiftUI

/// Attaches global track-action sheets + toast to any root content.
struct TrackActionHost<Content: View>: View {
    @StateObject private var presenter = TrackActionPresenter()
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environmentObject(presenter)
            .sheet(isPresented: $presenter.showActions) {
                if let context = presenter.context {
                    TrackActionSheet(context: context)
                        .environmentObject(presenter)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.hidden)
                }
            }
            .sheet(isPresented: $presenter.showPlaylistPicker) {
                if let context = presenter.context {
                    PlaylistPickerSheet(item: context.asVideoItem)
                        .environmentObject(presenter)
                }
            }
            .sheet(isPresented: $presenter.showEditInfo) {
                if let context = presenter.context {
                    EditTrackMetadataSheet(context: context)
                        .environmentObject(presenter)
                }
            }
            .sheet(isPresented: $presenter.showLyrics) {
                if let context = presenter.context {
                    TrackLyricsSheet(videoId: context.videoId)
                }
            }
            .overlay(alignment: .bottom) {
                if let message = presenter.toastMessage {
                    Text(message)
                        .font(YTLiteType.meta.weight(.semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(YTLiteColor.surfaceElevated, in: Capsule())
                        .padding(.bottom, 88)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeOut(duration: 0.2), value: presenter.toastMessage)
                }
            }
    }
}
