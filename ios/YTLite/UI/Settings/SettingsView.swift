import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @State private var rateUnavailableAlert = false

    var body: some View {
        Form {
            Section(L("settings.appearance")) {
                NavigationLink {
                    ThemePickerView()
                } label: {
                    HStack {
                        Text(L("theme.title"))
                        Spacer()
                        Text(appModel.themeDisplayName)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                }
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

            Section(L("settings.support_section")) {
                Button(L("settings.support_us")) {
                    if let url = AppLinks.writeReviewURL {
                        AppLinks.open(url)
                    } else {
                        rateUnavailableAlert = true
                    }
                }

                Button(L("settings.help_support")) {
                    AppLinks.open(AppLinks.support)
                }

                Button(L("settings.privacy_policy")) {
                    AppLinks.open(AppLinks.privacyPolicy)
                }

                Button(L("settings.terms_of_service")) {
                    AppLinks.open(AppLinks.termsOfService)
                }

                Button(L("settings.suggestions")) {
                    if let url = AppLinks.suggestionsMailtoURL(subject: L("settings.suggestions_subject")) {
                        AppLinks.open(url)
                    }
                }

                LabeledContent(L("settings.about"), value: appVersionLabel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.background)
        .navigationTitle(L("settings.title"))
        .alert(L("settings.support_us"), isPresented: $rateUnavailableAlert) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(L("settings.rate_unavailable"))
        }
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, !build.isEmpty, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    private var sleepTimerSelection: Binding<Int?> {
        Binding(
            get: { playback.sleepTimerMinutes },
            set: { playback.setSleepTimer(minutes: $0) }
        )
    }
}
