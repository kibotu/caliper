import Foundation
import Yams

/// Service for handling module ownership configuration
public struct OwnershipService {
    /// Load ownership entries from a YAML file
    public func loadOwnershipFile(from path: String) throws -> [OwnershipEntry] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CaliperError.fileNotFound(path)
        }
        let yamlString = try String(contentsOfFile: path, encoding: .utf8)
        do {
            return try YAMLDecoder().decode([OwnershipEntry].self, from: yamlString)
        } catch {
            // Surface a Yams parse failure as the ownership-file error the user can
            // act on, rather than an untyped decoding error.
            throw CaliperError.invalidOwnershipFile(path, error.localizedDescription)
        }
    }

    /// Find the ownership entry for a given module name. First match wins, so the
    /// order of entries in the file is significant: put specific patterns first.
    public func findEntry(for moduleName: String, in entries: [OwnershipEntry]) -> OwnershipEntry? {
        entries.first { $0.matches(moduleName) }
    }

    /// Assign owners to modules in the app size report
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
            // Only emit additionalOwners when there is more than one, so the JSON
            // stays quiet for the common single-owner case.
            moduleSize.additionalOwners = owners.count > 1 ? Array(owners.dropFirst()) : nil
            moduleSize.internal = entry.`internal`
        }
    }
    
    /// Automatically tag the app module as internal with owner 'App'
    /// The app module is identified from the .app directory name in the IPA
    public func tagAppModule(
        in modules: [String: ModuleSize],
        appInfo: AppInfo?
    ) {
        // Get the app module name from the .app directory
        guard let appModuleName = appInfo?.appModuleName else {
            return
        }
        
        // Check if this module exists in our modules list
        guard let appModule = modules[appModuleName] else {
            ProgressReporter.warning("App module '\(appModuleName)' not found in modules list")
            return
        }
        
        var changes: [String] = []
        
        // Only set if not already set by ownership file
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
