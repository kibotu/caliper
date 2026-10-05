import Foundation
import Testing
@testable import CaliperCore

/// A framework is analysed like any other module, and its container directory must not
/// be mistaken for its executable.
///
/// The archive lists both `Foo.framework/` and `Foo.framework/Foo`, and both reduce to
/// the same stem, so a name comparison cannot tell them apart. The directory entry is 0
/// bytes, so recording it as the binary overwrites the real figure whenever the archive
/// happens to list it last — which varies with how the IPA was built.
@Suite("Framework binaries")
struct FrameworkBinaryTests {

    private func module(_ listing: String) throws -> ModuleSize {
        try module(named: "Data", listing)
    }

    private func module(named name: String, _ listing: String) throws -> ModuleSize {
        let report = try IPAParser().buildAppSizeReport(
            report: listing,
            unzippedPath: "/nonexistent"
        )
        return try #require(report[name], "\(name) was not attributed")
    }

    @Test("a framework's binary is recognised")
    func frameworkBinaryRecognised() throws {
        let module = try module("""
        90000 45000 Payload/App.app/Frameworks/Data.framework/Data
        """)

        #expect(module.binaryCompressedSize == 45000)
        // The binary is not also listed as a file, which would double-count it.
        #expect(module.downloadSize == 45000)
    }

    @Test("the container directory is not recorded as the binary")
    func containerDirectoryIgnored() throws {
        // The directory entry sorts last here, so recording it would zero the binary.
        let module = try module("""
        90000 45000 Payload/App.app/Frameworks/Data.framework/Data
        0 0 Payload/App.app/Frameworks/Data.framework/
        """)

        #expect(module.binaryCompressedSize == 45000)
        #expect(module.downloadSize == 45000)
    }

    /// A framework binary is named after the framework, so it can end in an extension the
    /// categoriser treats as a resource. This one is a 90 KB executable, not a JSON
    /// payload, and reading it as a resource left the binary size at 0.
    @Test("a binary whose name ends in a resource extension is still a binary")
    func resourceLookingBinaryRecognised() throws {
        let module = try module("""
        90015 90015 Payload/App.app/Frameworks/Data.framework/Data.json
        """)

        #expect(module.binaryCompressedSize == 90015)
        // Not filed as a JSON resource.
        #expect(module.resources["json"] == nil)
        #expect(module.downloadSize == 90015)
    }

    /// A `.plist` alongside the binary must still be counted as a resource. The binary
    /// check is deliberately narrow, so it cannot swallow the framework's real resources.
    @Test("a framework's other resources are still counted")
    func frameworkResourcesStillCounted() throws {
        let module = try module("""
        90000 45000 Payload/App.app/Frameworks/Data.framework/Data
        4096 2048 Payload/App.app/Frameworks/Data.framework/Info.plist
        9000 3000 Payload/App.app/Frameworks/Data.framework/en.lproj/Localizable.strings
        """)

        #expect(module.binaryCompressedSize == 45000)
        #expect(module.resources["plist"]?.size == 2048)
        #expect(module.resources["strings"]?.size == 3000)
        #expect(module.downloadSize == 45000 + 2048 + 3000)
    }

    /// macOS-style versioned bundles, and the shape Xcode produced for the Sample app.
    @Test("a versioned framework layout is analysed")
    func versionedLayoutAnalysed() throws {
        let module = try module(named: "Versioned", """
        40000 40010 Payload/App.app/Frameworks/Versioned.framework/Versions/A/Versioned
        2048 1024 Payload/App.app/Frameworks/Versioned.framework/Info.plist
        """)

        #expect(module.binaryCompressedSize == 40010)
        #expect(module.downloadSize == 40010 + 1024)
    }
}