import Foundation

/// Console filter: `YTLite.AdProbe`
enum AdProbe {
    static let tag = "YTLite.AdProbe"

    static func log(_ stage: String, _ detail: String = "") {
        let detailPart = detail.isEmpty ? "" : " | \(detail)"
        print("[\(tag)] [\(stage)]\(detailPart)")
    }
}
