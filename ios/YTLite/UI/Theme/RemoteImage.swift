import Foundation
import UIKit
import SwiftUI
import ImageIO

/// Memory + disk image loader for remote thumbnails.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let folder: URL
    private let ioQueue = DispatchQueue(label: "com.ytlite.image-store", qos: .utility)
    private let stateLock = NSLock()
    /// Waiters for an in-flight load of the same cache key.
    private var inFlight: [String: [CheckedContinuation<UIImage?, Never>]] = [:]
    private var leaders: Set<String> = []

    private init() {
        memory.countLimit = 250
        memory.totalCostLimit = 48 * 1024 * 1024
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = base.appendingPathComponent("remote_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            diskPath: "ytlite_url"
        )
        session = URLSession(configuration: config)
    }

    func image(for url: URL, maxPixelSize: Int? = nil) async -> UIImage? {
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let mem = memory.object(forKey: key as NSString) {
            return mem
        }

        if let joined = await joinOrLead(key: key) {
            return joined
        }

        var loaded: UIImage?
        defer { finishInFlight(key: key, image: loaded) }
        loaded = await loadUncached(url: url, maxPixelSize: maxPixelSize)
        if let loaded {
            memory.setObject(loaded, forKey: key as NSString, cost: loaded.approximateCost)
        }
        return loaded
    }

    /// Returns `nil` when this caller should perform the load (leader).
    /// Returns `Optional.some(image)` when this caller waited for another load.
    private func joinOrLead(key: String) async -> UIImage?? {
        let shouldLead: Bool = {
            stateLock.lock()
            defer { stateLock.unlock() }
            if leaders.contains(key) {
                return false
            }
            leaders.insert(key)
            inFlight[key] = []
            return true
        }()

        if shouldLead {
            // Distinct from "waiter got a nil image": outer nil means lead.
            return nil
        }

        let image: UIImage? = await withCheckedContinuation { cont in
            stateLock.lock()
            if !leaders.contains(key) {
                // Leader already finished between our check and now — shouldn't happen often.
                stateLock.unlock()
                cont.resume(returning: memory.object(forKey: key as NSString))
                return
            }
            inFlight[key, default: []].append(cont)
            stateLock.unlock()
        }
        return .some(image)
    }

    private func finishInFlight(key: String, image: UIImage?) {
        stateLock.lock()
        let waiters = inFlight.removeValue(forKey: key) ?? []
        leaders.remove(key)
        stateLock.unlock()
        for waiter in waiters {
            waiter.resume(returning: image)
        }
    }

    private func loadUncached(url: URL, maxPixelSize: Int?) async -> UIImage? {
        if url.isFileURL {
            return await decodeFile(url: url, maxPixelSize: maxPixelSize)
        }
        if let disk = await loadFromDisk(url: url, maxPixelSize: maxPixelSize) {
            return disk
        }
        do {
            var request = URLRequest(url: url)
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            if let host = url.host, host.contains("ggpht.com") || host.contains("googleusercontent.com") {
                request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            saveToDisk(data: data, url: url)
            return Self.decodeImage(data: data, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }

    private func loadFromDisk(url: URL, maxPixelSize: Int?) async -> UIImage? {
        let file = diskFile(for: url)
        return await withCheckedContinuation { cont in
            ioQueue.async {
                guard let data = try? Data(contentsOf: file) else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: Self.decodeImage(data: data, maxPixelSize: maxPixelSize))
            }
        }
    }

    private func decodeFile(url: URL, maxPixelSize: Int?) async -> UIImage? {
        await withCheckedContinuation { cont in
            ioQueue.async {
                guard let data = try? Data(contentsOf: url) else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: Self.decodeImage(data: data, maxPixelSize: maxPixelSize))
            }
        }
    }

    private func saveToDisk(data: Data, url: URL) {
        let file = diskFile(for: url)
        ioQueue.async {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func diskFile(for url: URL) -> URL {
        let name = url.absoluteString.data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            ?? UUID().uuidString
        return folder.appendingPathComponent(name)
    }

    func cacheKey(url: URL, maxPixelSize: Int?) -> String {
        if let maxPixelSize, maxPixelSize > 0 {
            return "\(url.absoluteString)#\(maxPixelSize)"
        }
        return url.absoluteString
    }

    static func decodeImage(data: Data, maxPixelSize: Int?) -> UIImage? {
        guard let maxPixelSize, maxPixelSize > 0 else {
            return UIImage(data: data)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

private extension UIImage {
    var approximateCost: Int {
        Int(size.width * size.height * scale * scale * 4)
    }
}

/// SwiftUI image that reuses `ImageStore` (memory + disk).
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// Longest edge in points; converted to pixels via screen scale for decode.
    var maxPointSize: CGFloat? = nil

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                YTLiteColor.surfaceVariant
            }
        }
        .task(id: taskId) {
            await load()
        }
    }

    private var taskId: String {
        "\(url?.absoluteString ?? "")|\(maxPointSize.map { Int($0) } ?? 0)"
    }

    private var maxPixelSize: Int? {
        guard let maxPointSize else { return nil }
        let scale = UIScreen.main.scale
        return max(1, Int(maxPointSize * scale))
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let mem = ImageStore.shared.memoryHit(url, maxPixelSize: maxPixelSize) {
            image = mem
            return
        }
        let loaded = await ImageStore.shared.image(for: url, maxPixelSize: maxPixelSize)
        guard !Task.isCancelled else { return }
        image = loaded
        loadFailed = loaded == nil
    }
}

extension ImageStore {
    /// Synchronous memory peek used by `RemoteImage` to avoid flicker.
    func memoryHit(_ url: URL, maxPixelSize: Int? = nil) -> UIImage? {
        memory.object(forKey: cacheKey(url: url, maxPixelSize: maxPixelSize) as NSString)
    }
}
