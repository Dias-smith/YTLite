import Combine
import SwiftUI
import UIKit

enum AppBackgroundKind: String, Codable, CaseIterable, Sendable {
    case theme
    case color
    case image
}

enum AppBackgroundImageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit
    case stretch
    case tile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return L("background.mode.fill")
        case .fit: return L("background.mode.fit")
        case .stretch: return L("background.mode.stretch")
        case .tile: return L("background.mode.tile")
        }
    }
}

struct AppBackgroundPreference: Codable, Equatable, Sendable {
    var kind: AppBackgroundKind
    var color: CodableColor
    var imageFileName: String?
    var imageMode: AppBackgroundImageMode

    static let `default` = AppBackgroundPreference(
        kind: .theme,
        color: CodableColor(white: 0.08),
        imageFileName: nil,
        imageMode: .fill
    )
}

@MainActor
final class AppBackgroundStore: ObservableObject {
    static let shared = AppBackgroundStore()

    private static let defaultsKey = "app_background_preference_v1"
    private static let folderName = "app_background"
    private static let imageFileName = "wallpaper.jpg"

    @Published private(set) var preference: AppBackgroundPreference
    @Published private(set) var image: UIImage?
    @Published private(set) var revision = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppBackgroundPreference.self, from: data)
        {
            preference = decoded
        } else {
            preference = .default
        }
        image = Self.loadImageFromDisk(fileName: preference.imageFileName)
        if preference.kind == .image, image == nil {
            preference.kind = .theme
            preference.imageFileName = nil
            persist()
        }
    }

    var summaryLabel: String {
        switch preference.kind {
        case .theme: return L("background.use_theme")
        case .color: return L("background.solid_color")
        case .image: return L("background.choose_photo")
        }
    }

    func useThemeDefault() {
        preference.kind = .theme
        bump()
    }

    func useSolidColor(_ color: Color) {
        preference.kind = .color
        preference.color = CodableColor(color)
        bump()
    }

    func setImageMode(_ mode: AppBackgroundImageMode) {
        preference.imageMode = mode
        bump()
    }

    func setImage(_ uiImage: UIImage) {
        guard VipStore.shared.isVipActive else { return }
        guard let data = uiImage.jpegData(compressionQuality: 0.92) else { return }
        do {
            let url = try Self.imageURL(createDirectory: true)
            try data.write(to: url, options: .atomic)
            preference.kind = .image
            preference.imageFileName = Self.imageFileName
            image = uiImage
            bump()
        } catch {
            // Keep previous preference on write failure.
        }
    }

    func clearImage() {
        if let url = try? Self.imageURL(createDirectory: false),
           FileManager.default.fileExists(atPath: url.path)
        {
            try? FileManager.default.removeItem(at: url)
        }
        image = nil
        preference.imageFileName = nil
        if preference.kind == .image {
            preference.kind = .theme
        }
        bump()
    }

    func reset() {
        clearImage()
        preference = .default
        bump()
    }

    private func bump() {
        persist()
        revision += 1
        objectWillChange.send()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func loadImageFromDisk(fileName: String?) -> UIImage? {
        guard fileName != nil,
              let url = try? imageURL(createDirectory: false),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    private static func imageURL(createDirectory: Bool) throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(imageFileName)
    }
}
