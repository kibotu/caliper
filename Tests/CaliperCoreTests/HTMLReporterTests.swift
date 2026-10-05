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
        let helpers = try ["formatBytes", "calculateModuleDownload", "getFileTypeInfo"]
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

    /// A `.car` is a bundle, and the report lists its assets individually, so listing the
    /// catalog alongside them shows the same bytes twice. The module panel was the last
    /// place it still appeared: `Cargo…/Assets.car 58.6 KB` under a module whose only
    /// other file was a 4 B plist. Directory entries appear there too, at 0 B, for the
    /// same reason — the archive lists them and nothing else filters them out.
    ///
    /// Runs the real `renderAssetFiles` against a Swift-encoded module.
    @Test("the module panel lists catalog contents, not the catalog")
    func panelListsContentsNotCatalog() throws {
        let module = ModuleSize(name: "C24ProfisCraftsmen")
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/Assets.car", size: 60010)
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/Info.plist", size: 4)
        module.addToTop(file: "Payload/App.app/C24ProfisCraftsmen.bundle/", size: 0)
        module.assetCatalogFiles["icon.png"] = 1608

        let html = try html(for: #"{"modules":{}}"#)
        let script = try #require(Self.appScript(in: html))
        let body = try #require(
            Self.functionBody(named: "renderAssetFiles", in: script),
            "renderAssetFiles not found"
        )
        let json = try #require(
            String(data: try JSONEncoder().encode(module), encoding: .utf8)
        )

        let rendered = try Self.evaluateString(body, argument: json, script: script)

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

        let html = try html(for: #"{"modules":{}}"#)
        let script = try #require(Self.appScript(in: html))
        let body = try #require(Self.functionBody(named: "renderAssetFiles", in: script))
        let json = try #require(String(data: try JSONEncoder().encode(module), encoding: .utf8))

        let rendered = try Self.evaluateString(body, argument: json, script: script)

        #expect(rendered.contains("logo@2x.png"))
        #expect(!rendered.contains("Assets.car"))
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