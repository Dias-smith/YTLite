import SwiftUI
import PhotosUI
import UIKit

struct EditTrackMetadataSheet: View {
    let context: TrackActionContext
    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var rewardUnlocks = RewardUnlockStore.shared

    @State private var titleText = ""
    @State private var artistText = ""
    @State private var albumText = ""
    @State private var yearText = ""
    /// Persisted thumbnail: https URL or `localthumb:` token.
    @State private var thumbText = ""
    @State private var showArtworkOptions = false
    @State private var showPhotoPicker = false
    @State private var showWebImageSheet = false
    @State private var webURLDraft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var previewRevision = 0
    @State private var showSaveRewardPrompt = false
    @State private var isPresentingReward = false

    private var previewURL: URL? {
        _ = previewRevision
        return TrackThumbnailStorage.resolveURL(thumbText) ?? context.thumbnailURL
    }

    var body: some View {
        VStack(spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: L("action.edit_info"))

            ScrollView {
                VStack(alignment: .leading, spacing: YTLiteLayout.stackLoose) {
                    artworkSection

                    fieldLabel(L("action.field_title"))
                    YTLiteSheetField(placeholder: L("action.field_title"), text: $titleText)

                    fieldLabel(L("action.field_artist"))
                    YTLiteSheetField(placeholder: L("action.field_artist"), text: $artistText)

                    fieldLabel(L("action.field_album"))
                    YTLiteSheetField(placeholder: L("action.field_album"), text: $albumText)

                    fieldLabel(L("action.field_year"))
                    YTLiteSheetField(placeholder: L("action.field_year"), text: $yearText)
                }
                .padding(.top, 4)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                YTLiteSheetPrimaryButton(
                    title: L("common.save"),
                    enabled: !isPresentingReward,
                    action: requestSave
                )
                YTLiteSheetSecondaryButton(title: L("common.cancel")) { dismiss() }
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(YTLiteColor.surfaceElevated)
        .onAppear {
            load()
            AdSceneLifecycle.setUIBlocked("edit_track_info", blocked: true)
        }
        .onDisappear {
            AdSceneLifecycle.setUIBlocked("edit_track_info", blocked: false)
        }
        .alert(
            L("ad.reward.edit_title"),
            isPresented: $showSaveRewardPrompt
        ) {
            Button(L("ad.reward.watch")) { presentRewardedAdForSave() }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("ad.reward.edit_message"))
        }
        .sheet(isPresented: $showArtworkOptions) {
            ChangeArtworkOptionsSheet(
                onChoosePhoto: {
                    showArtworkOptions = false
                    showPhotoPicker = true
                },
                onWebImage: {
                    showArtworkOptions = false
                    webURLDraft = thumbText.hasPrefix("http") ? thumbText : ""
                    showWebImageSheet = true
                }
            )
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await applyPhoto(item) }
        }
        .sheet(isPresented: $showWebImageSheet) {
            webImageSheet
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(YTLiteType.meta)
            .foregroundStyle(YTLiteColor.onSurfaceVariant)
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.top, 4)
    }

    private var artworkSection: some View {
        ZStack(alignment: .bottomTrailing) {
            RemoteImage(url: previewURL)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(width: 32, height: 32)
                .background(YTLiteColor.surfaceElevated.opacity(0.92), in: Circle())
                .padding(10)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .contentShape(Rectangle())
        .onTapGesture { showArtworkOptions = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L("action.change_artwork"))
    }

    private var webImageSheet: some View {
        VStack(spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: L("action.web_image"))

            Text(L("action.paste_image_link"))
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.bottom, 8)

            YTLiteSheetField(
                placeholder: "Image URL",
                text: $webURLDraft,
                keyboardType: .URL,
                autocapitalization: .never,
                disableAutocorrection: true
            )

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                YTLiteSheetPrimaryButton(
                    title: L("common.apply"),
                    enabled: isValidWebURL(webURLDraft),
                    action: applyWebURL
                )
                YTLiteSheetSecondaryButton(title: L("common.cancel")) { showWebImageSheet = false }
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(YTLiteColor.surfaceElevated)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(YTLiteColor.surfaceElevated)
    }

    private func load() {
        let meta = store?.metadata(for: context.videoId)
        titleText = meta?.customTitle ?? context.title
        artistText = meta?.customArtistName ?? context.channelName
        albumText = meta?.customAlbum ?? ""
        yearText = meta?.customYear ?? ""
        thumbText = meta?.customThumbnailUrl ?? context.thumbnailURL?.absoluteString ?? ""
        previewRevision += 1
    }

    private func applyWebURL() {
        let cleaned = webURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidWebURL(cleaned) else { return }
        replaceThumb(with: cleaned)
        showWebImageSheet = false
    }

    private func applyPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let token = TrackThumbnailStorage.save(image, trackId: context.videoId)
            else {
                await MainActor.run {
                    trackActions.showToast(L("error.artwork_update"))
                }
                return
            }
            await MainActor.run {
                replaceThumb(with: token)
            }
        } catch {
            await MainActor.run {
                trackActions.showToast(L("error.artwork_update"))
            }
        }
    }

    private func replaceThumb(with newValue: String) {
        let previous = thumbText
        if previous != newValue, TrackThumbnailStorage.isLocalPath(previous) {
            if TrackThumbnailStorage.token(for: context.videoId) != newValue {
                TrackThumbnailStorage.deleteIfLocal(previous)
            }
        }
        thumbText = newValue
        previewRevision += 1
    }

    private func requestSave() {
        if rewardUnlocks.isUnlockedToday(.editInfo) {
            commitSave()
        } else {
            showSaveRewardPrompt = true
        }
    }

    private func presentRewardedAdForSave() {
        isPresentingReward = true
        let didPresent = RewardedInterstitialAdManager.shared.show(
            reason: "reward_edit_info"
        ) { earned in
            isPresentingReward = false
            guard earned else {
                trackActions.showToast(L("ad.reward.not_earned"))
                return
            }
            rewardUnlocks.unlockToday(.editInfo)
            commitSave()
        }
        if !didPresent {
            isPresentingReward = false
            trackActions.showToast(L("ad.reward.not_ready"))
        }
    }

    private func commitSave() {
        let previous = store?.metadata(for: context.videoId)?.customThumbnailUrl
        let cleanedThumb = thumbText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let previous, previous != cleanedThumb {
            TrackThumbnailStorage.deleteIfLocal(previous)
        }
        store?.saveMetadata(
            trackId: context.videoId,
            customTitle: titleText,
            customArtistName: artistText,
            customThumbnailUrl: cleanedThumb,
            customAlbum: albumText,
            customYear: yearText
        )
        trackActions.showToast(L("toast.saved"))
        trackActions.notifyListsChanged()
        dismiss()
    }

    private func isValidWebURL(_ raw: String) -> Bool {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return false }
        return true
    }
}

private struct ChangeArtworkOptionsSheet: View {
    var onChoosePhoto: () -> Void
    var onWebImage: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: L("action.change_artwork"))
            Divider().overlay(YTLiteColor.surfaceVariant)
            YTLiteSheetActionRow(systemImage: "photo", title: L("action.photo_library"), action: onChoosePhoto)
            YTLiteSheetActionRow(systemImage: "link", title: L("action.web_image"), action: onWebImage)
            YTLiteSheetActionRow(systemImage: "xmark", title: L("common.cancel")) { dismiss() }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(YTLiteColor.surfaceElevated)
    }
}

/// Local custom track artwork under Application Support (`localthumb:{trackId}`).
enum TrackThumbnailStorage {
    private static let tokenPrefix = "localthumb:"

    static func token(for trackId: String) -> String {
        "\(tokenPrefix)\(trackId)"
    }

    static func resolveURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if let trackId = trackId(fromLocalToken: raw) {
            return existingFileURL(for: trackId)
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            if FileManager.default.fileExists(atPath: url.path) { return url }
            return existingFileURL(for: url.deletingPathExtension().lastPathComponent)
        }
        if raw.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: raw) {
                return URL(fileURLWithPath: raw)
            }
            let name = URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
            return existingFileURL(for: name)
        }
        return URL(string: raw)
    }

    static func isLocalPath(_ raw: String) -> Bool {
        raw.hasPrefix(tokenPrefix) || raw.hasPrefix("/") || raw.hasPrefix("file://")
    }

    static func save(_ image: UIImage, trackId: String) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return nil }
        let dir = thumbsDirectory()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: trackId), options: .atomic)
            return token(for: trackId)
        } catch {
            return nil
        }
    }

    static func deleteIfLocal(_ raw: String) {
        guard isLocalPath(raw) else { return }
        if let trackId = trackId(fromLocalToken: raw) {
            try? FileManager.default.removeItem(at: fileURL(for: trackId))
            return
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if raw.hasPrefix("/") {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: raw))
        }
    }

    private static func trackId(fromLocalToken raw: String) -> String? {
        guard raw.hasPrefix(tokenPrefix) else { return nil }
        let id = String(raw.dropFirst(tokenPrefix.count))
        return id.isEmpty ? nil : id
    }

    private static func fileURL(for trackId: String) -> URL {
        thumbsDirectory().appendingPathComponent("\(trackId).jpg")
    }

    private static func existingFileURL(for trackId: String) -> URL? {
        guard !trackId.isEmpty else { return nil }
        let file = fileURL(for: trackId)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private static func thumbsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("track_thumbnails", isDirectory: true)
    }
}
