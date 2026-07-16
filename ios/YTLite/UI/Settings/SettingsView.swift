import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        Form {
            Section(L("settings.appearance")) {
                Toggle(L("settings.night_mode"), isOn: $appModel.nightModeEnabled)
                Picker(L("settings.language"), selection: $appModel.languageCode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
            }

            Section {
                Picker(L("settings.speed"), selection: $playback.playbackSpeed) {
                    ForEach(PlaybackSpeeds.options, id: \.self) { speed in
                        Text(PlaybackSpeeds.formatLabel(speed)).tag(speed)
                    }
                }

                Picker(L("settings.sleep_timer"), selection: sleepTimerSelection) {
                    Text(SleepTimerOptions.formatLabel(minutes: nil)).tag(Optional<Int>.none)
                    ForEach(SleepTimerOptions.minutesOptions, id: \.self) { minutes in
                        Text(SleepTimerOptions.formatLabel(minutes: minutes)).tag(Optional(minutes))
                    }
                }

                if let remaining = playback.sleepTimerRemaining,
                   playback.sleepTimerEndsAt != nil
                {
                    LabeledContent(L("settings.remaining"), value: SleepTimerOptions.formatRemaining(remaining))
                }
            } header: {
                Text(L("settings.playback"))
            } footer: {
                if playback.sleepTimerEndsAt != nil {
                    Text(L("settings.sleep_footer_active"))
                } else {
                    Text(L("settings.sleep_footer_idle"))
                }
            }

            Section(L("settings.about")) {
                LabeledContent(L("settings.bundle"), value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent(
                    L("settings.supabase"),
                    value: appModel.config.isConfigured ? L("settings.configured") : L("settings.missing_secrets")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.background)
        .navigationTitle(L("settings.title"))
    }

    private var sleepTimerSelection: Binding<Int?> {
        Binding(
            get: { playback.sleepTimerMinutes },
            set: { playback.setSleepTimer(minutes: $0) }
        )
    }
}
