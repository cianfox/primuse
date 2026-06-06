import Foundation

/// OneDrive 大文件的「单连接连续下载缓冲」。
///
/// OneDrive 服务端对大文件的逐段小 Range 请求会挂死(冷文件 hydration / 限流),
/// 但一个连续的整文件 GET 很快。这里用**一个连续下载**把字节顺序写进本地临时文件,
/// 上层(CloudPlaybackSource)的逐 chunk `fetchRange` 实际从这个正在增长的文件读
/// —— 读到还没下到的位置就 `await`,实现真正的「边下边播边缓存」,不再逐段 Range。
final class OneDriveSequentialReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let tempURL: URL
    private let writeHandle: FileHandle
    private let lock = NSLock()
    private var written: Int64 = 0
    private var finished = false
    private var failure: Error?
    private var waiters: [(need: Int64, cont: CheckedContinuation<Void, Error>)] = []
    private var session: URLSession!

    init(url: URL) {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("primuse_od_seq_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        writeHandle = (try? FileHandle(forWritingTo: tempURL)) ?? .nullDevice
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 1800
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url)
        // 模拟浏览器 UA:OneDrive 对非首方客户端的请求可能限速,加 UA 让下载速度对齐网页直下。
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)",
            forHTTPHeaderField: "User-Agent"
        )
        session.dataTask(with: request).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
        try? writeHandle.close()
        try? FileManager.default.removeItem(at: tempURL)
    }

    /// 顺序读 `[offset, offset+length)`:等下载灌到该位置(或下载结束)再从本地读。
    func read(offset: Int64, length: Int64) async throws -> Data {
        let need = offset + length
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // 在锁内决定动作、锁外执行 resume(避免持锁跨线程恢复)。
            let resume: (() -> Void)? = lock.withLock {
                if let failure, written < need { return { cont.resume(throwing: failure) } }
                if written >= need || finished { return { cont.resume() } }
                waiters.append((need, cont))
                return nil
            }
            resume?()
        }
        let avail = lock.withLock { written }
        let end = min(need, avail)
        guard offset < end else { return Data() }
        let rh = try FileHandle(forReadingFrom: tempURL)
        defer { try? rh.close() }
        try rh.seek(toOffset: UInt64(offset))
        return (try? rh.read(upToCount: Int(end - offset))) ?? Data()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            completionHandler(.cancel)
            failWith(NSError(domain: "OneDriveSequentialReader", code: http.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        try? writeHandle.write(contentsOf: data)
        written += Int64(data.count)
        let ready = waiters.filter { $0.need <= written }
        waiters.removeAll { $0.need <= written }
        lock.unlock()
        ready.forEach { $0.cont.resume() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { failWith(error); return }
        lock.lock()
        finished = true
        let pending = waiters; waiters.removeAll()
        lock.unlock()
        try? writeHandle.close()
        // 下载完成:解除所有等待(read 自行按已写入量返回,短读视为 EOF)。
        pending.forEach { $0.cont.resume() }
    }

    private func failWith(_ error: Error) {
        lock.lock()
        failure = error; finished = true
        let pending = waiters; waiters.removeAll()
        lock.unlock()
        try? writeHandle.close()
        pending.forEach { $0.cont.resume(throwing: error) }
    }
}
