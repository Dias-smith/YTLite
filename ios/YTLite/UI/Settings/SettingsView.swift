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
}
