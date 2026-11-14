import AVFoundation
import Foundation
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
        var artworkURL: URL?
        if let sourceURL {
            let meta = await probeMetadata(url: sourceURL)
            duration = meta.durationSeconds
            if let art = meta.artworkData {
                artworkURL = try? writeArtwork(art, trackId: trackId)
            }
        }

        let trimmedTitle = titleHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? trackId : trimmedTitle
        let trimmedArtist = artistHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist: String? = trimmedArtist.isEmpty ? nil : trimmedArtist
        let item = VideoItem(
            videoId: trackId,
            title: title,
            channelName: artist ?? L("import.artist.unknown"),
            thumbnailURL: artworkURL,
            durationText: DurationFormat.text(seconds: duration)
        )
        _ = store.upsertImportedTrack(
            item: item,
            sourceKind: sourceKind,
            localRelativePath: relativePath,
            contentHash: contentHash,
            remoteURI: remoteURI,
            cacheEligible: cacheEligible,
            durationSeconds: duration
        )
        store.ensureImportedPlaylistEntry(trackId: trackId)
        store.trimImportCacheIfNeeded()
        return Result(trackId: trackId, item: item)
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
        return Probed(durationSeconds: durationSeconds, artworkData: artwork)
    }

    private func writeArtwork(_ data: Data, trackId: String) throws -> URL {
        let dir = LocalMediaStore.shared.directory(for: trackId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("cover.jpg")
        try data.write(to: url, options: .atomic)
        return url
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
