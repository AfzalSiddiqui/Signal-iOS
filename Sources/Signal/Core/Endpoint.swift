import Foundation

/// Cache policy for API requests.
public enum CachePolicy: Sendable {
    case none
    case memory(ttl: TimeInterval)
    case disk(ttl: TimeInterval)

    public var ttl: TimeInterval {
        switch self {
        case .none: return 0
        case .memory(let ttl), .disk(let ttl): return ttl
        }
    }
}

/// Represents an API endpoint configuration.
public struct Endpoint: Sendable {
    public let path: String
    public let method: HTTPMethod
    public let headers: [String: String]?
    public let queryItems: [URLQueryItem]?
    public let body: Data?
    public let cachePolicy: CachePolicy

    public init(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        cachePolicy: CachePolicy = .none
    ) {
        self.path = path
        self.method = method
        self.headers = headers
        self.queryItems = queryItems
        self.body = body
        self.cachePolicy = cachePolicy
    }

    /// Convenience initializer that encodes an `Encodable` body.
    public init<B: Encodable>(
        path: String,
        method: HTTPMethod = .post,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        body: B,
        encoder: JSONEncoder = JSONEncoder(),
        cachePolicy: CachePolicy = .none
    ) throws {
        self.path = path
        self.method = method
        self.headers = headers
        self.queryItems = queryItems
        self.body = try encoder.encode(body)
        self.cachePolicy = cachePolicy
    }

    /// Builds a `URLRequest` from this endpoint and a base URL.
    public func buildRequest(baseURL: URL) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true) else {
            throw SignalError.validationError(message: "Invalid URL components for path: \(path)")
        }

        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw SignalError.validationError(message: "Failed to construct URL from components")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        if body != nil && headers?["Content-Type"] == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}
