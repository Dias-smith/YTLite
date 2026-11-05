import SwiftUI
import UIKit

enum ThemeAppearance: String, Codable, CaseIterable, Sendable {
    case light
    case dark

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }
}

/// sRGB components for persistence.
struct CodableColor: Codable, Equatable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            // Fallback for non-RGB spaces.
            let rgb = ui.cgColor.converted(
                to: CGColorSpaceCreateDeviceRGB(),
                intent: .defaultIntent,
                options: nil
            )
            let comps = rgb?.components ?? [0, 0, 0, 1]
            self.r = Double(comps.count > 0 ? comps[0] : 0)
            self.g = Double(comps.count > 1 ? comps[1] : 0)
            self.b = Double(comps.count > 2 ? comps[2] : 0)
            self.a = Double(comps.count > 3 ? comps[3] : 1)
            return
        }
        self.r = Double(r)
        self.g = Double(g)
        self.b = Double(b)
        self.a = Double(a)
    }

    init(white: Double, a: Double = 1) {
        self.init(r: white, g: white, b: white, a: a)
    }

    var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var uiColor: UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    /// Relative luminance 0…1 (sRGB).
    var luminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.065, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    static func onAccent(for accent: CodableColor) -> CodableColor {
        accent.luminance > 0.55
            ? CodableColor(white: 0.1, a: 0.85)
            : CodableColor(white: 1, a: 0.92)
    }

    static func accentDeep(from accent: CodableColor) -> CodableColor {
        CodableColor(
            r: max(0, accent.r * 0.77),
            g: max(0, accent.g * 0.80),
            b: max(0, accent.b * 0.80)
        )
    }
}

struct ThemePalette: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var nameKey: String
    var appearance: ThemeAppearance
    var isBuiltIn: Bool

    var accent: CodableColor
    var accentDeep: CodableColor
    var background: CodableColor
    var surface: CodableColor
    var surfaceElevated: CodableColor
    var surfaceChip: CodableColor
    var surfaceVariant: CodableColor
    var onSurface: CodableColor
    var onSurfaceVariant: CodableColor
    var feedMeta: CodableColor
    var miniPlayer: CodableColor
    var miniProgress: CodableColor
    var miniProgressTrack: CodableColor
    var miniMeta: CodableColor
    var tabBar: CodableColor
    var chromeDivider: CodableColor
    var searchField: CodableColor
    var danger: CodableColor
    var onAccent: CodableColor

    /// Display name: localized for built-in keys, raw for custom.
    var displayName: String {
        if isBuiltIn {
            return L(nameKey)
        }
        return nameKey
    }

    mutating func recomputeDerivedAccents() {
        accentDeep = .accentDeep(from: accent)
        onAccent = .onAccent(for: accent)
    }

    /// Copy as a new custom theme.
    func makingCustom(id: String = UUID().uuidString, name: String) -> ThemePalette {
        var copy = self
        copy.id = id
        copy.nameKey = name
        copy.isBuiltIn = false
        return copy
    }
}

enum ThemeCatalog {
    static let defaultThemeId = "dark.classic"

    static var builtIn: [ThemePalette] {
        [lightClassic, lightSoft, lightCool, lightContrast, lightSand,
         darkClassic, darkAmoled, darkSlate, darkDim, darkEmber]
    }

    static func builtIn(id: String) -> ThemePalette? {
        builtIn.first { $0.id == id }
    }

    static var lightThemes: [ThemePalette] {
        builtIn.filter { $0.appearance == .light }
    }

    static var darkThemes: [ThemePalette] {
        builtIn.filter { $0.appearance == .dark }
    }

    // MARK: - Brand constants

    private static let brandOrange = CodableColor(r: 1, g: 0.416, b: 0)
    private static let brandOrangeDeep = CodableColor(r: 0.769, g: 0.333, b: 0)
    private static let progressBlue = CodableColor(r: 0.243, g: 0.651, b: 1)
    private static let dangerRed = CodableColor(r: 1, g: 0.23, b: 0.19)

    // MARK: - Light

    static let lightClassic = ThemePalette(
        id: "light.classic",
        nameKey: "theme.light.classic",
        appearance: .light,
        isBuiltIn: true,
        accent: brandOrange,
        accentDeep: brandOrangeDeep,
        background: .init(white: 1),
        surface: .init(white: 0.96),
        surfaceElevated: .init(white: 1),
        surfaceChip: .init(white: 0.91),
        surfaceVariant: .init(white: 0.94),
        onSurface: .init(white: 0.102),
        onSurfaceVariant: .init(white: 0.42),
        feedMeta: .init(white: 0.459),
        miniPlayer: .init(white: 1),
        miniProgress: progressBlue,
        miniProgressTrack: .init(white: 0.82),
        miniMeta: .init(white: 0.459),
        tabBar: .init(white: 1),
        chromeDivider: .init(white: 0.85),
        searchField: .init(white: 0.91),
        danger: dangerRed,
        onAccent: .init(white: 0.1, a: 0.85)
    )

    /// Rose accent on blush paper — distinct from warm sand / brand orange.
    static let lightSoft = ThemePalette(
        id: "light.soft",
        nameKey: "theme.light.soft",
        appearance: .light,
        isBuiltIn: true,
        accent: CodableColor(r: 0.86, g: 0.28, b: 0.48),
        accentDeep: CodableColor(r: 0.68, g: 0.16, b: 0.36),
        background: CodableColor(r: 0.99, g: 0.95, b: 0.96),
        surface: CodableColor(r: 0.97, g: 0.91, b: 0.93),
        surfaceElevated: CodableColor(r: 1, g: 0.98, b: 0.99),
        surfaceChip: CodableColor(r: 0.94, g: 0.86, b: 0.89),
        surfaceVariant: CodableColor(r: 0.95, g: 0.88, b: 0.91),
        onSurface: CodableColor(r: 0.22, g: 0.10, b: 0.14),
        onSurfaceVariant: CodableColor(r: 0.52, g: 0.36, b: 0.42),
        feedMeta: CodableColor(r: 0.55, g: 0.40, b: 0.45),
        miniPlayer: CodableColor(r: 1, g: 0.98, b: 0.99),
        miniProgress: CodableColor(r: 0.86, g: 0.28, b: 0.48),
        miniProgressTrack: CodableColor(r: 0.90, g: 0.82, b: 0.85),
        miniMeta: CodableColor(r: 0.55, g: 0.40, b: 0.45),
        tabBar: CodableColor(r: 1, g: 0.98, b: 0.99),
        chromeDivider: CodableColor(r: 0.90, g: 0.82, b: 0.85),
        searchField: CodableColor(r: 0.94, g: 0.86, b: 0.89),
        danger: dangerRed,
        onAccent: .init(white: 1, a: 0.95)
    )

    /// Icy cyan — cool side of the spectrum.
    static let lightCool = ThemePalette(
        id: "light.cool",
        nameKey: "theme.light.cool",
        appearance: .light,
        isBuiltIn: true,
        accent: CodableColor(r: 0.0, g: 0.62, b: 0.78),
        accentDeep: CodableColor(r: 0.0, g: 0.45, b: 0.60),
        background: CodableColor(r: 0.93, g: 0.97, b: 0.99),
        surface: CodableColor(r: 0.88, g: 0.94, b: 0.97),
        surfaceElevated: CodableColor(r: 0.98, g: 1.0, b: 1.0),
        surfaceChip: CodableColor(r: 0.80, g: 0.90, b: 0.94),
        surfaceVariant: CodableColor(r: 0.84, g: 0.92, b: 0.95),
        onSurface: CodableColor(r: 0.06, g: 0.16, b: 0.22),
        onSurfaceVariant: CodableColor(r: 0.28, g: 0.42, b: 0.48),
        feedMeta: CodableColor(r: 0.32, g: 0.46, b: 0.52),
        miniPlayer: CodableColor(r: 0.98, g: 1.0, b: 1.0),
        miniProgress: CodableColor(r: 0.0, g: 0.62, b: 0.78),
        miniProgressTrack: CodableColor(r: 0.78, g: 0.88, b: 0.92),
        miniMeta: CodableColor(r: 0.32, g: 0.46, b: 0.52),
        tabBar: CodableColor(r: 0.98, g: 1.0, b: 1.0),
        chromeDivider: CodableColor(r: 0.78, g: 0.88, b: 0.92),
        searchField: CodableColor(r: 0.80, g: 0.90, b: 0.94),
        danger: dangerRed,
        onAccent: .init(white: 1, a: 0.95)
    )

    /// Stark crimson on pure white.
    static let lightContrast = ThemePalette(
        id: "light.contrast",
        nameKey: "theme.light.contrast",
        appearance: .light,
        isBuiltIn: true,
        accent: CodableColor(r: 0.82, g: 0.05, b: 0.18),
        accentDeep: CodableColor(r: 0.62, g: 0.02, b: 0.12),
        background: .init(white: 1),
        surface: .init(white: 0.97),
        surfaceElevated: .init(white: 1),
        surfaceChip: .init(white: 0.86),
        surfaceVariant: .init(white: 0.90),
        onSurface: .init(white: 0.0),
        onSurfaceVariant: .init(white: 0.22),
        feedMeta: .init(white: 0.28),
        miniPlayer: .init(white: 1),
        miniProgress: CodableColor(r: 0.82, g: 0.05, b: 0.18),
        miniProgressTrack: .init(white: 0.72),
        miniMeta: .init(white: 0.28),
        tabBar: .init(white: 1),
        chromeDivider: .init(white: 0.70),
        searchField: .init(white: 0.86),
        danger: CodableColor(r: 0.75, g: 0.0, b: 0.05),
        onAccent: .init(white: 1, a: 0.95)
    )

    /// Forest green on soft sage — formerly sand-orange.
    static let lightSand = ThemePalette(
        id: "light.sand",
        nameKey: "theme.light.sand",
        appearance: .light,
        isBuiltIn: true,
        accent: CodableColor(r: 0.18, g: 0.55, b: 0.32),
        accentDeep: CodableColor(r: 0.10, g: 0.40, b: 0.22),
        background: CodableColor(r: 0.95, g: 0.97, b: 0.93),
        surface: CodableColor(r: 0.90, g: 0.94, b: 0.88),
        surfaceElevated: CodableColor(r: 0.98, g: 0.99, b: 0.97),
        surfaceChip: CodableColor(r: 0.84, g: 0.90, b: 0.80),
        surfaceVariant: CodableColor(r: 0.87, g: 0.92, b: 0.84),
        onSurface: CodableColor(r: 0.10, g: 0.18, b: 0.12),
        onSurfaceVariant: CodableColor(r: 0.34, g: 0.44, b: 0.36),
        feedMeta: CodableColor(r: 0.38, g: 0.48, b: 0.40),
        miniPlayer: CodableColor(r: 0.98, g: 0.99, b: 0.97),
        miniProgress: CodableColor(r: 0.18, g: 0.55, b: 0.32),
        miniProgressTrack: CodableColor(r: 0.80, g: 0.86, b: 0.76),
        miniMeta: CodableColor(r: 0.38, g: 0.48, b: 0.40),
        tabBar: CodableColor(r: 0.98, g: 0.99, b: 0.97),
        chromeDivider: CodableColor(r: 0.80, g: 0.86, b: 0.76),
        searchField: CodableColor(r: 0.84, g: 0.90, b: 0.80),
        danger: dangerRed,
        onAccent: .init(white: 1, a: 0.95)
    )

    // MARK: - Dark

    static let darkClassic = ThemePalette(
        id: "dark.classic",
        nameKey: "theme.dark.classic",
        appearance: .dark,
        isBuiltIn: true,
        accent: brandOrange,
        accentDeep: brandOrangeDeep,
        background: .init(white: 0),
        surface: CodableColor(r: 0.051, g: 0.051, b: 0.051),
        surfaceElevated: CodableColor(r: 0.118, g: 0.118, b: 0.118),
        surfaceChip: CodableColor(r: 0.129, g: 0.129, b: 0.129),
        surfaceVariant: CodableColor(r: 0.165, g: 0.165, b: 0.165),
        onSurface: .init(white: 1),
        onSurfaceVariant: CodableColor(r: 0.69, g: 0.69, b: 0.69),
        feedMeta: CodableColor(r: 0.667, g: 0.667, b: 0.667),
        miniPlayer: CodableColor(r: 0.129, g: 0.129, b: 0.129),
        miniProgress: progressBlue,
        miniProgressTrack: CodableColor(r: 0.259, g: 0.259, b: 0.259),
        miniMeta: CodableColor(r: 0.667, g: 0.667, b: 0.667),
        tabBar: CodableColor(r: 0.059, g: 0.059, b: 0.059),
        chromeDivider: CodableColor(white: 1, a: 0.08),
        searchField: CodableColor(r: 0.118, g: 0.118, b: 0.118),
        danger: dangerRed,
        onAccent: .init(white: 0.1, a: 0.85)
    )

    /// Pure black with neon lime — distinct from brand orange classic.
    static let darkAmoled = ThemePalette(
        id: "dark.amoled",
        nameKey: "theme.dark.amoled",
        appearance: .dark,
        isBuiltIn: true,
        accent: CodableColor(r: 0.45, g: 0.95, b: 0.35),
        accentDeep: CodableColor(r: 0.28, g: 0.72, b: 0.20),
        background: .init(white: 0),
        surface: .init(white: 0),
        surfaceElevated: CodableColor(r: 0.06, g: 0.07, b: 0.06),
        surfaceChip: CodableColor(r: 0.10, g: 0.12, b: 0.10),
        surfaceVariant: CodableColor(r: 0.12, g: 0.14, b: 0.12),
        onSurface: .init(white: 1),
        onSurfaceVariant: CodableColor(r: 0.70, g: 0.76, b: 0.68),
        feedMeta: CodableColor(r: 0.66, g: 0.72, b: 0.64),
        miniPlayer: CodableColor(r: 0.05, g: 0.06, b: 0.05),
        miniProgress: CodableColor(r: 0.45, g: 0.95, b: 0.35),
        miniProgressTrack: CodableColor(r: 0.20, g: 0.24, b: 0.20),
        miniMeta: CodableColor(r: 0.66, g: 0.72, b: 0.64),
        tabBar: .init(white: 0),
        chromeDivider: CodableColor(white: 1, a: 0.06),
        searchField: CodableColor(r: 0.08, g: 0.09, b: 0.08),
        danger: dangerRed,
        onAccent: .init(white: 0.08, a: 0.90)
    )

    /// Deep indigo / sky blue.
    static let darkSlate = ThemePalette(
        id: "dark.slate",
        nameKey: "theme.dark.slate",
        appearance: .dark,
        isBuiltIn: true,
        accent: CodableColor(r: 0.40, g: 0.58, b: 1.0),
        accentDeep: CodableColor(r: 0.25, g: 0.38, b: 0.85),
        background: CodableColor(r: 0.04, g: 0.06, b: 0.14),
        surface: CodableColor(r: 0.08, g: 0.10, b: 0.20),
        surfaceElevated: CodableColor(r: 0.12, g: 0.16, b: 0.28),
        surfaceChip: CodableColor(r: 0.16, g: 0.20, b: 0.34),
        surfaceVariant: CodableColor(r: 0.18, g: 0.24, b: 0.38),
        onSurface: CodableColor(r: 0.92, g: 0.94, b: 1.0),
        onSurfaceVariant: CodableColor(r: 0.62, g: 0.68, b: 0.82),
        feedMeta: CodableColor(r: 0.58, g: 0.64, b: 0.78),
        miniPlayer: CodableColor(r: 0.10, g: 0.14, b: 0.24),
        miniProgress: CodableColor(r: 0.40, g: 0.58, b: 1.0),
        miniProgressTrack: CodableColor(r: 0.22, g: 0.28, b: 0.42),
        miniMeta: CodableColor(r: 0.58, g: 0.64, b: 0.78),
        tabBar: CodableColor(r: 0.05, g: 0.07, b: 0.16),
        chromeDivider: CodableColor(r: 1, g: 1, b: 1, a: 0.08),
        searchField: CodableColor(r: 0.12, g: 0.16, b: 0.28),
        danger: dangerRed,
        onAccent: .init(white: 1, a: 0.95)
    )

    /// Violet night — formerly grey Dim.
    static let darkDim = ThemePalette(
        id: "dark.dim",
        nameKey: "theme.dark.dim",
        appearance: .dark,
        isBuiltIn: true,
        accent: CodableColor(r: 0.72, g: 0.42, b: 1.0),
        accentDeep: CodableColor(r: 0.52, g: 0.25, b: 0.82),
        background: CodableColor(r: 0.08, g: 0.05, b: 0.12),
        surface: CodableColor(r: 0.13, g: 0.09, b: 0.18),
        surfaceElevated: CodableColor(r: 0.18, g: 0.13, b: 0.26),
        surfaceChip: CodableColor(r: 0.22, g: 0.16, b: 0.30),
        surfaceVariant: CodableColor(r: 0.26, g: 0.18, b: 0.34),
        onSurface: CodableColor(r: 0.96, g: 0.93, b: 1.0),
        onSurfaceVariant: CodableColor(r: 0.72, g: 0.66, b: 0.80),
        feedMeta: CodableColor(r: 0.68, g: 0.62, b: 0.76),
        miniPlayer: CodableColor(r: 0.16, g: 0.11, b: 0.22),
        miniProgress: CodableColor(r: 0.72, g: 0.42, b: 1.0),
        miniProgressTrack: CodableColor(r: 0.30, g: 0.24, b: 0.40),
        miniMeta: CodableColor(r: 0.68, g: 0.62, b: 0.76),
        tabBar: CodableColor(r: 0.10, g: 0.06, b: 0.14),
        chromeDivider: CodableColor(r: 1, g: 0.95, b: 1, a: 0.10),
        searchField: CodableColor(r: 0.18, g: 0.13, b: 0.26),
        danger: dangerRed,
        onAccent: .init(white: 1, a: 0.95)
    )

    /// Deep crimson ember on warm charcoal.
    static let darkEmber = ThemePalette(
        id: "dark.ember",
        nameKey: "theme.dark.ember",
        appearance: .dark,
        isBuiltIn: true,
        accent: CodableColor(r: 1.0, g: 0.32, b: 0.18),
        accentDeep: CodableColor(r: 0.78, g: 0.18, b: 0.08),
        background: CodableColor(r: 0.10, g: 0.04, b: 0.03),
        surface: CodableColor(r: 0.15, g: 0.07, b: 0.05),
        surfaceElevated: CodableColor(r: 0.22, g: 0.11, b: 0.08),
        surfaceChip: CodableColor(r: 0.26, g: 0.13, b: 0.09),
        surfaceVariant: CodableColor(r: 0.28, g: 0.15, b: 0.10),
        onSurface: CodableColor(r: 1.0, g: 0.94, b: 0.90),
        onSurfaceVariant: CodableColor(r: 0.78, g: 0.64, b: 0.58),
        feedMeta: CodableColor(r: 0.74, g: 0.60, b: 0.54),
        miniPlayer: CodableColor(r: 0.18, g: 0.09, b: 0.06),
        miniProgress: CodableColor(r: 1.0, g: 0.38, b: 0.20),
        miniProgressTrack: CodableColor(r: 0.34, g: 0.20, b: 0.14),
        miniMeta: CodableColor(r: 0.74, g: 0.60, b: 0.54),
        tabBar: CodableColor(r: 0.12, g: 0.05, b: 0.04),
        chromeDivider: CodableColor(r: 1, g: 0.85, b: 0.75, a: 0.10),
        searchField: CodableColor(r: 0.22, g: 0.11, b: 0.08),
        danger: dangerRed,
        onAccent: .init(white: 1, a: 0.95)
    )
}
