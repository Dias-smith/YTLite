#if !targetEnvironment(macCatalyst)
import AppTrackingTransparency
import Combine
import Foundation
import UIKit
import UserMessagingPlatform

@MainActor
final class AdConsentStatus: ObservableObject {
    static let shared = AdConsentStatus()
    @Published private(set) var revision = 0

    private init() {}

    func refresh() {
        revision += 1
    }
}

/// UMP consent + ATT. Prompts are deferred while the app is backgrounded / inactive.
@MainActor
enum AdConsentManager {
    private static var hasUpdatedConsentInfoThisSession = false
    private static var hasPresentedConsentFormThisSession = false
    private static var hasRequestedATTThisSession = false
    private static var pendingATT = false
    private static var pendingConsentForm = false

    static var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    static var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Call once at launch, before UMP / AdMob. Skips (and defers) when not foreground-active.
    static func requestTrackingAuthorizationAtLaunch() async {
        guard AdMobConfig.adsEnabled else { return }
        guard !hasRequestedATTThisSession else { return }
        guard AppPermissionPromptGate.canPresent else {
            pendingATT = true
            AdProbe.log("att.defer", "app_not_active")
            return
        }
        pendingATT = false
        hasRequestedATTThisSession = true
        await requestTrackingAuthorizationIfNeeded()
    }

    /// Resume ATT / UMP form after returning to foreground.
    static func resumeDeferredPromptsIfNeeded() async {
        guard AppPermissionPromptGate.canPresent else { return }
        if pendingATT, !hasRequestedATTThisSession {
            AdProbe.log("att.resume")
            await requestTrackingAuthorizationAtLaunch()
        }
        if pendingConsentForm {
            AdProbe.log("consent.form.resume")
            _ = await gatherConsentIfNeeded()
            await AdBootstrap.startIfNeeded()
        }
    }

    @discardableResult
    static func gatherConsentIfNeeded() async -> Bool {
        guard AdMobConfig.adsEnabled else {
            AdProbe.log("consent.skip", "adsEnabled=false")
            return false
        }

        if !hasUpdatedConsentInfoThisSession {
            hasUpdatedConsentInfoThisSession = true
            AdProbe.log("consent.info_update.start")
            let parameters = makeRequestParameters()
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                    if let error {
                        AdProbe.log("consent.info_update.fail", error.localizedDescription)
                    } else {
                        AdProbe.log(
                            "consent.info_update.ok",
                            "canRequestAds=\(ConsentInformation.shared.canRequestAds)"
                        )
                    }
                    cont.resume()
                }
            }
        }

        if !hasPresentedConsentFormThisSession {
            guard AppPermissionPromptGate.canPresent else {
                pendingConsentForm = true
                AdProbe.log("consent.form.defer", "app_not_active")
                return canRequestAds
            }
            pendingConsentForm = false
            hasPresentedConsentFormThisSession = true
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                ConsentForm.loadAndPresentIfRequired(from: nil) { error in
                    Task { @MainActor in
                        if let error {
                            AdProbe.log("consent.form.fail", error.localizedDescription)
                        } else {
                            AdProbe.log(
                                "consent.form.done",
                                "canRequestAds=\(canRequestAds) privacyOptions=\(isPrivacyOptionsRequired)"
                            )
                        }
                        AdConsentStatus.shared.refresh()
                        cont.resume()
                    }
                }
            }
        } else {
            AdProbe.log("consent.stored", "canRequestAds=\(canRequestAds)")
        }

        return canRequestAds
    }

    /// System ATT prompt when status is still `.notDetermined`.
    private static func requestTrackingAuthorizationIfNeeded() async {
        guard AdMobConfig.adsEnabled else { return }
        guard #available(iOS 14, *) else { return }
        guard AppPermissionPromptGate.canPresent else {
            pendingATT = true
            hasRequestedATTThisSession = false
            AdProbe.log("att.defer", "app_not_active_mid_request")
            return
        }
        let status = ATTrackingManager.trackingAuthorizationStatus
        guard status == .notDetermined else {
            AdProbe.log("att.skip", "status=\(status.rawValue)")
            return
        }
        AdProbe.log("att.request")
        let result = await ATTrackingManager.requestTrackingAuthorization()
        AdProbe.log("att.result", "status=\(result.rawValue)")
    }

    static func presentPrivacyOptions() async {
        guard AppPermissionPromptGate.canPresent else {
            AdProbe.log("consent.privacy_options.skip", "app_not_active")
            return
        }
        AdProbe.log("consent.privacy_options.present")
        AdSceneLifecycle.setUIBlocked("privacy_options", blocked: true)
        defer {
            AdSceneLifecycle.setUIBlocked("privacy_options", blocked: false)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ConsentForm.presentPrivacyOptionsForm(from: nil) { error in
                Task { @MainActor in
                    if let error {
                        AdProbe.log("consent.privacy_options.fail", error.localizedDescription)
                    }
                    AdConsentStatus.shared.refresh()
                    cont.resume()
                }
            }
        }
    }

    #if DEBUG
    static func resetForTesting() {
        ConsentInformation.shared.reset()
        hasUpdatedConsentInfoThisSession = false
        hasPresentedConsentFormThisSession = false
        hasRequestedATTThisSession = false
        pendingATT = false
        pendingConsentForm = false
        AdConsentStatus.shared.refresh()
        AdProbe.log("consent.reset")
    }
    #endif

    private static func makeRequestParameters() -> RequestParameters {
        let parameters = RequestParameters()
        #if DEBUG
        let debugSettings = DebugSettings()
        // debugSettings.testDeviceIdentifiers = ["DEVICE_HASH_FROM_CONSOLE"]
        // debugSettings.geography = .EEA
        parameters.debugSettings = debugSettings
        #endif
        return parameters
    }
}

/// System permission / consent UI must only appear while Mixtube is foreground-active.
@MainActor
enum AppPermissionPromptGate {
    static var canPresent: Bool {
        UIApplication.shared.applicationState == .active
    }
}
#else
import Combine
import Foundation
import UIKit

@MainActor
final class AdConsentStatus: ObservableObject {
    static let shared = AdConsentStatus()
    @Published private(set) var revision = 0

    private init() {}

    func refresh() {
        revision += 1
    }
}

@MainActor
enum AdConsentManager {
    static var canRequestAds: Bool { false }
    static var isPrivacyOptionsRequired: Bool { false }

    static func requestTrackingAuthorizationAtLaunch() async {}
    static func resumeDeferredPromptsIfNeeded() async {}

    @discardableResult
    static func gatherConsentIfNeeded() async -> Bool { false }

    static func presentPrivacyOptions() async {}

    #if DEBUG
    static func resetForTesting() {
        AdConsentStatus.shared.refresh()
    }
    #endif
}

@MainActor
enum AppPermissionPromptGate {
    static var canPresent: Bool {
        UIApplication.shared.applicationState == .active
    }
}
#endif
