import Foundation

/// Temporary stage probe for diagnosing library sync latency (filter Console: `YTLite.SyncProbe`).
/// Observe-only — must not drive control flow or change sync behavior.
enum SyncProbe {
    static let tag = "YTLite.SyncProbe"

    /// Active sync round id (MainActor sync path only).
    @MainActor
    static var currentTrace: String = "-"

    static func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }

    static func ms(since start: CFAbsoluteTime) -> Int {
        max(0, Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))
    }

    static func newTraceId() -> String {
        String(UUID().uuidString.prefix(8))
    }

    static func log(_ stage: String, _ detail: String = "") {
        let detailPart = detail.isEmpty ? "" : " | \(detail)"
        print("[\(tag)] [\(stage)]\(detailPart)")
    }

    @MainActor
    static func logTrace(_ stage: String, _ detail: String = "") {
        let base = "trace=\(currentTrace)"
        let combined = detail.isEmpty ? base : "\(base) \(detail)"
        log(stage, combined)
    }
}
