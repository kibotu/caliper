import Foundation
import Testing
@testable import CaliperCore

@Suite("HTMLReporter")
struct HTMLReporterTests {

    private func html(for json: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("caliper-html-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = dir.appendingPathComponent("report.html")
        try HTMLReporter().generate(jsonString: json, outputPath: out.path)
        return try String(contentsOf: out, encoding: .utf8)
    }

    @Test("inlines d3 instead of fetching it from a CDN")
    func isSelfContained() throws {
        let html = try html(for: #"{"modules":{}}"#)

        // Asserted on loadable references: the vendored bundle still mentions its own
        // homepage in a comment.
        #expect(!html.contains("<script src="))
        #expect(!html.contains("d3js.org/d3.v7.min.js"))
        #expect(html.contains("d3.select"))
    }

    /// `swift build` and the release archive keep d3 in the bundle's root; `mint install`
    /// produces an Apple bundle with it under `Contents/Resources`. Both must resolve.
    private func makeBundle(resources relative: String) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("caliper-bundle-\(UUID().uuidString)")
            .appendingPathComponent("caliper_CaliperCore.bundle")
        let directory = relative.isEmpty ? bundle : bundle.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.d3StandIn.write(
            to: directory.appendingPathComponent("d3.v7.min.js"),
            atomically: true,
            encoding: .utf8
        )
        return bundle
    }

    private func remove(_ bundle: URL) {
        try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent())
    }

    private static let d3StandIn = "// d3 stand-in"

    @Test("d3 is found in the Apple bundle layout a Mint install produces")
    func findsD3InMintLayout() throws {
        let bundle = try makeBundle(resources: "Contents/Resources")
        defer { remove(bundle) }

        let d3 = try #require(HTMLReporter.d3URL(inBundleAt: bundle))
        #expect(try String(contentsOf: d3, encoding: .utf8) == Self.d3StandIn)
    }

    @Test("d3 is found in the flat bundle layout a SwiftPM build produces")
    func findsD3InFlatLayout() throws {
        let bundle = try makeBundle(resources: "")
        defer { remove(bundle) }

        let d3 = try #require(HTMLReporter.d3URL(inBundleAt: bundle))
        #expect(try String(contentsOf: d3, encoding: .utf8) == Self.d3StandIn)
    }

    @Test("an empty bundle directory does not pass for one holding d3")
    func emptyBundleDirectoryIsNotAccepted() throws {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("caliper-empty-\(UUID().uuidString)")
            .appendingPathComponent("caliper_CaliperCore.bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { remove(bundle) }

        #expect(Bundle(url: bundle) != nil)
        #expect(HTMLReporter.d3URL(inBundleAt: bundle) == nil)
    }

    @Test("embeds the report data")
    func embedsData() throws {
        let html = try html(for: #"{"totalPackageSize":42}"#)
        #expect(!html.contains("__DATA__"))
        #expect(html.contains("totalPackageSize"))
    }

    @Test("cannot be broken out of the script element by a hostile module name")
    func escapesInjectedMarkup() throws {
        let hostile = "</script><script>alert('x')</script>"
        let json = #"{"modules":{"\#(hostile)":{"name":"\#(hostile)","proguard":1}}}"#
        let html = try html(for: json)

        #expect(!html.contains("</script><script>alert"))
        #expect(html.contains("\\u003c/script>"))
    }

    /// The template contains regex literals and division, so delimiter counting by hand
    /// is unreliable; a real parser is the only trustworthy check. Skipped without one,
    /// rather than passing vacuously.
    @Test("emits syntactically valid script blocks")
    func scriptBlocksAreValid() throws {
        guard let node = Self.javaScriptEngine() else {
            return
        }

        let html = try html(for: #"{"modules":{},"totalPackageSize":1}"#)
        let blocks = html.components(separatedBy: "<script>").dropFirst()
            .map { $0.components(separatedBy: "</script>")[0] }
        #expect(blocks.count == 2)

        for (index, script) in blocks.enumerated() {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("caliper-block-\(UUID().uuidString)-\(index).js")
            try script.write(to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }

            let process = Process()
            process.executableURL = node
            process.arguments = ["--check", file.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "script block \(index) is not valid JavaScript")
        }
    }

    /// Run against a Swift-encoded module, so the shipped JavaScript is pinned to the
    /// Swift definition rather than asserted about directly.
    @Test("the report's download figure matches the Swift total for a static module")
    func downloadFigureMatchesForStaticModule() throws {
        let encoded = ModuleSize(name: "Orchard")
        encoded.staticallyLinked = true
        encoded.binarySize = 35_730
        let json = try #require(String(data: try JSONEncoder().encode(encoded), encoding: .utf8))

        let html = try html(for: #"{"modules":{}}"#)
        let script = try #require(Self.appScript(in: html))
        let body = try #require(
            Self.functionBody(named: "calculateModuleDownload", in: script),
            "calculateModuleDownload not found"
        )

        #expect(try Self.evaluate(body, argument: json) == encoded.downloadSize)
    }

    static func javaScriptEngine() -> URL? {
        for candidate in ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["node"]
        which.standardOutput = FileHandle.nullDevice
        which.standardError = FileHandle.nullDevice
        guard (try? which.run()) != nil else { return nil }
        which.waitUntilExit()
        return which.terminationStatus == 0 ? URL(fileURLWithPath: "/opt/homebrew/bin/node") : nil
    }

    @Test("escapes angle brackets in the embedded payload")
    func htmlSafeEscapesLessThan() {
        #expect("a<b".htmlSafe() == "a\\u003cb")
        #expect("no brackets".htmlSafe() == "no brackets")
    }

    /// The report carries its own copy of the size arithmetic, so the two can drift.
    @Test("the report's size functions agree with the Swift totals")
    func sizeFunctionsMatchSwiftTotals() throws {
        let module = ModuleSize(name: "Alpha")
        module.binaryCompressedSize = 4096
        module.binarySize = 90_000          // uncompressed LinkMap output
        module.proguard = 120_000
        module.addToTop(file: "Alpha/Assets.car", size: 1024)

        let json = try #require(
            String(data: try JSONEncoder().encode(module), encoding: .utf8)
        )
        let html = try html(for: #"{"modules":{"Alpha":\#(json)}}"#)

        // The module is spliced in as a literal: the bodies are evaluated outside the
        // page, where `data` does not exist.
        let script = try #require(Self.appScript(in: html))
        for (name, expected) in [
            ("calculateModuleDownload", module.downloadSize),
            ("calculateModuleTotal", module.installSize),
        ] {
            let body = try #require(Self.functionBody(named: name, in: script), "\(name) not found")
            let actual = try Self.evaluate(body, argument: json)
            #expect(Int64(actual) == expected, "\(name) returned \(actual), expected \(expected)")
        }
    }

    /// `ProfisCore` is shared between `core`, `app` and `payments`; `ProfisBus` between
    /// `bus` and `core`. The case every assertion in this group turns on.
    private func multiOwnerModule() throws -> String {
        let core = ModuleSize(name: "ProfisCore")
        core.owner = "core"
        core.additionalOwners = ["app", "payments"]
        core.`internal` = true
        core.binaryCompressedSize = 180_000
        core.proguard = 420_000

        let bus = ModuleSize(name: "ProfisBus")
        bus.owner = "bus"
        bus.additionalOwners = ["core"]
        bus.`internal` = true
        bus.binaryCompressedSize = 120_000
        bus.proguard = 300_000

        let unowned = ModuleSize(name: "PaymentsSDK")
        unowned.owner = "payments"
        unowned.binaryCompressedSize = 60_000
        unowned.proguard = 150_000

        let modules = try JSONEncoder().encode([
            "ProfisCore": core, "ProfisBus": bus, "PaymentsSDK": unowned,
        ])
        return try #require(String(data: modules, encoding: .utf8))
    }

    private func report(withModules json: String) throws -> String {
        try html(for: #"{"totalPackageSize":4200000,"totalInstallSize":11900000,"modules":\#(json)}"#)
    }

    @Test("a module's owners are the primary plus its co-owners, de-duplicated")
    func allOwnersDeduplicates() throws {
        let html = try report(withModules: multiOwnerModule())
        let script = try #require(Self.appScript(in: html))
        let declaration = try Self.declaration(named: "allOwners", in: script)

        func owners(_ module: String) throws -> String {
            try Self.run("""
            \(declaration)
            console.log(JSON.stringify(allOwners(\(module))));
            """).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        #expect(try owners(#"{"owner":"core","additionalOwners":["app","payments"]}"#)
            == #"["core","app","payments"]"#)
        #expect(try owners(#"{"owner":"bus","additionalOwners":["core"]}"#)
            == #"["bus","core"]"#)
        // A repeated primary must not yield twice, or the team filter would match on a
        // name the report only ever shows once.
        #expect(try owners(#"{"owner":"core","additionalOwners":["core","app"]}"#)
            == #"["core","app"]"#)
        #expect(try owners("{}") == "[]")
    }

    @Test("the team filter matches on any owner, not only the first")
    func teamFilterMatchesAnyOwner() throws {
        let html = try report(withModules: multiOwnerModule())
        let script = try #require(Self.appScript(in: html))
        let declaration = try Self.declaration(named: "moduleMatchesBreakdownFilters", in: script)
        let helpers = try Self.declarations(["allOwners"], in: script)

        let shared = #"{"name":"ProfisCore","owner":"core","additionalOwners":["app","payments"],"internal":true}"#

        func matches(_ team: String) throws -> Bool {
            let out = try Self.run("""
            let breakdownFilters = { internal: true, external: true, owned: true, unowned: true };
            let breakdownTeamFilter = '\(team)';
            \(helpers)
            \(declaration)
            console.log(moduleMatchesBreakdownFilters(\(shared)));
            """).trimmingCharacters(in: .whitespacesAndNewlines)
            return out == "true"
        }

        #expect(try matches("core"))
        #expect(try matches("app"))
        #expect(try matches("payments"))
        #expect(try matches("bus") == false)
        #expect(try matches("") == true)
    }

    @Test("every owner is badged, and only the breakdown ones filter")
    func everyOwnerIsBadged() throws {
        let html = try report(withModules: multiOwnerModule())
        let script = try #require(Self.appScript(in: html))
        let declaration = try Self.declaration(named: "renderOwnerBadges", in: script)
        let helpers = try Self.declarations(["allOwners"], in: script)

        let module = #"{"owner":"core","additionalOwners":["app","payments"]}"#

        func badges(_ argument: String) throws -> String {
            try Self.run("""
            let breakdownTeamFilter = '';
            const escapeHtml = (text) => text;
            \(helpers)
            \(declaration)
            console.log(renderOwnerBadges(\(argument)));
            """).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let filtering = try badges(module)
        let plain = try badges(module + ", false")

        for team in ["core", "app", "payments"] {
            #expect(filtering.contains(">\(team)</span>"), "missing badge for \(team)")
        }
        // Three owners, three badges, and two of them marked as co-owners.
        #expect(filtering.components(separatedBy: "owner-badge-filter").count - 1 == 3)
        #expect(filtering.components(separatedBy: " additional").count - 1 == 2)
        #expect(!plain.contains("owner-badge-filter"))
        #expect(plain.contains(">payments</span>"))
    }

    @Test("the chart partitions by primary owner while the list counts shared modules for each team")
    func ownershipGroupingsDifferDeliberately() throws {
        let json = try multiOwnerModule()
        let html = try report(withModules: json)
        let script = try #require(Self.appScript(in: html))

        let helpers = try Self.declarations(
            ["calculateModuleDownload", "calculateModuleTotal", "allOwners",
             "summariseOwner", "sortOwners", "prepareOwnershipChartData", "prepareOwnerGroupData"],
            in: script
        )
        let preamble = """
        const data = { modules: \(json) };
        const moduleMatchesOwnershipFilters = () => true;
        """

        func groups(_ function: String) throws -> [String: (size: Int64, count: Int64)] {
            let out = try Self.run("""
            \(helpers)
            \(preamble)
            console.log(JSON.stringify(\(function)().map(o => ({ name: o.name, size: o.totalDownloadSize, n: o.moduleCount }))));
            """).trimmingCharacters(in: .whitespacesAndNewlines)
            let rows = try #require(
                try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]]
            )
            var result: [String: (size: Int64, count: Int64)] = [:]
            for row in rows {
                result[try #require(row["name"] as? String)] = (
                    size: try #require(row["size"] as? Int64),
                    count: try #require(row["n"] as? Int64)
                )
            }
            return result
        }

        let chart = try groups("prepareOwnershipChartData")
        let detail = try groups("prepareOwnerGroupData")

        // ProfisCore's 180 000 sits with `core` alone, so the bars sum to the app's
        // 360 000. `app` owns nothing outright, so it is absent.
        #expect(chart["core"]?.size == 180_000)
        #expect(chart["core"]?.count == 1)
        #expect(chart["bus"]?.size == 120_000)
        #expect(chart["payments"]?.size == 60_000)
        #expect(chart["app"] == nil)
        let chartTotal = try #require(chart.values.reduce(0) { $0 + $1.size })
        #expect(chartTotal == 360_000)

        // ProfisCore in full for core, app and payments; ProfisBus for bus and core.
        #expect(detail["core"]?.size == 300_000)      // ProfisCore + ProfisBus
        #expect(detail["core"]?.count == 2)
        #expect(detail["app"]?.size == 180_000)        // ProfisCore
        #expect(detail["payments"]?.size == 240_000)   // ProfisCore + PaymentsSDK
        #expect(detail["bus"]?.size == 120_000)        // ProfisBus
        let detailTotal = try #require(detail.values.reduce(0) { $0 + $1.size })
        #expect(detailTotal == 840_000)
        #expect(detailTotal > chartTotal)
    }

    @Test("the team filter offers every team, co-owners included")
    func teamFilterOptionsIncludeCoOwners() throws {
        let json = try multiOwnerModule()
        let html = try report(withModules: json)
        let script = try #require(Self.appScript(in: html))
        let declaration = try Self.declaration(named: "collectAllTeams", in: script)
        let helpers = try Self.declarations(["allOwners"], in: script)

        let out = try Self.run("""
        const data = { modules: \(json) };
        \(helpers)
        \(declaration)
        console.log(JSON.stringify(collectAllTeams()));
        """).trimmingCharacters(in: .whitespacesAndNewlines)

        let teams = try #require(
            try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String]
        )
        #expect(teams == ["app", "bus", "core", "payments"])
    }

    @Test("a bar click resolves its team by name, not by index")
    func barClickResolvesByName() throws {
        let html = try html(for: #"{"modules":{}}"#)
        let script = try #require(Self.appScript(in: html))
        let declaration = try Self.declaration(named: "showOwnerDetails", in: script)

        let out = try Self.run("""
        const ownerGroupData = [
            { name: 'core', totalDownloadSize: 300000 },
            { name: 'app', totalDownloadSize: 180000 },
            { name: 'bus', totalDownloadSize: 120000 }
        ];
        let selected = null, rendered = null, scrolled = false;
        const document = {
            getElementById: (id) => ({
                // A select coerces an assigned value to a string, as a browser does.
                set value(v) { if (id === 'ownerDropdown') selected = String(v); },
                get value() { return selected; },
                scrollIntoView: () => { if (id === 'ownerDetailSection') scrolled = true; }
            })
        };
        const renderOwnerDetails = (i) => { rendered = i; };
        \(declaration)
        showOwnerDetails('bus');
        showOwnerDetails('nobody');
        console.log(JSON.stringify({ selected, rendered, scrolled }));
        """).trimmingCharacters(in: .whitespacesAndNewlines)

        let result = try #require(
            try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        )
        // The unknown team must leave the selection alone rather than blanking it.
        #expect(result["rendered"] as? Int == 2)
        #expect(result["selected"] as? String == "2")
        #expect(result["scrolled"] as? Bool == true)
    }

    @Test("the owner detail cards name the module, not its index")
    func ownerDetailNamesModulesNotIndices() throws {
        let json = try multiOwnerModule()
        let html = try report(withModules: json)
        let script = try #require(Self.appScript(in: html))
        let body = try Self.declaration(named: "renderOwnerDetails", in: script)
        let helpers = try Self.declarations(
            ["formatBytes", "calculateModuleDownload", "calculateModuleTotal", "allOwners",
             "getFileTypeInfo", "renderResourceRow", "compiledCatalogNote", "renderModuleResources",
             "renderOwnerBadges"],
            in: script
        )

        let out = try Self.run("""
        const data = { modules: \(json) };
        // About the markup rather than the grouping, so the group is handed over.
        const ownerGroupData = [{ name: 'core', moduleCount: 2, fileCount: 0,
            totalDownloadSize: 300000, totalInstallSize: 720000,
            modules: data.modules.ProfisCore ? [data.modules.ProfisCore, data.modules.ProfisBus] : [] }];
        const escapeHtml = (text) => text;
        const document = {
            getElementById: (id) => ({
                style: {},
                scrollIntoView: () => {},
                set innerHTML(v) { globalThis.captured = v; },
                get innerHTML() { return globalThis.captured || ''; }
            })
        };
        \(helpers)
        \(body)
        const index = ownerGroupData.findIndex(o => o.name === 'core');
        renderOwnerDetails(String(index));
        console.log(JSON.stringify({
            names: [...String(globalThis.captured).matchAll(/<div class="module-name-row">\\s*([^<]+)/g)].map(m => m[1].trim())
        }));
        """).trimmingCharacters(in: .whitespacesAndNewlines)

        let result = try #require(
            try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        )
        let names = try #require(result["names"] as? [String])
        #expect(names == ["ProfisCore", "ProfisBus"])
        #expect(!names.contains("0"))
    }

    /// The compressed and uncompressed pairs are far apart, so a test can tell which
    /// one a chart used.
    private func dualFigureModule() -> ModuleSize {
        let module = ModuleSize(name: "Alpha")
        module.`internal` = true
        module.binaryCompressedSize = 40_000
        module.binarySize = 90_000
        module.proguard = 210_000
        module.imageSize = 2_000            // compressed
        module.imageFileSize = 30_000       // uncompressed
        module.addToTop(file: "Payload/App.app/Alpha.bundle/Assets.car", size: 60_010)
        module.addToTop(file: "Payload/App.app/Alpha.bundle/Info.plist", size: 4)
        module.addToTop(file: "Payload/App.app/Alpha.bundle/icon.png", size: 2_000)
        module.addResource(type: "plist", size: 4)
        module.addResource(type: "png", size: 2_000)
        module.assetCatalogFiles["logo.png"] = 5_000
        return module
    }

    /// The lifted bodies read module-level state that does not exist outside the page,
    /// so `preamble` supplies it: `%MODULE%` is the encoded module.
    private func runInPage(
        module: ModuleSize,
        basis: String,
        lifting names: [String],
        preamble: String = "",
        expression: String
    ) throws -> String {
        let json = try #require(String(data: try JSONEncoder().encode(module), encoding: .utf8))
        let script = try #require(Self.appScript(in: try html(for: #"{"modules":{}}"#)))
        let lifted = try Self.declarations(
            ["formatBytes", "calculateModuleDownload", "calculateModuleTotal", "moduleSizeForInsights"] + names,
            in: script
        )
        return try Self.run("""
        let insightsSizeBasis = '\(basis)';
        \(lifted)
        \(preamble.replacingOccurrences(of: "%MODULE%", with: json))
        console.log(JSON.stringify(\(expression.replacingOccurrences(of: "%MODULE%", with: json))));
        """).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func declarations(_ names: [String], in script: String) throws -> String {
        try names.map { try declaration(named: $0, in: script) }.joined(separator: "\n")
    }

    @Test("the Insights size control picks the download figure when asked")
    func insightsSizeBasisSelectsDownload() throws {
        let module = dualFigureModule()

        let install = try runInPage(
            module: module, basis: "installSize", lifting: [],
            expression: "moduleSizeForInsights(%MODULE%)"
        )
        let download = try runInPage(
            module: module, basis: "downloadSize", lifting: [],
            expression: "moduleSizeForInsights(%MODULE%)"
        )

        #expect(Int64(install) == module.installSize)
        #expect(Int64(download) == module.downloadSize)
        #expect(install != download)
    }

    /// Listing both representations counts the same bytes twice in one ranked chart.
    @Test("the catalog is one labelled container row when compressed, its contents when not")
    func catalogRepresentationFollowsBasis() throws {
        let module = dualFigureModule()
        // What matters is the rows the renderer is handed, so it is stubbed.
        let capture = """
        const data = { modules: { Alpha: %MODULE% } };
        const moduleMatchesInsightsFilters = () => true;
        let captured = null;
        const renderHorizontalBarChart = (id, rows) => {
            if (id === 'topResourcesChart') captured = rows;
        };
        """

        func rows(basis: String) throws -> [[String: Any]] {
            let json = try runInPage(
                module: module, basis: basis,
                lifting: ["renderTopOffenders", "catalogLabel", "catalogAssetCount"],
                preamble: capture,
                expression: "(() => { renderTopOffenders(); return captured; })()"
            )
            return try #require(
                try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
            )
        }

        let compressed = try rows(basis: "downloadSize")
        let uncompressed = try rows(basis: "installSize")

        // One row per catalog, named as a container rather than after a file.
        let catalogs = compressed.filter { $0["catalog"] as? Bool == true }
        #expect(catalogs.count == 1)
        #expect(catalogs.first?["name"] as? String == "Alpha catalog")
        #expect((catalogs.first?["path"] as? String)?.hasSuffix("Assets.car") == true)
        #expect(catalogs.first?["assets"] as? Int == module.assetCatalogFiles.count)
        #expect(!compressed.contains { ($0["name"] as? String) == "logo.png" })

        #expect(uncompressed.contains { ($0["name"] as? String) == "logo.png" })
        #expect(!uncompressed.contains { $0["catalog"] as? Bool == true })
    }

    /// The residual is measured against a compressed total, not the uncompressed install
    /// size, which would make it absorb the app's whole compression delta.
    @Test("the breakdown residual is measured in the categories' own unit, with no image double count")
    func breakdownResidualAndCategoriesAreCorrect() throws {
        let module = dualFigureModule()
        let capture = """
        const data = { modules: { Alpha: %MODULE% } };
        const moduleMatchesInsightsFilters = () => true;
        const d3 = { scaleOrdinal: () => ({ domain: () => ({ range: () => {} }) }) };
        let captured = null;
        const renderDonutChart = (id, rows) => { if (id === 'resourceSizeChart') captured = rows; };
        const renderResourceLegend = () => {};
        """

        let output = try runInPage(
            module: module, basis: "downloadSize",
            lifting: ["renderResourceBreakdown"], preamble: capture,
            expression: "(() => { renderResourceBreakdown(); return captured; })()"
        )
        let categories = try #require(
            try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]]
        )

        let types = categories.compactMap { $0["type"] as? String }
        let sizes: [Int64] = categories.compactMap { $0["size"] as? Int64 }
        #expect(sizes.count == categories.count, "every category must carry a size")
        let total = sizes.reduce(0, +)

        // "Other" is the .car alone: the whole compressed module is binary + plist +
        // png + .car, and `resources` records everything but the catalog.
        let expected = Int64(40_000 + 4 + 2_000 + 60_010)
        #expect(total == expected)
        #expect(total < module.installSize)

        #expect(!types.contains("Images"))
        #expect(types.contains("png"))
        #expect(types.contains("plist"))
    }

    @Test("a statically linked module is kept out of the breakdown's total")
    func staticModuleExcludedFromBreakdownTotal() throws {
        let module = dualFigureModule()
        module.staticallyLinked = true
        module.binarySize = 500_000
        module.proguard = 500_000

        let capture = """
        const data = { modules: { Alpha: %MODULE% } };
        const moduleMatchesInsightsFilters = () => true;
        const d3 = { scaleOrdinal: () => ({ domain: () => ({ range: () => {} }) }) };
        let captured = null;
        const renderDonutChart = (id, rows) => { if (id === 'resourceSizeChart') captured = rows; };
        const renderResourceLegend = () => {};
        """

        let output = try runInPage(
            module: module, basis: "downloadSize",
            lifting: ["renderResourceBreakdown"], preamble: capture,
            expression: "(() => { renderResourceBreakdown(); return captured; })()"
        )
        let categories = try #require(
            try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]]
        )
        let sizes: [Int64] = categories.compactMap { $0["size"] as? Int64 }
        let total = sizes.reduce(0, +)

        #expect(total < Int64(60_010))
    }

    /// Source files are compiled into the binary and never exist in the IPA, and a
    /// transfer is over the compressed IPA while an install occupies the uncompressed
    /// one, so these sections have only one honest figure to show.
    @Test("sections that do not follow the control are labelled with their unit")
    func fixedUnitSectionsAreLabelled() throws {
        let html = try html(for: #"{"modules":{}}"#)

        #expect(html.contains("Size: Install (uncompressed)"))
        #expect(html.contains("Size: Download (compressed)"))
        #expect(html.contains("By Size (Compressed)"))
        #expect(!html.contains("By Size (Install Size)"))
        #expect(html.contains("Largest Source Files <span"))
        #expect(html.contains("Uncompressed, of "))

        let script = try #require(Self.appScript(in: html))
        #expect(html.contains("id=\"insightsSizeSelect\""))
        #expect(script.contains("getElementById('insightsSizeSelect')"))
        #expect(script.contains("setInsightsSizeBasis"))
    }

    @Test("re-rendering clears the tooltips and the user impact container")
    func reRenderIsIdempotent() throws {
        let script = try #require(Self.appScript(in: try html(for: #"{"modules":{}}"#)))
        let body = try #require(Self.functionBody(named: "renderInsights", in: script))

        #expect(body.contains("selectAll('.d3-tooltip').remove()"))
        #expect(body.contains("userImpactSection"))
    }

    static func appScript(in html: String) -> String? {
        let blocks = html.components(separatedBy: "<script>").dropFirst()
            .map { $0.components(separatedBy: "</script>")[0] }
        return blocks.count >= 2 ? blocks[blocks.count - 1] : nil
    }

    /// Brace-matched: the template contains regex literals and division, so counting
    /// delimiters by hand is not reliable.
    static func functionBody(named name: String, in script: String) -> String? {
        guard let start = script.range(of: "function \(name)(") else { return nil }
        guard let open = script.range(of: "{", range: start.upperBound..<script.endIndex) else {
            return nil
        }

        var depth = 0
        var index = open.lowerBound
        while index < script.endIndex {
            switch script[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(script[open.upperBound..<index])
                }
            default: break
            }
            index = script.index(after: index)
        }
        return nil
    }

    /// Signature included: rebuilding one from a body alone means inventing the
    /// parameter list, which silently passes `undefined` where a module is expected.
    static func declaration(named name: String, in script: String) throws -> String {
        let signature = try #require(
            script.range(of: "function \(name)("),
            "\(name) not found"
        )
        let body = try #require(functionBody(named: name, in: script), "\(name) has no body")
        let head = script[signature.lowerBound..<script.range(of: "{", range: signature.upperBound..<script.endIndex)!.lowerBound]
        return "\(head){\(body)}"
    }

    /// The helpers are lifted from `script` rather than retyped, so the assertion
    /// exercises the shipped definitions instead of copies that could drift.
    static func evaluateString(
        _ body: String,
        argument: String,
        script: String
    ) throws -> String {
        let helpers = try [
            "formatBytes", "calculateModuleDownload", "getFileTypeInfo",
            "renderResourceRow", "compiledCatalogNote",
        ]
        .map { name -> String in
            try declaration(named: name, in: script)
        }
        .joined(separator: "\n")

        // A pass-through: these tests assert on the markup, not on how the browser
        // escapes it, which the payload tests above cover.
        let escapeStub = """
        const escapeHtml = (text) => text;
        """

        let source = """
        \(helpers)
        \(escapeStub)
        console.log((function(module) {\(body)})(\(argument)));
        """
        // console.log appends a newline; the value under test is the string itself.
        return try run(source).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The catalog is not listed beside the renditions it unpacks into; directory
    /// entries, which the archive lists at 0 B, are not files either.
    @Test("the module panel lists catalog contents, not the catalog")
    func panelListsContentsNotCatalog() throws {
        let module = ModuleSize(name: "C24ProfisCraftsmen")
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/Assets.car", size: 60010)
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/Info.plist", size: 4)
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/", size: 0)
        module.assetCatalogFiles["icon.png"] = 1608

        let rendered = try render(module)

        #expect(!rendered.contains("Assets.car"))
        #expect(!rendered.contains("Craftsmen.bundle/</span>"))
        #expect(rendered.contains("icon.png"))
        #expect(rendered.contains("Info.plist"))
    }

    @Test("a module holding only a catalog is not left blank")
    func catalogOnlyModuleRenders() throws {
        let module = ModuleSize(name: "Bundle")
        module.addToTop(file: "Payload/App.app/Bundle.bundle/Assets.car", size: 60010)
        module.assetCatalogFiles["logo@2x.png"] = 2400

        let rendered = try render(module)

        #expect(rendered.contains("logo@2x.png"))
        #expect(!rendered.contains("Assets.car"))
    }

    /// A marker would have to live inside the file name, which is what the type badge
    /// is parsed from: "bus.svg (in catalog)" matched no file type.
    @Test("catalog assets keep their file type instead of becoming unknown files")
    func catalogAssetsKeepTheirType() throws {
        let module = ModuleSize(name: "ProfisBus")
        module.addToTop(file: "Payload/App.app/ProfisBus.bundle/Assets.car", size: 60010)
        module.assetCatalogFiles["bus.svg"] = 4096
        module.assetCatalogFiles["seat.strop"] = 24576
        module.assetCatalogFiles["AccentColor"] = 512

        let rendered = try render(module)

        // Provenance comes from the section, so the name is left alone.
        #expect(!rendered.contains("(in catalog)"))
        #expect(!rendered.contains("SVG (IN CATALOG)"))

        // svg is an image and strop is not, and both are now recognised as such.
        #expect(rendered.contains(">SVG</span>"))
        #expect(rendered.contains(">STROP</span>"))
        #expect(rendered.contains("file-type-image"))

        #expect(rendered.contains(">ASSET</span>"))
        #expect(!rendered.contains(">ACCENTCOLOR</span>"))
    }

    /// `top` holds files in the bundle and `assetCatalogFiles` renditions unpacked from a
    /// catalog, so one list needed a marker to tell them apart.
    @Test("resources and catalog contents are separate sections")
    func resourcesAndCatalogAreSeparateSections() throws {
        let module = ModuleSize(name: "ProfisBus")
        module.addToTop(file: "Payload/App.app/ProfisBus.bundle/Assets.car", size: 60010)
        module.addToTop(file: "Payload/App.app/ProfisBus.bundle/Info.plist", size: 4)
        module.assetCatalogFiles["bus.svg"] = 4096

        let rendered = try render(module)

        #expect(rendered.contains(">Resources <"))
        #expect(rendered.contains("Asset Catalog"))

        #expect(rendered.contains("58.6 KB compiled"))

        // A module with no catalog renders one section, not an empty one.
        let plain = ModuleSize(name: "Plain")
        plain.addToTop(file: "Payload/App.app/Plain.framework/Plain", size: 900)
        let plainRendered = try render(plain)
        #expect(plainRendered.contains(">Resources <"))
        #expect(!plainRendered.contains("Asset Catalog"))
    }

    @Test("the resource breakdown and the resource list are labelled apart")
    func breakdownAndListAreLabelledApart() throws {
        let html = try html(for: #"{"modules":{}}"#)

        #expect(html.contains("Resource Types"))
        #expect(html.contains(">Resources <span class=\"count-badge\">"))
    }

    private func render(_ module: ModuleSize) throws -> String {
        let html = try html(for: #"{"modules":{}}"#)
        let script = try #require(Self.appScript(in: html))
        let body = try #require(
            Self.functionBody(named: "renderModuleResources", in: script),
            "renderModuleResources not found"
        )
        let json = try #require(String(data: try JSONEncoder().encode(module), encoding: .utf8))
        return try Self.evaluateString(body, argument: json, script: script)
    }

    /// Wrapped rather than spliced into a declaration, so its own `module` parameter
    /// shadows nothing.
    static func evaluate(_ body: String, argument: String) throws -> Int {
        let source = "console.log((function(module) {\(body)})(\(argument)));"
        let printed = try run(source)
        guard let value = Int(printed.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CalibrationError.evaluationFailed(
                "expected a number, got \(printed)\nsource: \(source)"
            )
        }
        return value
    }

    /// Returns whatever `source` wrote to stdout.
    static func run(_ source: String) throws -> String {
        let script = try #require(javaScriptEngine(), "node not available")
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("caliper-eval-\(UUID().uuidString).js")
        try source.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        process.executableURL = script
        process.arguments = [file.path]
        let output = Pipe()
        process.standardOutput = output
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CalibrationError.evaluationFailed(
                String(decoding: data, as: UTF8.self)
                    + String(decoding: errorData, as: UTF8.self)
                    + "\nsource: \(source)"
            )
        }
        return String(decoding: data, as: UTF8.self)
    }

    enum CalibrationError: Error {
        case evaluationFailed(String)
    }
}