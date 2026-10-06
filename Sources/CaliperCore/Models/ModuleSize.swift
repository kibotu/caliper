import Foundation

/// A class, not a struct: the parsers mutate modules in place while streaming files.
public final class ModuleSize: Codable, @unchecked Sendable {
    public let name: String
    public var owner: String?
    /// Co-owners after the primary. `nil` when there is only one.
    public var additionalOwners: [String]?
    public var `internal`: Bool?
    public var version: String?
    public var binarySize: Int64 = 0
    /// Compressed size of the main binary, from the IPA listing. Kept separate because
    /// a LinkMap overwrites `binarySize` with uncompressed output.
    public var binaryCompressedSize: Int64 = 0
    public var imageSize: Int64 = 0
    public var imageFileSize: Int64 = 0
    public var proguard: Int64 = 0
    /// No container of its own in the IPA; the linker put its code in the app binary.
    public var staticallyLinked: Bool = false
    public var resources: [String: Resource] = [:]
    /// Renditions unpacked from this module's `.car` catalogs. Display only: these are
    /// uncompressed, so they never enter a compressed total. The `.car` itself is
    /// counted in `top`.
    public var assetCatalogFiles: [String: Int64] = [:]
    public var top: [String: Int64] = [:]
    public var files: [FileSize] = []

    private var filesDict: [String: FileSize] = [:]

    public init(name: String) {
        self.name = name
    }

    public func addResource(type: String, size: Int64) {
        resources[type, default: Resource()].size += size
        resources[type, default: Resource()].count += 1
    }
    
    public func addToTop(file: String, size: Int64) {
        top[file] = size
    }

    /// No-op: `top` is unordered and consumers sort at display time.
    public func finalizeTop() {}

    public func addFileSize(fileName: String, size: Int64) {
        var fileSize = filesDict[fileName] ?? FileSize(fileName: fileName, size: 0, symbolCount: 0)
        fileSize.size += size
        fileSize.symbolCount += 1
        filesDict[fileName] = fileSize
    }
    
    /// Drops the module-level entry, which holds unattributed code.
    public func finalizeFiles() {
        files = filesDict.values
            .filter { $0.fileName != name }
            .sorted { $0.size > $1.size }
        filesDict.removeAll()
    }
    
    public enum CodingKeys: String, CodingKey {
        case name, owner, additionalOwners, `internal`, version, binarySize, binaryCompressedSize, imageSize, imageFileSize, proguard, staticallyLinked, resources, assetCatalogFiles, top, files
    }

    /// Size as stored on device. `proguard` already carries the uncompressed sum of
    /// every file attributed here, plus the LinkMap binary size for modules that ship
    /// no bundle. The name is inherited from upstream Ruler.
    public var installSize: Int64 { proguard }

    /// Size as downloaded. `binarySize` is excluded: with a LinkMap it holds
    /// uncompressed output. A statically linked module has no container, so it reports
    /// its uncompressed LinkMap size instead — summing downloads over-counts the IPA,
    /// because those bytes are already inside the app binary.
    public var downloadSize: Int64 {
        if staticallyLinked { return binarySize }
        return binaryCompressedSize + top.values.reduce(0, +)
    }
}
