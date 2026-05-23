import SwiftUI
import MusicKit

/// Apple Music 在系统侧播放时的"大屏"播放器。猿音自己的 NowPlayingView
/// 是为 AudioPlayerService 设计的, 上面的刮削 / EQ / 播放速度 / Spatial Audio
/// 全部对 ApplicationMusicPlayer 不适用, 所以单独搞一个简化版:
/// - 大封面 / 标题 / 艺术家 / 专辑
/// - 播放 / 暂停 / 停止
/// - 在 Apple Music App 中打开
/// - 歌词显示 (整段 plain text, MusicKit 不提供同步 timestamp API)
struct AppleMusicNowPlayingView: View {
    let song: MusicKit.Song
    @Environment(AppleMusicService.self) private var appleMusic
    @Environment(AppleMusicLibraryService.self) private var appleMusicLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// 这首歌在 Apple Music 上是否有歌词 — MusicKit 只暴露 hasLyrics: Bool,
    /// 实际歌词内容不开放给第三方, 所以"查看歌词"只能跳转到 Apple Music App。
    @State private var hasLyrics: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            handleBar
            coverContent
            metadata
            controls

            if hasLyrics, let url = song.url {
                // 公开 API 拿不到歌词内容, 退一步给用户一个直达 Apple Music
                // App 看歌词的按钮 — 系统 app 内有 time-synced lyrics 显示。
                Button {
                    openURL(url)
                } label: {
                    Label("apple_music_view_lyrics", systemImage: "text.bubble.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.pink)
                .padding(.top, 4)
            }

            Text("apple_music_now_playing_hint")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task(id: song.id.rawValue) {
            hasLyrics = await appleMusicLibrary.fetchHasLyrics(forFilePath: song.id.rawValue)
        }
    }

    // MARK: - Subviews

    private var handleBar: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 40, height: 5)
            .padding(.top, 8)
    }

    private var coverContent: some View {
        AsyncImage(url: song.artwork?.url(width: 600, height: 600)) { phase in
            if let img = phase.image {
                img.resizable().aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(maxWidth: 320, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        .padding(.top, 4)
    }

    private var metadata: some View {
        VStack(spacing: 4) {
            Text(song.title)
                .font(.title2).fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: "applelogo").font(.subheadline)
                Text(song.artistName)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let album = song.albumTitle, !album.isEmpty {
                Text(album)
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { appleMusic.stopAppleMusic(); dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("stop")

            Button { appleMusic.togglePlayPauseAppleMusic() } label: {
                Image(systemName: appleMusic.isAppleMusicPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(appleMusic.isAppleMusicPlaying
                ? String(localized: "a11y_pause")
                : String(localized: "a11y_play"))

            if let url = song.url {
                Button { openURL(url) } label: {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("apple_music_open_in_app")
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.top, 4)
    }
}
