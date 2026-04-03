import Foundation

/// Log severity levels.
public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case none = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var prefix: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        case .none: return ""
        }
    }
}

/// Protocol for custom logger implementations.
public protocol SignalLoggerProtocol: Sendable {
    func log(level: LogLevel, message: String)
}

/// Default logger with configurable minimum level and request/response logging.
public final class SignalLogger: SignalLoggerProtocol, @unchecked Sendable {
    private let minimumLevel: LogLevel
    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter

    public init(minimumLevel: LogLevel = .debug) {
        self.minimumLevel = minimumLevel
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func log(level: LogLevel, message: String) {
        guard level >= minimumLevel, level != .none else { return }
        let timestamp = dateFormatter.string(from: Date())
        lock.lock()
        print("\(timestamp) \(level.prefix) [Signal] \(message)")
        lock.unlock()
    }

    public func debug(_ message: String) {
        log(level: .debug, message: message)
    }

    public func info(_ message: String) {
        log(level: .info, message: message)
    }

    public func warning(_ message: String) {
        log(level: .warning, message: message)
    }

    public func error(_ message: String) {
        log(level: .error, message: message)
    }

    public func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "nil"
        let bodySize = request.httpBody?.count ?? 0

        debug("→ \(method) \(url)")
        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            debug("  Headers: \(headers)")
        }
        if bodySize > 0 {
            debug("  Body: \(bodySize) bytes")
        }
    }

    public func logResponse(statusCode: Int, url: URL?, duration: TimeInterval, dataSize: Int) {
        let urlString = url?.absoluteString ?? "nil"
        let durationMs = String(format: "%.1f", duration * 1000)
        let level: LogLevel = (200...299).contains(statusCode) ? .info : .warning
        log(level: level, message: "← \(statusCode) \(urlString) (\(durationMs)ms, \(dataSize) bytes)")
    }
}
