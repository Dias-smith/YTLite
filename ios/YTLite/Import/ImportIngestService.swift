import AVFoundation
import Foundation
import ImageIO
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
            let meta = await probeMetadata(url: sourceURL)
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

    private func probeMetadata(url: URL) async -> Probed {
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
                   let data = try? await item.load(.dataValue)
                {
                    artwork = data
                    break
                }
            }
        }
        // Videos often have no embedded album art — grab a frame as cover.
        if artwork == nil {
            artwork = await extractVideoPoster(asset: asset, durationSeconds: durationSeconds)
        }
        return Probed(durationSeconds: durationSeconds, artworkData: artwork)
    }

    /// First usable video frame (≈1s or 10% of duration) as JPEG cover.
    private func extractVideoPoster(asset: AVURLAsset, durationSeconds: Int) async -> Data? {
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
            return nil
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let candidates: [Double] = {
            if durationSeconds <= 0 { return [0.5, 0] }
            let mid = min(1.0, max(0.1, Double(durationSeconds) * 0.1))
            return [mid, 0.5, 0]
        }()
        for seconds in candidates {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cgImage = try? await generator.image(at: time).image,
                  let jpeg = jpegData(from: cgImage, quality: 0.85)
            else { continue }
            return jpeg
        }
        return nil
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
