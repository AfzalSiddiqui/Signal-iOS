import Foundation

/// Executes async tasks sequentially in order.
public enum SerialTaskExecutor {
    /// Executes tasks one by one. If `stopOnError` is true, throws on first failure.
    public static func execute<T>(
        _ tasks: [() async throws -> T],
        stopOnError: Bool = false
    ) async throws -> [Result<T, Error>] {
        var results = [Result<T, Error>]()
        results.reserveCapacity(tasks.count)

        for task in tasks {
            do {
                let value = try await task()
                results.append(.success(value))
            } catch {
                if stopOnError {
                    throw error
                }
                results.append(.failure(error))
            }
        }
        return results
    }

    /// Executes tasks sequentially, returning only successful values.
    public static func executeCompact<T>(
        _ tasks: [() async throws -> T]
    ) async -> [T] {
        var results = [T]()
        for task in tasks {
            if let value = try? await task() {
                results.append(value)
            }
        }
        return results
    }
}
