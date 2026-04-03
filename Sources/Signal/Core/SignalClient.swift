import Foundation

// MARK: - Interceptor Protocols

/// Intercepts and optionally modifies outgoing requests.
public protocol RequestInterceptor: Sendable {
    func intercept(_ request: URLRequest) async throws -> URLRequest
}

/// Intercepts and optionally modifies incoming responses.
public protocol ResponseInterceptor: Sendable {
    func intercept<T: Decodable>(_ response: Response<T>) async throws -> Response<T>
}

// MARK: - Retry Configuration

/// Configuration for automatic request retries.
public struct RetryConfiguration: Sendable {
    public let maxAttempts: Int
    public let delay: TimeInterval
    public let multiplier: Double
    public let retryableStatusCodes: Set<Int>

    public init(
        maxAttempts: Int = 3,
        delay: TimeInterval = 1.0,
        multiplier: Double = 2.0,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxAttempts = maxAttempts
        self.delay = delay
        self.multiplier = multiplier
        self.retryableStatusCodes = retryableStatusCodes
    }
}

// MARK: - Signal Client

/// The main API client for performing network requests.
public final class SignalClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let authProvider: (any AuthProvider)?
    private let cacheManager: CacheManager?
    private let logger: SignalLogger?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let retryConfig: RetryConfiguration
    private let requestInterceptors: [any RequestInterceptor]
    private let responseInterceptors: [any ResponseInterceptor]

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authProvider: (any AuthProvider)? = nil,
        cacheManager: CacheManager? = nil,
        logger: SignalLogger? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder(),
        retryConfig: RetryConfiguration = RetryConfiguration(),
        requestInterceptors: [any RequestInterceptor] = [],
        responseInterceptors: [any ResponseInterceptor] = []
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authProvider = authProvider
        self.cacheManager = cacheManager
        self.logger = logger
        self.decoder = decoder
        self.encoder = encoder
        self.retryConfig = retryConfig
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
    }

    // MARK: - Generic Request

    /// Performs a typed API request.
    public func request<T: Decodable>(_ endpoint: Endpoint) async throws -> Response<T> {
        var urlRequest = try endpoint.buildRequest(baseURL: baseURL)

        // Apply authentication
        if var provider = authProvider as? TokenAuthManager {
            try await provider.applyAuth(to: &urlRequest)
        } else if let provider = authProvider {
            try await provider.applyAuth(to: &urlRequest)
        }

        // Check cache
        if case .memory(let ttl) = endpoint.cachePolicy, ttl > 0, let cacheManager = cacheManager {
            let key = cacheKey(for: urlRequest)
            if let cachedData = await cacheManager.get(for: key) {
                do {
                    let decoded = try decoder.decode(T.self, from: cachedData)
                    logger?.debug("Cache hit for \(urlRequest.url?.absoluteString ?? "")")
                    return Response(data: decoded, statusCode: 200, headers: [:], rawData: cachedData)
                } catch {
                    logger?.debug("Cache data decode failed, proceeding with network request")
                }
            }
        }

        // Apply request interceptors
        for interceptor in requestInterceptors {
            urlRequest = try await interceptor.intercept(urlRequest)
        }

        // Log request
        logger?.logRequest(urlRequest)

        // Perform with retry
        let startTime = Date()
        let (data, httpResponse) = try await performWithRetry(urlRequest)
        let duration = Date().timeIntervalSince(startTime)

        // Log response
        logger?.logResponse(
            statusCode: httpResponse.statusCode,
            url: urlRequest.url,
            duration: duration,
            dataSize: data.count
        )

        // Check for error status codes
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SignalError.from(statusCode: httpResponse.statusCode, data: data)
        }

        // Decode response
        let decoded: T
        do {
            decoded = try decoder.decode(T.self, from: data)
        } catch {
            throw SignalError.parsingError(underlying: error)
        }

        var response = Response(
            data: decoded,
            statusCode: httpResponse.statusCode,
            headers: httpResponse.allHeaderFields,
            rawData: data
        )

        // Apply response interceptors
        for interceptor in responseInterceptors {
            response = try await interceptor.intercept(response)
        }

        // Store in cache
        if case .memory(let ttl) = endpoint.cachePolicy, ttl > 0, let cacheManager = cacheManager {
            let key = cacheKey(for: urlRequest)
            await cacheManager.set(data, for: key, ttl: ttl)
        }

        return response
    }

    // MARK: - Convenience Methods

    public func get<T: Decodable>(
        path: String,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        cachePolicy: CachePolicy = .none
    ) async throws -> Response<T> {
        let endpoint = Endpoint(
            path: path,
            method: .get,
            headers: headers,
            queryItems: queryItems,
            cachePolicy: cachePolicy
        )
        return try await request(endpoint)
    }

    public func post<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        headers: [String: String]? = nil
    ) async throws -> Response<T> {
        let endpoint = try Endpoint(
            path: path,
            method: .post,
            headers: headers,
            body: body,
            encoder: encoder
        )
        return try await request(endpoint)
    }

    public func put<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        headers: [String: String]? = nil
    ) async throws -> Response<T> {
        let endpoint = try Endpoint(
            path: path,
            method: .put,
            headers: headers,
            body: body,
            encoder: encoder
        )
        return try await request(endpoint)
    }

    public func delete<T: Decodable>(
        path: String,
        headers: [String: String]? = nil
    ) async throws -> Response<T> {
        let endpoint = Endpoint(path: path, method: .delete, headers: headers)
        return try await request(endpoint)
    }

    public func patch<T: Decodable, B: Encodable>(
        path: String,
        body: B,
        headers: [String: String]? = nil
    ) async throws -> Response<T> {
        let endpoint = try Endpoint(
            path: path,
            method: .patch,
            headers: headers,
            body: body,
            encoder: encoder
        )
        return try await request(endpoint)
    }

    // MARK: - Upload

    /// Uploads data as multipart/form-data.
    public func upload(
        path: String,
        data: Data,
        mimeType: String,
        fileName: String,
        fieldName: String = "file",
        headers: [String: String]? = nil
    ) async throws -> Response<Data> {
        let boundary = "Signal-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var allHeaders = headers ?? [:]
        allHeaders["Content-Type"] = "multipart/form-data; boundary=\(boundary)"

        let endpoint = Endpoint(
            path: path,
            method: .post,
            headers: allHeaders,
            body: body
        )

        var urlRequest = try endpoint.buildRequest(baseURL: baseURL)

        if let provider = authProvider {
            try await provider.applyAuth(to: &urlRequest)
        }

        logger?.logRequest(urlRequest)
        let startTime = Date()
        let (responseData, httpResponse) = try await performRequest(urlRequest)
        let duration = Date().timeIntervalSince(startTime)
        logger?.logResponse(statusCode: httpResponse.statusCode, url: urlRequest.url, duration: duration, dataSize: responseData.count)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SignalError.from(statusCode: httpResponse.statusCode, data: responseData)
        }

        return Response(data: responseData, statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, rawData: responseData)
    }

    // MARK: - Download

    /// Downloads a file and returns the temporary file URL.
    public func download(
        path: String,
        headers: [String: String]? = nil
    ) async throws -> (URL, URLResponse) {
        let endpoint = Endpoint(path: path, method: .get, headers: headers)
        var urlRequest = try endpoint.buildRequest(baseURL: baseURL)

        if let provider = authProvider {
            try await provider.applyAuth(to: &urlRequest)
        }

        logger?.logRequest(urlRequest)
        let (localURL, response) = try await session.download(for: urlRequest)

        if let httpResponse = response as? HTTPURLResponse {
            logger?.logResponse(statusCode: httpResponse.statusCode, url: urlRequest.url, duration: 0, dataSize: 0)
            guard (200...299).contains(httpResponse.statusCode) else {
                throw SignalError.from(statusCode: httpResponse.statusCode, data: nil)
            }
        }

        return (localURL, response)
    }

    // MARK: - Private Helpers

    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SignalError.unknown(underlying: nil)
            }
            return (data, httpResponse)
        } catch let error as SignalError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw SignalError.timeout
            case .cancelled:
                throw SignalError.cancelled
            case .notConnectedToInternet, .networkConnectionLost:
                throw SignalError.networkError(underlying: error)
            default:
                throw SignalError.networkError(underlying: error)
            }
        } catch {
            throw SignalError.networkError(underlying: error)
        }
    }

    private func performWithRetry(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?
        var currentDelay = retryConfig.delay

        for attempt in 1...retryConfig.maxAttempts {
            do {
                let (data, response) = try await performRequest(request)
                if retryConfig.retryableStatusCodes.contains(response.statusCode) && attempt < retryConfig.maxAttempts {
                    logger?.warning("Retryable status \(response.statusCode), attempt \(attempt)/\(retryConfig.maxAttempts)")
                    try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                    currentDelay *= retryConfig.multiplier
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt < retryConfig.maxAttempts {
                    logger?.warning("Request failed (attempt \(attempt)/\(retryConfig.maxAttempts)): \(error.localizedDescription)")
                    try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                    currentDelay *= retryConfig.multiplier
                }
            }
        }

        throw lastError ?? SignalError.unknown(underlying: nil)
    }

    private func cacheKey(for request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        return "\(method):\(url)"
    }
}
