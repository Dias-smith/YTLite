import Foundation
import CryptoKit

/// Installed / remote resolver knobs (from Supabase Storage `manifest.json` `config`).
struct ResolverRemoteConfig: Codable, Equatable, Sendable {
    var androidClientVersion: String
    var signatureTimestamp: Int
    var preferItags: [Int]
    var enableAndroidPlayerFallback: Bool
    var enableWatchPageFallback: Bool

    static let defaults = ResolverRemoteConfig(
        androidClientVersion: "20.10.38",
        signatureTimestamp: 20_646,
        preferItags: [18, 22, 37],
        enableAndroidPlayerFallback: true,
        enableWatchPageFallback: true
    )
}

/// Thread-safe snapshot of the last successfully installed resolver config.
enum ResolverRemoteConfigStore {
    private static let lock = NSLock()
    private static var _current = ResolverRemoteConfig.defaults
    private static let defaultsKey = "resolver_remote_config_json"

    static var current: ResolverRemoteConfig {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    static func apply(_ config: ResolverRemoteConfig) {
        lock.lock()
        _current = config
        lock.unlock()
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        CatalogConstants.applyPreferredVideoItags(config.preferItags)
    }

    static func restoreFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(ResolverRemoteConfig.self, from: data)
        else { return }
        apply(config)
    }
}

/// Fetches / stores remote resolver assets from Supabase Storage (no in-app bundle).
actor ResolverBundleStore {
    /// Remote Storage bucket + asset names — must match published Supabase objects.
    private enum RemoteContract {
        static let storageBucket = "resolution"
        static var scriptFile: String { SaltedLiteral.scriptResolution }
        static let bridgeHTML = "bridge.html"
        static let bridgeIOSHTML = "bridge-ios.html"
    }

    enum BundleError: LocalizedError {
        case supabaseNotConfigured
        case fetchFailed(String)
        case checksumMismatch(String)
        case incompleteBundle
        case appVersionTooLow(required: String, current: String)
        case incompatibleNativeApi(remote: Int, local: Int)
        case invalidManifest

        var errorDescription: String? {
            switch self {
            case .supabaseNotConfigured:
                return "Supabase URL is not configured; cannot fetch stream resolver"
            case .fetchFailed(let msg):
                return "Stream resolver fetch failed: \(msg)"
            case .checksumMismatch(let file):
                return "Stream resolver checksum mismatch: \(file)"
            case .incompleteBundle:
                return "Stream resolver bundle incomplete"
            case .appVersionTooLow(let required, let current):
                return "App \(current) is too old for stream resolver (needs \(required))"
            case .incompatibleNativeApi(let remote, let local):
                return "Stream resolver nativeApi=\(remote) is not compatible with app api=\(local)"
            case .invalidManifest:
                return "Invalid stream resolver manifest"
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
        /// Highest native protocol this bundle speaks.
        var nativeApi: Int
        /// Lowest native protocol this bundle speaks (defaults to `nativeApi`).
        var minNativeApi: Int
        var files: [String: ManifestFile]
        var config: ResolverRemoteConfig?

        enum CodingKeys: String, CodingKey {
            case version, minAppVersion, nativeApi, minNativeApi, files, config
        }

        init(
            version: Int,
            minAppVersion: String,
            nativeApi: Int,
            minNativeApi: Int,
            files: [String: ManifestFile],
            config: ResolverRemoteConfig?
        ) {
            self.version = version
            self.minAppVersion = minAppVersion
            self.nativeApi = nativeApi
            self.minNativeApi = minNativeApi
            self.files = files
            self.config = config
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            minAppVersion = try c.decodeIfPresent(String.self, forKey: .minAppVersion) ?? "1.0.0"
            let api = try c.decodeIfPresent(Int.self, forKey: .nativeApi) ?? 1
            nativeApi = api
            minNativeApi = try c.decodeIfPresent(Int.self, forKey: .minNativeApi) ?? api
            files = try c.decode([String: ManifestFile].self, forKey: .files)
            config = try c.decodeIfPresent(ResolverRemoteConfig.self, forKey: .config)
        }
    }

    /// Bump only when the JS ↔ native bridge / resolve payload contract changes.
    static let nativeApi = 1

    static let shared = ResolverBundleStore()

    private let fileManager = FileManager.default
    private var lastBackgroundCheck: Date?

    func ensureBundle(backgroundRefresh: Bool = true) async throws -> URL {
        ResolverRemoteConfigStore.restoreFromDisk()
        let dir = try storeDirectory()
        if isComplete(dir: dir) {
            if let installed = try? loadInstalledManifest(dir: dir) {
                ResolverRemoteConfigStore.apply(installed.config ?? .defaults)
            }
            if backgroundRefresh {
                scheduleBackgroundRefreshIfNeeded()
            }
            return dir
        }
        try await fetchAndInstall()
        return try storeDirectory()
    }

    func storeDirectoryURL() throws -> URL {
        try storeDirectory()
    }

    func installedManifest() throws -> Manifest? {
        let dir = try storeDirectory()
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
        let remote: Manifest
        do {
            remote = try await fetchCompatibleManifest()
        } catch {
            PlayProbe.log(
                "resolver.bundle.compat_skip",
                "keepInstalled=1 err=\(error.localizedDescription)"
            )
            return
        }
        let dir = try storeDirectory()
        let installedVersion = (try? loadInstalledManifest(dir: dir))?.version ?? 0
        guard remote.version > installedVersion else { return }
        guard Self.isCompatible(remote) else { return }
        do {
            try await install(manifest: remote)
        } catch let BundleError.appVersionTooLow(required, _) {
            PlayProbe.log(
                "resolver.bundle.min_app_skip",
                "keepInstalled=1 required=\(required)"
            )
        }
    }

    private func fetchAndInstall() async throws {
        let remote = try await fetchCompatibleManifest()
        try await install(manifest: remote)
    }

    private func install(manifest: Manifest) async throws {
        guard Self.isCompatible(manifest) else {
            throw BundleError.incompatibleNativeApi(remote: manifest.nativeApi, local: Self.nativeApi)
        }
        try checkMinAppVersion(manifest.minAppVersion)
        let required = [
            RemoteContract.scriptFile,
            RemoteContract.bridgeHTML,
            RemoteContract.bridgeIOSHTML,
        ]
        for name in required {
            guard manifest.files[name] != nil else { throw BundleError.invalidManifest }
        }

        let dir = try storeDirectory()
        let staging = dir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            for name in required {
                let entry = manifest.files[name]!
                let bytes = try await fetchPublicObject(relativePath: entry.path)
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
            ResolverRemoteConfigStore.apply(manifest.config ?? .defaults)
            PlayProbe.log(
                "resolver.bundle.installed",
                "version=\(manifest.version) nativeApi=\(manifest.nativeApi) sts=\(ResolverRemoteConfigStore.current.signatureTimestamp)"
            )
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func fetchCompatibleManifest() async throws -> Manifest {
        let latest = try await fetchManifest(relativePath: "manifest.json")
        if Self.isCompatible(latest) {
            return latest
        }
        let channelPath = "compat/api-\(Self.nativeApi)/manifest.json"
        do {
            let channel = try await fetchManifest(relativePath: channelPath)
            if Self.isCompatible(channel) {
                PlayProbe.log(
                    "resolver.bundle.compat_channel",
                    "nativeApi=\(Self.nativeApi) version=\(channel.version)"
                )
                return channel
            }
        } catch {
            PlayProbe.log(
                "resolver.bundle.compat_miss",
                "path=\(channelPath) err=\(error.localizedDescription)"
            )
        }
        throw BundleError.incompatibleNativeApi(remote: latest.nativeApi, local: Self.nativeApi)
    }

    private func fetchManifest(relativePath: String = "manifest.json") async throws -> Manifest {
        let url = try publicURL(relativePath: relativePath)
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw BundleError.fetchFailed("\(relativePath) HTTP \(code)")
        }
        do {
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw BundleError.invalidManifest
        }
    }

    nonisolated private static func isCompatible(_ manifest: Manifest) -> Bool {
        nativeApi >= manifest.minNativeApi && nativeApi <= manifest.nativeApi
    }

    private func fetchPublicObject(relativePath: String) async throws -> Data {
        let url = try publicURL(relativePath: relativePath)
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code), !data.isEmpty else {
            throw BundleError.fetchFailed("\(relativePath) HTTP \(code)")
        }
        return data
    }

    private func publicURL(relativePath: String) throws -> URL {
        let base = AppConfig.fromBundle().supabaseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty else { throw BundleError.supabaseNotConfigured }
        let path = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/storage/v1/object/public/\(RemoteContract.storageBucket)/\(path)") else {
            throw BundleError.fetchFailed("bad url \(path)")
        }
        return url
    }

    private func storeDirectory() throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = root.appendingPathComponent("resolver", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func isComplete(dir: URL) -> Bool {
        let required = [
            RemoteContract.scriptFile,
            RemoteContract.bridgeHTML,
            RemoteContract.bridgeIOSHTML,
            "installed-manifest.json",
        ]
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
