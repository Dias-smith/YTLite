import Foundation
import StoreKit
import SwiftUI
import UIKit

enum ReviewPromptReason: String {
    case completedPlays
    case activeDays
    case positiveAction
    case youShelf
}

/// Coordinates when to show the custom “Enjoying YouLite?” sheet and routes outcomes.
@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    static let shared = ReviewPromptCoordinator()

    static let completedPlaysThreshold = 5
    static let activeDaysThreshold = 3
    static let quietSeconds: TimeInterval = 60
    static let laterCooldownDays: TimeInterval = 14
    static let decisiveCooldownDays: TimeInterval = 180

    @Published var showSheet = false

    /// Player fullscreen / auth UI / sync overlay — defer prompt until clear.
    private var busyFlags: Set<String> = []
    private var pendingPrompt = false
    private var quietRetryTask: Task<Void, Never>?
    private var sessionCompletedVideoIds = Set<String>()

    private init() {}

    // MARK: - Triggers

    func recordCompletedPlay(videoId: String) {
        let id = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        guard !sessionCompletedVideoIds.contains(id) else { return }
        sessionCompletedVideoIds.insert(id)
        ReviewPromptStore.completedPlays += 1
        if ReviewPromptStore.completedPlays >= Self.completedPlaysThreshold {
            requestPromptIfEligible(reason: .completedPlays)
        }
    }

    func recordActiveDay() {
        let day = ReviewPromptStore.dayStamp()
        var days = ReviewPromptStore.activeDays
        if !days.contains(day) {
            days.append(day)
            if days.count > 60 {
                days = Array(days.suffix(60))
            }
            ReviewPromptStore.activeDays = days
        }
        if days.count >= Self.activeDaysThreshold {
            requestPromptIfEligible(reason: .activeDays)
        }
    }

    func recordPositiveAction() {
        guard !ReviewPromptStore.positiveActionPrompted else { return }
        ReviewPromptStore.positiveActionPrompted = true
        requestPromptIfEligible(reason: .positiveAction)
    }

    func recordYouShelfSuccess(hasContent: Bool) {
        guard hasContent else { return }
        guard !ReviewPromptStore.youShelfPrompted else { return }
        ReviewPromptStore.youShelfPrompted = true
        requestPromptIfEligible(reason: .youShelf)
    }

    // MARK: - Suppression

    func setBusy(_ key: String, _ busy: Bool) {
        if busy {
            busyFlags.insert(key)
        } else {
            busyFlags.remove(key)
            if busyFlags.isEmpty, pendingPrompt {
                flushPendingIfPossible()
            }
        }
    }

    // MARK: - Outcomes

    func loveIt() {
        showSheet = false
        ReviewPromptStore.outcome = .loved
        ReviewPromptStore.lastPromptAt = Date()
        requestSystemReview()
    }

    func notReally() {
        showSheet = false
        ReviewPromptStore.outcome = .feedback
        ReviewPromptStore.lastPromptAt = Date()
        if let url = AppLinks.suggestionsMailtoURL(subject: L("settings.suggestions_subject")) {
            AppLinks.open(url)
        }
    }

    func later() {
        showSheet = false
        ReviewPromptStore.outcome = .later
        ReviewPromptStore.lastPromptAt = Date()
    }

    // MARK: - Gates

    func requestPromptIfEligible(reason: ReviewPromptReason) {
        _ = reason
        guard !showSheet else { return }

        if ReviewPromptStore.secondsSinceProcessStart < Self.quietSeconds {
            pendingPrompt = true
            scheduleQuietRetry()
            return
        }

        guard cooldownAllowsPrompt() else { return }

        if !busyFlags.isEmpty {
            pendingPrompt = true
            return
        }

        pendingPrompt = false
        showSheet = true
    }

    private func flushPendingIfPossible() {
        guard pendingPrompt else { return }
        guard !showSheet else { return }
        if ReviewPromptStore.secondsSinceProcessStart < Self.quietSeconds {
            scheduleQuietRetry()
            return
        }
        guard cooldownAllowsPrompt() else {
            pendingPrompt = false
            return
        }
        guard busyFlags.isEmpty else { return }
        pendingPrompt = false
        showSheet = true
    }

    private func cooldownAllowsPrompt() -> Bool {
        guard let last = ReviewPromptStore.lastPromptAt else { return true }
        let days = Date().timeIntervalSince(last) / 86_400
        switch ReviewPromptStore.outcome {
        case .loved, .feedback:
            return days >= Self.decisiveCooldownDays
        case .later:
            return days >= Self.laterCooldownDays
        case .none:
            return true
        }
    }

    private func scheduleQuietRetry() {
        quietRetryTask?.cancel()
        let remaining = Self.quietSeconds - ReviewPromptStore.secondsSinceProcessStart
        guard remaining > 0 else {
            flushPendingIfPossible()
            return
        }
        quietRetryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000) + 50_000_000)
            guard !Task.isCancelled else { return }
            flushPendingIfPossible()
        }
    }

    private func requestSystemReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}
