import Foundation

struct PlaybackEqualizerPreset: Identifiable, Equatable, Sendable {
    let id: String
    let nameKey: String
    let gainsDb: [Float]
}

enum PlaybackEqualizerCatalog {
    static let customPresetID = "custom"
    static let bandCount = 10
    static let minGainDb: Float = -12
    static let maxGainDb: Float = 12
    static let minVolumeBoostPercent: Float = 100
    static let maxVolumeBoostPercent: Float = 500
    static let defaultVolumeBoostPercent: Float = 100

    static func volumeBoostMultiplier(for percent: Float) -> Float {
        min(max(percent, minVolumeBoostPercent), maxVolumeBoostPercent) / 100
    }

    static let bandFrequenciesHz: [Int] = {
        guard let catalog = loadCatalog() else {
            return [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        }
        return catalog.bandFrequenciesHz
    }()

    static let presets: [PlaybackEqualizerPreset] = {
        let loaded: [PlaybackEqualizerPreset]
        if let catalog = loadCatalog() {
            loaded = catalog.presets.map {
                PlaybackEqualizerPreset(id: $0.id, nameKey: $0.nameKey, gainsDb: $0.gainsDb.map(Float.init))
            }
        } else {
            loaded = fallbackPresets
        }
        return loaded + [customPreset]
    }()

    static func isCustomPreset(_ id: String) -> Bool {
        id == customPresetID
    }

    static func preset(id: String) -> PlaybackEqualizerPreset? {
        if isCustomPreset(id) { return customPreset }
        return presets.first { $0.id == id && !isCustomPreset($0.id) }
    }

    static func flatGains() -> [Float] {
        Array(repeating: 0, count: bandCount)
    }

    private struct CatalogDTO: Decodable {
        let bandFrequenciesHz: [Int]
        let presets: [PresetDTO]
    }

    private struct PresetDTO: Decodable {
        let id: String
        let nameKey: String
        let gainsDb: [Double]
    }

    private static func loadCatalog() -> CatalogDTO? {
        guard let url = Bundle.main.url(forResource: "playback_equalizer_presets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CatalogDTO.self, from: data),
              decoded.presets.allSatisfy({ $0.gainsDb.count == bandCount })
        else { return nil }
        return decoded
    }

    private static let fallbackPresets: [PlaybackEqualizerPreset] = [
        PlaybackEqualizerPreset(id: "flat", nameKey: "equalizer.preset.flat", gainsDb: flatGains()),
    ]

    private static let customPreset = PlaybackEqualizerPreset(
        id: customPresetID,
        nameKey: "equalizer.preset.custom",
        gainsDb: flatGains()
    )
}
