import Foundation
import Testing
@testable import CaliperCore

@Suite("VersionService")
struct VersionServiceTests {

    private let service = VersionService()

    /// `Dictionary` iteration order is randomised per process, so the resolution order
    /// is what these tests pin.
    @Test("prefers an explicit package mapping")
    func prefersExplicitMapping() throws {
        let modules = ["AdjustSDK": ModuleSize(name: "AdjustSDK")]
        service.assignVersions(
            to: modules,
            using: ["ext.adjust_signature_sdk": "5.1.0", "AdjustSDK": "9.9.9"],
            packageNameMapping: ["AdjustSDK": "ext.adjust_signature_sdk"]
        )
        #expect(modules["AdjustSDK"]?.version == "5.1.0")
    }

    @Test("falls back to an exact match")
    func exactMatch() {
        let modules = ["Orchard": ModuleSize(name: "Orchard")]
        service.assignVersions(to: modules, using: ["Orchard": "2.0.0"])
        #expect(modules["Orchard"]?.version == "2.0.0")
    }

    @Test("matches case-insensitively")
    func caseInsensitiveMatch() {
        let modules = ["Alamofire": ModuleSize(name: "Alamofire")]
        service.assignVersions(to: modules, using: ["alamofire": "5.9.0"])
        #expect(modules["Alamofire"]?.version == "5.9.0")
    }

    @Test("resolves a partial match deterministically")
    func partialMatchIsDeterministic() {
        // A substring of both identities; the longer one must win on every run.
        let mapping = [
            "orchard": "1.0.0",
            "orchardsdk": "2.5.0",
        ]
        for _ in 0..<50 {
            let modules = ["OrchardSDK": ModuleSize(name: "OrchardSDK")]
            service.assignVersions(to: modules, using: mapping)
            #expect(modules["OrchardSDK"]?.version == "2.5.0")
        }
    }

    @Test("leaves the version unset when nothing matches")
    func noMatch() {
        let modules = ["Unrelated": ModuleSize(name: "Unrelated")]
        service.assignVersions(to: modules, using: ["Something": "1.0.0"])
        #expect(modules["Unrelated"]?.version == nil)
    }

    @Test("does nothing for an empty version map")
    func emptyMapping() {
        let modules = ["Core": ModuleSize(name: "Core")]
        service.assignVersions(to: modules, using: [:])
        #expect(modules["Core"]?.version == nil)
    }
}

@Suite("PackageMappingService")
struct PackageMappingServiceTests {

    private let service = PackageMappingService()

    @Test("builds a module to identity map")
    func buildsMapping() {
        let mapping = service.buildMappingDictionary(from: [
            PackageNameMapping(moduleName: "A", packageIdentity: "a.pkg"),
            PackageNameMapping(moduleName: "B", packageIdentity: "b.pkg"),
        ])
        #expect(mapping == ["A": "a.pkg", "B": "b.pkg"])
    }

    @Test("does not crash on a duplicate module name")
    func duplicateKeysDoNotTrap() {
        // `Dictionary(uniqueKeysWithValues:)` would trap here.
        let mapping = service.buildMappingDictionary(from: [
            PackageNameMapping(moduleName: "A", packageIdentity: "first.pkg"),
            PackageNameMapping(moduleName: "A", packageIdentity: "second.pkg"),
        ])
        #expect(mapping == ["A": "first.pkg"])
    }
}