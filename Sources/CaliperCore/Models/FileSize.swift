import Foundation

/// Represents size information for an individual file within a module
public struct FileSize: Codable {
    public let fileName: String
    public var size: Int64
    public var symbolCount: Int
}
