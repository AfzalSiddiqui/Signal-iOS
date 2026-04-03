import Foundation

/// Protocol for providing authentication to requests.
public protocol AuthProvider: Sendable {
    func applyAuth(to request: inout URLRequest) async throws
    func refreshToken() async throws -> String
}

/// Thread-safe token-based authentication manager.
public actor TokenAuthManager: AuthProvider {
    private var accessToken: String?
    private var refreshTokenValue: String?
    private let onRefresh: (@Sendable (String) async throws -> String)?
    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<String, Error>] = []

    public init(
        accessToken: String? = nil,
        refreshToken: String? = nil,
        onRefresh: (@Sendable (String) async throws -> String)? = nil
    ) {
        self.accessToken = accessToken
        self.refreshTokenValue = refreshToken
        self.onRefresh = onRefresh
    }

    public func applyAuth(to request: inout URLRequest) async throws {
        guard let token = accessToken else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    public func refreshToken() async throws -> String {
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                refreshContinuations.append(continuation)
            }
        }

        guard let refreshTokenValue = refreshTokenValue,
              let onRefresh = onRefresh else {
            throw SignalError.authenticationError
        }

        isRefreshing = true
        do {
            let newToken = try await onRefresh(refreshTokenValue)
            self.accessToken = newToken
            isRefreshing = false
            for continuation in refreshContinuations {
                continuation.resume(returning: newToken)
            }
            refreshContinuations.removeAll()
            return newToken
        } catch {
            isRefreshing = false
            for continuation in refreshContinuations {
                continuation.resume(throwing: error)
            }
            refreshContinuations.removeAll()
            throw error
        }
    }

    public func setToken(_ token: String) {
        self.accessToken = token
    }

    public func setRefreshToken(_ token: String) {
        self.refreshTokenValue = token
    }

    public func clearTokens() {
        self.accessToken = nil
        self.refreshTokenValue = nil
    }

    public func currentToken() -> String? {
        return accessToken
    }
}
