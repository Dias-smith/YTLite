import Foundation
import UIKit
import SwiftUI

/// Memory + disk image loader for remote thumbnails.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private let folder: URL
    private let ioQueue = DispatchQueue(label: "com.ytlite.image-store", qos: .utility)

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 40 * 1024 * 1024
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = base.appendingPathComponent("remote_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            diskPath: "ytlite_url"
        )
        session = URLSession(configuration: config)
    }

    func image(for url: URL) async -> UIImage? {
        if let mem = memory.object(forKey: url as NSURL) {
            return mem
        }
        if url.isFileURL {
            let local = await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
                ioQueue.async {
                    cont.resume(returning: UIImage(contentsOfFile: url.path))
                }
            }
            if let local {
                memory.setObject(local, forKey: url as NSURL, cost: local.approximateCost)
            }
            return local
        }
        if let disk = await loadFromDisk(url: url) {
            memory.setObject(disk, forKey: url as NSURL, cost: disk.approximateCost)
            return disk
        }
        do {
            var request = URLRequest(url: url)
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            // yt3.ggpht / googleusercontent occasionally require a YouTube referer.
            if let host = url.host, host.contains("ggpht.com") || host.contains("googleusercontent.com") {
                request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
            }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data)
            else { return nil }
            memory.setObject(image, forKey: url as NSURL, cost: image.approximateCost)
            saveToDisk(data: data, url: url)
            return image
        } catch {
            return nil
        }
    }

    private func loadFromDisk(url: URL) async -> UIImage? {
        let file = diskFile(for: url)
        return await withCheckedContinuation { cont in
            ioQueue.async {
                guard let data = try? Data(contentsOf: file),
                      let image = UIImage(data: data)
                else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: image)
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
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let mem = ImageStore.shared.memoryHit(url) {
            image = mem
            return
        }
        let loaded = await ImageStore.shared.image(for: url)
        image = loaded
        loadFailed = loaded == nil
    }
}

extension ImageStore {
    /// Synchronous memory peek used by `RemoteImage` to avoid flicker.
    func memoryHit(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }
}
