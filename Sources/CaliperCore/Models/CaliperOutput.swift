import Foundation

public struct CaliperOutput: Codable {
    public let appInfo: AppInfo?
    public let modules: [String: ModuleSize]
    public let totalPackageSize: Int64
    public let totalInstallSize: Int64
}
