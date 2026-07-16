import Foundation
import CryptoKit

/// Installed / remote extractor knobs (from Supabase Storage `manifest.json` `config`).
struct ExtractorRemoteConfig: Codable, Equatable, Sendable {
    var androidClientVersion: String
    var signatureTimestamp: Int
    var preferItags: [Int]
    var enableAndroidPlayerFallback: Bool
    var enableWatchPageFallback: Bool

    static let defaults = ExtractorRemoteConfig(
        androidClientVersion: "20.10.38",
        signatureTimestamp: 20_646,
        preferItags: [18, 22, 37],
        enableAndroidPlayerFallback: true,
        enableWatchPageFallback: true
    )
}

/// Thread-safe snapshot of the last successfully installed extractor config.
enum ExtractorRemoteConfigStore {
    private static let lock = NSLock()
    private static var _current = ExtractorRemoteConfig.defaults
    private static let defaultsKey = "extractor_remote_config_json"

    static var current: ExtractorRemoteConfig {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    static func apply(_ config: ExtractorRemoteConfig) {
        lock.lock()
        _current = config
        lock.unlock()
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        YouTubeConstants.applyPreferredVideoItags(config.preferItags)
    }

    static func restoreFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(ExtractorRemoteConfig.self, from: data)
        else { return }
        apply(config)
    }
}

/// Downloads / caches remote extractor assets from Supabase Storage (no in-app bundle).
actor ExtractorBundleStore {
    enum BundleError: LocalizedError {
        case supabaseNotConfigured
        case downloadFailed(String)
        case checksumMismatch(String)
        case incompleteBundle
        case appVersionTooLow(required: String, current: String)
        case invalidManifest

        var errorDescription: String? {
            switch self {
            case .supabaseNotConfigured:
                return "Supabase URL is not configured; cannot download extractor"
            case .downloadFailed(let msg):
                return "Extractor download failed: \(msg)"
            case .checksumMismatch(let file):
                return "Extractor checksum mismatch: \(file)"
            case .incompleteBundle:
                return "Extractor bundle incomplete"
            case .appVersionTooLow(let required, let current):
                return "App \(current) is too old for extractor (needs \(required))"
            case .invalidManifest:
                return "Invalid extractor manifest"
            }
        }
    }

    struct ManifestFile: Codable, Sendable {
        var path: String
        var sha256: String
    }

    struct Manifest: Codable, Sendable {
        var version: Int
        var minAppVersion: String
        var files: [String: ManifestFile]
        var config: ExtractorRemoteConfig?
    }

    static let shared = ExtractorBundleStore()

    private let fileManager = FileManager.default
    private var lastBackgroundCheck: Date?

    func ensureBundle(backgroundRefresh: Bool = true) async throws -> URL {
        ExtractorRemoteConfigStore.restoreFromDisk()
        let dir = try cacheDirectory()
        if isComplete(dir: dir) {
            if let installed = try? loadInstalledManifest(dir: dir) {
                ExtractorRemoteConfigStore.apply(installed.config ?? .defaults)
            }
            if backgroundRefresh {
                scheduleBackgroundRefreshIfNeeded()
            }
            return dir
        }
        try await downloadAndInstall()
        return try cacheDirectory()
    }

    func cacheDirectoryURL() throws -> URL {
        try cacheDirectory()
    }

    func installedManifest() throws -> Manifest? {
        let dir = try cacheDirectory()
        guard isComplete(dir: dir) else { return nil }
        return try loadInstalledManifest(dir: dir)
    }

    // MARK: - Private

    private func scheduleBackgroundRefreshIfNeeded() {
        let now = Date()
        if let last = lastBackgroundCheck, now.timeIntervalSince(last) < 60 {
            return
        }
        lastBackgroundCheck = now
        Task { try? await self.refreshIfNewer() }
    }

    private func refreshIfNewer() async throws {
        let remote = try await fetchManifest()
        let dir = try cacheDirectory()
        let installedVersion = (try? loadInstalledManifest(dir: dir))?.version ?? 0
        guard remote.version > installedVersion else { return }
        try await install(manifest: remote)
    }

    private func downloadAndInstall() async throws {
        let remote = try await fetchManifest()
        try await install(manifest: remote)
    }

    private func install(manifest: Manifest) async throws {
        try checkMinAppVersion(manifest.minAppVersion)
        let required = ["extractor.js", "bridge.html", "bridge-ios.html"]
        for name in required {
            guard manifest.files[name] != nil else { throw BundleError.invalidManifest }
        }

        let dir = try cacheDirectory()
        let staging = dir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            for name in required {
                let entry = manifest.files[name]!
                let bytes = try await downloadPublicObject(relativePath: entry.path)
                let digest = SHA256.hash(data: bytes)
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                guard hex.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
                    throw BundleError.checksumMismatch(name)
                }
                let dest = staging.appendingPathComponent(name)
                try bytes.write(to: dest, options: .atomic)
            }
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(
                to: staging.appendingPathComponent("installed-manifest.json"),
                options: .atomic
            )

            for name in required + ["installed-manifest.json"] {
                let src = staging.appendingPathComponent(name)
                let dest = dir.appendingPathComponent(name)
                if fileManager.fileExists(atPath: dest.path) {
                    try fileManager.removeItem(at: dest)
                }
                try fileManager.moveItem(at: src, to: dest)
            }
            try? fileManager.removeItem(at: staging)
            ExtractorRemoteConfigStore.apply(manifest.config ?? .defaults)
            PlayProbe.log(
                "extractor.bundle.installed",
                "version=\(manifest.version) sts=\(ExtractorRemoteConfigStore.current.signatureTimestamp)"
            )
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func fetchManifest() async throws -> Manifest {
        let url = try publicURL(relativePath: "manifest.json")
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw BundleError.downloadFailed("manifest HTTP \(code)")
        }
        do {
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw BundleError.invalidManifest
        }
    }

    private func downloadPublicObject(relativePath: String) async throws -> Data {
        let url = try publicURL(relativePath: relativePath)
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code), !data.isEmpty else {
            throw BundleError.downloadFailed("\(relativePath) HTTP \(code)")
        }
        return data
    }

    private func publicURL(relativePath: String) throws -> URL {
        let base = AppConfig.fromBundle().supabaseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { throw BundleError.supabaseNotConfigured }
        let path = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/storage/v1/object/public/extractor/\(path)") else {
            throw BundleError.downloadFailed("bad url \(path)")
        }
        return url
    }

    private func cacheDirectory() throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = root.appendingPathComponent("extractor", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func isComplete(dir: URL) -> Bool {
        let required = ["extractor.js", "bridge.html", "bridge-ios.html", "installed-manifest.json"]
        return required.allSatisfy {
            fileManager.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
    }

    private func loadInstalledManifest(dir: URL) throws -> Manifest {
        let url = dir.appendingPathComponent("installed-manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func checkMinAppVersion(_ required: String) throws {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        if Self.compareSemver(current, required) == .orderedAscending {
            throw BundleError.appVersionTooLow(required: required, current: current)
        }
    }

    /// Numeric semver compare: `1.2.0` vs `1.10.0`.
    nonisolated private static func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }
}
