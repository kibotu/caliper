import Foundation

public struct PackageResolvedParser {
    public func parse(path: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: path)
        
        guard FileManager.default.fileExists(atPath: path) else {
            throw CaliperError.fileNotFound(path)
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        
        do {
            let packageResolved = try decoder.decode(PackageResolved.self, from: data)
            
            var versionMapping: [String: String] = [:]
            
            for pin in packageResolved.pins {
                let packageName = extractPackageName(from: pin.identity)
                let versionString = extractVersionString(from: pin.state)

                versionMapping[pin.identity] = versionString
                versionMapping[packageName] = versionString
            }
            
            ProgressReporter.success("Loaded version info for \(packageResolved.pins.count) packages")
            
            return versionMapping
            
        } catch {
            throw CaliperError.parseError("Failed to parse Package.resolved: \(error.localizedDescription)")
        }
    }
    
    /// "ext.firebaseiossdk" -> "firebaseiossdk"
    private func extractPackageName(from identity: String) -> String {
        let components = identity.split(separator: ".")
        return components.count > 1 ? components.dropFirst().joined(separator: ".") : identity
    }
    
    private func extractVersionString(from state: PackageState) -> String {
        if let version = state.version {
            return version
        }
        if let revision = state.revision {
            return "rev:\(revision.prefix(7))"
        }
        if let branch = state.branch {
            return "branch:\(branch)"
        }
        return "unknown"
    }
    public init() {}
}
