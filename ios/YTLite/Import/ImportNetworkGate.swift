import Foundation
import Network

enum ImportNetworkGate {
    /// Whether auto-cache downloads are allowed under current Wi‑Fi-only policy.
    static func allowAutoCacheDownload() async -> Bool {
        guard ImportCachePolicy.wifiOnlyAutoCache else { return true }
        return await withCheckedContinuation { cont in
            let monitor = NWPathMonitor()
            let lock = NSLock()
            var resumed = false
            let finish: (Bool) -> Void = { allowed in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                monitor.cancel()
                cont.resume(returning: allowed)
            }
            monitor.pathUpdateHandler = { path in
                // Allow when Wi‑Fi/wired and not marked expensive cellular.
                let ok = path.status == .satisfied
                    && !path.usesInterfaceType(.cellular)
                    && !path.isExpensive
                finish(ok)
            }
            monitor.start(queue: DispatchQueue(label: "import.network.gate"))
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                finish(true) // fail-open so imports are not stuck offline-probing
            }
        }
    }
}
