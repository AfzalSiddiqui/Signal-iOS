import Foundation

/// Thread-safe in-memory LRU cache with TTL support.
public actor CacheManager {
    private struct CacheEntry {
        let data: Data
        let timestamp: Date
        let ttl: TimeInterval

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }

    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let maxSize: Int

    public init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }

    public func get(for key: String) -> Data? {
        guard let entry = cache[key] else { return nil }
        if entry.isExpired {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            return nil
        }
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }
        return entry.data
    }

    public func set(_ data: Data, for key: String, ttl: TimeInterval) {
        evictExpired()
        if cache.count >= maxSize, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
        cache[key] = CacheEntry(data: data, timestamp: Date(), ttl: ttl)
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    public func remove(for key: String) {
        cache.removeValue(forKey: key)
        accessOrder.removeAll { $0 == key }
    }

    public func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    public var count: Int {
        cache.count
    }

    private func evictExpired() {
        let expiredKeys = cache.filter { $0.value.isExpired }.map(\.key)
        for key in expiredKeys {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
}
