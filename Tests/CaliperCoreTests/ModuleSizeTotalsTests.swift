import Foundation
import Testing
@testable import CaliperCore

@Suite("ModuleSize totals")
struct ModuleSizeTotalsTests {

    @Test("a module that ships only a binary still has a download size")
    func binaryOnlyModuleHasDownloadSize() {
        let module = ModuleSize(name: "Alpha")
        module.binaryCompressedSize = 4096

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

        // Adding binarySize would mix compressed and uncompressed units.
        #expect(module.downloadSize == 40_000)
    }

    @Test("install size is the uncompressed total")
    func installSizeIsProguard() {
        let module = ModuleSize(name: "Alpha")
        module.proguard = 90_000
        module.binarySize = 40_000
        module.imageFileSize = 30_000
        module.addResource(type: "png", size: 30_000)

        #expect(module.installSize == 90_000)
    }

    @Test("a module with no binary reports zero, not a negative total")
    func emptyModuleTotals() {
        let module = ModuleSize(name: "Empty")
        #expect(module.downloadSize == 0)
        #expect(module.installSize == 0)
    }
}

@Suite("Statically linked modules")
struct StaticallyLinkedTests {

    /// A framework and a bundle with no binary: what the IPA parser produces.
    private func ipaModules() -> [String: ModuleSize] {
        let framework = ModuleSize(name: "Alpha")
        framework.binaryCompressedSize = 4096

        let bundle = ModuleSize(name: "Beta")
        bundle.addToTop(file: "Payload/Beta.bundle/Assets.car", size: 1024)

        return ["Alpha": framework, "Beta": bundle]
    }

    @Test("a module created from LinkMap alone is flagged as statically linked")
    func flagsLinkMapOnlyModules() {
        var report = ipaModules()

        SizeCalculator().updateBinarySizes(in: &report, moduleSizes: ["Alpha": 9000, "Gamma": 7000])

        #expect(report["Gamma"]?.staticallyLinked == true)
        #expect(report["Gamma"]?.downloadSize == 7000)
    }

    @Test("a statically linked module reports its measured size, not zero")
    func staticallyLinkedReportsMeasuredSize() {
        let module = ModuleSize(name: "Orchard")
        module.staticallyLinked = true
        module.binarySize = 35_730     // LinkMap symbols, uncompressed
        module.proguard = 35_730

        #expect(module.downloadSize == 35_730)
    }

    @Test("a module that ships a container is not flagged")
    func leavesContaineredModulesUnflagged() {
        var report = ipaModules()

        SizeCalculator().updateBinarySizes(in: &report, moduleSizes: ["Alpha": 9000, "Beta": 8000])

        #expect(report["Alpha"]?.staticallyLinked == false)
        #expect(report["Beta"]?.staticallyLinked == false)
        #expect(report["Alpha"]?.downloadSize == 4096)
        #expect(report["Beta"]?.downloadSize == 1024)
    }

    @Test("the flag is absent for a module that was never linked")
    func defaultsToFalse() {
        #expect(ModuleSize(name: "Alpha").staticallyLinked == false)
    }

    @Test("the flag reaches the report")
    func isEncoded() throws {
        let module = ModuleSize(name: "Gamma")
        module.staticallyLinked = true

        let data = try JSONEncoder().encode(module)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["staticallyLinked"] as? Bool == true)
    }
}

/// The report is built from the JSON, so the canonical totals have to survive it.
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