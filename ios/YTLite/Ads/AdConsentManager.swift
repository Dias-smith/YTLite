import AppTrackingTransparency
import Combine
import Foundation
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

/// UMP consent + ATT. ATT is requested at app launch (before UMP).
@MainActor
enum AdConsentManager {
    private static var hasStartedConsentThisSession = false
    private static var hasRequestedATTThisSession = false

    static var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    static var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Call once at launch, before UMP / AdMob, so the system ATT sheet appears immediately.
    static func requestTrackingAuthorizationAtLaunch() async {
        guard AdMobConfig.adsEnabled else { return }
        guard !hasRequestedATTThisSession else { return }
        hasRequestedATTThisSession = true
        await requestTrackingAuthorizationIfNeeded()
    }

    @discardableResult
    static func gatherConsentIfNeeded() async -> Bool {
        guard AdMobConfig.adsEnabled else {
            AdProbe.log("consent.skip", "adsEnabled=false")
            return false
        }
        guard !hasStartedConsentThisSession else {
            AdProbe.log("consent.stored", "canRequestAds=\(canRequestAds)")
            return canRequestAds
        }
        hasStartedConsentThisSession = true
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

        return canRequestAds
    }

    /// System ATT prompt when status is still `.notDetermined`.
    private static func requestTrackingAuthorizationIfNeeded() async {
        guard AdMobConfig.adsEnabled else { return }
        guard #available(iOS 14, *) else { return }
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
        hasStartedConsentThisSession = false
        hasRequestedATTThisSession = false
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
