import PhotosUI
import SwiftUI

struct AppBackgroundSettingsView: View {
    @ObservedObject private var store = AppBackgroundStore.shared
    @ObservedObject private var vip = VipStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showVip = false
    @State private var draftColor: Color = YTLiteColor.background

    private var visibleKind: AppBackgroundKind {
        if store.preference.kind == .image, !vip.isVipActive { return .theme }
        return store.preference.kind
    }

    var body: some View {
        let _ = store.revision
        let _ = vip.revision
        Form {
            Section {
                previewCard
            } header: {
                Text(L("background.preview"))
            }

            Section {
                Button {
                    store.useThemeDefault()
                    draftColor = YTLiteColor.background
                } label: {
                    sourceRow(
                        title: L("background.use_theme"),
                        selected: visibleKind == .theme
                    )
                }
                .buttonStyle(.plain)

                ColorPicker(
                    selection: $draftColor,
                    supportsOpacity: false
                ) {
                    sourceRow(
                        title: L("background.solid_color"),
                        selected: visibleKind == .color
                    )
                }
                .onChange(of: draftColor) { _, color in
                    store.useSolidColor(color)
                }

                Button {
                    if vip.isVipActive {
                        showPhotoPicker = true
                    } else {
                        showVip = true
                    }
                } label: {
                    sourceRow(
                        title: store.image == nil
                            ? L("background.choose_photo")
                            : L("background.change_photo"),
                        selected: visibleKind == .image,
                        locked: !vip.isVipActive
                    )
                }
                .buttonStyle(.plain)

                if store.preference.kind == .image || store.image != nil {
                    Button(role: .destructive) {
                        store.clearImage()
                        photoItem = nil
                    } label: {
                        Text(L("background.remove_photo"))
                    }
                }
            } header: {
                Text(L("background.section_source"))
            }

            if visibleKind == .image {
                Section {
                    Picker(selection: imageModeBinding) {
                        ForEach(AppBackgroundImageMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        Text(L("background.section_mode"))
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text(L("background.section_mode"))
                }
            }

            Section {
                Button(role: .destructive) {
                    store.reset()
                    draftColor = YTLiteColor.background
                    photoItem = nil
                } label: {
                    Text(L("background.reset"))
                }
            }
        }
        .ytLiteContentWidth(
            720,
            enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass)
        )
        .scrollContentBackground(.hidden)
        .ytLiteAppBackground()
        .navigationTitle(L("background.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if store.preference.kind == .color {
                draftColor = store.preference.color.color
            } else {
                draftColor = YTLiteColor.background
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await applyPhoto(item) }
        }
        .fullScreenCover(isPresented: $showVip) {
            VipView()
        }
    }

    private var imageModeBinding: Binding<AppBackgroundImageMode> {
        Binding(
            get: { store.preference.imageMode },
            set: { store.setImageMode($0) }
        )
    }

    private var previewCard: some View {
        AppBackgroundCanvas()
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(YTLiteColor.onSurface.opacity(0.12), lineWidth: 1)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
    }

    private func sourceRow(title: String, selected: Bool, locked: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer(minLength: 0)
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(YTLiteColor.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private func applyPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { return }
            await MainActor.run {
                store.setImage(image)
            }
        } catch {
            // Leave previous wallpaper on failure.
        }
    }
}
