import Foundation

enum LocalTrackID {
    static let prefix = "local_"

    static func isLocal(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    static func make() -> String {
        prefix + UUID().uuidString
    }
}

enum ImportSourceKind: String, Codable, CaseIterable, Sendable {
    case youtube
    case local
    case wifi
    case webdav
    case icloud
    case gdrive
    case baidu

    var isImported: Bool { self != .youtube }

    var displayKey: String {
        switch self {
        case .youtube: return "import.source.youtube"
        case .local: return "import.source.local"
        case .wifi: return "import.source.wifi"
        case .webdav: return "import.source.webdav"
        case .icloud: return "import.source.icloud"
        case .gdrive: return "import.source.gdrive"
        case .baidu: return "import.source.baidu"
        }
    }
}
