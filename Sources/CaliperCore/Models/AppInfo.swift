import Foundation

public struct AppInfo: Codable {
    public let appName: String?
    public let appModuleName: String?
    public let version: String?
    public let buildNumber: String?
    public let bundleIdentifier: String?

    public init(
        appName: String? = nil,
        appModuleName: String? = nil,
        version: String? = nil,
        buildNumber: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        self.appName = appName
        self.appModuleName = appModuleName
        self.version = version
        self.buildNumber = buildNumber
        self.bundleIdentifier = bundleIdentifier
    }

    public enum CodingKeys: String, CodingKey {
        case appName, appModuleName, version, buildNumber, bundleIdentifier
    }
    
    public var versionString: String? {
        if let version, let build = buildNumber {
            return "\(version) (\(build))"
        }
        return version ?? buildNumber
    }
}
