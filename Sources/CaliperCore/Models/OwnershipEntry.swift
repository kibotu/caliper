import Foundation

public struct OwnershipEntry: Codable {
    /// A single owner, as written `owner: team`.
    public let owner: String?
    /// Several owners, as written `owners: [a, b]`.
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

    /// `owners:` wins over `owner:`; neither yields empty, meaning "matched but unowned".
    public var allOwners: [String] {
        if let owners, !owners.isEmpty {
            return owners
        }
        if let owner, !owner.isEmpty {
            return [owner]
        }
        return []
    }

    /// Matches a module name against `identifier`, honouring `*` and `?`. Everything
    /// else is escaped, so `Foundation.tbd` does not also match `FoundationXtbd`.
    public func matches(_ moduleName: String) -> Bool {
        let pattern = Self.globToRegex(identifier)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return identifier.caseInsensitiveCompare(moduleName) == .orderedSame
        }
        let range = NSRange(moduleName.startIndex..., in: moduleName)
        return regex.firstMatch(in: moduleName, options: [], range: range) != nil
    }

    /// Anchored at both ends, so the whole name must match.
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