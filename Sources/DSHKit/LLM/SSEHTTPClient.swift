import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 以 SSE 行流形式读取 HTTP 响应。
///
/// 使用 `URLSessionDataDelegate` 而不是 `URLSession.bytes`，因为后者在
/// swift-corelibs-foundation（Windows/Linux）上并不总是可用；delegate 方案在
/// iOS / iPadOS / macOS / Windows 上行为一致，也便于用 `URLProtocol` 注入测试。
public final class SSEHTTPClient: @unchecked Sendable {
    public init() {}

    public func lines(for request: URLRequest, sessionConfiguration: URLSessionConfiguration = .ephemeral) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let delegate = SSEDelegate(continuation: continuation)
            let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            let task = session.dataTask(with: request)
            delegate.task = task
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
    }
}

private final class SSEDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private var buffer = Data()
    private var status: Int?
    private var errorBody = Data()
    private var finished = false

    var session: URLSession?
    var task: URLSessionDataTask?

    init(continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        status = (response as? HTTPURLResponse)?.statusCode
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let status, !(200..<300).contains(status) {
            errorBody.append(data)
            return
        }
        buffer.append(data)
        drainLines()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error: error)
    }

    private func drainLines() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            var line = String(decoding: lineData, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            continuation.yield(line)
        }
    }

    private func finish(error: Error?) {
        guard !finished else { return }
        finished = true
        defer {
            session?.invalidateAndCancel()
            continuation.finish()
        }
        if let error {
            if (error as NSError).code == NSURLErrorCancelled { return }
            continuation.finish(throwing: LLMFailure(kind: .network, message: error.localizedDescription))
            return
        }
        if let status, !(200..<300).contains(status) {
            let body = String(decoding: errorBody, as: UTF8.self)
            continuation.finish(throwing: LLMFailure.classify(status: status, body: body))
            return
        }
        // 处理最后一行没有换行符的情况
        if !buffer.isEmpty {
            var line = String(decoding: buffer, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            continuation.yield(line)
            buffer.removeAll()
        }
    }
}

/// 一次性 HTTP 请求（非流式，用于 web_fetch / 模型列表等）。
public enum HTTP {
    public static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: LLMFailure(kind: .network, message: error.localizedDescription))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: LLMFailure(kind: .network, message: "non-HTTP response"))
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }
            task.resume()
        }
    }
}
