import Foundation

/// Service to manage package version information from Package.resolved
public struct VersionService {

    /// Assign versions to modules based on package resolved data.
    ///
    /// Matching runs in a fixed order and the candidate list is sorted, so the same
    /// inputs always produce the same assignment. Iterating a `Dictionary` directly
    /// would give a different answer on each run whenever a module name matches more
    /// than one package identity.
    public func assignVersions(
        to modules: [String: ModuleSize],
        using versionMapping: [String: String],
        packageNameMapping: [String: String]? = nil
    ) {
        guard !versionMapping.isEmpty else { return }

        for moduleSize in modules.values {
            if let version = resolveVersion(
                for: moduleSize.name,
                versionMapping: versionMapping,
                packageNameMapping: packageNameMapping
            ) {
                moduleSize.version = version
            }
        }
    }

    /// Resolves the version for one module name, strongest match first.
    ///
    /// Order: an explicit mapping, an exact match, a case-insensitive match, then a
    /// prefix match in either direction. The last step is the fuzzy one, so it is
    /// only reached when nothing exact matched, and it prefers the longest candidate
    /// to avoid a short identity shadowing a longer, more specific one.
    func resolveVersion(
        for moduleName: String,
        versionMapping: [String: String],
        packageNameMapping: [String: String]?
    ) -> String? {
        if let mapped = packageNameMapping?[moduleName], let version = versionMapping[mapped] {
            return version
        }

        if let version = versionMapping[moduleName] {
            return version
        }

        let lowered = moduleName.lowercased()
        let identities = versionMapping.keys.sorted()

        for identity in identities where identity.lowercased() == lowered {
            return versionMapping[identity]
        }

        // Longest identity first, so `firebaseiossdk` beats a shorter `firebase`.
        // Deterministic because `identities` is sorted and ties cannot occur.
        let partial = identities
            .filter { lowered.contains($0.lowercased()) || $0.lowercased().contains(lowered) }
            .sorted { $0.count > $1.count }

        guard let best = partial.first else { return nil }
        return versionMapping[best]
    }

    public init() {}
}