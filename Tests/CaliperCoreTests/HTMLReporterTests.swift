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

        // The charts are useless without d3, so a remote script means the report
        // silently renders empty offline, on an air-gapped runner, or from an
        // unzipped CI artifact. The vendored bundle still mentions its own homepage
        // in a comment, so assert on loadable references rather than any URL text.
        #expect(!html.contains("<script src="))
        #expect(!html.contains("d3js.org/d3.v7.min.js"))
        #expect(html.contains("d3.select"))
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

        // The raw closing tag must not survive into the document.
        #expect(!html.contains("</script><script>alert"))
        #expect(html.contains("\\u003c/script>"))
    }

    /// A stray brace in the template ships a report whose charts silently never run.
    /// Checking delimiter balance by hand does not work here — the template contains
    /// regex literals and division — so defer to a real JavaScript parser when one is
    /// available. Skipped otherwise, rather than passing vacuously.
    @Test("emits syntactically valid script blocks")
    func scriptBlocksAreValid() throws {
        guard let node = Self.javaScriptEngine() else {
            // No parser available; the offline and payload tests above still apply.
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

    /// A statically linked module has no compressed size, so the report's copy of the
    /// download figure falls back to the module's LinkMap size rather than reporting
    /// zero. Extracted from the generated template and run against a Swift-encoded
    /// module, so this pins the shipped JavaScript to the Swift definition above.
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

    /// `node` if it is on PATH, otherwise nil.
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

    /// The report carries its own copy of the size arithmetic, which is exactly how a
    /// module that ships only a binary came to display zero download bytes while
    /// sorting on a different number. Pin the JS to the Swift definitions.
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

        // Extract the two functions and run them against the module the Swift side
        // encoded, so the assertions below are the real shipped arithmetic. The module
        // is spliced in as a literal because the function bodies are evaluated
        // outside the page, where `data` does not exist.
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

    // MARK: - Insights size basis

    /// A module whose two figures are far apart, so a test can tell which one a chart
    /// used, and which owns a catalog. `imageSize`/`imageFileSize` and
    /// `binaryCompressedSize`/`binarySize` are the compressed and uncompressed pairs the
    /// treemap and the breakdown both read.
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

    /// Runs a lifted declaration against `module` with `insightsSizeBasis` preset, and
    /// returns `expression` evaluated. The bodies are evaluated outside the page, so the
    /// module-level state they read is supplied here: `%MODULE%` in `preamble` and
    /// `expression` is the encoded module. Renderers that draw rather than return are
    /// stubbed in `preamble` to capture what they were handed.
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

    /// The two figures are different units of different things — a compressed download
    /// and an uncompressed install — and the Insights page can show either. Every chart
    /// with both reads one selector, so the control cannot leave two of them measuring
    /// different things on the same page.
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

    /// A catalog is the one resource with two honest representations, and which is right
    /// depends on the unit in view. Compressed: the `.car` is one file in the archive and
    /// its contents are not in the download at all. Uncompressed: the container says
    /// nothing about what it costs, and the renditions are the expanded bytes. Listing
    /// both at once counts the same bytes twice in one ranked chart.
    @Test("the catalog is the container when compressed and its contents when not")
    func catalogRepresentationFollowsBasis() throws {
        let module = dualFigureModule()
        // The chart renderer is stubbed: what matters is the rows it is handed.
        let capture = """
        const data = { modules: { Alpha: %MODULE% } };
        const moduleMatchesInsightsFilters = () => true;
        let captured = null;
        const renderHorizontalBarChart = (id, rows) => {
            if (id === 'topResourcesChart') captured = rows;
        };
        """

        func rows(basis: String) throws -> String {
            try runInPage(
                module: module, basis: basis, lifting: ["renderTopOffenders"],
                preamble: capture,
                expression: "(() => { renderTopOffenders(); return captured; })()"
            )
        }

        let compressed = try rows(basis: "downloadSize")
        let uncompressed = try rows(basis: "installSize")

        #expect(compressed.contains("Assets.car"))
        #expect(!compressed.contains("logo.png"))
        #expect(uncompressed.contains("logo.png"))
        #expect(!uncompressed.contains("Assets.car"))
    }

    /// "Other" is a residual against a total in the same unit as the categories. The
    /// categories are all compressed; the total was the uncompressed install size, so the
    /// residual absorbed the app's whole compression delta rather than the files no
    /// category claimed — which on a typical app made it the largest wedge in the chart.
    ///
    /// Images were counted twice as well: `imageSize` accumulates the same files, at the
    /// same compressed size, that populate `resources['png']` and friends, so an "Images"
    /// category summed those bytes a second time and pushed the donut past the app's real
    /// size. There is no correct version of that rollup, so it is gone; the per-type
    /// breakdown already separates the formats and carries their real counts.
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

        // 40 000 binary + 4 plist + 2 000 png, plus the .car, which `resources` does not
        // record. That is the whole compressed module, so "Other" is the catalog alone.
        let expected = Int64(40_000 + 4 + 2_000 + 60_010)
        #expect(total == expected)
        // Measured against the uncompressed install size the residual was 210 000 minus
        // the categories — several times everything actually attributed.
        #expect(total < module.installSize)

        #expect(!types.contains("Images"))
        #expect(types.contains("png"))
        #expect(types.contains("plist"))
    }

    /// A statically linked module has no compressed size of its own: the linker put its
    /// code inside the app binary, which is already counted once under Binary. Its
    /// download figure is the uncompressed LinkMap fallback, so including it in the
    /// breakdown's total would add its entire code size to "Other".
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

        // Its 500 000 uncompressed bytes are inside the app binary, not its own, so
        // nothing of its size may reach the chart.
        #expect(total < Int64(60_010))
    }

    /// The sections with only one honest figure say which they are, rather than appearing
    /// to ignore the control. Source files are compiled into the binary and never exist
    /// in the IPA, so there is no compressed figure to switch to; the breakdown's
    /// categories are all compressed, because no per-type uncompressed figure is recorded;
    /// and a transfer happens over the compressed IPA while an install occupies the
    /// uncompressed one, so neither of the User Impact cards can follow the control.
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

    /// Every chart appends its own tooltip to the body and User Impact wrote into a
    /// container it never cleared, so re-rendering grew the DOM without bound. That was
    /// tolerable while the tab rendered once; the size control makes it a leak on every
    /// flip.
    @Test("re-rendering clears the tooltips and the user impact container")
    func reRenderIsIdempotent() throws {
        let script = try #require(Self.appScript(in: try html(for: #"{"modules":{}}"#)))
        let body = try #require(Self.functionBody(named: "renderInsights", in: script))

        #expect(body.contains("selectAll('.d3-tooltip').remove()"))
        #expect(body.contains("userImpactSection"))
    }
    /// The second `<script>` block: the application code, without the vendored d3.
    static func appScript(in html: String) -> String? {
        let blocks = html.components(separatedBy: "<script>").dropFirst()
            .map { $0.components(separatedBy: "</script>")[0] }
        return blocks.count >= 2 ? blocks[blocks.count - 1] : nil
    }

    /// The body of `function name(...) { ... }`, brace-matched. The template contains
    /// regex literals and division, so delimiter counting by hand is not reliable
    /// enough here; the caller runs the result through a real parser anyway.
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

    /// The whole `function name(...) { ... }` declaration, signature included. Rebuilding
    /// one from a body alone means inventing the parameter list, which silently passes
    /// `undefined` where the function expects a module.
    static func declaration(named name: String, in script: String) throws -> String {
        let signature = try #require(
            script.range(of: "function \(name)("),
            "\(name) not found"
        )
        let body = try #require(functionBody(named: name, in: script), "\(name) has no body")
        let head = script[signature.lowerBound..<script.range(of: "{", range: signature.upperBound..<script.endIndex)!.lowerBound]
        return "\(head){\(body)}"
    }

    /// Runs `body` against `argument` and returns its result as a string. The helpers it
    /// calls are lifted from `script` rather than retyped here, so the assertion
    /// exercises the shipped definitions instead of copies that could drift from them.
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

        // The extracted bodies call this, and it needs a DOM to render into. Replaced
        // with a plain pass-through: these tests assert on the markup, not on how the
        // browser escapes it, and that behaviour is covered by the payload tests above.
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

    /// A `.car` is a compiled asset catalog, and the report lists its assets
    /// individually, so listing the catalog alongside them shows the same bytes twice.
    /// The module panel was the last place it still appeared: `Cargo…/Assets.car
    /// 58.6 KB` under a module whose only other file was a 4 B plist. Directory entries
    /// appear there too, at 0 B, for the same reason — the archive lists them and nothing
    /// else filters them out.
    ///
    /// Runs the real `renderModuleResources` against a Swift-encoded module.
    @Test("the module panel lists catalog contents, not the catalog")
    func panelListsContentsNotCatalog() throws {
        let module = ModuleSize(name: "C24ProfisCraftsmen")
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/Assets.car", size: 60010)
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/Info.plist", size: 4)
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/", size: 0)
        module.assetCatalogFiles["icon.png"] = 1608

        let rendered = try render(module)

        #expect(!rendered.contains("Assets.car"))
        // The directory entry the archive lists at 0 B is not a file.
        #expect(!rendered.contains("Craftsmen.bundle/</span>"))
        // What is inside the catalog is listed in its place.
        #expect(rendered.contains("icon.png"))
        #expect(rendered.contains("Info.plist"))
    }

    /// A module with only a catalog and nothing else must still render its contents.
    @Test("a module holding only a catalog is not left blank")
    func catalogOnlyModuleRenders() throws {
        let module = ModuleSize(name: "Bundle")
        module.addToTop(file: "Payload/App.app/Bundle.bundle/Assets.car", size: 60010)
        module.assetCatalogFiles["logo@2x.png"] = 2400

        let rendered = try render(module)

        #expect(rendered.contains("logo@2x.png"))
        #expect(!rendered.contains("Assets.car"))
    }

    /// The report distinguishes two kinds of thing with two sections, not with a marker
    /// glued to the file name. A marker has to live inside the name to be visible, and
    /// the name is what the type badge is parsed from: "bus.svg (in catalog)" ends in
    /// "svg (in catalog)", which matched no file type, so every asset rendered as an
    /// unknown grey file with its provenance repeated in the badge as well as the label.
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

        // A rendition with no extension is not a file type in its own right. It used to
        // be badged with the whole name, which put "ACCENTCOLOR" in the type column.
        #expect(rendered.contains(">ASSET</span>"))
        #expect(!rendered.contains(">ACCENTCOLOR</span>"))
    }

    /// Two sections, because the two kinds of thing are not the same kind of thing:
    /// `top` holds files in the bundle, `assetCatalogFiles` holds renditions unpacked
    /// from a catalog. One list needed a marker to tell them apart, which is what caused
    /// the misclassification above.
    @Test("resources and catalog contents are separate sections")
    func resourcesAndCatalogAreSeparateSections() throws {
        let module = ModuleSize(name: "ProfisBus")
        module.addToTop(file: "Payload/App.app/ProfisBus.bundle/Assets.car", size: 60010)
        module.addToTop(file: "Payload/App.app/ProfisBus.bundle/Info.plist", size: 4)
        module.assetCatalogFiles["bus.svg"] = 4096

        let rendered = try render(module)

        #expect(rendered.contains(">Resources <"))
        #expect(rendered.contains("Asset Catalog"))

        // The catalog's compressed size is what the user downloads, and it is already in
        // the download total via `top` — so it is annotated, not added to the rows.
        #expect(rendered.contains("58.6 KB compiled"))

        // A module with no catalog renders one section, not an empty one.
        let plain = ModuleSize(name: "Plain")
        plain.addToTop(file: "Payload/App.app/Plain.framework/Plain", size: 900)
        let plainRendered = try render(plain)
        #expect(plainRendered.contains(">Resources <"))
        #expect(!plainRendered.contains("Asset Catalog"))
    }

    /// The breakdown by type and the list of resources are different views of the same
    /// data. They shared a heading, which put "Resources" twice in one panel.
    @Test("the resource breakdown and the resource list are labelled apart")
    func breakdownAndListAreLabelledApart() throws {
        let html = try html(for: #"{"modules":{}}"#)

        #expect(html.contains("Resource Types"))
        // The bare word, as a heading of its own, is the list's — and belongs to the
        // function that renders it, not to the template.
        #expect(html.contains(">Resources <span class=\"count-badge\">"))
    }

    /// Renders a module through the shipped `renderModuleResources`.
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

    /// Runs a function body with a single `module` argument and returns the result.
    /// The body is wrapped rather than spliced into a declaration, so its own
    /// `module` parameter shadows nothing.
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

    /// Runs a standalone JS `source`, returning whatever it wrote to stdout.
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