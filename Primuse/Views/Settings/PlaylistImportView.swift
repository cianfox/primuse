import SwiftUI
import PrimuseKit
import UniformTypeIdentifiers

/// 歌单导入页 — 走 .fileImporter 选 .m3u8 / .json, 解析 + 库匹配, 给
/// 用户看预览 (匹配成功 N 首 / 缺 M 首) → 用户改名后确认 → 创建歌单。
///
/// 三种状态:
/// - 还没选文件: 引导选文件
/// - 解析中 / 出错: 提示
/// - 已解析: 显示 preview, 让用户编辑名字 + 确认 / 取消
struct PlaylistImportView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var preview: PlaylistImporter.ImportPreview?
    @State private var playlistName: String = ""
    @State private var importError: String?
    @State private var showFileImporter = false
    @State private var importedFromName: String = ""
    @State private var showCSVExporter = false
    @State private var csvDocument = PlaylistImportCSVDocument()
    @State private var manualMatchEntry: PlaylistImporter.ImportEntry?
    @State private var manualMatchQuery = ""
    /// 解析 + 库匹配在后台跑期间为 true, 用来显示进度并阻止重复触发。
    @State private var isParsing = false

    var body: some View {
        #if os(macOS)
        baseBody
            .sheet(item: $manualMatchEntry) { entry in
                manualMatchSheet(entry)
            }
        #else
        baseBody
        #endif
    }

    private var baseBody: some View {
        Group {
            #if os(macOS)
            macBody
            #else
            iosBody
            #endif
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importableTypes()
        ) { result in
            Task { await handleFile(result) }
        }
        .fileExporter(
            isPresented: $showCSVExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "\(importedFromName.isEmpty ? "unmatched-playlist" : importedFromName)-unmatched.csv"
        ) { result in
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
        }
        .alert(String(localized: "playlist_import_err_title"),
               isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("ok", role: .cancel) {}
        } message: { Text(importError ?? "") }
    }

    private var iosBody: some View {
        Form {
            if preview == nil {
                introSection
            } else if let preview {
                summarySection(preview)
                nameSection
                entriesSection(preview)
            }
        }
        .navigationTitle("playlist_import_title")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if preview == nil {
                // 没选文件时, 顶部一个明显的「选择文件」入口 —— Form 内的
                // .borderedProminent 按钮在 iOS 26 偶尔渲染成跟背景同色看
                // 不见, 工具栏入口更稳。
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("playlist_import_pick_file", systemImage: "folder")
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("playlist_import_create") { confirm() }
                        .fontWeight(.semibold)
                        .disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (preview?.matchedCount ?? 0) == 0)
                }
            }
        }
    }

    #if os(macOS)
    /// 整面板铺满 sheet (PMColor.bg 打底), 跟「重复清理 / Scrobble」两个弹框
    /// 一致 —— 不再是一张 760 宽、带阴影的浮动卡片浮在更大的窗口里 (那样会留
    /// 大片空白 + 卡片浮空感)。结构: 顶栏 + 内容(引导/预览) + 底栏。
    private var macBody: some View {
        VStack(spacing: 0) {
            macHeader

            Rectangle().fill(PMColor.divider).frame(height: 0.5)

            Group {
                if let preview {
                    macPreview(preview)
                } else {
                    macIntro
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle().fill(PMColor.divider).frame(height: 0.5)
            macFooter
        }
        .frame(width: 620, height: 680)
        .background(PMColor.bg)
    }

    private var macHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PMColor.brand.opacity(0.16))
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PMColor.brand)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("playlist_import_title")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PMColor.text)
                Text(verbatim: preview == nil ? String(localized: "playlist_import_mac_subtitle") : importedFromName)
                    .font(.system(size: 12.5))
                    .foregroundStyle(PMColor.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if preview != nil {
                Text("READY")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PMColor.textFaint)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PMColor.textMuted)
                    .frame(width: 26, height: 26)
                    .background(PMColor.glassBtn, in: .circle)
            }
            .buttonStyle(.plain)
            .help(Text("close"))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var macIntro: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: "doc.badge.plus")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(PMColor.brand)
            Text("playlist_import_mac_intro_title")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PMColor.text)
            Text("playlist_import_mac_intro_desc")
                .font(.system(size: 12.5))
                .foregroundStyle(PMColor.textMuted)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                macFormatPill("M3U8")
                macFormatPill("M3U")
                macFormatPill("JSON")
            }
            .padding(.top, 4)

            if isParsing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("scanning")
                        .font(.system(size: 12.5))
                        .foregroundStyle(PMColor.textMuted)
                }
                .padding(.top, 6)
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    Label("playlist_import_pick_file", systemImage: "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(PMColor.brand, in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func macPreview(_ p: PlaylistImporter.ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                MacImportStatusPill(text: String(format: String(localized: "playlist_import_matched_count_format"), p.matchedCount), color: PMColor.ok)
                MacImportStatusPill(text: String(format: String(localized: "playlist_import_pending_count_format"), p.missingCount), color: p.missingCount > 0 ? PMColor.warn : PMColor.textFaint)
                Spacer()
                Text(verbatim: String(format: String(localized: "playlist_import_entries_count_format"), p.entries.count))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(PMColor.textFaint)
            }

            macSegmentedProgress(p)

            VStack(alignment: .leading, spacing: 8) {
                Text("playlist_import_name_header")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PMColor.textMuted)
                TextField("playlist_name", text: $playlistName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(PMColor.card.opacity(0.78), in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(PMColor.cardBorder, lineWidth: 0.5)
                    }
            }

            macGroupedEntries(p)
        }
        .padding(22)
    }

    private func macSegmentedProgress(_ p: PlaylistImporter.ImportPreview) -> some View {
        let total = max(p.entries.count, 1)
        let matched = CGFloat(p.matchedCount) / CGFloat(total)
        let missing = CGFloat(p.missingCount) / CGFloat(total)

        return GeometryReader { geo in
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(PMColor.ok)
                    .frame(width: max(0, geo.size.width * matched))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(p.missingCount > 0 ? PMColor.warn : PMColor.textFaint.opacity(0.24))
                    .frame(width: max(0, geo.size.width * missing))
                if p.entries.isEmpty {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(PMColor.textFaint.opacity(0.18))
                }
            }
        }
        .frame(height: 5)
        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }

    private func macGroupedEntries(_ p: PlaylistImporter.ImportPreview) -> some View {
        let matched = p.entries.filter { $0.matchedSong != nil }
        let unmatched = p.entries.filter { $0.matchedSong == nil }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("playlist_import_match_results")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PMColor.textMuted)
                Spacer()
                if p.missingCount > 0 {
                    Text("playlist_import_unmatched_skip_hint")
                        .font(.system(size: 11))
                        .foregroundStyle(PMColor.textFaint)
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    macEntryGroup(title: String(localized: "playlist_import_matched_group"), count: matched.count, color: PMColor.ok) {
                        ForEach(matched) { entry in
                            macEntryRow(entry, manualMatch: false)
                            if entry.id != matched.last?.id {
                                Divider().overlay(PMColor.divider).padding(.leading, 28)
                            }
                        }
                    }

                    macEntryGroup(title: String(localized: "playlist_import_unmatched_group"), count: unmatched.count, color: unmatched.isEmpty ? PMColor.textFaint : PMColor.warn) {
                        if unmatched.isEmpty {
                            Text("playlist_import_no_manual_items")
                                .font(.system(size: 12))
                                .foregroundStyle(PMColor.textFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(unmatched) { entry in
                                macEntryRow(entry, manualMatch: true)
                                if entry.id != unmatched.last?.id {
                                    Divider().overlay(PMColor.divider).padding(.leading, 28)
                                }
                            }
                        }
                    }
                }
                .padding(1)
            }
            .frame(height: 300)
        }
    }

    private func macEntryGroup<Content: View>(title: String,
                                              count: Int,
                                              color: Color,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(verbatim: "\(title) (\(count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PMColor.text)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(PMColor.bgElev.opacity(0.82))

            Divider().overlay(PMColor.divider)

            content()
        }
        .background(PMColor.card.opacity(0.62), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(PMColor.cardBorder, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 设计稿 PL-06 底栏: 左「导出未匹配 → CSV」(仅有缺失时), 右「取消 + 仅创建
    /// 已匹配 (N)」。还没选文件时右侧主按钮换成「选择文件」。
    private var macFooter: some View {
        HStack(spacing: 10) {
            if let preview, preview.missingCount > 0 {
                Button {
                    exportUnmatchedCSV(preview)
                } label: {
                    Label("playlist_import_export_unmatched_csv", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(PMColor.text)
                .frame(height: 28)
                .padding(.horizontal, 12)
                .background(PMColor.glassBtn, in: .rect(cornerRadius: 6))
            } else if preview != nil {
                Button {
                    showFileImporter = true
                } label: {
                    Label("playlist_import_change_file", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(PMColor.textMuted)
                .frame(height: 28)
                .padding(.horizontal, 12)
                .background(PMColor.glassBtn, in: .rect(cornerRadius: 6))
            }

            Spacer()

            Button("cancel") { dismiss() }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(PMColor.text)
                .frame(height: 28)
                .padding(.horizontal, 14)
                .background(PMColor.glassBtn, in: .rect(cornerRadius: 6))

            // 引导态的「选择文件」主按钮在内容区里, 这里底栏不再重复; 只有
            // 解析出预览后才在底栏放「仅创建已匹配」主操作。
            if let preview {
                Button {
                    confirm()
                } label: {
                    Text(verbatim: String(format: String(localized: "playlist_import_create_matched_only_format"), preview.matchedCount))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 28)
                        .padding(.horizontal, 14)
                        .background(canCreatePlaylist ? PMColor.brand : PMColor.textFaint.opacity(0.45), in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!canCreatePlaylist)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var canCreatePlaylist: Bool {
        playlistName.trimmingCharacters(in: .whitespaces).isEmpty == false
            && (preview?.matchedCount ?? 0) > 0
    }

    private func macFormatPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(PMColor.textMuted)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(PMColor.glassBtn, in: .capsule)
    }

    private func macMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(PMColor.text)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(PMColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.20), lineWidth: 0.5)
        }
    }

    private func macEntryRow(_ entry: PlaylistImporter.ImportEntry, manualMatch: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.matchedSong == nil ? "questionmark.circle" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(entry.matchedSong == nil ? PMColor.warn : PMColor.ok)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(PMColor.text)
                    .lineLimit(1)
                if let artist = entry.displayArtist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(PMColor.textFaint)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let kind = entry.matchKind {
                Text(matchKindText(kind))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(matchKindColor(kind))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(matchKindColor(kind).opacity(0.14), in: .capsule)
            } else if manualMatch {
                Button {
                    manualMatchQuery = [entry.displayTitle, entry.displayArtist]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    manualMatchEntry = entry
                } label: {
                    Text("playlist_import_manual_match")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(PMColor.brand)
                .padding(.horizontal, 9)
                .frame(height: 23)
                .background(PMColor.brand.opacity(0.12), in: .rect(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func matchKindText(_ kind: PlaylistImporter.ImportEntry.MatchKind) -> String {
        switch kind {
        case .songID: return "ID"
        case .basename: return "PATH"
        case .fuzzy: return "FUZZY"
        }
    }
    #endif

    // MARK: - Sections

    private var introSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text("playlist_import_intro_title").font(.headline)
                Text("playlist_import_intro_desc")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if isParsing {
                    ProgressView { Text("scanning") }
                        .padding(.top, 8)
                } else {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Label("playlist_import_pick_file", systemImage: "folder")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func summarySection(_ p: PlaylistImporter.ImportPreview) -> some View {
        Section {
            HStack {
                Label("playlist_import_matched", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Text("\(p.matchedCount)").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Label("playlist_import_missing", systemImage: "questionmark.circle")
                    .foregroundStyle(p.missingCount > 0 ? .orange : .secondary)
                Spacer()
                Text("\(p.missingCount)").monospacedDigit().foregroundStyle(.secondary)
            }
        } footer: {
            if p.missingCount > 0 {
                Text("playlist_import_missing_footer")
            }
        }
    }

    private var nameSection: some View {
        Section {
            TextField("playlist_name", text: $playlistName)
        } header: {
            Text("playlist_import_name_header")
        }
    }

    private func entriesSection(_ p: PlaylistImporter.ImportPreview) -> some View {
        Section {
            ForEach(p.entries) { entry in
                entryRow(entry)
            }
        } header: {
            Text("playlist_import_entries_header")
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: PlaylistImporter.ImportEntry) -> some View {
        HStack(spacing: 10) {
            statusIcon(for: entry)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                if let artist = entry.displayArtist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let kind = entry.matchKind {
                Text(matchKindLabel(kind))
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(matchKindColor(kind).opacity(0.18)))
                    .foregroundStyle(matchKindColor(kind))
            }
        }
        .padding(.vertical, 2)
    }

    private func statusIcon(for entry: PlaylistImporter.ImportEntry) -> some View {
        if entry.matchedSong != nil {
            return AnyView(Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green))
        } else {
            return AnyView(Image(systemName: "questionmark.circle")
                .foregroundStyle(.orange))
        }
    }

    // MARK: - Actions

    private func handleFile(_ result: Result<URL, Error>) async {
        switch result {
        case .success(let url):
            guard !isParsing else { return }
            // 主线程只负责拍 songs 快照 + 读文件字节 (security-scoped 访问要
            // 在主线程短暂持有), 解析 + 库匹配 (O(条目数×库) 带 folding)
            // 全部丢到后台跑, 否则 1000 条对 5 万首库会冻结 UI 数秒。
            // 匹配池用 visibleSongs(排除停用源), 与歌单展示 / 手动匹配口径一致 ——
            // 命中停用源的歌写进歌单后 songs(forPlaylist:) 也看不到。
            let snapshot = library.visibleSongs
            isParsing = true
            defer { isParsing = false }
            do {
                let data = try readImportData(url)
                let ext = url.pathExtension.lowercased()
                let fileName = url.deletingPathExtension().lastPathComponent
                let raw = try await Task.detached(priority: .userInitiated) {
                    try Self.parseAndMatchOffMain(data: data, ext: ext, fileName: fileName, songs: snapshot)
                }.value
                // @MainActor 隔离的 ImportEntry/ImportPreview 只能在主线程构造,
                // 但这一步是 O(条目数) 纯映射 (无 folding/全库扫描), 不卡 UI。
                let p = PlaylistImporter.ImportPreview(
                    suggestedName: raw.suggestedName,
                    entries: raw.matches.map { m in
                        PlaylistImporter.ImportEntry(
                            displayTitle: m.displayTitle,
                            displayArtist: m.displayArtist,
                            matchedSong: m.matchedSong,
                            matchKind: m.matchKindRaw.flatMap { PlaylistImporter.ImportEntry.MatchKind(rawValue: $0) }
                        )
                    }
                )
                preview = p
                playlistName = p.suggestedName
                importedFromName = fileName
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    /// 读取被沙箱保护的 import 文件字节。Files document picker 给的 URL 必须
    /// startAccessing 才能读 (否则 Data(contentsOf:) 报权限错)。
    private func readImportData(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw OffMainImportError.malformed(error.localizedDescription)
        }
    }

    /// 后台解析产出的中间结果 —— 全部 Sendable, 不碰 @MainActor 隔离的
    /// PlaylistImporter.ImportEntry/ImportPreview (那两个只能在主线程构造)。
    nonisolated private struct RawMatch: Sendable {
        let displayTitle: String
        let displayArtist: String?
        let matchedSong: Song?
        let matchKindRaw: String?  // PlaylistImporter.ImportEntry.MatchKind.rawValue
    }

    nonisolated private struct RawImportResult: Sendable {
        let suggestedName: String
        let matches: [RawMatch]
    }

    /// 后台可抛的错误 —— 复刻 PlaylistImporter.ImportError 的三种 case 与本地化
    /// 文案。PlaylistImporter.ImportError 自身被 @MainActor 隔离, 不能在后台抛。
    nonisolated private enum OffMainImportError: LocalizedError {
        case unsupportedFormat
        case malformed(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return String(localized: "playlist_import_err_format")
            case .malformed(let why): return String(format: String(localized: "playlist_import_err_malformed_format"), why)
            case .empty: return String(localized: "playlist_import_err_empty")
            }
        }
    }

    /// 后台解析 + 库匹配。复刻 `PlaylistImporter.parseAndMatch` 的解析与匹配
    /// 优先级 (songID → basename → title+artist 模糊), 但:
    /// - 不在 @MainActor 上, 可丢到 Task.detached;
    /// - 匹配前预构建 basename → [Song] / normalized(title) → [Song] 字典,
    ///   把每条目匹配从 O(全库) 降为 O(1), 不再对每条目全量 filter + folding。
    nonisolated private static func parseAndMatchOffMain(
        data: Data,
        ext: String,
        fileName: String,
        songs: [Song]
    ) throws -> RawImportResult {
        let index = MatchIndex(songs: songs)
        switch ext {
        case "m3u", "m3u8":
            return try parseM3U8OffMain(data: data, fileName: fileName, index: index)
        case "json":
            return try parseJSONOffMain(data: data, fileName: fileName, index: index)
        default:
            throw OffMainImportError.unsupportedFormat
        }
    }

    /// 预建匹配索引: basename(小写) → [Song], normalized(title) → [Song]。
    /// 每条目匹配降为字典查找 + 同 normalized(artist) 过滤命中桶。
    nonisolated private struct MatchIndex {
        let byBasename: [String: [Song]]
        let byNormTitle: [String: [Song]]
        let byID: [String: Song]

        init(songs: [Song]) {
            var basename: [String: [Song]] = [:]
            var normTitle: [String: [Song]] = [:]
            var ids: [String: Song] = [:]
            basename.reserveCapacity(songs.count)
            normTitle.reserveCapacity(songs.count)
            ids.reserveCapacity(songs.count)
            for song in songs {
                ids[song.id] = song
                let base = (song.filePath as NSString).lastPathComponent.lowercased()
                basename[base, default: []].append(song)
                let nt = Self.normalize(song.title)
                if !nt.isEmpty {
                    normTitle[nt, default: []].append(song)
                }
            }
            byBasename = basename
            byNormTitle = normTitle
            byID = ids
        }

        func songByID(_ id: String) -> Song? { byID[id] }

        func matchByBasename(_ path: String) -> Song? {
            let needle = (path as NSString).lastPathComponent.lowercased()
            return Self.chooseBest(from: byBasename[needle] ?? [])
        }

        func matchByTitleArtist(title: String, artist: String?) -> Song? {
            let normTitle = Self.normalize(title)
            guard !normTitle.isEmpty, let bucket = byNormTitle[normTitle] else { return nil }
            let normArtist = artist.map { Self.normalize($0) }
            let hits = bucket.filter { song in
                if let normArtist {
                    return Self.normalize(song.artistName ?? "") == normArtist
                }
                return true
            }
            return Self.chooseBest(from: hits)
        }

        /// 多个命中挑最高音质 (跟 PlaylistImporter / DuplicateDetector 一致)。
        static func chooseBest(from songs: [Song]) -> Song? {
            songs.max { DuplicateDetector.qualityScore(of: $0) < DuplicateDetector.qualityScore(of: $1) }
        }

        static func normalize(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        }
    }

    nonisolated private static func parseJSONOffMain(
        data: Data,
        fileName: String,
        index: MatchIndex
    ) throws -> RawImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: PlaylistExporter.PrimusePlaylistFile
        do {
            file = try decoder.decode(PlaylistExporter.PrimusePlaylistFile.self, from: data)
        } catch {
            throw OffMainImportError.malformed(error.localizedDescription)
        }
        guard !file.tracks.isEmpty else { throw OffMainImportError.empty }

        let matches = file.tracks.map { track -> RawMatch in
            if let s = index.songByID(track.songID) {
                return RawMatch(displayTitle: track.title, displayArtist: track.artistName, matchedSong: s, matchKindRaw: "songID")
            }
            if let s = index.matchByBasename(track.filePath) {
                return RawMatch(displayTitle: track.title, displayArtist: track.artistName, matchedSong: s, matchKindRaw: "basename")
            }
            if let s = index.matchByTitleArtist(title: track.title, artist: track.artistName) {
                return RawMatch(displayTitle: track.title, displayArtist: track.artistName, matchedSong: s, matchKindRaw: "fuzzy")
            }
            return RawMatch(displayTitle: track.title, displayArtist: track.artistName, matchedSong: nil, matchKindRaw: nil)
        }
        return RawImportResult(suggestedName: file.playlist.name, matches: matches)
    }

    nonisolated private static func parseM3U8OffMain(
        data: Data,
        fileName: String,
        index: MatchIndex
    ) throws -> RawImportResult {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw OffMainImportError.malformed("encoding")
        }
        var playlistName = fileName
        var pendingExtInf: String?
        var rawEntries: [(path: String, extInf: String?)] = []

        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTM3U") { continue }
            if line.hasPrefix("#PLAYLIST:") {
                playlistName = String(line.dropFirst("#PLAYLIST:".count)).trimmingCharacters(in: .whitespaces)
                if playlistName.isEmpty { playlistName = fileName }
                continue
            }
            if line.hasPrefix("#EXTINF:") {
                pendingExtInf = String(line.dropFirst("#EXTINF:".count))
                continue
            }
            if line.hasPrefix("#") { continue }
            rawEntries.append((path: line, extInf: pendingExtInf))
            pendingExtInf = nil
        }
        guard !rawEntries.isEmpty else { throw OffMainImportError.empty }

        let matches = rawEntries.map { raw -> RawMatch in
            let (displayTitle, displayArtist) = Self.parseExtInf(raw.extInf, fallbackPath: raw.path)
            if let s = index.matchByBasename(raw.path) {
                return RawMatch(displayTitle: displayTitle, displayArtist: displayArtist, matchedSong: s, matchKindRaw: "basename")
            }
            if let s = index.matchByTitleArtist(title: displayTitle, artist: displayArtist) {
                return RawMatch(displayTitle: displayTitle, displayArtist: displayArtist, matchedSong: s, matchKindRaw: "fuzzy")
            }
            return RawMatch(displayTitle: displayTitle, displayArtist: displayArtist, matchedSong: nil, matchKindRaw: nil)
        }
        return RawImportResult(suggestedName: playlistName, matches: matches)
    }

    /// 解析 `#EXTINF:duration,Artist - Title`。Artist 段可能没有, 这种整段当
    /// title (跟 PlaylistImporter.parseExtInf 行为一致)。
    nonisolated private static func parseExtInf(_ extInf: String?, fallbackPath: String) -> (title: String, artist: String?) {
        guard let extInf else {
            let base = (fallbackPath as NSString).lastPathComponent
            let withoutExt = (base as NSString).deletingPathExtension
            return (withoutExt, nil)
        }
        guard let commaIdx = extInf.firstIndex(of: ",") else {
            return (extInf.trimmingCharacters(in: .whitespaces), nil)
        }
        let rest = String(extInf[extInf.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
        if let dashRange = rest.range(of: " - ") {
            let artist = String(rest[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let title = String(rest[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (title, artist.isEmpty ? nil : artist)
        }
        return (rest, nil)
    }

    private func confirm() {
        guard let preview else { return }
        let name = playlistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        PlaylistImporter.createPlaylist(from: preview, named: name, library: library)
        dismiss()
    }

    #if os(macOS)
    private func exportUnmatchedCSV(_ preview: PlaylistImporter.ImportPreview) {
        let unmatched = preview.entries.filter { $0.matchedSong == nil }
        csvDocument = PlaylistImportCSVDocument(text: unmatchedCSV(for: unmatched))
        showCSVExporter = true
    }

    private func unmatchedCSV(for entries: [PlaylistImporter.ImportEntry]) -> String {
        let header = ["title", "artist", "reason"].map(csvEscape).joined(separator: ",")
        let rows = entries.map { entry in
            [
                entry.displayTitle,
                entry.displayArtist ?? "",
                "not_matched"
            ].map(csvEscape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func manualMatchSheet(_ entry: PlaylistImporter.ImportEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(PMColor.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("playlist_import_manual_match_title")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PMColor.text)
                    Text(entry.displayTitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(PMColor.textMuted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(18)

            Divider().overlay(PMColor.divider)

            TextField("playlist_import_search_library", text: $manualMatchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(PMColor.card.opacity(0.78), in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(PMColor.cardBorder, lineWidth: 0.5)
                }
                .padding(16)

            List(manualMatchResults, id: \.id) { song in
                Button {
                    applyManualMatch(entry: entry, song: song)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .foregroundStyle(PMColor.brand)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(PMColor.text)
                            Text([song.artistName, song.albumTitle].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11))
                                .foregroundStyle(PMColor.textFaint)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider().overlay(PMColor.divider)

            HStack {
                Spacer()
                Button("cancel") { manualMatchEntry = nil }
                    .keyboardShortcut(.cancelAction)
                Button("playlist_import_use_first_result") {
                    if let song = manualMatchResults.first {
                        applyManualMatch(entry: entry, song: song)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(manualMatchResults.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 520, height: 520)
        .background(PMColor.bg)
    }

    private var manualMatchResults: [Song] {
        let query = manualMatchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(library.visibleSongs.prefix(40)) }
        let folded = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return library.visibleSongs
            .filter { song in
                [song.title, song.artistName, song.albumTitle]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    .contains(folded)
            }
            .prefix(40)
            .map { $0 }
    }

    private func applyManualMatch(entry: PlaylistImporter.ImportEntry, song: Song) {
        guard let current = preview else { return }
        let entries = current.entries.map { item in
            item.id == entry.id
                ? PlaylistImporter.ImportEntry(
                    displayTitle: item.displayTitle,
                    displayArtist: item.displayArtist,
                    matchedSong: song,
                    matchKind: .fuzzy
                )
                : item
        }
        preview = PlaylistImporter.ImportPreview(suggestedName: current.suggestedName, entries: entries)
        manualMatchEntry = nil
    }
    #endif

    // MARK: - Helpers

    private func importableTypes() -> [UTType] {
        var types: [UTType] = [.json]
        // m3u8 + m3u —— 用 mpeg4Audio 显然不对, 正确做法是 mpegURL/audio/x-mpegurl
        if let m3u8 = UTType(filenameExtension: "m3u8") { types.append(m3u8) }
        if let m3u = UTType(filenameExtension: "m3u") { types.append(m3u) }
        return types
    }

    private func matchKindLabel(_ kind: PlaylistImporter.ImportEntry.MatchKind) -> LocalizedStringKey {
        switch kind {
        case .songID: return "playlist_import_kind_id"
        case .basename: return "playlist_import_kind_path"
        case .fuzzy: return "playlist_import_kind_fuzzy"
        }
    }

    private func matchKindColor(_ kind: PlaylistImporter.ImportEntry.MatchKind) -> Color {
        switch kind {
        case .songID: return .green
        case .basename: return .blue
        case .fuzzy: return .orange
        }
    }
}

private struct PlaylistImportCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String = ""

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let contents = String(data: data, encoding: .utf8) {
            text = contents
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

#if os(macOS)
private struct MacImportStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(verbatim: text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(PMColor.text)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(color.opacity(0.12), in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 0.5)
        }
    }
}
#endif
