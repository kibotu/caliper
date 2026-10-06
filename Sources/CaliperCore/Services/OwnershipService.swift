import Foundation
import Yams

public struct OwnershipService {
    public func loadOwnershipFile(from path: String) throws -> [OwnershipEntry] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CaliperError.fileNotFound(path)
        }
        let yamlString = try String(contentsOfFile: path, encoding: .utf8)
        do {
            return try YAMLDecoder().decode([OwnershipEntry].self, from: yamlString)
        } catch {
            throw CaliperError.invalidOwnershipFile(path, error.localizedDescription)
        }
    }

    /// First match wins, so entry order is significant: put specific patterns first.
    public func findEntry(for moduleName: String, in entries: [OwnershipEntry]) -> OwnershipEntry? {
        entries.first { $0.matches(moduleName) }
    }

    public func assignOwners(
        to modules: [String: ModuleSize],
        using entries: [OwnershipEntry]
    ) {
        for moduleSize in modules.values {
            guard let entry = findEntry(for: moduleSize.name, in: entries) else {
                continue
            }
            let owners = entry.allOwners
            moduleSize.owner = owners.first
            moduleSize.additionalOwners = owners.count > 1 ? Array(owners.dropFirst()) : nil
            moduleSize.internal = entry.`internal`
        }
    }
    
    /// Never overwrites a value the ownership file already set.
    public func tagAppModule(
        in modules: [String: ModuleSize],
        appInfo: AppInfo?
    ) {
        guard let appModuleName = appInfo?.appModuleName else {
            return
        }

        guard let appModule = modules[appModuleName] else {
            ProgressReporter.warning("App module '\(appModuleName)' not found in modules list")
            return
        }
        
        var changes: [String] = []

        if appModule.owner == nil {
            appModule.owner = "App"
            changes.append("owner='App'")
        }
        
        if appModule.internal == nil {
            appModule.internal = true
            changes.append("internal=true")
        }
        
        if !changes.isEmpty {
            ProgressReporter.message("Tagged app module '\(appModuleName)' with \(changes.joined(separator: ", "))")
        }
    }
    
    public init() {}
}
