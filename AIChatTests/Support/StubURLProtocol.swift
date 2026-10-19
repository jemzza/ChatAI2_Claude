import Foundation
@testable import AIChat

/// Подменяет сеть для `URLSession`. У каждой сессии свой обработчик (по заголовку
/// `X-Stub-ID`), поэтому параллельные тесты не мешают друг другу.
final class StubURLProtocol: URLProtocol {
    enum Reply: Sendable {
        case response(status: Int, body: Data = Data(), headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    typealias Handler = @Sendable (URLRequest) -> Reply

    private static let handlers = Locked<[String: Handler]>([:])
    private static let idHeader = "X-Stub-ID"

    /// Сессия с этим обработчиком и список запросов, которые до него дошли.
    static func session(_ handler: @escaping Handler) -> (URLSession, RequestLog) {
        let id = UUID().uuidString
        let log = RequestLog()
        handlers.withLock {
            $0[id] = { request in
                log.append(request)
                return handler(request)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [idHeader: id]
        return (URLSession(configuration: configuration), log)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.idHeader),
              let handler = Self.handlers.withLock({ $0[id] }),
              let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        switch handler(Self.withBody(request)) {
        case let .response(status, body, headers):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    /// `URLSession` переносит `httpBody` в поток — возвращаем его обратно для проверок.
    private static func withBody(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
        var copy = request
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        copy.httpBody = data
        return copy
    }
}

/// Запросы, дошедшие до заглушки.
final class RequestLog: Sendable {
    private let requests = Locked<[URLRequest]>([])

    var all: [URLRequest] { requests.withLock { $0 } }

    func append(_ request: URLRequest) {
        requests.withLock { $0.append(request) }
    }
}
