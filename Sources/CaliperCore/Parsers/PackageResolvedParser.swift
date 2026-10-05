import Foundation

/// Parser for Package.resolved files to extract Swift package version information
public struct PackageResolvedParser {
    /// Parse a Package.resolved file and return a mapping of module names to versions
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
                // Extract the package name from identity
                // Identity format is typically: "owner.PackageName" or "ext.PackageName"
                let packageName = extractPackageName(from: pin.identity)
                
                // Determine version string
                let versionString = extractVersionString(from: pin.state)
                
                // Store both the full identity and extracted name
                versionMapping[pin.identity] = versionString
                versionMapping[packageName] = versionString
            }
            
            ProgressReporter.success("Loaded version info for \(packageResolved.pins.count) packages")
            
            return versionMapping
            
        } catch {
            throw CaliperError.parseError("Failed to parse Package.resolved: \(error.localizedDescription)")
        }
    }
    
    /// Extract the package name from the identity (e.g., "ext.firebaseiossdk" -> "firebaseiossdk")
    private func extractPackageName(from identity: String) -> String {
        let components = identity.split(separator: ".")
        return components.count > 1 ? components.dropFirst().joined(separator: ".") : identity
    }
    
    /// Extract a version string from package state
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
