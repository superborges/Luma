import Foundation

/// 抽象 HTTP 调用，便于 Provider 单测时注入 `MockHTTPClient`。
///
/// 设计取舍：返回 `(Data, HTTPURLResponse)` 与 `URLSession.data(for:)` 同形，
/// 让 Provider 内部不感知 mock / 真实差异，也避免封装复杂度。
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// 默认实现：直接走 `URLSession.shared`。
struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LumaError.networkFailed("非 HTTP 响应：\(response)")
        }
        return (data, http)
    }
}

/// 测试用 mock：可预设按请求 URL 路径匹配的 stub，并记录所有请求供断言。
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    /// 每次 `send` 后追加的请求记录；测试断言 URL / Header / Body 用。
    private(set) var sentRequests: [URLRequest] = []

    /// 按路径匹配的 stub。匹配规则：URL.path 包含 substring 即命中。
    private var stubs: [(matcher: String, response: Result<(Data, HTTPURLResponse), Error>)] = []

    private let lock = NSLock()

    init() {}

    /// 注册 stub。匹配从前向后；首次命中即返回。
    func stub(pathContains substring: String, status: Int = 200, body: Data, headers: [String: String] = [:]) {
        let url = URL(string: "https://mock.luma.local")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        lock.lock()
        stubs.append((matcher: substring, response: .success((body, response))))
        lock.unlock()
    }

    func stubError(pathContains substring: String, error: Error) {
        lock.lock()
        stubs.append((matcher: substring, response: .failure(error)))
        lock.unlock()
    }

    func reset() {
        lock.lock()
        sentRequests.removeAll()
        stubs.removeAll()
        lock.unlock()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let resolved = recordAndResolve(request)
        switch resolved {
        case .success(let payload): return payload
        case .failure(let error): throw error
        }
    }

    /// 同步小函数，把 `NSLock` 调用与 async 上下文隔离开（避免 Swift 6 警告）。
    private func recordAndResolve(_ request: URLRequest) -> Result<(Data, HTTPURLResponse), Error> {
        lock.lock()
        defer { lock.unlock() }
        sentRequests.append(request)
        let path = request.url?.absoluteString ?? ""
        guard let match = stubs.first(where: { path.contains($0.matcher) }) else {
            return .failure(LumaError.networkFailed("MockHTTPClient: 未找到匹配 \(path) 的 stub"))
        }
        return match.response
    }
}
