import Foundation
import SwiftUI
import Combine

/// Nonisolated snapshot so `YTLiteColor` can read tokens from any context.
enum ThemeRuntime {
    nonisolated(unsafe) static var activePalette: ThemePalette = ThemeCatalog.darkClassic
}

/// Persists selected theme id + custom palettes; hydrates before first paint.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    private static let selectedIdKey = "theme_selected_id"
    private static let customPalettesKey = "theme_custom_palettes"
    private static let legacyNightKey = "night_mode_enabled"

    @Published private(set) var selectedThemeId: String
    @Published private(set) var customThemes: [ThemePalette]
    @Published private(set) var themeRevision: Int = 0

    private(set) var activePalette: ThemePalette {
        didSet { ThemeRuntime.activePalette = activePalette }
    }

    var colorScheme: ColorScheme {
        activePalette.appearance.colorScheme
    }

    var activeDisplayName: String {
        activePalette.displayName
    }

    private init() {
        let customs = Self.loadCustomThemes()
        customThemes = customs
        let id = Self.resolveInitialThemeId(customs: customs)
        let resolved = Self.resolvePalette(id: id, customs: customs) ?? ThemeCatalog.darkClassic
        selectedThemeId = resolved.id
        activePalette = resolved
        ThemeRuntime.activePalette = resolved
        // Persist resolved id (covers migration / invalid custom).
        UserDefaults.standard.set(resolved.id, forKey: Self.selectedIdKey)
    }

    func select(themeId: String) {
        guard let palette = Self.resolvePalette(id: themeId, customs: customThemes) else { return }
        selectedThemeId = themeId
        activePalette = palette
        UserDefaults.standard.set(themeId, forKey: Self.selectedIdKey)
        themeRevision += 1
    }

    @discardableResult
    func saveCustom(_ palette: ThemePalette, selectAfterSave: Bool = true) -> ThemePalette {
        var saved = palette
        saved.isBuiltIn = false
        if let idx = customThemes.firstIndex(where: { $0.id == saved.id }) {
            customThemes[idx] = saved
        } else {
            customThemes.append(saved)
        }
        persistCustomThemes()
        if selectAfterSave {
            select(themeId: saved.id)
        } else {
            themeRevision += 1
        }
        return saved
    }

    func deleteCustom(id: String) {
        customThemes.removeAll { $0.id == id }
        persistCustomThemes()
        if selectedThemeId == id {
            select(themeId: ThemeCatalog.defaultThemeId)
        } else {
            themeRevision += 1
        }
    }

    func palette(for id: String) -> ThemePalette? {
        Self.resolvePalette(id: id, customs: customThemes)
    }

    // MARK: - Persistence

    private func persistCustomThemes() {
        guard let data = try? JSONEncoder().encode(customThemes) else { return }
        UserDefaults.standard.set(data, forKey: Self.customPalettesKey)
    }

    private static func loadCustomThemes() -> [ThemePalette] {
        guard let data = UserDefaults.standard.data(forKey: customPalettesKey),
              let decoded = try? JSONDecoder().decode([ThemePalette].self, from: data)
        else { return [] }
        return decoded.filter { !$0.isBuiltIn }
    }

    private static func resolveInitialThemeId(customs: [ThemePalette]) -> String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: selectedIdKey),
           resolvePalette(id: stored, customs: customs) != nil
        {
            return stored
        }
        // Migrate legacy night mode toggle.
        if defaults.object(forKey: legacyNightKey) != nil {
            let night = defaults.bool(forKey: legacyNightKey)
            defaults.removeObject(forKey: legacyNightKey)
            return night ? "dark.classic" : "light.classic"
        }
        return ThemeCatalog.defaultThemeId
    }

    private static func resolvePalette(id: String, customs: [ThemePalette]) -> ThemePalette? {
        if let builtIn = ThemeCatalog.builtIn(id: id) { return builtIn }
        return customs.first { $0.id == id }
    }
}
