import Foundation

public struct FileSize: Codable {
    public let fileName: String
    public var size: Int64
    public var symbolCount: Int
}
