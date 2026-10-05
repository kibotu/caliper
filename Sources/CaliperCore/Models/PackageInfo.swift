import Foundation

/// Represents a package pin entry from Package.resolved
public struct PackagePin: Codable {
    public let identity: String
    public let kind: String
    public let location: String
    public let state: PackageState
}

/// Represents the state of a package including version
public struct PackageState: Codable {
    public let version: String?
    public let revision: String?
    public let branch: String?
}

/// Root structure of Package.resolved
public struct PackageResolved: Codable {
    public let originHash: String?
    public let pins: [PackagePin]
    public let version: Int
}
