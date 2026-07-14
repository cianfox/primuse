import Foundation
import Testing
@testable import PrimuseKit

@Test func testAudioFormatRouting() {
    #expect(AudioFormat.mp3.requiresFFmpeg == false)
    #expect(AudioFormat.flac.requiresFFmpeg == false)
    #expect(AudioFormat.ape.requiresFFmpeg == true)
    #expect(AudioFormat.dsf.requiresFFmpeg == true)
    #expect(AudioFormat.ogg.requiresFFmpeg == true)
}

@Test func testAudioFormatFromExtension() {
    #expect(AudioFormat.from(fileExtension: "mp3") == .mp3)
    #expect(AudioFormat.from(fileExtension: "FLAC") == .flac)
    #expect(AudioFormat.from(fileExtension: "ape") == .ape)
    #expect(AudioFormat.from(fileExtension: "xyz") == nil)
}

@Test func testTransportAwareDefaultPorts() {
    #expect(MusicSourceType.webdav.defaultPort(useSsl: true) == 443)
    #expect(MusicSourceType.webdav.defaultPort(useSsl: false) == 80)
    #expect(MusicSourceType.s3.defaultPort(useSsl: true) == 443)
    #expect(MusicSourceType.s3.defaultPort(useSsl: false) == 80)
    #expect(MusicSourceType.smb.defaultPort(useSsl: true) == 445)
    #expect(MusicSourceType.smb.defaultPort(useSsl: false) == 445)
}

@Test func testVideoFormatRouting() {
    #expect(VideoFormat.from(fileExtension: "MP4") == .mp4)
    #expect(VideoFormat.mov.isNativelyPlayable == true)
    #expect(VideoFormat.m4v.isNativelyPlayable == true)
    #expect(VideoFormat.mkv.isNativelyPlayable == false)
    #expect(PrimuseConstants.supportedMusicVideoExtensions == ["mp4", "m4v", "mov"])
}

@Test func testStandaloneMusicVideoDetection() {
    let standalone = Song(
        id: "standalone-mv",
        title: "Concert",
        fileFormat: .m4v,
        filePath: "/Music/Concert.m4v",
        sourceID: "nas",
        mvPath: "/Music/Concert.m4v"
    )
    let sidecar = Song(
        id: "audio-with-mv",
        title: "Song",
        fileFormat: .flac,
        filePath: "/Music/Song.flac",
        sourceID: "nas",
        mvPath: "/Music/Song.mp4"
    )

    #expect(standalone.isStandaloneMusicVideo)
    #expect(sidecar.isStandaloneMusicVideo == false)
}

@Test func testEQPresets() {
    let flat = EQPreset.flat
    #expect(flat.bands.count == 10)
    #expect(flat.bands.allSatisfy { $0 == 0 })
    #expect(EQPreset.builtInPresets.count == 10)
}

@Test func testPlaybackState() {
    let state = PlaybackState(
        currentSongID: "test-id",
        songTitle: "Test Song",
        artistName: "Test Artist",
        isPlaying: true,
        currentTime: 30,
        duration: 180
    )

    #expect(state.songTitle == "Test Song")
    #expect(state.isPlaying == true)
}

@Test func musicSourcePreservesCustomSMBPort() throws {
    let source = MusicSource(
        name: "Remote NAS",
        type: .smb,
        host: "nas.example.com",
        port: 14_445,
        username: "listener",
        shareName: "Music"
    )

    #expect(source.port == 14_445)

    let restored = try JSONDecoder().decode(
        MusicSource.self,
        from: JSONEncoder().encode(source)
    )
    #expect(restored.port == 14_445)
}
