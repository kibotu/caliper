import Foundation

/// Represents size information for a module/framework
/// Class is used for reference semantics - allows mutation during incremental parsing
public final class ModuleSize: Codable, @unchecked Sendable {
    public let name: String
    public var owner: String?
    /// Co-owners after the primary one. `nil` when the module has a single owner.
    public var additionalOwners: [String]?
    public var `internal`: Bool?
    public var version: String?
    public var binarySize: Int64 = 0
    /// Compressed size of the main binary, straight from the IPA listing.
    ///
    /// `binarySize` is overwritten with uncompressed LinkMap output when a LinkMap is
    /// supplied, so it cannot serve as the compressed figure. Without this, a module
    /// that ships nothing but a binary has an empty `top` and therefore reports zero
    /// download bytes — which is most frameworks in a real app.
    public var binaryCompressedSize: Int64 = 0
    public var imageSize: Int64 = 0
    public var imageFileSize: Int64 = 0
    public var proguard: Int64 = 0
    /// This module has no container in the IPA; its code is linked into the app binary.
    ///
    /// Such a module is created from LinkMap output alone (see `SizeCalculator`), so it
    /// owns no compressed bytes of its own and `downloadSize` is legitimately zero. The
    /// report labels these rather than printing "0 B", which reads as a measurement
    /// rather than the absence of one.
    public var staticallyLinked: Bool = false
    public var resources: [String: Resource] = [:]
    /// Assets found inside this module's `.car` catalogs, keyed by rendition name.
    ///
    /// Display only, and never part of any total: these are `assetutil` figures for the
    /// catalog *expanded*, so they are uncompressed and would corrupt the download
    /// figure. The `.car` file itself is counted in `top` at its compressed size.
    ///
    /// Kept separate from `top` so the report can list what a catalog contains instead
    /// of listing the catalog, which is only a container.
    public var assetCatalogFiles: [String: Int64] = [:]
    public var top: [String: Int64] = [:]
    public var files: [FileSize] = []
    
    // Internal dictionary for building files during parsing
    private var filesDict: [String: FileSize] = [:]
    
    public init(name: String) {
        self.name = name
    }
    
    /// Add a resource to this module
    public func addResource(type: String, size: Int64) {
        resources[type, default: Resource()].size += size
        resources[type, default: Resource()].count += 1
    }
    
    /// Track a file in the top files list
    public func addToTop(file: String, size: Int64) {
        top[file] = size
    }
    
    /// Finalize the top files list.
    ///
    /// A dictionary has no order, so there is nothing to finalize: consumers sort by
    /// value at the point of display. The previous implementation sorted into a fresh
    /// dictionary, which discarded the ordering it had just computed.
    public func finalizeTop() {}
    
    /// Add file size information
    public func addFileSize(fileName: String, size: Int64) {
        var fileSize = filesDict[fileName] ?? FileSize(fileName: fileName, size: 0, symbolCount: 0)
        fileSize.size += size
        fileSize.symbolCount += 1
        filesDict[fileName] = fileSize
    }
    
    /// Finalize the files list (convert to sorted array by size, largest first)
    /// Filters out the module-level entry (unattributed code)
    public func finalizeFiles() {
        files = filesDict.values
            .filter { $0.fileName != name }
            .sorted { $0.size > $1.size }
        filesDict.removeAll()
    }
    
    public enum CodingKeys: String, CodingKey {
        case name, owner, additionalOwners, `internal`, version, binarySize, binaryCompressedSize, imageSize, imageFileSize, proguard, staticallyLinked, resources, assetCatalogFiles, top, files
    }

    // MARK: - Canonical sizes

    /// Size of this module as stored on device, in bytes.
    ///
    /// `proguard` already carries the sum of every uncompressed file attributed to this
    /// module, plus the LinkMap binary size for modules that ship no bundle of their own
    /// (see `IPAParser.processLine` and `SizeCalculator`). The HTML report used to
    /// recompute this as `binarySize + imageFileSize + resources`, which double-counts
    /// images because the parsers record them in both `imageFileSize` and `resources`.
    /// Computing it once here keeps the two views from drifting.
    ///
    /// The field is still called `proguard` on the wire, a name inherited from upstream Ruler.
    public var installSize: Int64 { proguard }

    /// Size of this module as the user downloads it, in bytes.
    ///
    /// For a module with a container in the IPA this is the compressed size of its main
    /// binary plus every other file it owns. `binarySize` is excluded, because with a
    /// LinkMap it holds uncompressed output and would mix units in one number.
    ///
    /// A statically linked module has no container, so there is no compressed size to
    /// report and the sum above is legitimately zero. Its code is inside the app binary,
    /// which is why that zero was misleading: the module has a real, measured size —
    /// the LinkMap's uncompressed symbol bytes — and showing it is more useful than
    /// showing nothing. It is the same figure as `installSize` for such a module, and
    /// summing downloads across an app will over-count against the IPA, because these
    /// bytes are already inside the app binary's compressed size.
    ///
    /// The one-line summary: download size is compressed where a compressed size is
    /// known, and the best available measurement otherwise.
    public var downloadSize: Int64 {
        if staticallyLinked { return binarySize }
        return binaryCompressedSize + top.values.reduce(0, +)
    }
}
