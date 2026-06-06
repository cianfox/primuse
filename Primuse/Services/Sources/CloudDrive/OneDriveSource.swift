import Foundation
import PrimuseKit

/// OneDrive Source — Microsoft Graph API
actor OneDriveSource: MusicSourceConnector, OAuthCloudSource {
    let sourceID: String
    private let helper: CloudDriveHelper
    private static let graphBase = "https://graph.microsoft.com/v1.0"
    private static let authBase = "https://login.microsoftonline.com/common/oauth2/v2.0"
    private static let fallbackRedirectURI = "\(CloudOAuthConfig.callbackScheme)://onedrive/callback"

    init(sourceID: String) {
        self.sourceID = sourceID
        self.helper = CloudDriveHelper(sourceID: sourceID)
    }

    func connect() async throws { _ = try await getToken() }

    /// Microsoft Graph `/me` returns the signed-in user record. The `id`
    /// field is the Azure AD object identifier — stable across token
    /// refresh and across devices logged into the same Microsoft account.
    /// `$select=id` keeps the response tiny.
    func accountIdentifier() async throws -> String {
        let token = try await getToken()
        let (data, http) = try await helper.makeAuthorizedRequest(
            url: URL(string: "\(Self.graphBase)/me?$select=id")!,
            accessToken: token
        )
        guard http.statusCode == 200 else {
            throw CloudDriveError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let id = json["id"] as? String, !id.isEmpty else {
            plog("⚠️ OneDrive accountIdentifier: missing id in response: \(json)")
            throw CloudDriveError.invalidResponse
        }
        return id
    }
    func disconnect() async {}

    func listFiles(at path: String) async throws -> [RemoteFileItem] {
        let endpoint = (path.isEmpty || path == "/") ? "\(Self.graphBase)/me/drive/root/children" : "\(Self.graphBase)/me/drive/items/\(path)/children"
        var all: [RemoteFileItem] = []
        var nextURL: URL? = {
            var components = URLComponents(string: endpoint)!
            components.queryItems = [
                .init(name: "$select", value: "id,name,folder,file,size"),
                .init(name: "$top", value: "999"),
                .init(name: "$orderby", value: "name"),
            ]
            return components.url
        }()
        while let url = nextURL {
            let token = try await getToken()
            let (data, http) = try await helper.makeAuthorizedRequest(url: url, accessToken: token)
            guard http.statusCode == 200 else { throw CloudDriveError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "") }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let items = json["value"] as? [[String: Any]] ?? []
            all.append(contentsOf: items.compactMap { item in
                guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
                // Microsoft Graph driveItem returns file.hashes.sha1Hash /
                // sha256Hash / quickXorHash. Use whichever is present as
                // the revision fingerprint; eTag is a final fallback.
                let revision: String? = {
                    if let file = item["file"] as? [String: Any],
                       let hashes = file["hashes"] as? [String: Any] {
                        if let h = hashes["sha256Hash"] as? String { return h }
                        if let h = hashes["sha1Hash"] as? String { return h }
                        if let h = hashes["quickXorHash"] as? String { return h }
                    }
                    return item["eTag"] as? String
                }()
                return RemoteFileItem(name: name, path: id, isDirectory: item["folder"] != nil, size: item["size"] as? Int64 ?? 0, modifiedDate: nil, revision: revision)
            })
            // @odata.nextLink 是完整 URL（已包含 skiptoken）
            if let next = json["@odata.nextLink"] as? String, let nextU = URL(string: next) {
                nextURL = nextU
            } else {
                nextURL = nil
            }
        }
        return all
    }

    func localURL(for path: String) async throws -> URL {
        if helper.hasCached(path: path) { return helper.cachedURL(for: path) }
        let token = try await getToken()
        let (data, http) = try await helper.makeAuthorizedRequest(url: URL(string: "\(Self.graphBase)/me/drive/items/\(path)")!, accessToken: token)
        guard http.statusCode == 200 else { throw CloudDriveError.apiError(http.statusCode, "Item not found") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let downloadUrl = json["@microsoft.graph.downloadUrl"] as? String, let fileURL = URL(string: downloadUrl) else { throw CloudDriveError.fileNotFound(path) }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        let (fileData, _) = try await URLSession(configuration: config).data(from: fileURL)
        try helper.cacheData(fileData, for: path)
        return helper.cachedURL(for: path)
    }

    func streamData(for path: String) async throws -> AsyncThrowingStream<Data, Error> {
        _ = try await localURL(for: path)
        return helper.streamFromCache(path: path)
    }

    func scanAudioFiles(from path: String) async throws -> AsyncThrowingStream<RemoteFileItem, Error> {
        helper.scanAudioFiles(from: path) { [self] p in try await listFiles(at: p) }
    }

    /// 每首歌一个「连续下载缓冲」(per-path)。用 Task 去重,避免 actor 在 await
    /// getDownloadURL 期间被并发 fetchRange 重入而重复建连。
    private var seqReaderTasks: [String: Task<OneDriveSequentialReader, Error>] = [:]

    func fetchRange(path: String, offset: Int64, length: Int64) async throws -> Data {
        // OneDrive 对大文件的逐段小 Range 请求会被服务端挂死(冷文件 hydration / 限流),
        // 但一个连续的整文件 GET 很快。所以这里不再逐段 Range,而是用「单连接连续下载缓冲」:
        // 一个连续 GET 把字节顺序灌进本地临时文件,本方法按 [offset,length) 从这个正在
        // 增长的文件读(没下到就 await)。上层 CloudPlaybackSource 仍逐 chunk 调本方法、
        // 把拿到的字节写进它的持久缓存 —— 整体实现「边下边播边缓存」,且只在 OneDrive
        // connector 内部,完全不影响其它源。
        let reader = try await sequentialReader(for: path)
        do {
            return try await reader.read(offset: offset, length: length)
        } catch {
            // 连续下载失败(dlink 过期 / 网络中断):丢弃缓冲与 dlink,下次重建。
            let stale = seqReaderTasks[path]
            seqReaderTasks[path] = nil
            stale?.cancel()
            Task { (try? await stale?.value)?.cancel() }
            invalidateDownloadURL(for: path)
            throw error
        }
    }

    private func sequentialReader(for path: String) async throws -> OneDriveSequentialReader {
        if let task = seqReaderTasks[path] { return try await task.value }
        // 切歌:取消上一首的连续下载,只保留当前曲目的缓冲。
        for (key, task) in seqReaderTasks where key != path {
            seqReaderTasks[key] = nil
            Task { (try? await task.value)?.cancel() }
        }
        let task = Task { () throws -> OneDriveSequentialReader in
            let url = try await getDownloadURL(for: path)
            return OneDriveSequentialReader(url: url)
        }
        seqReaderTasks[path] = task
        return try await task.value
    }

    private var downloadURLCache: [String: (url: URL, expiresAt: Date)] = [:]
    /// Microsoft documents `@microsoft.graph.downloadUrl` as valid for ~1
    /// hour. Use 50min to leave a safety margin against clock skew.
    private static let downloadURLTTL: TimeInterval = 50 * 60

    private func getDownloadURL(for path: String) async throws -> URL {
        if let cached = downloadURLCache[path], cached.expiresAt > Date() {
            return cached.url
        }
        let token = try await getToken()
        let (data, http) = try await helper.makeAuthorizedRequest(url: URL(string: "\(Self.graphBase)/me/drive/items/\(path)")!, accessToken: token)
        guard http.statusCode == 200 else { throw CloudDriveError.apiError(http.statusCode, "Item not found") }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let downloadUrl = json["@microsoft.graph.downloadUrl"] as? String,
              let fileURL = URL(string: downloadUrl) else {
            throw CloudDriveError.fileNotFound(path)
        }
        downloadURLCache[path] = (fileURL, Date().addingTimeInterval(Self.downloadURLTTL))
        return fileURL
    }

    private func invalidateDownloadURL(for path: String) {
        downloadURLCache.removeValue(forKey: path)
    }

    private func getToken() async throws -> String {
        guard var tokens = await helper.tokenManager.getTokens() else { throw CloudDriveError.notAuthenticated }
        if tokens.isExpired {
            tokens = try await refreshToken(tokens)
            await helper.tokenManager.saveTokens(tokens)
        }
        return tokens.accessToken
    }

    private func refreshToken(_ tokens: CloudTokenManager.Tokens) async throws -> CloudTokenManager.Tokens {
        guard let rt = tokens.refreshToken else { throw CloudDriveError.tokenRefreshFailed("No refresh token") }
        let creds = await helper.tokenManager.getAppCredentials()
        guard let cid = creds?.clientId else { throw CloudDriveError.tokenRefreshFailed("No client ID") }
        var request = URLRequest(url: URL(string: "\(Self.authBase)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = CloudDriveHelper.formURLEncodedBody([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: rt),
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "scope", value: "Files.Read offline_access"),
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let at = json["access_token"] as? String else { throw CloudDriveError.tokenRefreshFailed("") }
        return .init(accessToken: at, refreshToken: json["refresh_token"] as? String ?? rt, expiresAt: Date().addingTimeInterval(json["expires_in"] as? TimeInterval ?? 3600))
    }

    static func oauthConfig(clientId: String) -> CloudOAuthConfig {
        CloudOAuthConfig(
            authURL: "\(authBase)/authorize",
            tokenURL: "\(authBase)/token",
            clientId: clientId,
            clientSecret: nil,
            scopes: ["Files.Read", "offline_access"],
            redirectURI: redirectURI()
        )
    }

    private static func redirectURI() -> String {
        guard let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty else {
            return fallbackRedirectURI
        }
        return "msauth.\(bundleID)://auth"
    }
}
