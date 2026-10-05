import Foundation
import Testing
@testable import CaliperCore

/// A `.car` is a file in the IPA, so it belongs in the download total at its compressed
/// size. `assetutil` describes the catalog's *contents* once expanded, so those figures
/// describe installed size.
///
/// These two were previously conflated: the per-asset uncompressed numbers were added to
/// the compressed dictionaries, so an asset catalog's contribution to the download was
/// overstated by its compression ratio and the catalog itself was absent entirely.
/// Measured on a compiled catalog: 1,608 uncompressed asset bytes were reported against
/// a 940-byte compressed file in the IPA.
@Suite("Asset catalog accounting")
struct AssetCatalogAccountingTests {

    /// `buildAppSizeReport` reads the listing `unzip -v` produces, so a real IPA is not
    /// needed to exercise the accounting. `unzippedPath` points nowhere: the `.car` is
    /// not a real file, so `assetutil` fails and the parser's error path runs. That is
    /// deliberate — the compressed size must be recorded whether or not the catalog can
    /// be parsed.
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
        // No catalog on disk, so assetutil fails. The bytes still shipped in the IPA.
        let module = try report(for: "19576 940 Payload/Demo.app/Assets.car")

        #expect(module.downloadSize == 940)
    }

    @Test("a failed catalog parse does not invent download bytes")
    func failedParseAddsNothing() throws {
        // Without assetutil there is no per-asset detail at all. The download must be
        // the compressed file size alone, not a sum of figures that were never read.
        let module = try report(for: "19576 940 Payload/Demo.app/Assets.car")

        #expect(module.top.count == 1)
        #expect(module.imageFileSize == 0)
    }

    /// The whole point of the split: the two figures measure different things and must
    /// not be derived from one another.
    @Test("download and install size are independent figures")
    func downloadAndInstallAreIndependent() throws {
        let module = try report(for: """
        19576 940 Payload/Demo.app/Assets.car
        1200 150 Payload/Demo.app/Demo
        """)

        // Download is compressed, straight from the listing.
        #expect(module.downloadSize == 940 + 150)
        // Install is uncompressed, also from the listing.
        #expect(module.installSize == 19576 + 1200)
        // Neither is a multiple of the other here, which is the regression in one line:
        // an uncompressed number in the download total is detectable exactly this way.
        #expect(module.installSize / module.downloadSize > 1)
    }

    /// Loose images in the bundle are still recorded both ways, as before. Only the
    /// catalog path changed.
    @Test("a loose image still records both a compressed and an uncompressed size")
    func looseImageUnchanged() throws {
        let module = try report(for: "4096 900 Payload/Demo.app/logo.png")

        #expect(module.imageSize == 900)
        #expect(module.imageFileSize == 4096)
        #expect(module.downloadSize == 900)
    }

    /// `assetCatalogFiles` is display-only. If it were ever summed into a total, an
    /// uncompressed figure would leak back into the compressed accounting, which is the
    /// defect this suite exists to prevent.
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