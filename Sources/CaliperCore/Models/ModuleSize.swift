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
    public var imageSize: Int64 = 0
    public var imageFileSize: Int64 = 0
    public var proguard: Int64 = 0
    public var resources: [String: Resource] = [:]
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
    
    /// Finalize the top files list (sort by size)
    public func finalizeTop() {
        // `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key. `top` cannot
        // have one, but building it by assignment keeps that precondition out of a
        // method that would otherwise be a crash waiting on an unrelated change.
        top = top.sorted { $0.value > $1.value }.reduce(into: [:]) { $0[$1.key] = $1.value }
    }
    
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
        case name, owner, additionalOwners, `internal`, version, binarySize, imageSize, imageFileSize, proguard, resources, top, files
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

    /// Size of this module inside the IPA, in bytes.
    ///
    /// Sum of the compressed sizes of the files this module owns. `binarySize` is
    /// deliberately excluded: it is uncompressed LinkMap output, so adding it here would
    /// mix compressed and uncompressed figures in one number.
    public var downloadSize: Int64 {
        top.values.reduce(0, +)
    }
}
