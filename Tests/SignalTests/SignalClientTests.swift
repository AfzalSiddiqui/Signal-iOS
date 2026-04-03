import XCTest
@testable import Signal

final class SignalClientTests: XCTestCase {

    // MARK: - HTTPMethod Tests

    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
        XCTAssertEqual(HTTPMethod.patch.rawValue, "PATCH")
    }

    // MARK: - SignalError Tests

    func testSignalErrorDescriptions() {
        let networkError = SignalError.networkError(underlying: URLError(.notConnectedToInternet))
        XCTAssertNotNil(networkError.errorDescription)
        XCTAssertTrue(networkError.errorDescription!.contains("Network error"))

        let serverError = SignalError.serverError(statusCode: 500, data: nil)
        XCTAssertTrue(serverError.errorDescription!.contains("500"))

        let authError = SignalError.authenticationError
        XCTAssertTrue(authError.errorDescription!.contains("401"))

        let notFound = SignalError.notFound
        XCTAssertTrue(notFound.errorDescription!.contains("404"))

        let timeout = SignalError.timeout
        XCTAssertTrue(timeout.errorDescription!.contains("timed out"))
    }

    func testSignalErrorFromStatusCode() {
        let auth = SignalError.from(statusCode: 401, data: nil)
        if case .authenticationError = auth {} else {
            XCTFail("Expected authenticationError for 401")
        }

        let forbidden = SignalError.from(statusCode: 403, data: nil)
        if case .unauthorized = forbidden {} else {
            XCTFail("Expected unauthorized for 403")
        }

        let notFound = SignalError.from(statusCode: 404, data: nil)
        if case .notFound = notFound {} else {
            XCTFail("Expected notFound for 404")
        }

        let client = SignalError.from(statusCode: 422, data: nil)
        if case .clientError(let code, _) = client {
            XCTAssertEqual(code, 422)
        } else {
            XCTFail("Expected clientError for 422")
        }

        let server = SignalError.from(statusCode: 503, data: nil)
        if case .serverError(let code, _) = server {
            XCTAssertEqual(code, 503)
        } else {
            XCTFail("Expected serverError for 503")
        }
    }

    func testSignalErrorAllDescriptionsNonNil() {
        let errors: [SignalError] = [
            .networkError(underlying: URLError(.notConnectedToInternet)),
            .serverError(statusCode: 500, data: nil),
            .clientError(statusCode: 400, data: nil),
            .parsingError(underlying: NSError(domain: "test", code: 0)),
            .validationError(message: "invalid email"),
            .authenticationError,
            .unauthorized,
            .notFound,
            .timeout,
            .cancelled,
            .unknown(underlying: nil)
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error description should not be nil for \(error)")
        }
    }

    func testSignalErrorFromStatusCode408() {
        let timeout = SignalError.from(statusCode: 408, data: nil)
        if case .timeout = timeout {} else {
            XCTFail("Expected timeout for 408")
        }
    }

    func testSignalErrorUnknownStatusCode() {
        let unknown = SignalError.from(statusCode: 999, data: nil)
        if case .unknown = unknown {} else {
            XCTFail("Expected unknown for 999")
        }
    }

    func testSignalErrorValidation() {
        let error = SignalError.validationError(message: "Email is required")
        XCTAssertTrue(error.errorDescription!.contains("Email is required"))
    }

    func testSignalErrorParsing() {
        let error = SignalError.parsingError(underlying: NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "bad json"]))
        XCTAssertTrue(error.errorDescription!.contains("parse"))
    }

    func testSignalErrorCancelled() {
        let error = SignalError.cancelled
        XCTAssertTrue(error.errorDescription!.contains("cancelled"))
    }

    // MARK: - Endpoint Tests

    func testEndpointBuildRequest() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = Endpoint(
            path: "/users",
            method: .get,
            headers: ["Accept": "application/json"],
            queryItems: [URLQueryItem(name: "page", value: "1")]
        )

        let request = try endpoint.buildRequest(baseURL: baseURL)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(request.url!.absoluteString.contains("/users"))
        XCTAssertTrue(request.url!.absoluteString.contains("page=1"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testEndpointWithBody() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let body = ["name": "Test"]
        let bodyData = try JSONEncoder().encode(body)

        let endpoint = Endpoint(
            path: "/users",
            method: .post,
            body: bodyData
        )

        let request = try endpoint.buildRequest(baseURL: baseURL)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testEndpointMultipleQueryItems() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = Endpoint(
            path: "/search",
            method: .get,
            queryItems: [
                URLQueryItem(name: "q", value: "swift"),
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: "20")
            ]
        )

        let request = try endpoint.buildRequest(baseURL: baseURL)
        let urlString = request.url!.absoluteString
        XCTAssertTrue(urlString.contains("q=swift"))
        XCTAssertTrue(urlString.contains("page=1"))
        XCTAssertTrue(urlString.contains("limit=20"))
    }

    func testEndpointDeleteMethod() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = Endpoint(path: "/users/1", method: .delete)
        let request = try endpoint.buildRequest(baseURL: baseURL)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertNil(request.httpBody)
    }

    func testEndpointPatchMethod() throws {
        let baseURL = URL(string: "https://api.example.com")!
        let bodyData = try JSONEncoder().encode(["name": "Updated"])
        let endpoint = Endpoint(path: "/users/1", method: .patch, body: bodyData)
        let request = try endpoint.buildRequest(baseURL: baseURL)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertNotNil(request.httpBody)
    }

    // MARK: - Cache Tests

    func testCacheSetAndGet() async {
        let cache = CacheManager(maxSize: 10)
        let data = "hello".data(using: .utf8)!

        await cache.set(data, for: "key1", ttl: 60)
        let result = await cache.get(for: "key1")

        XCTAssertNotNil(result)
        XCTAssertEqual(result, data)
    }

    func testCacheMiss() async {
        let cache = CacheManager(maxSize: 10)
        let result = await cache.get(for: "nonexistent")
        XCTAssertNil(result)
    }

    func testCacheClear() async {
        let cache = CacheManager(maxSize: 10)
        let data = "hello".data(using: .utf8)!
        await cache.set(data, for: "key1", ttl: 60)
        await cache.clear()

        let result = await cache.get(for: "key1")
        XCTAssertNil(result)
    }

    func testCacheEvictionAtCapacity() async {
        let cache = CacheManager(maxSize: 2)
        let data1 = "one".data(using: .utf8)!
        let data2 = "two".data(using: .utf8)!
        let data3 = "three".data(using: .utf8)!

        await cache.set(data1, for: "key1", ttl: 60)
        await cache.set(data2, for: "key2", ttl: 60)
        await cache.set(data3, for: "key3", ttl: 60)

        // key1 should be evicted
        let result1 = await cache.get(for: "key1")
        XCTAssertNil(result1, "Oldest entry should be evicted")

        let result2 = await cache.get(for: "key2")
        XCTAssertNotNil(result2)
        let result3 = await cache.get(for: "key3")
        XCTAssertNotNil(result3)
    }

    func testCacheRemove() async {
        let cache = CacheManager(maxSize: 10)
        let data = "hello".data(using: .utf8)!
        await cache.set(data, for: "key1", ttl: 60)
        await cache.remove(for: "key1")

        let result = await cache.get(for: "key1")
        XCTAssertNil(result)
    }

    func testCacheCount() async {
        let cache = CacheManager(maxSize: 10)
        let data = "hello".data(using: .utf8)!

        await cache.set(data, for: "key1", ttl: 60)
        await cache.set(data, for: "key2", ttl: 60)
        let count = await cache.count
        XCTAssertEqual(count, 2)
    }

    func testCacheOverwriteKey() async {
        let cache = CacheManager(maxSize: 10)
        let data1 = "first".data(using: .utf8)!
        let data2 = "second".data(using: .utf8)!

        await cache.set(data1, for: "key1", ttl: 60)
        await cache.set(data2, for: "key1", ttl: 60)

        let result = await cache.get(for: "key1")
        XCTAssertEqual(result, data2)

        let count = await cache.count
        XCTAssertEqual(count, 1)
    }

    func testCacheTTLExpiry() async {
        let cache = CacheManager(maxSize: 10)
        let data = "hello".data(using: .utf8)!
        await cache.set(data, for: "key1", ttl: 0.001) // 1ms TTL

        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        let result = await cache.get(for: "key1")
        XCTAssertNil(result, "Expired entry should return nil")
    }

    // MARK: - Logger Tests

    func testLogLevelComparison() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
        XCTAssertTrue(LogLevel.error < LogLevel.none)
    }

    func testLogLevelRawValues() {
        XCTAssertEqual(LogLevel.debug.rawValue, 0)
        XCTAssertEqual(LogLevel.info.rawValue, 1)
        XCTAssertEqual(LogLevel.warning.rawValue, 2)
        XCTAssertEqual(LogLevel.error.rawValue, 3)
        XCTAssertEqual(LogLevel.none.rawValue, 4)
    }

    func testLoggerCreation() {
        let logger = SignalLogger(minimumLevel: .warning)
        // Should not crash and be usable
        logger.debug("This should be filtered")
        logger.warning("This should pass")
        logger.error("This should pass")
    }

    func testLoggerPrefixes() {
        XCTAssertEqual(LogLevel.debug.prefix, "[DEBUG]")
        XCTAssertEqual(LogLevel.info.prefix, "[INFO]")
        XCTAssertEqual(LogLevel.warning.prefix, "[WARN]")
        XCTAssertEqual(LogLevel.error.prefix, "[ERROR]")
        XCTAssertEqual(LogLevel.none.prefix, "")
    }

    // MARK: - Auth Manager Tests

    func testAuthManagerSetToken() async {
        let auth = TokenAuthManager(accessToken: "initial-token")
        let token = await auth.currentToken()
        XCTAssertEqual(token, "initial-token")
    }

    func testAuthManagerClearTokens() async {
        let auth = TokenAuthManager(accessToken: "token", refreshToken: "refresh")
        await auth.clearTokens()
        let token = await auth.currentToken()
        XCTAssertNil(token)
    }

    func testAuthManagerUpdateToken() async {
        let auth = TokenAuthManager()
        await auth.setToken("new-token")
        let token = await auth.currentToken()
        XCTAssertEqual(token, "new-token")
    }

    func testAuthManagerApplyAuth() async throws {
        let auth = TokenAuthManager(accessToken: "my-jwt")
        var request = URLRequest(url: URL(string: "https://api.example.com")!)
        try await auth.applyAuth(to: &request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer my-jwt")
    }

    func testAuthManagerApplyAuthNoToken() async throws {
        let auth = TokenAuthManager()
        var request = URLRequest(url: URL(string: "https://api.example.com")!)
        try await auth.applyAuth(to: &request)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testAuthManagerRefreshWithoutCallback() async {
        let auth = TokenAuthManager(refreshToken: "refresh")
        do {
            _ = try await auth.refreshToken()
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }

    func testAuthManagerRefreshSuccess() async throws {
        let auth = TokenAuthManager(
            accessToken: "old",
            refreshToken: "refresh-token",
            onRefresh: { _ in return "new-token" }
        )

        let newToken = try await auth.refreshToken()
        XCTAssertEqual(newToken, "new-token")

        let current = await auth.currentToken()
        XCTAssertEqual(current, "new-token")
    }

    // MARK: - Parallel Executor Tests

    func testParallelExecution() async throws {
        let tasks: [@Sendable () async throws -> Int] = [
            { 1 },
            { 2 },
            { 3 }
        ]

        let results = try await ParallelExecutor.execute(tasks)
        XCTAssertEqual(results, [1, 2, 3])
    }

    func testParallelExecutionMaintainsOrder() async throws {
        let tasks: [@Sendable () async throws -> String] = [
            {
                try await Task.sleep(nanoseconds: 30_000_000) // 30ms
                return "slow"
            },
            { "fast" },
            {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                return "medium"
            }
        ]

        let results = try await ParallelExecutor.execute(tasks)
        XCTAssertEqual(results, ["slow", "fast", "medium"])
    }

    func testParallelExecutionThrowsOnFailure() async {
        let tasks: [@Sendable () async throws -> Int] = [
            { 1 },
            { throw SignalError.timeout },
            { 3 }
        ]

        do {
            _ = try await ParallelExecutor.execute(tasks)
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    func testParallelSettledCollectsResults() async {
        let tasks: [@Sendable () async -> Result<Int, Error>] = [
            { .success(1) },
            { .failure(SignalError.timeout) },
            { .success(3) }
        ]

        let results = await ParallelExecutor.executeSettled(tasks)
        XCTAssertEqual(results.count, 3)

        if case .success(let val) = results[0] { XCTAssertEqual(val, 1) }
        else { XCTFail("Expected success") }

        if case .failure = results[1] { /* expected */ }
        else { XCTFail("Expected failure") }

        if case .success(let val) = results[2] { XCTAssertEqual(val, 3) }
        else { XCTFail("Expected success") }
    }

    func testParallelWithLimitBasic() async throws {
        let tasks: [@Sendable () async throws -> Int] = [
            { 1 }, { 2 }, { 3 }, { 4 }, { 5 }
        ]

        let results = try await ParallelExecutor.executeWithLimit(tasks, limit: 2)
        XCTAssertEqual(results, [1, 2, 3, 4, 5])
    }

    func testParallelWithLimitMaintainsOrder() async throws {
        let tasks: [@Sendable () async throws -> Int] = (0..<10).map { i in
            { return i }
        }

        let results = try await ParallelExecutor.executeWithLimit(tasks, limit: 3)
        XCTAssertEqual(results, Array(0..<10))
    }

    func testParallelWithLimitThrowsOnFailure() async {
        let tasks: [@Sendable () async throws -> Int] = [
            { 1 },
            { throw SignalError.networkError(underlying: URLError(.notConnectedToInternet)) },
            { 3 }
        ]

        do {
            _ = try await ParallelExecutor.executeWithLimit(tasks, limit: 1)
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }

    func testParallelWithLimitSingleWorker() async throws {
        var order = [Int]()
        let lock = NSLock()
        let tasks: [@Sendable () async throws -> Int] = [1, 2, 3].map { i in
            {
                lock.lock()
                order.append(i)
                lock.unlock()
                return i
            }
        }

        let results = try await ParallelExecutor.executeWithLimit(tasks, limit: 1)
        XCTAssertEqual(results, [1, 2, 3])
        XCTAssertEqual(order, [1, 2, 3]) // With limit=1, should execute sequentially
    }

    // MARK: - Serial Executor Tests

    func testSerialExecution() async throws {
        var order = [Int]()
        let tasks: [() async throws -> Int] = [
            { order.append(1); return 1 },
            { order.append(2); return 2 },
            { order.append(3); return 3 }
        ]

        let results = try await SerialTaskExecutor.execute(tasks)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(order, [1, 2, 3])
    }

    func testSerialExecutionContinuesOnError() async throws {
        let tasks: [() async throws -> Int] = [
            { return 1 },
            { throw SignalError.timeout },
            { return 3 }
        ]

        let results = try await SerialTaskExecutor.execute(tasks, stopOnError: false)
        XCTAssertEqual(results.count, 3)

        if case .success(let val) = results[0] { XCTAssertEqual(val, 1) }
        else { XCTFail("Expected success") }

        if case .failure = results[1] { /* expected */ }
        else { XCTFail("Expected failure") }

        if case .success(let val) = results[2] { XCTAssertEqual(val, 3) }
        else { XCTFail("Expected success") }
    }

    func testSerialExecutionStopsOnError() async {
        let tasks: [() async throws -> Int] = [
            { return 1 },
            { throw SignalError.timeout },
            { return 3 }
        ]

        do {
            _ = try await SerialTaskExecutor.execute(tasks, stopOnError: true)
            XCTFail("Expected error to be thrown")
        } catch {
            if case SignalError.timeout = error { /* expected */ }
            else { XCTFail("Expected timeout error") }
        }
    }

    func testSerialExecuteCompact() async {
        let tasks: [() async throws -> Int] = [
            { return 1 },
            { throw SignalError.timeout },
            { return 3 }
        ]

        let results = await SerialTaskExecutor.executeCompact(tasks)
        XCTAssertEqual(results, [1, 3])
    }

    func testSerialExecuteCompactAllSucceed() async {
        let tasks: [() async throws -> String] = [
            { "a" }, { "b" }, { "c" }
        ]

        let results = await SerialTaskExecutor.executeCompact(tasks)
        XCTAssertEqual(results, ["a", "b", "c"])
    }

    func testSerialExecuteCompactAllFail() async {
        let tasks: [() async throws -> Int] = [
            { throw SignalError.timeout },
            { throw SignalError.notFound },
            { throw SignalError.cancelled }
        ]

        let results = await SerialTaskExecutor.executeCompact(tasks)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - RetryConfiguration Tests

    func testRetryConfigurationDefaults() {
        let config = RetryConfiguration()
        XCTAssertEqual(config.maxAttempts, 3)
        XCTAssertEqual(config.delay, 1.0)
        XCTAssertEqual(config.multiplier, 2.0)
        XCTAssertTrue(config.retryableStatusCodes.contains(503))
        XCTAssertTrue(config.retryableStatusCodes.contains(429))
        XCTAssertTrue(config.retryableStatusCodes.contains(408))
        XCTAssertTrue(config.retryableStatusCodes.contains(500))
        XCTAssertTrue(config.retryableStatusCodes.contains(502))
        XCTAssertTrue(config.retryableStatusCodes.contains(504))
    }

    func testRetryConfigurationCustom() {
        let config = RetryConfiguration(
            maxAttempts: 5,
            delay: 2.0,
            multiplier: 3.0,
            retryableStatusCodes: [500]
        )
        XCTAssertEqual(config.maxAttempts, 5)
        XCTAssertEqual(config.delay, 2.0)
        XCTAssertEqual(config.multiplier, 3.0)
        XCTAssertEqual(config.retryableStatusCodes, [500])
    }

    // MARK: - SignalClient Initialization

    func testSignalClientInit() {
        let client = SignalClient(baseURL: URL(string: "https://api.example.com")!)
        XCTAssertNotNil(client)
    }

    func testSignalClientWithAllOptions() {
        let cache = CacheManager(maxSize: 50)
        let logger = SignalLogger(minimumLevel: .info)
        let auth = TokenAuthManager(accessToken: "token")
        let retryConfig = RetryConfiguration(maxAttempts: 5)

        let client = SignalClient(
            baseURL: URL(string: "https://api.example.com")!,
            authProvider: auth,
            cacheManager: cache,
            logger: logger,
            retryConfig: retryConfig
        )
        XCTAssertNotNil(client)
    }
}
