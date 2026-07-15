import SwiftUI

struct EditTrackMetadataSheet: View {
    let context: TrackActionContext
    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.dismiss) private var dismiss

    @State private var titleText = ""
    @State private var artistText = ""
    @State private var albumText = ""
    @State private var yearText = ""
    @State private var thumbText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    RemoteImage(url: URL(string: thumbText) ?? context.thumbnailURL)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                }

                Section("Details") {
                    TextField("Title", text: $titleText)
                    TextField("Artist", text: $artistText)
                    TextField("Album", text: $albumText)
                    TextField("Year", text: $yearText)
                    TextField("Thumbnail URL", text: $thumbText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(YTLiteColor.background)
            .navigationTitle("Edit info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { load() }
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        let meta = store?.metadata(for: context.videoId)
        titleText = meta?.customTitle ?? context.title
        artistText = meta?.customArtistName ?? context.channelName
        albumText = meta?.customAlbum ?? ""
        yearText = meta?.customYear ?? ""
        thumbText = meta?.customThumbnailUrl ?? context.thumbnailURL?.absoluteString ?? ""
    }

    private func save() {
        store?.saveMetadata(
            trackId: context.videoId,
            customTitle: titleText,
            customArtistName: artistText,
            customThumbnailUrl: thumbText,
            customAlbum: albumText,
            customYear: yearText
        )
        trackActions.showToast("Saved")
        trackActions.notifyListsChanged()
        dismiss()
    }
}
