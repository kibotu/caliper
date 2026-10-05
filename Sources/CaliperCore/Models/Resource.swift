import Foundation

/// Represents a resource type and its aggregate size
public struct Resource: Codable {
    public var size: Int64 = 0
    public var count: Int = 0
}
