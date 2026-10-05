import Foundation
import Yams

/// Service for handling package name mapping configuration
public struct PackageMappingService {
    /// Load package name mappings from a YAML file
    public func loadMappingFile(from path: String) throws -> [PackageNameMapping] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CaliperError.fileNotFound(path)
        }

        let yamlString = try String(contentsOfFile: path, encoding: .utf8)
        let mappings = try YAMLDecoder().decode([PackageNameMapping].self, from: yamlString)

        ProgressReporter.success("Loaded \(mappings.count) package name mappings")
        return mappings
    }

    /// Build a dictionary from module names to package identities.
    ///
    /// A repeated `moduleName` is a user error, and `Dictionary(uniqueKeysWithValues:)`
    /// would trap on it. The first entry wins, with a warning, so a typo in a mapping
    /// file degrades to a diagnostic instead of a crash.
    public func buildMappingDictionary(from mappings: [PackageNameMapping]) -> [String: String] {
        var result: [String: String] = [:]
        for mapping in mappings {
            if let existing = result[mapping.moduleName], existing != mapping.packageIdentity {
                ProgressReporter.warning(
                    "Duplicate package mapping for '\(mapping.moduleName)': "
                        + "keeping '\(existing)', ignoring '\(mapping.packageIdentity)'"
                )
                continue
            }
            result[mapping.moduleName] = mapping.packageIdentity
        }
        return result
    }

    public init() {}
}