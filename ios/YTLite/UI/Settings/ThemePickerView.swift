import SwiftUI

private enum ThemeRewardAction {
    case select(String)
    case create
    case edit(ThemePalette)
}

struct ThemePickerView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var themes = ThemeStore.shared
    @ObservedObject private var rewardUnlocks = RewardUnlockStore.shared
    @State private var editorDraft: ThemeEditorDraft?
    @State private var pendingRewardAction: ThemeRewardAction?
    @State private var showRewardPrompt = false
    @State private var rewardErrorText: String?

    var body: some View {
        List {
            Section(L("theme.section.light")) {
                ForEach(ThemeCatalog.lightThemes) { palette in
                    themeRow(palette)
                }
            }
            Section(L("theme.section.dark")) {
                ForEach(ThemeCatalog.darkThemes) { palette in
                    themeRow(palette)
                }
            }
            Section(L("theme.section.custom")) {
                if themes.customThemes.isEmpty {
                    Text(L("theme.custom.empty"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                } else {
                    ForEach(themes.customThemes) { palette in
                        themeRow(palette, allowsEdit: true)
                    }
                    .onDelete(perform: deleteCustoms)
                }
                Button {
                    requestRewardedAction(.create)
                } label: {
                    HStack {
                        Label(L("theme.custom.create"), systemImage: "plus.circle.fill")
                            .foregroundStyle(YTLiteColor.accent)
                        Spacer()
                        if !themesUnlockedToday {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }
                    }
                }
                .listRowBackground(YTLiteColor.surfaceElevated)
            }
        }
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.background)
        .navigationTitle(L("theme.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            AdSceneLifecycle.setUIBlocked("theme_picker", blocked: true)
        }
        .onDisappear {
            AdSceneLifecycle.setUIBlocked("theme_picker", blocked: false)
        }
        .alert(
            L("ad.reward.theme_title"),
            isPresented: $showRewardPrompt
        ) {
            Button(L("ad.reward.watch")) { presentThemeRewardedAd() }
            Button(L("common.cancel"), role: .cancel) { pendingRewardAction = nil }
        } message: {
            Text(L("ad.reward.theme_message"))
        }
        .alert(
            rewardErrorText ?? "",
            isPresented: Binding(
                get: { rewardErrorText != nil },
                set: { if !$0 { rewardErrorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $editorDraft) { draft in
            NavigationStack {
                ThemeEditorView(draft: draft) { saved in
                    themes.saveCustom(saved, selectAfterSave: true)
                    editorDraft = nil
                } onCancel: {
                    editorDraft = nil
                }
            }
            // Editor chrome follows the *app* theme, not the draft palette
            // (draft colors are only shown in the preview card).
            .preferredColorScheme(appModel.themeColorScheme)
            .presentationDetents([.large])
            .presentationBackground(YTLiteColor.surfaceElevated)
        }
    }

    private func themeRow(_ palette: ThemePalette, allowsEdit: Bool = false) -> some View {
        Button {
            requestThemeSelection(palette)
        } label: {
            HStack(spacing: 12) {
                ThemeSwatch(palette: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.displayName)
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurface)
                    Text(palette.appearance == .dark ? L("theme.appearance.dark") : L("theme.appearance.light"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
                Spacer(minLength: 0)
                if themes.selectedThemeId == palette.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(YTLiteColor.accent)
                }
                if requiresReward(palette), !themesUnlockedToday {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
                if allowsEdit {
                    Button {
                        requestRewardedAction(.edit(palette))
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(YTLiteColor.surfaceElevated)
    }

    private var themesUnlockedToday: Bool {
        _ = rewardUnlocks.revision
        return rewardUnlocks.isUnlockedToday(.themes)
    }

    private func requiresReward(_ palette: ThemePalette) -> Bool {
        palette.id != ThemeCatalog.lightClassic.id
            && palette.id != ThemeCatalog.darkClassic.id
    }

    private func requestThemeSelection(_ palette: ThemePalette) {
        if !requiresReward(palette) || themesUnlockedToday {
            appModel.selectTheme(id: palette.id)
        } else {
            requestRewardedAction(.select(palette.id))
        }
    }

    private func requestRewardedAction(_ action: ThemeRewardAction) {
        if themesUnlockedToday {
            perform(action)
        } else {
            pendingRewardAction = action
            showRewardPrompt = true
        }
    }

    private func presentThemeRewardedAd() {
        let didPresent = RewardedInterstitialAdManager.shared.show(
            reason: "reward_theme"
        ) { earned in
            guard earned else {
                rewardErrorText = L("ad.reward.not_earned")
                pendingRewardAction = nil
                return
            }
            rewardUnlocks.unlockToday(.themes)
            if let pendingRewardAction {
                perform(pendingRewardAction)
            }
            pendingRewardAction = nil
        }
        if !didPresent {
            rewardErrorText = L("ad.reward.not_ready")
            pendingRewardAction = nil
        }
    }

    private func perform(_ action: ThemeRewardAction) {
        switch action {
        case .select(let id):
            appModel.selectTheme(id: id)
        case .create:
            let base = themes.activePalette
            editorDraft = ThemeEditorDraft(
                palette: base.makingCustom(name: L("theme.custom.default_name")),
                isNew: true
            )
        case .edit(let palette):
            editorDraft = ThemeEditorDraft(palette: palette, isNew: false)
        }
    }

    private func deleteCustoms(at offsets: IndexSet) {
        for index in offsets {
            let id = themes.customThemes[index].id
            themes.deleteCustom(id: id)
        }
    }
}

struct ThemeSwatch: View {
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 0) {
            palette.accent.color
            palette.surface.color
            palette.background.color
        }
        .frame(width: 48, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(YTLiteColor.chromeDivider, lineWidth: 1)
        )
    }
}

struct ThemeEditorDraft: Identifiable {
    var id: String { palette.id }
    var palette: ThemePalette
    var isNew: Bool
}

struct ThemeEditorView: View {
    @State private var palette: ThemePalette
    let isNew: Bool
    var onSave: (ThemePalette) -> Void
    var onCancel: () -> Void

    init(draft: ThemeEditorDraft, onSave: @escaping (ThemePalette) -> Void, onCancel: @escaping () -> Void) {
        _palette = State(initialValue: draft.palette)
        self.isNew = draft.isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        Form {
            Section {
                TextField(L("theme.editor.name"), text: $palette.nameKey)
                    .foregroundStyle(YTLiteColor.onSurface)
                Picker(L("theme.editor.appearance"), selection: $palette.appearance) {
                    Text(L("theme.appearance.light")).tag(ThemeAppearance.light)
                    Text(L("theme.appearance.dark")).tag(ThemeAppearance.dark)
                }
                .tint(YTLiteColor.accent)
                .onChange(of: palette.appearance) { _, newValue in
                    applyBase(for: newValue)
                }
            } header: {
                sectionHeader(L("theme.editor.basics"))
            }
            .listRowBackground(YTLiteColor.surfaceElevated)

            Section {
                ThemePreviewCard(palette: palette)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                sectionHeader(L("theme.editor.preview"))
            }
            .listRowBackground(Color.clear)

            Section {
                colorRow(L("theme.token.accent"), keyPath: \.accent) {
                    palette.recomputeDerivedAccents()
                }
                colorRow(L("theme.token.background"), keyPath: \.background)
                colorRow(L("theme.token.surface"), keyPath: \.surface)
                colorRow(L("theme.token.surface_elevated"), keyPath: \.surfaceElevated)
                colorRow(L("theme.token.surface_variant"), keyPath: \.surfaceVariant)
                colorRow(L("theme.token.on_surface"), keyPath: \.onSurface)
                colorRow(L("theme.token.on_surface_variant"), keyPath: \.onSurfaceVariant)
            } header: {
                sectionHeader(L("theme.editor.colors"))
            }
            .listRowBackground(YTLiteColor.surfaceElevated)

            Section {
                ForEach(ThemeCatalog.builtIn.filter { $0.appearance == palette.appearance }) { base in
                    Button {
                        let name = palette.nameKey
                        let id = palette.id
                        palette = base.makingCustom(id: id, name: name.isEmpty ? base.displayName : name)
                    } label: {
                        HStack {
                            ThemeSwatch(palette: base)
                            Text(base.displayName)
                                .foregroundStyle(YTLiteColor.onSurface)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                sectionHeader(L("theme.editor.start_from"))
            }
            .listRowBackground(YTLiteColor.surfaceElevated)
        }
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.background)
        .tint(YTLiteColor.accent)
        .navigationTitle(isNew ? L("theme.custom.create") : L("theme.editor.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.surfaceElevated, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("common.cancel"), action: onCancel)
                    .foregroundStyle(YTLiteColor.onSurface)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("common.save")) {
                    var saved = palette
                    let trimmed = saved.nameKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    saved.nameKey = trimmed.isEmpty ? L("theme.custom.default_name") : trimmed
                    saved.isBuiltIn = false
                    saved.recomputeDerivedAccents()
                    // Keep secondary surfaces in sync when user only tweaks mains.
                    saved.surfaceChip = saved.surfaceVariant
                    saved.miniPlayer = saved.surfaceElevated
                    saved.tabBar = saved.surfaceElevated
                    saved.searchField = saved.surfaceVariant
                    saved.miniMeta = saved.onSurfaceVariant
                    saved.feedMeta = saved.onSurfaceVariant
                    saved.chromeDivider = saved.appearance == .dark
                        ? CodableColor(white: 1, a: 0.08)
                        : CodableColor(white: 0.85)
                    saved.miniProgressTrack = saved.appearance == .dark
                        ? CodableColor(white: 0.26)
                        : CodableColor(white: 0.82)
                    onSave(saved)
                }
                .disabled(palette.nameKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(YTLiteType.labelEmphasized)
                .foregroundStyle(YTLiteColor.accent)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(YTLiteType.meta)
            .foregroundStyle(YTLiteColor.onSurfaceVariant)
            .textCase(nil)
    }

    private func colorRow(
        _ title: String,
        keyPath: WritableKeyPath<ThemePalette, CodableColor>,
        onChange: (() -> Void)? = nil
    ) -> some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { palette[keyPath: keyPath].color },
                set: { newValue in
                    palette[keyPath: keyPath] = CodableColor(newValue)
                    onChange?()
                }
            ),
            supportsOpacity: false
        )
        .foregroundStyle(YTLiteColor.onSurface)
    }

    private func applyBase(for appearance: ThemeAppearance) {
        let base = appearance == .dark ? ThemeCatalog.darkClassic : ThemeCatalog.lightClassic
        let name = palette.nameKey
        let id = palette.id
        palette = base.makingCustom(id: id, name: name)
        palette.appearance = appearance
    }
}

private struct ThemePreviewCard: View {
    let palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(palette.displayName)
                .font(YTLiteType.rowTitle)
                .foregroundStyle(palette.onSurface.color)
            Text(L("theme.editor.preview_hint"))
                .font(YTLiteType.meta)
                .foregroundStyle(palette.onSurfaceVariant.color)
            HStack(spacing: 8) {
                Text(L("theme.editor.preview_chip"))
                    .font(YTLiteType.label)
                    .foregroundStyle(palette.onAccent.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.accent.color, in: Capsule())
                Text(L("theme.editor.preview_chip"))
                    .font(YTLiteType.label)
                    .foregroundStyle(palette.onSurface.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.surfaceChip.color, in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(palette.chromeDivider.color, lineWidth: 1)
        )
    }
}
