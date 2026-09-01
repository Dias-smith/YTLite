import Combine
import Foundation

@MainActor
final class PlaybackEqualizerStore: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { persistIfNeeded() }
    }
    @Published var selectedPresetID: String {
        didSet { persistIfNeeded() }
    }
    @Published var usesCustomBands: Bool {
        didSet { persistIfNeeded() }
    }
    @Published var customBandGainsDb: [Float] {
        didSet { persistIfNeeded() }
    }
    @Published var volumeBoostPercent: Float {
        didSet {
            let clamped = Self.clampVolumeBoost(volumeBoostPercent)
            if clamped != volumeBoostPercent {
                volumeBoostPercent = clamped
                return
            }
            persistIfNeeded()
        }
    }

    private var isRestoringState = false

    private static let enabledKey = "playback_equalizer_enabled"
    private static let presetKey = "playback_equalizer_preset"
    private static let customKey = "playback_equalizer_custom"
    private static let customGainsKey = "playback_equalizer_custom_gains"
    private static let volumeBoostKey = "playback_equalizer_volume_boost"

    init() {
        isRestoringState = true
        defer { isRestoringState = false }

        isEnabled = false
        selectedPresetID = "flat"
        usesCustomBands = false
        customBandGainsDb = PlaybackEqualizerCatalog.flatGains()
        volumeBoostPercent = PlaybackEqualizerCatalog.defaultVolumeBoostPercent

        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let storedUsesCustom = defaults.bool(forKey: Self.customKey)
        let presetID = defaults.string(forKey: Self.presetKey) ?? "flat"
        if let stored = defaults.array(forKey: Self.customGainsKey) as? [Double],
           stored.count == PlaybackEqualizerCatalog.bandCount
        {
            customBandGainsDb = stored.map(Float.init)
        } else {
            customBandGainsDb = PlaybackEqualizerCatalog.flatGains()
        }
        let storedBoost = defaults.object(forKey: Self.volumeBoostKey) as? Double
        volumeBoostPercent = Self.clampVolumeBoost(
            Float(storedBoost ?? Double(PlaybackEqualizerCatalog.defaultVolumeBoostPercent))
        )
        usesCustomBands = storedUsesCustom || PlaybackEqualizerCatalog.isCustomPreset(presetID)
        selectedPresetID = usesCustomBands ? PlaybackEqualizerCatalog.customPresetID : presetID
    }

    var activeGainsDb: [Float] {
        if usesCustomBands || PlaybackEqualizerCatalog.isCustomPreset(selectedPresetID) {
            return customBandGainsDb
        }
        return PlaybackEqualizerCatalog.preset(id: selectedPresetID)?.gainsDb ?? PlaybackEqualizerCatalog.flatGains()
    }

    var volumeBoostMultiplier: Float {
        PlaybackEqualizerCatalog.volumeBoostMultiplier(for: volumeBoostPercent)
    }

    func selectPreset(_ id: String) {
        usesCustomBands = PlaybackEqualizerCatalog.isCustomPreset(id)
        selectedPresetID = id
    }

    func setCustomBand(index: Int, gainDb: Float) {
        guard customBandGainsDb.indices.contains(index) else { return }
        if !usesCustomBands {
            customBandGainsDb = activeGainsDb
        }
        customBandGainsDb[index] = min(
            max(gainDb, PlaybackEqualizerCatalog.minGainDb),
            PlaybackEqualizerCatalog.maxGainDb
        )
        usesCustomBands = true
        selectedPresetID = PlaybackEqualizerCatalog.customPresetID
    }

    func resetCustomBands() {
        customBandGainsDb = PlaybackEqualizerCatalog.flatGains()
        usesCustomBands = false
        selectedPresetID = "flat"
    }

    private func persistIfNeeded() {
        guard !isRestoringState else { return }
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: Self.enabledKey)
        defaults.set(selectedPresetID, forKey: Self.presetKey)
        defaults.set(usesCustomBands, forKey: Self.customKey)
        defaults.set(customBandGainsDb.map(Double.init), forKey: Self.customGainsKey)
        defaults.set(Double(volumeBoostPercent), forKey: Self.volumeBoostKey)
    }

    private static func clampVolumeBoost(_ value: Float) -> Float {
        min(max(value, PlaybackEqualizerCatalog.minVolumeBoostPercent), PlaybackEqualizerCatalog.maxVolumeBoostPercent)
    }
}
