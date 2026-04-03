import Foundation

/// Executes multiple async tasks in parallel and returns ordered results.
public enum ParallelExecutor {
    /// Executes all tasks concurrently. Throws on first failure.
    public static func execute<T: Sendable>(
        _ tasks: [@Sendable () async throws -> T]
    ) async throws -> [T] {
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for (index, task) in tasks.enumerated() {
                group.addTask {
                    let result = try await task()
                    return (index, result)
                }
            }
            var results = [(Int, T)]()
            results.reserveCapacity(tasks.count)
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Executes all tasks concurrently, collecting results without throwing.
    public static func executeSettled<T: Sendable>(
        _ tasks: [@Sendable () async -> Result<T, Error>]
    ) async -> [Result<T, Error>] {
        await withTaskGroup(of: (Int, Result<T, Error>).self) { group in
            for (index, task) in tasks.enumerated() {
                group.addTask {
                    let result = await task()
                    return (index, result)
                }
            }
            var results = [(Int, Result<T, Error>)]()
            results.reserveCapacity(tasks.count)
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Executes tasks concurrently with a concurrency limit. Returns ordered results.
    public static func executeWithLimit<T: Sendable>(
        _ tasks: [@Sendable () async throws -> T],
        limit: Int
    ) async throws -> [T] {
        let effectiveLimit = min(max(limit, 1), tasks.count)
        let results = UnsafeMutableBufferPointer<T?>.allocate(capacity: tasks.count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }

        let indexCounter = Counter()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<effectiveLimit {
                group.addTask {
                    while true {
                        let index = await indexCounter.next()
                        guard index < tasks.count else { return }
                        let result = try await tasks[index]()
                        results[index] = result
                    }
                }
            }
            try await group.waitForAll()
        }

        return (0..<tasks.count).map { results[$0]! }
    }
}

/// Thread-safe atomic counter for concurrency-limited execution.
private actor Counter {
    private var value = 0

    func next() -> Int {
        let current = value
        value += 1
        return current
    }
}
