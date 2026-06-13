#if os(iOS)
@preconcurrency import Intents
import PrimuseKit

/// Routes Siri "play X" voice commands to the player. Triggered by either:
/// - INPlayMediaIntent dispatched from Siri / CarPlay voice
/// - NSUserActivity restoration (`scene(_:continue:)`)
///
/// Without a separate Intents Extension target, Siri can still hand off
/// the intent at runtime via `application(_:handlerFor:)`. The Extension
/// would only matter for offline/locked-device handling.
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling, @unchecked Sendable {
    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        let box = UncheckedBox(completion)
        Task { @MainActor in
            guard let result = Self.resolve(intent: intent) else {
                box.value(INPlayMediaIntentResponse(code: .failureUnknownMediaType, userActivity: nil))
                return
            }
            let player = AppServices.shared.playerService
            let song = result.queue[result.startIndex]
            player.setQueue(result.queue, startAt: result.startIndex)
            await player.play(song: song)
            // play() returns once setup is kicked off; actual playback (esp.
            // cloud sources) can take a few seconds. Poll briefly for the
            // loading-or-playing state — same pattern as the CarPlay path —
            // so we don't tell Siri "playing" when a 401 / network failure
            // left nothing playing.
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if player.isPlaying || player.isLoading { break }
                try? await Task.sleep(for: .milliseconds(150))
            }
            let code: INPlayMediaIntentResponseCode =
                (player.isPlaying || player.isLoading) ? .success : .failure
            box.value(INPlayMediaIntentResponse(code: code, userActivity: nil))
        }
    }

    func resolveMediaItems(
        for intent: INPlayMediaIntent,
        with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void
    ) {
        let box = UncheckedBox(completion)
        Task { @MainActor in
            guard let result = Self.resolve(intent: intent) else {
                // Local library only — there's nothing to "log in" to.
                // Tell Siri the search just didn't match anything so it
                // reads back "I couldn't find that" instead of prompting
                // the user to sign in.
                box.value([INPlayMediaMediaItemResolutionResult.unsupported(forReason: .serviceUnavailable)])
                return
            }
            let inItems = result.queue.map { song in
                INMediaItem(
                    identifier: song.id,
                    title: song.title,
                    type: .song,
                    artwork: nil,
                    artist: song.artistName
                )
            }
            box.value(INPlayMediaMediaItemResolutionResult.successes(with: inItems))
        }
    }

    @MainActor
    private static func resolve(intent: INPlayMediaIntent) -> (queue: [Song], startIndex: Int)? {
        let library = AppServices.shared.musicLibrary
        let search = intent.mediaSearch
        let mediaName = search?.mediaName?.lowercased()
        let artistName = search?.artistName?.lowercased()
        let albumName = search?.albumName?.lowercased()
        let mediaType = search?.mediaType ?? .unknown

        // 1. Album match
        if mediaType == .album || (albumName != nil && mediaName == nil) {
            let target = (albumName ?? mediaName ?? "").lowercased()
            if !target.isEmpty,
               let album = library.visibleAlbums.first(where: {
                   $0.title.lowercased().contains(target)
               }) {
                let songs = library.songs(forAlbum: album.id)
                    .sorted { ($0.discNumber ?? 0, $0.trackNumber ?? 0) < ($1.discNumber ?? 0, $1.trackNumber ?? 0) }
                    .filteredPlayable()
                if !songs.isEmpty { return (songs, 0) }
            }
        }

        // 2. Artist match
        if mediaType == .artist || (artistName != nil && mediaName == nil && albumName == nil) {
            let target = (artistName ?? mediaName ?? "").lowercased()
            if !target.isEmpty,
               let artist = library.visibleArtists.first(where: {
                   $0.name.lowercased().contains(target)
               }) {
                let songs = library.songs(forArtist: artist.id).filteredPlayable()
                if !songs.isEmpty { return (songs, 0) }
            }
        }

        // 3. Song match (default)
        if let target = (mediaName ?? albumName ?? artistName)?.lowercased(),
           !target.isEmpty {
            let matches = library.visibleSongs.filter { song in
                song.title.lowercased().contains(target) ||
                (song.artistName?.lowercased().contains(target) ?? false)
            }.filteredPlayable()
            if !matches.isEmpty {
                return (matches, 0)
            }
        }

        // 4. No usable search term — shuffle whole library. Covers both
        // "mediaSearch == nil" and the common Siri "play music" form where
        // it builds an INMediaSearch(mediaType: .music) with every name
        // field nil/empty. Steps 1–3 skip those, so without this fallback
        // resolve() would return nil and the user hears "service unavailable"
        // even though the library has playable songs.
        let hasSearchTerm = [mediaName, artistName, albumName]
            .contains { ($0?.isEmpty == false) }
        if !hasSearchTerm {
            let pool = library.visibleSongs.filteredPlayable()
            if !pool.isEmpty { return (pool.shuffled(), 0) }
        }

        return nil
    }
}

/// Cross-actor closure box. The Intents protocol's completion handlers
/// aren't `@Sendable`, so we hand them across the actor boundary inside
/// this wrapper which the compiler trusts.
private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
#endif
