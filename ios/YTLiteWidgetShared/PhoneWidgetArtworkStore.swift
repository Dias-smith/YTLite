import Foundation
import UIKit

/// Cover art in the App Group container — WidgetKit cannot reliably load YouTube CDN via AsyncImage.
enum PhoneWidgetArtworkStore {
    private static let folderName = "WidgetArtwork"

    private static var directoryURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PhoneWidgetShared.appGroupId)?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func fileURL(videoId: String) -> URL? {
        let trimmed = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let directoryURL else { return nil }
        let safe = trimmed.replacingOccurrences(of: "/", with: "_")
        return directoryURL.appendingPathComponent("\(safe).jpg", isDirectory: false)
    }

    @discardableResult
    static func save(_ image: UIImage, videoId: String) -> Bool {
        guard let directoryURL, let fileURL = fileURL(videoId: videoId) else { return false }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let maxPixel: CGFloat = 512
            let rendered = resized(image, maxPixel: maxPixel)
            guard let data = rendered.jpegData(compressionQuality: 0.84) else { return false }
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load(videoId: String) -> UIImage? {
        guard let fileURL = fileURL(videoId: videoId),
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }
        return UIImage(data: data)
    }

    static func remove(videoId: String) {
        guard let fileURL = fileURL(videoId: videoId) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func resized(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxPixel, longest > 0 else { return image }
        let scale = maxPixel / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
