import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import PrimuseKit

/// Per-song dominant-color cache. Used by HomeView's recommendation /
/// continue-listening cards to tint their backgrounds with a soft
/// gradient pulled from the song's cover art — the "your music drives
/// the visuals" idea, no static decoration art needed.
///
/// Distinct from `ThemeService` (global accent for the currently
/// playing song): this never mutates app-wide state. Each card asks
/// for its own song's tint, gets a `Color?` back; the provider
/// schedules background extraction on first request and caches the
/// result for the rest of the app session.
@MainActor
@Observable
final class CoverTintProvider {
    /// In-memory cache: songID → derived tint. Reset on memory
    /// pressure via `clearCache()`. Covers don't change often, so a
    /// cold launch + extract pass for ~12 visible cards is cheap and
    /// the cache stays warm afterwards.
    private var cache: [String: Color] = [:]
    private var inFlight: Set<String> = []

    /// Synchronous read. Returns the cached tint if extraction has
    /// finished. Returns nil while computation is pending — callers
    /// fall back to plain Material until the cache fills in, at which
    /// point @Observable triggers a re-render.
    func tint(forSongID songID: String) -> Color? {
        cache[songID]
    }

    /// Schedule background extraction for any songs not already
    /// cached. Idempotent — safe to call on every body re-eval.
    func prepare(_ songs: [Song]) {
        let pending = songs.filter {
            cache[$0.id] == nil && !inFlight.contains($0.id)
        }
        guard !pending.isEmpty else { return }

        let pendingIDs = Set(pending.map(\.id))
        inFlight.formUnion(pendingIDs)
        Task.detached(priority: .utility) {
            // Read/decode the small visible set serially on one utility task.
            // Publishing one completed dictionary avoids re-evaluating the
            // entire HomeView once for every individual cover tint.
            var extracted: [String: Color] = [:]
            extracted.reserveCapacity(pending.count)
            for song in pending {
                guard !Task.isCancelled else { break }
                if let color = Self.computeTint(
                    songID: song.id,
                    coverFileName: song.coverArtFileName
                ) {
                    extracted[song.id] = color
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !extracted.isEmpty {
                    var nextCache = self.cache
                    nextCache.merge(extracted) { _, new in new }
                    self.cache = nextCache
                }
                self.inFlight.subtract(pendingIDs)
            }
        }
    }

    func clearCache() {
        cache.removeAll(keepingCapacity: false)
    }

    /// Off-main extraction. Mirrors ThemeService's load-then-extract
    /// flow: try songID-derived hashed filename first, fall back to
    /// the legacy filename column. `MetadataAssetStore.readCoverData`
    /// is `nonisolated`, so no actor hop needed.
    nonisolated private static func computeTint(songID: String, coverFileName: String?) -> Color? {
        let hashedName = MetadataAssetStore.shared.expectedCoverFileName(for: songID)
        var data = MetadataAssetStore.shared.readCoverData(named: hashedName)
        if data == nil,
           let coverFileName,
           !coverFileName.isEmpty,
           !coverFileName.contains("/"),
           !coverFileName.contains("://") {
            data = MetadataAssetStore.shared.readCoverData(named: coverFileName)
        }
        guard let data, let image = PlatformImage(data: data) else { return nil }
        return ThemeService.extractDominantColor(from: image).accent
    }
}
