import Foundation
import Testing
@testable import CaliperCore

/// Real `swiftc` output for a module `Demo` with two classes. Hand-written mangled
/// names are unreliable: `swift_demangle` returns one it cannot parse unchanged, and the
/// length-prefix fallback then misreads it.
let linkMapFixture = """
# Path: lib.dylib
# Arch: arm64
# Object files:
[  0] linker synthesized
[  1] /tmp/build/Demo.build/Objects-normal/arm64/Greeter.o
[  2] /tmp/build/Demo.build/Objects-normal/arm64/Formatter.o
# Sections:
# Address\tSize    \tSegment\tSection
# Symbols:
# Address\tSize    \tFile  Name
0x000009E0\t0x0000017C\t[  1] _$s4Demo7GreeterC5greet4nameS2S_tF
0x00000B84\t0x00000030\t[  1] _$s4Demo7GreeterCfd
0x00000C18\t0x00000038\t[  2] _$s4Demo9FormatterCACycfC
0x00000C50\t0x00000024\t[  2] _$s4Demo9FormatterCACycfc
"""


@Suite("LinkMapParser")
struct LinkMapParserTests {

    @Test("sums symbol sizes per module")
    func sumsSymbolSizesPerModule() throws {
        let details = try withTempFile(linkMapFixture) {
            try LinkMapParser().parseDetailed(linkMapPath: $0)
        }

        let demo = try #require(details.moduleSizes["Demo"])
        #expect(demo == 520)
    }

    @Test("groups symbols into their demangled type names")
    func groupsByTypeName() throws {
        let details = try withTempFile(linkMapFixture) {
            try LinkMapParser().parseDetailed(linkMapPath: $0)
        }
        let demo = try #require(details.fileDetails["Demo"])

        // greet and the deinit fold into Greeter (0x17C + 0x30 = 428).
        let greeter = try #require(demo["Greeter"])
        let formatter = try #require(demo["Formatter"])
        #expect(greeter == 428)
        #expect(formatter == 92)
    }

    @Test("parse returns only module sizes")
    func parseReturnsModuleSizesOnly() throws {
        let modules = try withTempFile(linkMapFixture) {
            try LinkMapParser().parse(linkMapPath: $0)
        }
        let demo = try #require(modules["Demo"])
        #expect(demo == 520)
    }

    @Test("routes symbols with an unknown object index to the other bucket")
    func attributesUnknownIndicesToOther() throws {
        let t = "\t"
        let details = try withTempFile(
            """
            # Object files:
            [  0] /tmp/build/Known.build/Objects-normal/arm64/Known.o
            # Symbols:
            0x00000000\(t)0x00000040\(t)[  0] _$s5Known3fooyyF
            0x00000040\(t)0x00000080\(t)[  9] _$s4Nope1wC3fooyyF
            """
        ) {
            try LinkMapParser().parseDetailed(linkMapPath: $0)
        }
        let known = try #require(details.moduleSizes["Known"])
        let other = try #require(details.moduleSizes["other"])
        #expect(known == 0x40)
        #expect(other == 0x80)
    }

    @Test("ignores dead-stripped symbols")
    func ignoresDeadStrippedSymbols() throws {
        let t = "\t"
        let details = try withTempFile(
            """
            # Object files:
            [  0] /tmp/build/Demo.build/Objects-normal/arm64/A.o
            # Symbols:
            # Address\(t)Size\(t)   File  Name
            0x00000000\(t)0x00000040\(t)[  0] _$s4Demo1fC3fooyyF
            # Dead stripped symbols:
            0x00000000\(t)0x00000080\(t)[  0] _$s4Demo1gC3fooyyF
            """
        ) {
            try LinkMapParser().parseDetailed(linkMapPath: $0)
        }
        let demo = try #require(details.moduleSizes["Demo"])
        #expect(demo == 0x40)
    }

    @Test("throws when the file does not exist")
    func throwsOnMissingFile() {
        #expect(throws: (any Error).self) {
            try LinkMapParser().parseDetailed(linkMapPath: "/nonexistent/nope.txt")
        }
    }
}