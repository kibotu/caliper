import Foundation
import Testing
@testable import CaliperCore

/// A `.car` is a file in the IPA, so it belongs in the download total at its compressed
/// size. `assetutil` describes the catalog's contents once expanded, so its figures
/// describe installed size and the two must not be mixed.
@Suite("Asset catalog accounting")
struct AssetCatalogAccountingTests {

    /// No real IPA is needed: `buildAppSizeReport` reads the listing `unzip -v` emits.
    /// `unzippedPath` points nowhere, so `assetutil` fails — deliberately, since the
    /// compressed size must be recorded either way.
    private func report(for listing: String) throws -> ModuleSize {
        let report = try IPAParser().buildAppSizeReport(
            report: listing,
            unzippedPath: "/nonexistent"
        )
        return try #require(report["Demo"], "the app module was not attributed")
    }

    @Test("a catalog counts towards the download at its compressed size")
    func catalogCountsAsCompressedFile() throws {
        let module = try report(for: """
        19576 940 Payload/Demo.app/Assets.car
        214 65 Payload/Demo.app/Info.plist
        """)

        // 940 from the listing, not the 19,576 the catalog expands to.
        #expect(module.top["Payload/Demo.app/Assets.car"] == 940)
        #expect(module.downloadSize == 940 + 65)
    }

    @Test("a catalog the listing cannot parse still counts")
    func unparseableCatalogStillCounts() throws {
        let module = try report(for: "19576 940 Payload/Demo.app/Assets.car")

        #expect(module.downloadSize == 940)
    }

    @Test("a failed catalog parse does not invent download bytes")
    func failedParseAddsNothing() throws {
        let module = try report(for: "19576 940 Payload/Demo.app/Assets.car")

        #expect(module.top.count == 1)
        #expect(module.imageFileSize == 0)
    }

    @Test("download and install size are independent figures")
    func downloadAndInstallAreIndependent() throws {
        let module = try report(for: """
        19576 940 Payload/Demo.app/Assets.car
        1200 150 Payload/Demo.app/Demo
        """)

        #expect(module.downloadSize == 940 + 150)
        #expect(module.installSize == 19576 + 1200)
        // An uncompressed figure in the download total is detectable exactly this way.
        #expect(module.installSize / module.downloadSize > 1)
    }

    @Test("a loose image still records both a compressed and an uncompressed size")
    func looseImageUnchanged() throws {
        let module = try report(for: "4096 900 Payload/Demo.app/logo.png")

        #expect(module.imageSize == 900)
        #expect(module.imageFileSize == 4096)
        #expect(module.downloadSize == 900)
    }

    @Test("catalog contents are kept out of the totals")
    func catalogContentsAreNotTotals() {
        let module = ModuleSize(name: "Demo")
        module.assetCatalogFiles["icon.png"] = 1608

        #expect(module.downloadSize == 0)
        #expect(module.installSize == 0)
    }

    @Test("catalog contents reach the report")
    func catalogContentsAreEncoded() throws {
        let module = ModuleSize(name: "Demo")
        module.assetCatalogFiles["icon.png"] = 536
        module.assetCatalogFiles["logo@2x.png"] = 1024

        let json = try #require(
            try JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(module)
            ) as? [String: Any]
        )
        let catalog = try #require(json["assetCatalogFiles"] as? [String: Int])

        #expect(catalog["icon.png"] == 536)
        #expect(catalog["logo@2x.png"] == 1024)
    }
}