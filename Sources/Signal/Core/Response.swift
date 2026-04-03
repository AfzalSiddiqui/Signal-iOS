import Foundation

/// Represents a typed API response.
public struct Response<T: Decodable> {
    public let data: T
    public let statusCode: Int
    public let headers: [AnyHashable: Any]
    public let rawData: Data

    public init(data: T, statusCode: Int, headers: [AnyHashable: Any], rawData: Data) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.rawData = rawData
    }
}
