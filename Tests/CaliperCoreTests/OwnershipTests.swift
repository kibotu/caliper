import Foundation
import Testing
@testable import CaliperCore

@Suite("OwnershipEntry")
struct OwnershipEntryTests {

    @Test("matches plain names exactly")
    func matchesPlainNames() {
        let entry = OwnershipEntry(identifier: "MyApp", owner: "App Team")
        #expect(entry.matches("MyApp"))
        #expect(entry.matches("myapp"))
        #expect(!entry.matches("MyAppHelper"))
        #expect(!entry.matches("NotMyApp"))
    }

    @Test("supports * and ? wildcards")
    func supportsWildcards() {
        #expect(OwnershipEntry(identifier: "*CoreFeature*", owner: "Core").matches("CoreFeatureOne"))
        #expect(OwnershipEntry(identifier: "Feature?", owner: "Core").matches("FeatureA"))
        #expect(!OwnershipEntry(identifier: "Feature?", owner: "Core").matches("FeatureAB"))
    }

    @Test("treats dots in an identifier literally")
    func escapesRegexMetacharacters() {
let entry = OwnershipEntry(identifier: "Foundation.tbd", owner: "Apple")
        #expect(entry.matches("Foundation.tbd"))
        #expect(!entry.matches("FoundationXtbd"))
    }

    @Test("treats other regex metacharacters literally")
    func escapesOtherMetacharacters() {
        #expect(OwnershipEntry(identifier: "a+b(c)", owner: "x").matches("a+b(c)"))
        #expect(!OwnershipEntry(identifier: "a+b(c)", owner: "x").matches("aab(c)"))
        #expect(OwnershipEntry(identifier: "[Internal]", owner: "x").matches("[Internal]"))
    }

    @Test("reads a single owner")
    func singleOwner() {
        let entry = OwnershipEntry(identifier: "Core", owner: "Core Team")
        #expect(entry.allOwners == ["Core Team"])
    }

    @Test("reads an owners list, primary first")
    func ownersList() {
        let entry = OwnershipEntry(identifier: "Core", owner: "A")
        #expect(entry.allOwners == ["A"])
    }

    @Test("has no owners when neither key is set")
    func noOwners() {
        let decoded = try? JSONDecoder().decode(
            OwnershipEntry.self,
            from: Data(#"{"identifier":"Core"}"#.utf8)
        )
        #expect(decoded?.allOwners.isEmpty == true)
    }
}

@Suite("OwnershipService")
struct OwnershipServiceTests {

    private let service = OwnershipService()

    private func entries(_ yaml: String) throws -> [OwnershipEntry] {
        try withTempFile(yaml) { try service.loadOwnershipFile(from: $0) }
    }

    @Test("parses entries from YAML")
    func parsesYaml() throws {
        let parsed = try entries("""
        - identifier: "*CoreFeature*"
          owner: Core Team
          internal: true

        - identifier: ThirdParty
          owner: External
        """)

        #expect(parsed.count == 2)
        #expect(parsed[0].identifier == "*CoreFeature*")
        #expect(parsed[0].allOwners == ["Core Team"])
        #expect(parsed[0].internal == true)
        #expect(parsed[1].internal == nil)
    }

    @Test("parses an owners list")
    func parsesOwnersList() throws {
        let parsed = try entries("""
        - identifier: Shared
          owners:
            - ui-team
            - design-systems
        """)
        #expect(parsed[0].allOwners == ["ui-team", "design-systems"])
    }

    @Test("first matching entry wins, so put specific patterns first")
    func firstMatchWins() throws {
        let parsed = try entries("""
        - identifier: "LoginFeature"
          owner: Auth
        - identifier: "*Feature*"
          owner: Generic
        """)

        let entry = service.findEntry(for: "LoginFeature", in: parsed)
        #expect(entry?.allOwners == ["Auth"])

let reversed = try entries("""
        - identifier: "*Feature*"
          owner: Generic
        - identifier: "LoginFeature"
          owner: Auth
        """)
        #expect(service.findEntry(for: "LoginFeature", in: reversed)?.allOwners == ["Generic"])
    }

    @Test("assigns owners and splits additional owners")
    func assignsAdditionalOwners() throws {
        let parsed = try entries("""
        - identifier: Shared
          owners:
            - primary
            - secondary
            - tertiary
        """)

        var modules = ["Shared": ModuleSize(name: "Shared")]
        service.assignOwners(to: modules, using: parsed)

        #expect(modules["Shared"]?.owner == "primary")
        #expect(modules["Shared"]?.additionalOwners == ["secondary", "tertiary"])
    }

    @Test("leaves additionalOwners nil for a single owner")
    func singleOwnerHasNoAdditionalOwners() throws {
        let parsed = try entries("- identifier: Solo\n  owner: Team")
        var modules = ["Solo": ModuleSize(name: "Solo")]
        service.assignOwners(to: modules, using: parsed)

        #expect(modules["Solo"]?.owner == "Team")
        #expect(modules["Solo"]?.additionalOwners == nil)
    }

    @Test("tags the app module as App and internal")
    func tagsAppModule() {
        var modules = ["MyApp": ModuleSize(name: "MyApp")]
        service.tagAppModule(
            in: modules,
            appInfo: AppInfo(appModuleName: "MyApp")
        )

        #expect(modules["MyApp"]?.owner == "App")
        #expect(modules["MyApp"]?.internal == true)
    }

    @Test("does not overwrite an ownership-file entry for the app module")
    func appTagRespectsExplicitOwner() {
        var modules = ["MyApp": ModuleSize(name: "MyApp")]
        modules["MyApp"]?.owner = "Mobile Platform"
        service.tagAppModule(
            in: modules,
            appInfo: AppInfo(appModuleName: "MyApp")
        )

        #expect(modules["MyApp"]?.owner == "Mobile Platform")
        #expect(modules["MyApp"]?.internal == true)
    }

    @Test("reports a missing ownership file")
    func missingFileThrows() {
        #expect(throws: CaliperError.self) {
            _ = try service.loadOwnershipFile(from: "/nonexistent/ownership.yml")
        }
    }

    @Test("reports malformed YAML as an ownership file error")
    func malformedYamlThrows() {
        #expect(throws: CaliperError.self) {
            _ = try withTempFile("not: a: list: at all: [") {
                try service.loadOwnershipFile(from: $0)
            }
        }
    }
}