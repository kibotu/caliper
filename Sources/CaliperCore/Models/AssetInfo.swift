import Foundation

/// Represents information about an asset from assetutil output
public struct AssetInfo: Codable {
    public let RenditionName: String?
    public let SizeOnDisk: Int?
}
