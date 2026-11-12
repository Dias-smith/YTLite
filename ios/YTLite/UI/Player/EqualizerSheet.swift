import SwiftUI

struct EqualizerSheet: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var equalizerStore: PlaybackEqualizerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if playback.isPlayingHLS {
                    Text(L("equalizer.live_unavailable"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .listRowBackground(YTLiteColor.surfaceElevated)
                }

                Section(L("equalizer.presets")) {
                    EqualizerPresetChipRow(
                        presets: PlaybackEqualizerCatalog.presets,
                        selectedPresetID: equalizerStore.selectedPresetID,
                        disabled: playback.isPlayingHLS,
                        onSelect: { presetID in
                            equalizerStore.selectPreset(presetID)
                            playback.refreshEqualizer()
                        }
                    )
                    .listRowBackground(YTLiteColor.surfaceElevated)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(0..<PlaybackEqualizerCatalog.bandCount, id: \.self) { index in
                                EqualizerBandSlider(
                                    frequencyHz: PlaybackEqualizerCatalog.bandFrequenciesHz[index],
                                    gainDb: binding(for: index)
                                )
                                .disabled(playback.isPlayingHLS || !equalizerStore.isEnabled)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .id(equalizerStore.selectedPresetID)
                    .frame(height: 360)
                    .listRowBackground(YTLiteColor.surfaceElevated)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                    Button(L("equalizer.reset_custom")) {
                        equalizerStore.resetCustomBands()
                        playback.refreshEqualizer()
                    }
                    .foregroundStyle(YTLiteColor.accent)
                    .disabled(playback.isPlayingHLS)
                    .listRowBackground(YTLiteColor.surfaceElevated)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("equalizer.volume_boost"))
                                .foregroundStyle(YTLiteColor.onSurface)
                            Spacer()
                            Text(Lf("equalizer.volume_boost_value", Int(equalizerStore.volumeBoostPercent)))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }
                        EqualizerVolumeSlider(
                            value: $equalizerStore.volumeBoostPercent,
                            range: PlaybackEqualizerCatalog.minVolumeBoostPercent...PlaybackEqualizerCatalog.maxVolumeBoostPercent,
                            step: 5
                        )
                        .disabled(playback.isPlayingHLS)
                        .onChange(of: equalizerStore.volumeBoostPercent) { _, _ in
                            playback.refreshEqualizer()
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(YTLiteColor.surfaceElevated)
                    .listRowSeparator(.hidden, edges: .bottom)
                    .listSectionSeparator(.hidden, edges: .bottom)
                } footer: {
                    Text(L("equalizer.airplay_notice"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            }
            .scrollContentBackground(.hidden)
            .background(YTLiteColor.surfaceElevated)
            .navigationTitle(L("equalizer.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Toggle("", isOn: $equalizerStore.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(YTLiteColor.accent)
                        .disabled(playback.isPlayingHLS)
                        .fixedSize()
                        .padding(.trailing, 6)
                }
            }
            .toolbarBackground(YTLiteColor.surfaceElevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: equalizerStore.isEnabled) { _, _ in
                playback.refreshEqualizer()
            }
        }
    }

    private func binding(for index: Int) -> Binding<Float> {
        Binding(
            get: { equalizerStore.activeGainsDb[index] },
            set: { newValue in
                equalizerStore.setCustomBand(index: index, gainDb: newValue)
                playback.refreshEqualizer()
            }
        )
    }
}

private struct EqualizerPresetChipRow: View {
    let presets: [PlaybackEqualizerPreset]
    let selectedPresetID: String
    let disabled: Bool
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        EqualizerPresetChip(
                            title: L(preset.nameKey),
                            selected: selectedPresetID == preset.id,
                            disabled: disabled
                        ) {
                            onSelect(preset.id)
                        }
                        .id(preset.id)
                    }
                }
            }
            .onAppear {
                scrollToSelectedPreset(using: proxy, animated: false)
            }
            .onChange(of: selectedPresetID) { _, _ in
                scrollToSelectedPreset(using: proxy, animated: true)
            }
        }
    }

    private func scrollToSelectedPreset(using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(selectedPresetID, anchor: .center)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        } else {
            DispatchQueue.main.async {
                action()
            }
        }
    }
}

private struct EqualizerPresetChip: View {
    let title: String
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(selected ? YTLiteType.labelEmphasized : YTLiteType.label)
                .foregroundStyle(selected ? YTLiteColor.onAccent : YTLiteColor.onSurface)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, YTLiteLayout.chipHorizontal)
                .padding(.vertical, YTLiteLayout.chipVertical)
                .background(
                    Capsule()
                        .fill(selected ? YTLiteColor.accent : YTLiteColor.surfaceChip)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct EqualizerVolumeSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float

    private let trackHeight: CGFloat = 3
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumbX = thumbCenterX(in: width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(YTLiteColor.onSurfaceVariant.opacity(0.22))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(YTLiteColor.accent)
                    .frame(width: max(thumbX, 0), height: trackHeight)
                Circle()
                    .fill(Color(white: 0.82))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: thumbX, y: geo.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = snappedValue(value(fromX: gesture.location.x, in: width))
                    }
            )
        }
        .frame(height: 24)
        .accessibilityLabel(L("equalizer.volume_boost"))
        .accessibilityValue(Lf("equalizer.volume_boost_value", Int(value)))
    }

    private func thumbCenterX(in width: CGFloat) -> CGFloat {
        let travel = max(width - thumbSize, 1)
        return normalizedValue * travel + thumbSize / 2
    }

    private var normalizedValue: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    private func value(fromX x: CGFloat, in width: CGFloat) -> Float {
        let travel = max(width - thumbSize, 1)
        let clampedX = min(max(x, thumbSize / 2), width - thumbSize / 2)
        let normalized = (clampedX - thumbSize / 2) / travel
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + Float(normalized) * span
    }

    private func snappedValue(_ raw: Float) -> Float {
        let stepped = round(raw / step) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

private struct EqualizerBandSlider: View {
    let frequencyHz: Int
    @Binding var gainDb: Float

    private let trackHeight: CGFloat = 320
    private let thumbSize: CGFloat = 14
    private let trackWidth: CGFloat = 3

    private var label: String {
        if frequencyHz >= 1000 {
            return "\(frequencyHz / 1000)k"
        }
        return "\(frequencyHz)"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%+.0f", gainDb))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(height: 12)

            GeometryReader { geo in
                let height = geo.size.height
                let thumbY = thumbCenterY(in: height)
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(YTLiteColor.onSurfaceVariant.opacity(0.22))
                        .frame(width: trackWidth, height: max(thumbY, 0))
                    Capsule()
                        .fill(YTLiteColor.accent)
                        .frame(width: trackWidth, height: max(height - thumbY, 0))
                        .offset(y: thumbY)
                    Circle()
                        .fill(Color(white: 0.82))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                        )
                        .frame(width: thumbSize, height: thumbSize)
                        .position(x: geo.size.width / 2, y: thumbY)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            gainDb = gainDb(fromY: value.location.y, in: height)
                        }
                )
            }
            .frame(width: 28, height: trackHeight)

            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .frame(width: 28)
    }

    private func thumbCenterY(in height: CGFloat) -> CGFloat {
        let travel = max(height - thumbSize, 1)
        let normalized = normalizedGain
        return (1 - normalized) * travel + thumbSize / 2
    }

    private var normalizedGain: CGFloat {
        let range = PlaybackEqualizerCatalog.maxGainDb - PlaybackEqualizerCatalog.minGainDb
        guard range > 0 else { return 0.5 }
        return CGFloat((gainDb - PlaybackEqualizerCatalog.minGainDb) / range)
    }

    private func gainDb(fromY y: CGFloat, in height: CGFloat) -> Float {
        let travel = max(height - thumbSize, 1)
        let clampedY = min(max(y, thumbSize / 2), height - thumbSize / 2)
        let normalized = 1 - ((clampedY - thumbSize / 2) / travel)
        let range = PlaybackEqualizerCatalog.maxGainDb - PlaybackEqualizerCatalog.minGainDb
        let raw = Float(normalized) * range + PlaybackEqualizerCatalog.minGainDb
        return min(max(raw, PlaybackEqualizerCatalog.minGainDb), PlaybackEqualizerCatalog.maxGainDb)
    }
}
