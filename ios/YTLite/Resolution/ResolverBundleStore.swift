import Foundation
import CryptoKit

/// Resolver knobs shipped with the app bundle.
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

/// Thread-safe snapshot of the resolver config shipped in the app bundle.
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
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        CatalogConstants.applyPreferredVideoItags(config.preferItags)
    }
}

/// Loads the resolver scripts shipped in the app bundle. Does not download or replace them.
actor ResolverBundleStore {
    private enum RemoteContract {
        static var scriptFile: String { SaltedLiteral.scriptResolution }
        static let bridgeHTML = "bridge.html"
        static let bridgeIOSHTML = "bridge-ios.html"
    }

    enum BundleError: LocalizedError {
        case checksumMismatch(String)
        case incompleteBundle
        case appVersionTooLow(required: String, current: String)
        case incompatibleNativeApi(remote: Int, local: Int)
        case invalidManifest

        var errorDescription: String? {
            switch self {
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

    /// Copy the shipped scripts over any previously stored copy, then return that directory.
    func ensureBundle() async throws -> URL {
        let manifest = try installBundledCopy()
        ResolverRemoteConfigStore.apply(manifest.config ?? .defaults)
        return try storeDirectory()
    }

    // MARK: - Private

    /// Always replace the on-disk copy with the scripts in the app bundle.
    private func installBundledCopy() throws -> Manifest {
        guard let manifestURL = bundledResourceURL(name: "bundled-manifest.json"),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData)
        else { throw BundleError.incompleteBundle }
        guard Self.isCompatible(manifest) else {
            throw BundleError.incompatibleNativeApi(remote: manifest.nativeApi, local: Self.nativeApi)
        }
        try checkMinAppVersion(manifest.minAppVersion)

        let required = [
            RemoteContract.scriptFile,
            RemoteContract.bridgeHTML,
            RemoteContract.bridgeIOSHTML,
        ]
        for name in required where manifest.files[name] == nil {
            throw BundleError.invalidManifest
        }

        let dir = try storeDirectory()
        var payloads: [(String, Data)] = []
        for name in required {
            guard let entry = manifest.files[name],
                  let url = bundledResourceURL(name: name),
                  let bytes = try? Data(contentsOf: url)
            else { throw BundleError.incompleteBundle }
            let digest = SHA256.hash(data: bytes)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex.caseInsensitiveCompare(entry.sha256) == .orderedSame else {
                throw BundleError.checksumMismatch(name)
            }
            payloads.append((name, bytes))
        }

        let staging = dir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for (name, bytes) in payloads {
                try bytes.write(to: staging.appendingPathComponent(name), options: .atomic)
            }
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
            PlayProbe.log(
                "resolver.bundle.seeded",
                "version=\(manifest.version) nativeApi=\(manifest.nativeApi)"
            )
            return manifest
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    nonisolated private func bundledResourceURL(name: String) -> URL? {
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        let fileExtension: String? = ext.isEmpty ? nil : ext
        if let url = Bundle.main.url(
            forResource: base,
            withExtension: fileExtension,
            subdirectory: "resolver"
        ) {
            return url
        }
        return Bundle.main.url(forResource: base, withExtension: fileExtension)
    }

    nonisolated private static func isCompatible(_ manifest: Manifest) -> Bool {
        nativeApi >= manifest.minNativeApi && nativeApi <= manifest.nativeApi
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
