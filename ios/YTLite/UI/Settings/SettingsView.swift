import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Night mode", isOn: $appModel.nightModeEnabled)
                Picker("Language", selection: $appModel.languageCode) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
            }

            Section {
                Picker("Speed", selection: $playback.playbackSpeed) {
                    ForEach(PlaybackSpeeds.options, id: \.self) { speed in
                        Text(PlaybackSpeeds.formatLabel(speed)).tag(speed)
                    }
                }

                Picker("Sleep timer", selection: sleepTimerSelection) {
                    Text(SleepTimerOptions.formatLabel(minutes: nil)).tag(Optional<Int>.none)
                    ForEach(SleepTimerOptions.minutesOptions, id: \.self) { minutes in
                        Text(SleepTimerOptions.formatLabel(minutes: minutes)).tag(Optional(minutes))
                    }
                }

                if let remaining = playback.sleepTimerRemaining,
                   playback.sleepTimerEndsAt != nil
                {
                    LabeledContent("Remaining", value: SleepTimerOptions.formatRemaining(remaining))
                }
            } header: {
                Text("Playback")
            } footer: {
                if playback.sleepTimerEndsAt != nil {
                    Text("Playback pauses automatically when the timer ends. Queue and mini player stay.")
                } else {
                    Text("Choose a duration to pause playback after that time.")
                }
            }

            Section("About") {
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent("Supabase", value: appModel.config.isConfigured ? "Configured" : "Missing secrets")
                Text("PRD: prd/IOS_MVP_SCOPE.md")
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
        }
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.background)
        .navigationTitle("Settings")
        .preferredColorScheme(.dark)
    }

    private var sleepTimerSelection: Binding<Int?> {
        Binding(
            get: { playback.sleepTimerMinutes },
            set: { playback.setSleepTimer(minutes: $0) }
        )
    }
}
