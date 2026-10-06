import Foundation

public struct PackagePin: Codable {
    public let identity: String
    public let kind: String
    public let location: String
    public let state: PackageState
}

public struct PackageState: Codable {
    public let version: String?
    public let revision: String?
    public let branch: String?
}

public struct PackageResolved: Codable {
    public let originHash: String?
    public let pins: [PackagePin]
    public let version: Int
}
