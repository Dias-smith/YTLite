import PhotosUI
import SwiftUI

struct AppBackgroundSettingsView: View {
    @ObservedObject private var store = AppBackgroundStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var photoItem: PhotosPickerItem?
    @State private var draftColor: Color = YTLiteColor.background

    var body: some View {
        let _ = store.revision
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
                        selected: store.preference.kind == .theme
                    )
                }
                .buttonStyle(.plain)

                ColorPicker(
                    selection: $draftColor,
                    supportsOpacity: false
                ) {
                    sourceRow(
                        title: L("background.solid_color"),
                        selected: store.preference.kind == .color
                    )
                }
                .onChange(of: draftColor) { _, color in
                    store.useSolidColor(color)
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    sourceRow(
                        title: store.image == nil
                            ? L("background.choose_photo")
                            : L("background.change_photo"),
                        selected: store.preference.kind == .image
                    )
                }
                .buttonStyle(.plain)
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task { await applyPhoto(item) }
                }

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

            if store.preference.kind == .image {
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

    private func sourceRow(title: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer(minLength: 0)
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
