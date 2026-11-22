import AVFoundation
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ImportIngestService {
    static let shared = ImportIngestService()

    struct Result: Sendable {
        let trackId: String
        let item: VideoItem
    }

    private init() {}

    func ingestFileURL(
        _ url: URL,
        sourceKind: ImportSourceKind,
        store: LibraryStore,
        titleHint: String? = nil,
        artistHint: String? = nil,
        remoteURI: String? = nil,
        cacheEligible: Bool = false
    ) async throws -> Result {
        let trackId = LocalTrackID.make()
        let (rel, hash, _) = try LocalMediaStore.shared.ingestCopy(from: url, trackId: trackId)
        return try await finalize(
            trackId: trackId,
            relativePath: rel,
            contentHash: hash,
            sourceURL: LocalMediaStore.shared.audioURL(trackId: trackId, relativePath: rel),
            sourceKind: sourceKind,
            store: store,
            titleHint: titleHint ?? url.deletingPathExtension().lastPathComponent,
            artistHint: artistHint,
            remoteURI: remoteURI,
            cacheEligible: cacheEligible
        )
    }

    func ingestData(
        _ data: Data,
        fileExtension: String,
        fileName: String,
        sourceKind: ImportSourceKind,
        store: LibraryStore,
        remoteURI: String? = nil,
        cacheEligible: Bool = false
    ) async throws -> Result {
        let trackId = LocalTrackID.make()
        let (rel, hash, _) = try LocalMediaStore.shared.ingestData(
            data,
            trackId: trackId,
            fileExtension: fileExtension
        )
        let title = (fileName as NSString).deletingPathExtension
        return try await finalize(
            trackId: trackId,
            relativePath: rel,
            contentHash: hash,
            sourceURL: LocalMediaStore.shared.audioURL(trackId: trackId, relativePath: rel),
            sourceKind: sourceKind,
            store: store,
            titleHint: title.isEmpty ? fileName : title,
            artistHint: nil,
            remoteURI: remoteURI,
            cacheEligible: cacheEligible
        )
    }

    /// Stores a JPEG cover for an imported track when the audio file had none.
    /// A blank frame already on disk can be replaced.
    func attachCover(trackId: String, jpeg: Data, store: LibraryStore, overwrite: Bool = false) throws {
        guard !jpeg.isEmpty, store.track(id: trackId) != nil else { return }
        let file = ImportCoverStorage.fileURL(trackId: trackId)
        if FileManager.default.fileExists(atPath: file.path) {
            guard overwrite else { return }
            try? FileManager.default.removeItem(at: file)
        }
        let token = try writeArtwork(jpeg, trackId: trackId)
        guard let track = store.track(id: trackId) else { return }
        track.thumbnailHigh = token
        track.updatedAt = .now
        store.saveLocalOnly()
    }

    /// True when this track has no cover, or the saved cover is a near-black frame.
    func coverNeedsReplacement(trackId: String) -> Bool {
        let file = ImportCoverStorage.fileURL(trackId: trackId)
        guard FileManager.default.fileExists(atPath: file.path) else { return true }
        return Self.jpegFileIsNearlyBlank(file)
    }

    /// Grabs a later, non-black video frame when the track still has no usable cover.
    func fillCoverIfBlank(trackId: String, store: LibraryStore) async {
        guard coverNeedsReplacement(trackId: trackId),
              let track = store.track(id: trackId),
              let audioURL = LocalMediaStore.shared.audioURL(
                trackId: trackId,
                relativePath: track.localRelativePath
              )
        else { return }
        let asset = AVURLAsset(url: audioURL)
        let duration = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        let seconds = duration.isFinite && duration > 0 ? Int(duration.rounded()) : track.durationSeconds
        guard let jpeg = await extractVideoPoster(asset: asset, durationSeconds: seconds) else { return }
        try? attachCover(trackId: trackId, jpeg: jpeg, store: store, overwrite: true)
    }

    /// Re-cache into an existing imported track (same trackId), e.g. WebDAV auto-cache refresh.
    func replaceAudio(
        trackId: String,
        from url: URL,
        store: LibraryStore
    ) throws {
        let (rel, hash, _) = try LocalMediaStore.shared.ingestCopy(from: url, trackId: trackId)
        guard let track = store.track(id: trackId) else { return }
        track.localRelativePath = rel
        track.contentHash = hash
        track.updatedAt = .now
        store.saveLocalOnly()
    }

    func replaceAudio(
        trackId: String,
        data: Data,
        fileExtension: String,
        store: LibraryStore
    ) throws {
        let (rel, hash, _) = try LocalMediaStore.shared.ingestData(
            data,
            trackId: trackId,
            fileExtension: fileExtension
        )
        guard let track = store.track(id: trackId) else { return }
        track.localRelativePath = rel
        track.contentHash = hash
        track.updatedAt = .now
        store.saveLocalOnly()
    }

    private func finalize(
        trackId: String,
        relativePath: String,
        contentHash: String,
        sourceURL: URL?,
        sourceKind: ImportSourceKind,
        store: LibraryStore,
        titleHint: String,
        artistHint: String?,
        remoteURI: String?,
        cacheEligible: Bool
    ) async throws -> Result {
        if let existing = store.importedTrack(contentHash: contentHash) {
            LocalMediaStore.shared.remove(trackId: trackId)
            return Result(trackId: existing.trackId, item: existing.asVideoItem)
        }

        var duration = 0
        var artworkToken: String?
        if let sourceURL {
            let meta = await probeMetadata(url: sourceURL, allowVideoPoster: sourceKind != .mac)
            duration = meta.durationSeconds
            if let art = meta.artworkData {
                artworkToken = try? writeArtwork(art, trackId: trackId)
            }
        }

        let trimmedTitle = titleHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? trackId : trimmedTitle
        let trimmedArtist = artistHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist: String? = trimmedArtist.isEmpty ? nil : trimmedArtist
        // Prefer the stable token as the URL string so SwiftData never stores a sandbox-absolute path.
        let thumbURL = artworkToken.flatMap(URL.init(string:))
            ?? ImportCoverStorage.existingURL(trackId: trackId)
        let item = VideoItem(
            videoId: trackId,
            title: title,
            channelName: artist ?? L("import.artist.unknown"),
            thumbnailURL: thumbURL,
            durationText: DurationFormat.text(seconds: duration)
        )
        let track = store.upsertImportedTrack(
            item: item,
            sourceKind: sourceKind,
            localRelativePath: relativePath,
            contentHash: contentHash,
            remoteURI: remoteURI,
            cacheEligible: cacheEligible,
            durationSeconds: duration
        )
        if let artworkToken {
            track.thumbnailHigh = artworkToken
            store.saveLocalOnly()
        }
        store.ensureImportedPlaylistEntry(trackId: trackId)
        store.trimImportCacheIfNeeded()
        let displayItem = VideoItem(
            videoId: item.videoId,
            title: item.title,
            channelName: item.channelName,
            thumbnailURL: ImportCoverStorage.resolveURL(
                trackId: trackId,
                stored: artworkToken ?? track.thumbnailHigh
            ),
            durationText: item.durationText
        )
        return Result(trackId: trackId, item: displayItem)
    }

    private struct Probed {
        var durationSeconds: Int
        var artworkData: Data?
    }

    private func probeMetadata(url: URL, allowVideoPoster: Bool) async -> Probed {
        let asset = AVURLAsset(url: url)
        var durationSeconds = 0
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                durationSeconds = Int(seconds.rounded())
            }
        }
        var artwork: Data?
        if let meta = try? await asset.load(.metadata) {
            for item in meta {
                guard let common = item.commonKey else { continue }
                if common == .commonKeyArtwork,
                   let data = try? await item.load(.dataValue),
                   !data.isEmpty,
                   !Self.jpegDataIsNearlyBlank(data)
                {
                    artwork = data
                    break
                }
            }
        }
        // Mac imports prefer the transferred thumbnail. A generated frame is only a fallback.
        if artwork == nil, allowVideoPoster {
            artwork = await extractVideoPoster(asset: asset, durationSeconds: durationSeconds)
        }
        return Probed(durationSeconds: durationSeconds, artworkData: artwork)
    }

    /// A frame from later in the video. The generator's default tolerance snaps to the opening keyframe, which is often black.
    private func extractVideoPoster(asset: AVURLAsset, durationSeconds: Int) async -> Data? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
            return nil
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let tolerance = CMTime(seconds: 0.35, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        for seconds in posterTimes(durationSeconds: durationSeconds) {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cgImage = try? await generator.image(at: time).image,
                  !Self.isNearlyBlank(cgImage),
                  let jpeg = jpegData(from: cgImage, quality: 0.85)
            else { continue }
            return jpeg
        }
        return nil
    }

    /// Sample past the usual black lead-in. Never asks for time zero.
    private func posterTimes(durationSeconds: Int) -> [Double] {
        let duration = Double(durationSeconds)
        guard duration > 1 else { return [0.4] }
        let end = max(1, duration - 0.3)
        let raw = [
            min(end, max(8, duration * 0.12)),
            min(end, duration * 0.30),
            min(end, duration * 0.50),
            min(end, 15),
            min(end, 5),
        ]
        var times: [Double] = []
        for time in raw where time >= 1 || duration < 4 {
            if times.allSatisfy({ abs($0 - time) >= 0.5 }) {
                times.append(time)
            }
        }
        return times.isEmpty ? [min(end, 1)] : times
    }

    static func jpegDataIsNearlyBlank(_ data: Data) -> Bool {
        guard let image = UIImage(data: data)?.cgImage else { return false }
        return isNearlyBlank(image)
    }

    private static func jpegFileIsNearlyBlank(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return jpegDataIsNearlyBlank(data)
    }

    /// A fade-from-black or empty opening frame, not a merely dark scene.
    private static func isNearlyBlank(_ image: CGImage) -> Bool {
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var sum = 0
        var peak = 0
        let count = width * height
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let luma = (Int(pixels[index]) * 3 + Int(pixels[index + 1]) * 6 + Int(pixels[index + 2])) / 10
            sum += luma
            peak = max(peak, luma)
        }
        let average = sum / count
        return average < 16 && peak < 36
    }

    /// Fill missing covers for already-imported video files (embedded art / prior ingest).
    /// Also migrates legacy absolute `file://` thumbnail paths to durable `importcover:` tokens.
    func backfillMissingCovers(store: LibraryStore) async -> Int {
        var updated = 0
        for track in store.importedTracks() {
            let trackId = track.trackId
            if ImportCoverStorage.existingURL(trackId: trackId) != nil {
                // Cover file is on disk — normalize DB to a stable token if needed.
                if !ImportCoverStorage.isImportCoverToken(track.thumbnailHigh) {
                    track.thumbnailHigh = ImportCoverStorage.token(for: trackId)
                    track.updatedAt = .now
                    updated += 1
                }
                continue
            }
            // Skip remote http thumbs; only extract for imports that still need a local cover.
            if let thumb = track.thumbnailURLString,
               thumb.hasPrefix("http://") || thumb.hasPrefix("https://")
            {
                continue
            }
            guard let audioURL = LocalMediaStore.shared.audioURL(
                trackId: trackId,
                relativePath: track.localRelativePath
            ) else { continue }
            let asset = AVURLAsset(url: audioURL)
            guard let data = await extractVideoPoster(
                asset: asset,
                durationSeconds: track.durationSeconds
            ),
                  let token = try? writeArtwork(data, trackId: trackId)
            else { continue }
            track.thumbnailHigh = token
            track.updatedAt = .now
            updated += 1
        }
        if updated > 0 {
            store.saveLocalOnly()
        }
        return updated
    }

    private func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Writes JPEG next to the audio file and returns a stable `importcover:{trackId}` token.
    private func writeArtwork(_ data: Data, trackId: String) throws -> String {
        let dir = LocalMediaStore.shared.directory(for: trackId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = ImportCoverStorage.fileURL(trackId: trackId)
        try data.write(to: url, options: .atomic)
        return ImportCoverStorage.token(for: trackId)
    }

    static func isSupportedAudioURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if LocalMediaStore.audioExtensions.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext) {
            return type.conforms(to: .audio) || type.conforms(to: .movie)
        }
        return false
    }
}
