import Foundation

/// Represents a module ownership entry from the YAML configuration
public struct OwnershipEntry: Codable {
    /// A single owner. Kept for decoding the common `owner: team` form.
    public let owner: String?
    /// Several owners, as written `owners: [a, b]`. Kept for the list form.
    public let owners: [String]?
    public let identifier: String
    public let `internal`: Bool?

    private enum CodingKeys: String, CodingKey {
        case owner, owners, identifier, `internal`
    }

    public init(identifier: String, owner: String, internal internalFlag: Bool? = nil) {
        self.identifier = identifier
        self.owner = owner
        self.owners = nil
        self.internal = internalFlag
    }

    /// All owners for this entry, primary first.
    ///
    /// `owners:` wins when both keys are present. An entry with neither yields an
    /// empty list, which callers treat as "matched but unowned".
    public var allOwners: [String] {
        if let owners, !owners.isEmpty {
            return owners
        }
        if let owner, !owner.isEmpty {
            return [owner]
        }
        return []
    }

    /// Matches a module name against `identifier`, honouring `*` and `?`.
    ///
    /// Everything that is not a wildcard is escaped before it reaches the regex, so a
    /// dotted module name like `Foundation.tbd` matches only itself. Without that,
    /// `Foundation.tbd` would also match `FoundationXtbd`, because `.` is a regex
    /// metacharacter.
    public func matches(_ moduleName: String) -> Bool {
        let pattern = Self.globToRegex(identifier)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return identifier.caseInsensitiveCompare(moduleName) == .orderedSame
        }
        let range = NSRange(moduleName.startIndex..., in: moduleName)
        return regex.firstMatch(in: moduleName, options: [], range: range) != nil
    }

    /// Escapes the identifier, then translates `*` and `?` into their regex
    /// equivalents. Anchored at both ends so the whole name must match.
    static func globToRegex(_ glob: String) -> String {
        var out = "^"
        for character in glob {
            switch character {
            case "*": out += ".*"
            case "?": out += "."
            default: out += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return out + "$"
    }
}