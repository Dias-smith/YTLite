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

            Section("Playback") {
                Picker("Speed", selection: $playback.playbackSpeed) {
                    ForEach(PlaybackSpeeds.options, id: \.self) { speed in
                        Text(PlaybackSpeeds.formatLabel(speed)).tag(speed)
                    }
                }
            }

            Section("Download (prefs for later Hub)") {
                Toggle("Wi‑Fi only", isOn: $appModel.downloadWifiOnly)
                Toggle("Resume", isOn: $appModel.downloadResumeEnabled)
                Picker("Threads", selection: $appModel.downloadThreadCount) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }
            }

            Section("About") {
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent("Supabase", value: appModel.config.isConfigured ? "Configured" : "Missing secrets")
                Text("PRD: prd/IOS_MVP_SCOPE.md")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
