import Foundation

public enum CaliperError: Error, LocalizedError {
    case unzipFailed
    case invalidIPA
    case invalidOwnershipFile(String, String)
    case invalidOutput
    case fileNotFound(String)
    case parseError(String)
    case linkMapParsingFailed(String)
    case assetCatalogParsingFailed(String)
    case sizeThresholdExceeded(String)

    public var errorDescription: String? {
        switch self {
        case .unzipFailed:
            "Failed to unzip IPA file"
        case .invalidIPA:
            "Invalid IPA file"
        case .invalidOwnershipFile(let path, let reason):
            "Invalid ownership file at \(path): \(reason)"
        case .invalidOutput:
            "Failed to generate output"
        case .fileNotFound(let path):
            "File not found: \(path)"
        case .parseError(let reason):
            "Parse error: \(reason)"
        case .linkMapParsingFailed(let reason):
            "Failed to parse LinkMap: \(reason)"
        case .assetCatalogParsingFailed(let reason):
            "Failed to parse asset catalog: \(reason)"
        case .sizeThresholdExceeded(let reason):
            reason
        }
    }
}
