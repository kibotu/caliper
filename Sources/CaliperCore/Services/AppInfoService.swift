import Foundation

/// Service for extracting app information from IPA
public struct AppInfoService {
    /// Extract app info from the unzipped IPA directory
    public func extractAppInfo(from unzippedPath: String) throws -> AppInfo? {
        // Breadcrumb: Start app info extraction
        fputs("  [AppInfo] Searching for .app directory in: \(unzippedPath)\n", stderr)
        
        // Find the .app directory
        guard let appDirectory = findAppDirectory(in: unzippedPath) else {
            ProgressReporter.warning("Could not find .app directory in IPA")
            fputs("  [AppInfo] ⚠️  No .app directory found\n", stderr)
            return nil
        }
        
        fputs("  [AppInfo] Found .app directory: \(appDirectory)\n", stderr)
        
        // Extract the app module name from the .app directory name
        let appModuleName = extractAppModuleName(from: appDirectory)
        if let moduleName = appModuleName {
            fputs("  [AppInfo] App module name: \(moduleName)\n", stderr)
        }
        
        // Read Info.plist
        let infoPlistPath = "\(appDirectory)/Info.plist"
        guard FileManager.default.fileExists(atPath: infoPlistPath) else {
            ProgressReporter.warning("Info.plist not found at: \(infoPlistPath)")
            fputs("  [AppInfo] ⚠️  Info.plist not found at expected location\n", stderr)
            return nil
        }
        
        fputs("  [AppInfo] Parsing Info.plist...\n", stderr)
        return try parseInfoPlist(at: infoPlistPath, appModuleName: appModuleName)
    }
    
    // MARK: - Private Methods
    
    private func findAppDirectory(in unzippedPath: String) -> String? {
        let payloadPath = "\(unzippedPath)/Payload"
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: payloadPath) else {
            fputs("  [AppInfo] ⚠️  Cannot read Payload directory at: \(payloadPath)\n", stderr)
            return nil
        }
        
        fputs("  [AppInfo] Found \(contents.count) items in Payload directory\n", stderr)
        let appDirs = contents.filter { $0.hasSuffix(".app") }
        if appDirs.isEmpty {
            fputs("  [AppInfo] ⚠️  No .app directories found in Payload\n", stderr)
        } else {
            fputs("  [AppInfo] Found .app directories: \(appDirs.joined(separator: ", "))\n", stderr)
        }
        
        return appDirs.first.map { "\(payloadPath)/\($0)" }
    }
    
    private func extractAppModuleName(from appDirectory: String) -> String? {
        // Extract the .app name from the path
        // e.g., "/path/to/Payload/ProfisPartner.app" -> "ProfisPartner"
        let url = URL(fileURLWithPath: appDirectory)
        let appNameWithExtension = url.lastPathComponent  // "ProfisPartner.app"
        
        // Remove the .app extension
        if appNameWithExtension.hasSuffix(".app") {
            return String(appNameWithExtension.dropLast(4))  // Remove ".app"
        }
        
        return nil
    }
    
    private func parseInfoPlist(at path: String, appModuleName: String?) throws -> AppInfo? {
        let url = URL(fileURLWithPath: path)
        
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            ProgressReporter.warning("Failed to parse Info.plist")
            fputs("  [AppInfo] ❌ Failed to parse Info.plist\n", stderr)
            return nil
        }
        
        let appName = plist["CFBundleDisplayName"] as? String 
            ?? plist["CFBundleName"] as? String
        let version = plist["CFBundleShortVersionString"] as? String
        let buildNumber = plist["CFBundleVersion"] as? String
        let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        
        fputs("  [AppInfo] ✅ Extracted: \(appName ?? "Unknown") v\(version ?? "?") (\(buildNumber ?? "?"))\n", stderr)
        
        return AppInfo(
            appName: appName,
            appModuleName: appModuleName,
            version: version,
            buildNumber: buildNumber,
            bundleIdentifier: bundleIdentifier
        )
    }
    public init() {}
}
