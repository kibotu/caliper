import Foundation
import Testing
@testable import CaliperCore

/// The canonical size totals, which the HTML report reads instead of recomputing
/// them. These had no coverage, which is how a module that ships nothing but a
/// binary came to report zero download bytes.
@Suite("ModuleSize totals")
struct ModuleSizeTotalsTests {

    @Test("a module that ships only a binary still has a download size")
    func binaryOnlyModuleHasDownloadSize() {
        let module = ModuleSize(name: "Alpha")
        module.binaryCompressedSize = 4096

        // `top` is empty, which is exactly the case that used to report zero.
        #expect(module.top.isEmpty)
        #expect(module.downloadSize == 4096)
    }

    @Test("download size is the compressed binary plus its other files")
    func downloadSizeCombinesBinaryAndFiles() {
        let module = ModuleSize(name: "Alpha")
        module.binaryCompressedSize = 4096
        module.addToTop(file: "Alpha/Assets.car", size: 1024)
        module.addToTop(file: "Alpha/en.lproj/Localizable.strings", size: 512)

        #expect(module.downloadSize == 4096 + 1024 + 512)
    }

    @Test("download size ignores the uncompressed binary figure")
    func downloadSizeExcludesUncompressedBinary() {
        let module = ModuleSize(name: "Alpha")
        module.binarySize = 90_000      // LinkMap output, uncompressed
        module.binaryCompressedSize = 40_000

        // Adding binarySize here would mix compressed and uncompressed units.
        #expect(module.downloadSize == 40_000)
    }

    @Test("install size is the uncompressed total")
    func installSizeIsProguard() {
        let module = ModuleSize(name: "Alpha")
        module.proguard = 90_000
        module.binarySize = 40_000
        module.imageFileSize = 30_000
        module.addResource(type: "png", size: 30_000)

        // The old formula was binarySize + imageFileSize + resources, which counted
        // every image twice because the parsers record it in both places.
        #expect(module.installSize == 90_000)
    }

    @Test("a module with no binary reports zero, not a negative total")
    func emptyModuleTotals() {
        let module = ModuleSize(name: "Empty")
        #expect(module.downloadSize == 0)
        #expect(module.installSize == 0)
    }
}

/// `installSize` and `downloadSize` are the single source of truth for the report,
/// so they have to survive the JSON round trip the HTML file is built from.
@Suite("ModuleSize encoding")
struct ModuleSizeEncodingTests {

    @Test("carries the canonical totals into the JSON")
    func encodesTotals() throws {
        let module = ModuleSize(name: "Alpha")
        module.binaryCompressedSize = 4096
        module.addToTop(file: "Alpha/Assets.car", size: 1024)
        module.proguard = 90_000

        let data = try JSONEncoder().encode(module)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["binaryCompressedSize"] as? Int == 4096)
    }

    @Test("round trips through JSON")
    func roundTrip() throws {
        let module = ModuleSize(name: "Alpha")
        module.binaryCompressedSize = 4096
        module.proguard = 90_000

        let decoded = try JSONDecoder().decode(ModuleSize.self, from: try JSONEncoder().encode(module))
        #expect(decoded.binaryCompressedSize == 4096)
        #expect(decoded.proguard == 90_000)
    }
}