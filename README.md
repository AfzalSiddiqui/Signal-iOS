# Signal-iOS

![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)
![iOS 15+](https://img.shields.io/badge/iOS-15+-blue.svg)
![macOS 12+](https://img.shields.io/badge/macOS-12+-blue.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)

**Signal-iOS** is a modern, type-safe, async/await networking toolkit for Swift. It provides a clean, generic API client with built-in support for authentication, caching, logging, retry logic, and parallel/serial task execution.

## Features

- Generic API client supporting GET, POST, PUT, DELETE, PATCH
- Type-safe request/response handling with `Codable` models
- Comprehensive error handling with specific error types
- Token-based authentication with automatic refresh
- In-memory LRU cache with TTL support
- Configurable request/response logging
- Parallel and serial async task execution
- Retry logic with exponential backoff
- Request and response interceptors
- Multipart file upload
- File download support
- Thread-safe design using Swift actors and Sendable

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add Signal to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/aspect-build/Signal-iOS.git", from: "1.0.0")
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

## Usage

### Basic GET Request

```swift
import Signal

let client = SignalClient(baseURL: URL(string: "https://api.example.com")!)

struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

let response: Response<[User]> = try await client.get(path: "/users")
print("Users: \(response.data)")
```

### POST Request with Body

```swift
struct CreateUser: Codable {
    let name: String
    let email: String
}

let newUser = CreateUser(name: "John", email: "john@example.com")
let response: Response<User> = try await client.post(path: "/users", body: newUser)
print("Created: \(response.data)")
```

### Error Handling

```swift
do {
    let response: Response<User> = try await client.get(path: "/users/999")
} catch let error as SignalError {
    switch error {
    case .notFound:
        print("User not found")
    case .authenticationError:
        print("Please login again")
    case .serverError(let code, _):
        print("Server error: \(code)")
    case .networkError:
        print("Check your connection")
    default:
        print(error.localizedDescription)
    }
}
```

### Authentication

```swift
let auth = TokenAuthManager(
    accessToken: "your-jwt-token",
    refreshToken: "your-refresh-token",
    onRefresh: { refreshToken in
        // Call your refresh endpoint
        return "new-access-token"
    }
)

let client = SignalClient(
    baseURL: URL(string: "https://api.example.com")!,
    authProvider: auth
)
```

### Parallel Requests

```swift
let results = try await ParallelExecutor.execute([
    { try await client.get(path: "/users") as Response<[User]> },
    { try await client.get(path: "/posts") as Response<[Post]> },
])
```

### Caching

```swift
let cache = CacheManager(maxSize: 50)
let client = SignalClient(
    baseURL: URL(string: "https://api.example.com")!,
    cacheManager: cache
)

// Cache response for 5 minutes
let response: Response<[User]> = try await client.get(
    path: "/users",
    cachePolicy: .memory(ttl: 300)
)
```

### Logging

```swift
let logger = SignalLogger(minimumLevel: .debug)
let client = SignalClient(
    baseURL: URL(string: "https://api.example.com")!,
    logger: logger
)

// All requests and responses will be logged:
// [DEBUG] [Signal] → GET https://api.example.com/users
// [INFO]  [Signal] ← 200 https://api.example.com/users (124.5ms, 2048 bytes)
```

### Retry Configuration

```swift
let client = SignalClient(
    baseURL: URL(string: "https://api.example.com")!,
    retryConfig: RetryConfiguration(
        maxAttempts: 3,
        delay: 1.0,
        multiplier: 2.0,
        retryableStatusCodes: [408, 429, 500, 502, 503, 504]
    )
)
```

## License

Signal-iOS is released under the MIT License. See [LICENSE](LICENSE) for details.
