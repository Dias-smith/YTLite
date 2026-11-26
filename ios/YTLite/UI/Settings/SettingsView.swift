import StoreKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var playback: PlaybackController
    @ObservedObject private var vip = VipStore.shared
    @ObservedObject private var adConsentStatus = AdConsentStatus.shared
    @ObservedObject private var appBackground = AppBackgroundStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var rateUnavailableAlert = false
    @State private var showVip = false

    var body: some View {
        let _ = adConsentStatus.revision
        let _ = vip.revision
        let _ = appBackground.revision
        let _ = appModel.languageCode
        Form {
            #if !targetEnvironment(macCatalyst)
            Section {
                Button {
                    showVip = true
                } label: {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "crown.fill")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("vip.entry_title"))
                                .font(YTLiteType.rowTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                            Text(
                                vip.isVipActive
                                    ? L("vip.entry_subtitle_active")
                                    : L("vip.entry_subtitle")
                            )
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(YTLiteColor.onSurfaceVariant.opacity(0.55))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text(L("vip.section"))
            }
            #endif

            Section {
                Toggle(
                    isOn: Binding(
                        get: { ImportCachePolicy.wifiOnlyAutoCache },
                        set: { ImportCachePolicy.wifiOnlyAutoCache = $0 }
                    )
                ) {
                    Text(L("import.settings.wifi_only_cache"))
                }
                .tint(YTLiteColor.accent)

                #if targetEnvironment(macCatalyst)
                Toggle(
                    isOn: Binding(
                        get: { MacPlaybackCacheStore.isEnabled },
                        set: { enabled in
                            MacPlaybackCacheStore.isEnabled = enabled
                            if !enabled {
                                Task { await PlaybackMediaStore.shared.clearAll() }
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.mac_media_cache"))
                        Text(L("settings.mac_media_cache.hint"))
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                }
                .tint(YTLiteColor.accent)
                #endif

                Picker(
                    selection: Binding(
                        get: { ImportCachePolicy.budgetBytes },
                        set: { ImportCachePolicy.budgetBytes = $0 }
                    )
                ) {
                    Text("512 MB").tag(Int64(512 * 1024 * 1024))
                    Text("1 GB").tag(Int64(1024 * 1024 * 1024))
                    Text("2 GB").tag(Int64(2 * 1024 * 1024 * 1024))
                    Text("4 GB").tag(Int64(4 * 1024 * 1024 * 1024))
                } label: {
                    Text(L("import.settings.cache_budget"))
                }

                NavigationLink {
                    ImportHubView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "square.and.arrow.down")
                        Text(L("import.hub.title"))
                    }
                }
            } header: {
                Text(L("import.settings.section"))
            } footer: {
                Text(L("import.settings.footer"))
            }

            Section {
                NavigationLink {
                    ThemePickerView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "paintpalette.fill")
                        Text(L("theme.title"))
                        Spacer(minLength: 0)
                        Text(appModel.themeDisplayName)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                }
                NavigationLink {
                    AppBackgroundSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "photo.on.rectangle.angled")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.app_background"))
                                .font(YTLiteType.rowTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                            Text(appBackground.summaryLabel)
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Picker(selection: $appModel.languageCode) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "globe")
                        Text(L("settings.language"))
                    }
                }
                Picker(selection: $appModel.contentRegionCode) {
                    ForEach(AppContentRegion.sortedForPicker) { region in
                        Text(region.displayName).tag(region.rawValue)
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "map.fill")
                        Text(L("settings.content_region"))
                    }
                }
            } header: {
                Text(L("settings.appearance"))
            } footer: {
                Text(L("settings.content_region_footer"))
            }

            Section {
                Picker(selection: $playback.playbackSpeed) {
                    ForEach(PlaybackSpeeds.options, id: \.self) { speed in
                        Text(PlaybackSpeeds.formatLabel(speed)).tag(speed)
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "gauge.with.dots.needle.67percent")
                        Text(L("settings.speed"))
                    }
                }

                Picker(selection: sleepTimerSelection) {
                    Text(SleepTimerOptions.formatLabel(minutes: nil)).tag(Optional<Int>.none)
                    ForEach(SleepTimerOptions.minutesOptions, id: \.self) { minutes in
                        Text(SleepTimerOptions.formatLabel(minutes: minutes)).tag(Optional(minutes))
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "moon.zzz.fill")
                        Text(L("settings.sleep_timer"))
                    }
                }

                if let remaining = playback.sleepTimerRemaining,
                   playback.sleepTimerEndsAt != nil
                {
                    LabeledContent(L("settings.remaining"), value: SleepTimerOptions.formatRemaining(remaining))
                }

                #if !targetEnvironment(macCatalyst)
                Toggle(isOn: $appModel.pictureInPictureEnabled) {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "pip.enter")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.pip"))
                                .font(YTLiteType.rowTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                            Text(L("settings.pip_subtitle"))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }
                    }
                }
                .tint(YTLiteColor.accent)
                #endif

                Toggle(isOn: $playback.autoSkipOnFailure) {
                    HStack(spacing: 12) {
                        SettingsLeadingIcon(systemName: "forward.end.alt")

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.auto_skip_on_failure"))
                                .font(YTLiteType.rowTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                            Text(L("settings.auto_skip_on_failure_subtitle"))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }
                    }
                }
                .tint(YTLiteColor.accent)
            } header: {
                Text(L("settings.playback"))
            } footer: {
                if playback.sleepTimerEndsAt != nil {
                    Text(L("settings.sleep_footer_active"))
                } else {
                    Text(L("settings.sleep_footer_idle"))
                }
            }

            #if targetEnvironment(macCatalyst)
            MacShortcutSettingsSection()
            #endif

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

                if AdMobConfig.adsEnabled && AdConsentManager.isPrivacyOptionsRequired {
                    Button(L("settings.ad_privacy_choices")) {
                        Task { await AdConsentManager.presentPrivacyOptions() }
                    }
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

            #if DEBUG && !targetEnvironment(macCatalyst)
            Section {
                Toggle(
                    "Force VIP (debug)",
                    isOn: Binding(
                        get: { vip.debugForceVip },
                        set: { vip.debugForceVip = $0 }
                    )
                )
                Toggle(
                    isOn: Binding(
                        get: { DebugPlaybackCacheStore.forceEnableMediaCache },
                        set: { enabled in
                            DebugPlaybackCacheStore.forceEnableMediaCache = enabled
                            if !enabled {
                                Task { await PlaybackMediaStore.shared.clearAll() }
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable media cache (debug)")
                        Text("Release builds never store streams")
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                }
                .tint(YTLiteColor.accent)
            } header: {
                Text("Debug")
            } footer: {
                Text("Debug-only. Media cache writes a local file after playback passes 10%.")
            }
            #elseif DEBUG
            Section {
                Toggle(
                    "Force VIP (debug)",
                    isOn: Binding(
                        get: { vip.debugForceVip },
                        set: { vip.debugForceVip = $0 }
                    )
                )
            } header: {
                Text("Debug")
            }
            #endif
        }
        .ytLiteContentWidth(
            720,
            enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass)
        )
        .scrollContentBackground(.hidden)
        .ytLiteMiniPlayerScrollInset()
        .ytLiteAppBackground()
        .navigationTitle(L("settings.title"))
        .alert(L("settings.support_us"), isPresented: $rateUnavailableAlert) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(L("settings.rate_unavailable"))
        }
        .fullScreenCover(isPresented: $showVip) {
            VipView()
                .environmentObject(appModel)
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

/// Leading icon tile shared by Settings rows (matches Picture in Picture styling).
private struct SettingsLeadingIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(YTLiteColor.accent)
            .frame(width: 36, height: 36)
            .background(
                YTLiteColor.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

/// Full-screen VIP / Premium paywall. Uses app theme colors (not competitor greens).
struct VipView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var vip = VipStore.shared
    @State private var selectedProductID: String?

    private static let manageSubscriptionsURL =
        URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        let _ = vip.revision
        let _ = appModel.languageCode
        ZStack(alignment: .topTrailing) {
            YTLiteColor.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 28)

                    benefits
                        .padding(.top, 28)
                        .padding(.horizontal, 36)

                    plansSection
                        .padding(.top, 28)
                        .padding(.horizontal, YTLiteLayout.screenPadding)

                    subscribeButton
                        .padding(.top, 20)
                        .padding(.horizontal, YTLiteLayout.screenPadding)

                    if let message = vip.lastErrorMessage, !message.isEmpty {
                        Text(message)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.danger)
                            .multilineTextAlignment(.center)
                            .padding(.top, YTLiteLayout.stackLoose)
                            .padding(.horizontal, YTLiteLayout.screenPadding)
                    }

                    Text(L("vip.legal_footer"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    footerLinks
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 36, height: 36)
                    .background(YTLiteColor.surfaceElevated, in: Circle())
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel(L("common.close"))
        }
        .onAppear {
            Task {
                await vip.reloadPricing()
                if selectedProductID == nil {
                    selectedProductID = vip.products.first?.id ?? VipProductID.yearly
                }
            }
        }
        .onChange(of: vip.products.map(\.id)) { _, ids in
            if selectedProductID == nil || !(ids.contains(selectedProductID ?? "")) {
                selectedProductID = ids.first
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(YTLiteColor.accent)
                .padding(.bottom, 4)

            Text(L("vip.hero_title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(YTLiteColor.onSurface)

            Text(L("vip.hero_subtitle"))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefitRow(icon: "nosign", text: L("vip.benefit_ad_free"))
            benefitRow(icon: "play.circle", text: L("vip.benefit_playback"))
            benefitRow(icon: "paintpalette", text: L("vip.benefit_themes"))
            benefitRow(icon: "photo", text: L("vip.benefit_photo_background"))
        }
        .frame(maxWidth: 320, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(YTLiteColor.accent)
                .frame(width: 24, alignment: .center)
            Text(text)
                .font(YTLiteType.rowTitleMedium)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var plansSection: some View {
        if vip.isVipActive {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("vip.status_active_message"))
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.accent)
                if let expiration = vip.expirationDate {
                    Text(
                        "\(L("vip.expires")): \(expiration.formatted(date: .abbreviated, time: .omitted))"
                    )
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(YTLiteColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if vip.isLoadingProducts && vip.products.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if vip.products.isEmpty {
            Text(L("vip.products_unavailable"))
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 12) {
                ForEach(vip.products, id: \.id) { product in
                    planCard(for: product)
                }
            }
        }
    }

    private func planCard(for product: Product) -> some View {
        let selected = selectedProductID == product.id
        let pricing = VipPlanPricing(
            product: product,
            eligibleForIntro: vip.introEligibleByProductID[product.id] ?? false
        )
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(for: product.id))
                        .font(YTLiteType.rowTitle)
                        .foregroundStyle(YTLiteColor.onSurface)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(pricing.priceLine)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(YTLiteColor.onSurface)
                        if let strike = pricing.strikethroughPrice {
                            Text(strike)
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                .strikethrough()
                        }
                    }

                    if let thenLine = pricing.thenLine {
                        Text(thenLine)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                }

                Spacer(minLength: 8)

                if let save = pricing.savePercent {
                    Text(Lf("vip.save_percent", save))
                        .font(YTLiteType.badge)
                        .foregroundStyle(YTLiteColor.onAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(YTLiteColor.accent, in: Capsule())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                YTLiteColor.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? YTLiteColor.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var subscribeButton: some View {
        if vip.isVipActive {
            EmptyView()
        } else {
            Button {
                guard let id = selectedProductID,
                      let product = vip.products.first(where: { $0.id == id })
                else { return }
                Task { await vip.purchase(product) }
            } label: {
                Group {
                    if vip.isPurchasing {
                        ProgressView()
                            .tint(YTLiteColor.onAccent)
                    } else {
                        Text(L("vip.buy"))
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(YTLiteColor.onAccent)
                .background(YTLiteColor.accent, in: Capsule())
            }
            .disabled(vip.isPurchasing || selectedProductID == nil || vip.products.isEmpty)
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 0) {
            footerLink(L("vip.restore")) {
                Task { await vip.restorePurchases() }
            }
            footerLink(L("vip.manage")) {
                AppLinks.open(Self.manageSubscriptionsURL)
            }
            footerLink(L("settings.terms_of_service")) {
                AppLinks.open(AppLinks.termsOfService)
            }
            footerLink(L("settings.privacy_policy")) {
                AppLinks.open(AppLinks.privacyPolicy)
            }
        }
        .padding(.horizontal, 8)
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func displayName(for productID: String) -> String {
        switch productID {
        case VipProductID.monthly: return L("vip.plan_monthly")
        case VipProductID.yearly: return L("vip.plan_yearly")
        default: return productID
        }
    }
}

private struct VipPlanPricing {
    let priceLine: String
    let strikethroughPrice: String?
    let thenLine: String?
    let savePercent: Int?

    init(product: Product, eligibleForIntro: Bool) {
        let regularPeriod = product.subscription?.subscriptionPeriod
        let regular = product.displayPrice
        let regularLine = Self.priceLine(amount: regular, period: regularPeriod, productID: product.id)

        // Prefer App Store introductory offer when the account is eligible.
        if eligibleForIntro, let intro = product.subscription?.introductoryOffer {
            switch intro.paymentMode {
            case .freeTrial:
                priceLine = L("vip.price_free")
                strikethroughPrice = regular
                thenLine = Lf("vip.then_price", regularLine)
                savePercent = 100
            case .payAsYouGo, .payUpFront:
                // Use the offer's own period (may differ from the base plan, e.g. P1M intro on yearly).
                priceLine = Self.priceLine(
                    amount: intro.displayPrice,
                    period: intro.period,
                    productID: product.id
                )
                strikethroughPrice = regular
                thenLine = Lf("vip.then_price", regularLine)
                let introValue = NSDecimalNumber(decimal: intro.price).doubleValue
                let regularValue = NSDecimalNumber(decimal: product.price).doubleValue
                if regularValue > 0, introValue < regularValue {
                    savePercent = Int(((regularValue - introValue) / regularValue * 100).rounded())
                } else {
                    savePercent = nil
                }
            default:
                priceLine = regularLine
                strikethroughPrice = nil
                thenLine = nil
                savePercent = nil
            }
            return
        }

        priceLine = regularLine
        strikethroughPrice = nil
        thenLine = nil
        savePercent = nil
    }

    private static func priceLine(
        amount: String,
        period: Product.SubscriptionPeriod?,
        productID: String
    ) -> String {
        guard let period else {
            return productID == VipProductID.yearly
                ? Lf("vip.price_year", amount)
                : Lf("vip.price_month", amount)
        }
        // Common 1-unit periods; otherwise show bare localized amount from StoreKit.
        if period.value == 1 {
            switch period.unit {
            case .year: return Lf("vip.price_year", amount)
            case .month: return Lf("vip.price_month", amount)
            default: break
            }
        }
        return amount
    }
}

/// First-launch (and DEBUG every launch) language + content region picker.
struct LocaleSetupSheet: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var draftLanguageCode: String
    @State private var draftRegionCode: String

    init(
        languageCode: String = AppLanguage.system.rawValue,
        regionCode: String = AppContentRegion.defaultForDevice().rawValue
    ) {
        _draftLanguageCode = State(initialValue: languageCode)
        _draftRegionCode = State(initialValue: regionCode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(L("locale_setup.message"))
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, YTLiteLayout.stackDefault)
                    .padding(.bottom, YTLiteLayout.stackLoose)

                Form {
                    Section(L("locale_setup.language")) {
                        Picker(L("locale_setup.language"), selection: $draftLanguageCode) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language.rawValue)
                            }
                        }
                        .labelsHidden()
                    }

                    Section(L("locale_setup.content_region")) {
                        Picker(L("locale_setup.content_region"), selection: $draftRegionCode) {
                            ForEach(AppContentRegion.sortedForPicker) { region in
                                Text(region.displayName).tag(region.rawValue)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(YTLiteColor.surfaceElevated)
            .navigationTitle(L("locale_setup.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("locale_setup.continue")) {
                        appModel.completeLocaleSetup(
                            languageCode: draftLanguageCode,
                            regionCode: draftRegionCode
                        )
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(YTLiteColor.surfaceElevated)
    }
}

// MARK: - First-launch feature intro

private struct FeatureIntroPage: Identifiable {
    let id: Int
    let imageName: String
    let titleKey: String
    let bodyKey: String

    static let all: [FeatureIntroPage] = [
        FeatureIntroPage(
            id: 0,
            imageName: "onboarding_search",
            titleKey: "feature_intro.search.title",
            bodyKey: "feature_intro.search.body"
        ),
        FeatureIntroPage(
            id: 1,
            imageName: "onboarding_recommend",
            titleKey: "feature_intro.recommend.title",
            bodyKey: "feature_intro.recommend.body"
        ),
        FeatureIntroPage(
            id: 2,
            imageName: "onboarding_sync",
            titleKey: "feature_intro.sync.title",
            bodyKey: "feature_intro.sync.body"
        ),
        FeatureIntroPage(
            id: 3,
            imageName: "onboarding_playback",
            titleKey: "feature_intro.playback.title",
            bodyKey: "feature_intro.playback.body"
        ),
        FeatureIntroPage(
            id: 4,
            imageName: "onboarding_watch_widget",
            titleKey: "feature_intro.watch_widget.title",
            bodyKey: "feature_intro.watch_widget.body"
        ),
    ]
}

/// First-launch slides introducing core Mixtube capabilities.
struct FeatureIntroSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var pageIndex = 0

    private var pages: [FeatureIntroPage] { FeatureIntroPage.all }
    private var isLastPage: Bool { pageIndex >= pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button(L("feature_intro.skip")) {
                    appModel.completeFeatureIntro()
                }
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
                .accessibilityHidden(isLastPage)
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.top, YTLiteLayout.stackDefault)

            TabView(selection: $pageIndex) {
                ForEach(pages) { page in
                    featurePage(page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if isLastPage {
                    appModel.completeFeatureIntro()
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        pageIndex = min(pageIndex + 1, pages.count - 1)
                    }
                }
            } label: {
                Text(isLastPage ? L("feature_intro.get_started") : L("feature_intro.next"))
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(YTLiteColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.top, YTLiteLayout.stackLoose)
            .padding(.bottom, 28)
        }
        .background(YTLiteColor.surfaceElevated.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .presentationDetents([.fraction(2.0 / 3.0)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(YTLiteColor.surfaceElevated)
    }

    private func featurePage(_ page: FeatureIntroPage) -> some View {
        VStack(spacing: YTLiteLayout.stackLoose) {
            Spacer(minLength: 0)

            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .accessibilityHidden(true)

            Text(L(page.titleKey))
                .font(YTLiteType.pageTitle)
                .foregroundStyle(YTLiteColor.onSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, YTLiteLayout.screenPadding)

            Text(L(page.bodyKey))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, YTLiteLayout.screenPadding)

            // Page dots sit in the TabView chrome — keep clear of the copy.
            Spacer(minLength: 44)
                .frame(maxHeight: 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if targetEnvironment(macCatalyst)
private struct MacKeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
}

private enum MacShortcutAction: String, CaseIterable, Identifiable {
    case playPause
    case previous
    case next
    case download

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .playPause: return "settings.shortcuts.play_pause"
        case .previous: return "settings.shortcuts.previous"
        case .next: return "settings.shortcuts.next"
        case .download: return "settings.shortcuts.download"
        }
    }

    static let command: UInt = 1 << 20
    static let shift: UInt = 1 << 17

    /// Spotify and QQ Music use Space, Command-Left, and Command-Right. Download is Command-Shift-D.
    static let defaults: [MacShortcutAction: MacKeyCombo] = [
        .playPause: MacKeyCombo(keyCode: 49, modifiers: 0),
        .previous: MacKeyCombo(keyCode: 123, modifiers: command),
        .next: MacKeyCombo(keyCode: 124, modifiers: command),
        .download: MacKeyCombo(keyCode: 2, modifiers: command | shift),
    ]
}

@MainActor
final class MacShortcutStore: ObservableObject {
    static let shared = MacShortcutStore()

    @Published private var bindings: [MacShortcutAction: MacKeyCombo]
    @Published fileprivate var recording: MacShortcutAction?

    private weak var playback: PlaybackController?
    private var monitor: AnyObject?
    private let storageKey = "ytlite.mac.shortcuts"

    private init() {
        bindings = Self.load() ?? MacShortcutAction.defaults
    }

    func attach(_ playback: PlaybackController) {
        self.playback = playback
        installMonitor()
    }

    fileprivate func beginRecording(_ action: MacShortcutAction) {
        recording = recording == action ? nil : action
    }

    func reset() {
        recording = nil
        bindings = MacShortcutAction.defaults
        save()
    }

    fileprivate func display(for action: MacShortcutAction) -> String {
        guard let combo = bindings[action] else { return L("settings.shortcuts.unset") }
        return Self.describe(combo)
    }

    private func installMonitor() {
        guard monitor == nil,
              let eventClass = NSClassFromString("NSEvent"),
              let method = class_getClassMethod(eventClass, NSSelectorFromString("addLocalMonitorForEventsMatchingMask:handler:"))
        else { return }
        let selector = NSSelectorFromString("addLocalMonitorForEventsMatchingMask:handler:")
        let mask: UInt = 1 << 10 // keyDown
        let handler: @convention(block) (AnyObject) -> AnyObject? = { event in
            let handled = MainActor.assumeIsolated {
                MacShortcutStore.shared.handle(event)
            }
            return handled ? nil : event
        }
        typealias AddMonitorIMP = @convention(c) (
            AnyClass, Selector, UInt, @convention(block) (AnyObject) -> AnyObject?
        ) -> AnyObject?
        let function = unsafeBitCast(method_getImplementation(method), to: AddMonitorIMP.self)
        monitor = function(eventClass, selector, mask, handler)
    }

    private func handle(_ event: AnyObject) -> Bool {
        guard let keyCode = Self.keyCode(of: event) else { return false }
        let modifiers = Self.modifiers(of: event)
        if Self.isRepeat(event) {
            return bindings.contains { $0.value.keyCode == keyCode && $0.value.modifiers == modifiers }
        }
        if let recording {
            if keyCode == 53, modifiers == 0 {
                self.recording = nil
                return true
            }
            if keyCode == 51, modifiers == 0 {
                bindings[recording] = nil
                self.recording = nil
                save()
                return true
            }
            if Self.isModifierOnly(keyCode) { return false }
            for action in bindings.keys where action != recording && bindings[action] == MacKeyCombo(keyCode: keyCode, modifiers: modifiers) {
                bindings[action] = nil
            }
            bindings[recording] = MacKeyCombo(keyCode: keyCode, modifiers: modifiers)
            self.recording = nil
            save()
            return true
        }
        if Self.isTyping() { return false }
        guard let action = bindings.first(where: { $0.value.keyCode == keyCode && $0.value.modifiers == modifiers })?.key else {
            return false
        }
        perform(action)
        return true
    }

    private func perform(_ action: MacShortcutAction) {
        guard let playback else { return }
        switch action {
        case .playPause:
            playback.togglePlayPause()
        case .previous:
            playback.playPrevious()
        case .next:
            playback.playNext()
        case .download:
            downloadCurrent(playback)
        }
    }

    private func downloadCurrent(_ playback: PlaybackController) {
        guard let item = playback.nowPlaying else { return }
        if LocalTrackID.isLocal(item.videoId) { return }
        if playback.libraryStore?.track(id: item.videoId)?.isImportedLocally == true { return }
        if playback.queue.indices.contains(playback.queueIndex) {
            let current = playback.queue[playback.queueIndex]
            if current.videoId == item.videoId, current.isLive { return }
        }
        MacSongCacheDownloads.start(
            videoId: item.videoId,
            thumbnailURL: item.thumbnailURL,
            libraryStore: playback.libraryStore
        )
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: bindings.map {
            ($0.key.rawValue, SavedCombo(keyCode: $0.value.keyCode, modifiers: $0.value.modifiers))
        })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func load() -> [MacShortcutAction: MacKeyCombo]? {
        guard let data = UserDefaults.standard.data(forKey: "ytlite.mac.shortcuts"),
              let stored = try? JSONDecoder().decode([String: SavedCombo].self, from: data)
        else { return nil }
        var bindings: [MacShortcutAction: MacKeyCombo] = [:]
        for action in MacShortcutAction.allCases {
            if let saved = stored[action.rawValue] {
                bindings[action] = MacKeyCombo(keyCode: saved.keyCode, modifiers: saved.modifiers)
            }
        }
        return bindings
    }

    private static func describe(_ combo: MacKeyCombo) -> String {
        var parts = ""
        if combo.modifiers & (1 << 18) != 0 { parts += "⌃" }
        if combo.modifiers & (1 << 19) != 0 { parts += "⌥" }
        if combo.modifiers & (1 << 17) != 0 { parts += "⇧" }
        if combo.modifiers & (1 << 20) != 0 { parts += "⌘" }
        parts += keyName(combo.keyCode)
        return parts
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 49: return L("settings.shortcuts.space")
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let letters: [UInt16: String] = [
                0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
                8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
                16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
                25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 31: "O", 32: "U",
                34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            ]
            return letters[keyCode] ?? "?"
        }
    }

    private static func isModifierOnly(_ keyCode: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    private static func isRepeat(_ event: AnyObject) -> Bool {
        (event as? NSObject)?.value(forKey: "isARepeat") as? Bool ?? false
    }

    private static func keyCode(of event: AnyObject) -> UInt16? {
        guard let object = event as? NSObject else { return nil }
        let selector = NSSelectorFromString("keyCode")
        guard object.responds(to: selector) else { return nil }
        typealias KeyIMP = @convention(c) (AnyObject, Selector) -> UInt16
        let function = unsafeBitCast(object.method(for: selector), to: KeyIMP.self)
        return function(object, selector)
    }

    private static func modifiers(of event: AnyObject) -> UInt {
        guard let object = event as? NSObject else { return 0 }
        let selector = NSSelectorFromString("modifierFlags")
        guard object.responds(to: selector) else { return 0 }
        typealias FlagIMP = @convention(c) (AnyObject, Selector) -> UInt
        let function = unsafeBitCast(object.method(for: selector), to: FlagIMP.self)
        let raw = function(object, selector)
        return raw & ((1 << 17) | (1 << 18) | (1 << 19) | (1 << 20))
    }

    private static func isTyping() -> Bool {
        guard let appClass = NSClassFromString("NSApplication") as? NSObject.Type,
              let app = appClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? NSObject,
              let window = app.value(forKey: "keyWindow") as? NSObject,
              let responder = window.value(forKey: "firstResponder") as? NSObject
        else { return false }
        let name = NSStringFromClass(type(of: responder))
        return name.contains("Text") || name.contains("FieldEditor")
    }

    private struct SavedCombo: Codable {
        var keyCode: UInt16
        var modifiers: UInt
    }
}

private struct MacShortcutSettingsSection: View {
    @ObservedObject private var store = MacShortcutStore.shared

    var body: some View {
        Section {
            ForEach(MacShortcutAction.allCases) { action in
                HStack {
                    Text(L(action.titleKey))
                        .font(YTLiteType.rowTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                    Spacer(minLength: 12)
                    Button {
                        store.beginRecording(action)
                    } label: {
                        Text(store.recording == action ? "…" : store.display(for: action))
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(YTLiteColor.onSurface)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                store.recording == action
                                    ? YTLiteColor.accent.opacity(0.22)
                                    : YTLiteColor.surfaceChip,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(L("settings.shortcuts.reset")) {
                store.reset()
            }
        } header: {
            Text(L("settings.shortcuts"))
        } footer: {
            Text(store.recording == nil ? L("settings.shortcuts.footer") : L("settings.shortcuts.recording"))
        }
    }
}
#endif
