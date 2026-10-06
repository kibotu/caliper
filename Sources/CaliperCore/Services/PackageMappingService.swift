import Foundation
import Yams

public struct PackageMappingService {
    public func loadMappingFile(from path: String) throws -> [PackageNameMapping] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CaliperError.fileNotFound(path)
        }

        let yamlString = try String(contentsOfFile: path, encoding: .utf8)
        let mappings = try YAMLDecoder().decode([PackageNameMapping].self, from: yamlString)

        ProgressReporter.success("Loaded \(mappings.count) package name mappings")
        return mappings
    }

    /// First entry wins on a duplicate, with a warning, rather than trapping.
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