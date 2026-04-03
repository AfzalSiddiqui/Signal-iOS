import Foundation

/// Comprehensive error types for Signal networking operations.
public enum SignalError: LocalizedError {
    case networkError(underlying: Error)
    case serverError(statusCode: Int, data: Data?)
    case clientError(statusCode: Int, data: Data?)
    case parsingError(underlying: Error)
    case validationError(message: String)
    case authenticationError
    case unauthorized
    case notFound
    case timeout
    case cancelled
    case unknown(underlying: Error?)

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, _):
            return "Server error with status code \(code)"
        case .clientError(let code, _):
            return "Client error with status code \(code)"
        case .parsingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .authenticationError:
            return "Authentication required (401)"
        case .unauthorized:
            return "Access denied (403)"
        case .notFound:
            return "Resource not found (404)"
        case .timeout:
            return "Request timed out"
        case .cancelled:
            return "Request was cancelled"
        case .unknown(let error):
            return "Unknown error: \(error?.localizedDescription ?? "No details")"
        }
    }

    /// Maps an HTTP status code to the appropriate `SignalError`.
    public static func from(statusCode: Int, data: Data?) -> SignalError {
        switch statusCode {
        case 401: return .authenticationError
        case 403: return .unauthorized
        case 404: return .notFound
        case 408: return .timeout
        case 400...499: return .clientError(statusCode: statusCode, data: data)
        case 500...599: return .serverError(statusCode: statusCode, data: data)
        default: return .unknown(underlying: nil)
        }
    }
}
