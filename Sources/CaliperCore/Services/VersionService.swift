import Foundation

public struct VersionService {

    /// Deterministic: a module matching several identities always resolves the same way.
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

    /// Strongest match first: explicit mapping, exact, case-insensitive, then longest
    /// substring match in either direction.
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

        let partial = identities
            .filter { lowered.contains($0.lowercased()) || $0.lowercased().contains(lowered) }
            .sorted { $0.count > $1.count }

        guard let best = partial.first else { return nil }
        return versionMapping[best]
    }

    public init() {}
}