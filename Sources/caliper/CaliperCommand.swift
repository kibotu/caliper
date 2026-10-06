import Foundation
import ArgumentParser
import CaliperCore

@main
struct Caliper: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Measure binary and bundle sizes for Swift packages in an IPA",
        version: CaliperVersion.current
    )

    @Option(name: .long, help: "Path to the IPA file")
    var ipaPath: String

    @Option(name: .long, help: "Optional path to LinkMap file for accurate binary sizes")
    var linkMapPath: String?

    @Option(name: .long, help: "Optional YAML file containing module ownership configuration")
    var ownershipFile: String?

    @Option(name: .long, help: "Optional path to Package.resolved file for Swift package version information")
    var packageResolvedPath: String?

    @Option(name: .long, help: "Optional YAML file containing package name mappings (for handling namespaced packages)")
    var packageMappingFile: String?

    @Option(
        name: .long,
        help: "Directory to write report.json and report.html into (default: current directory)"
    )
    var outputDir: String = "."

    @Option(
        name: [.customLong("max-package-size")],
        help: "Fail if the IPA size exceeds this many bytes"
    )
    var maxPackageSize: Int?

    @Option(
        name: [.customLong("max-install-size")],
        help: "Fail if the installed size exceeds this many bytes"
    )
    var maxInstallSize: Int?

    func run() throws {
        ProgressReporter.section("🔧 Initializing Caliper...")

        let (ipaService, appInfoService) = (IPAService(), AppInfoService())
        let (ipaParser, linkMapParser, packageResolvedParser) = (IPAParser(), LinkMapParser(), PackageResolvedParser())
        let (ownershipService, versionService, packageMappingService) = (OwnershipService(), VersionService(), PackageMappingService())
        let (sizeCalculator, jsonReporter, htmlReporter) = (SizeCalculator(), JSONReporter(), HTMLReporter())

        ProgressReporter.message("Verifying IPA file: \(ipaPath)")
        try ipaService.verifyIPAExists(at: ipaPath)

        // A bad --output-dir fails before any of the work, not after it.
        let outputDirectory = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let jsonOutputPath = outputDirectory.appendingPathComponent("report.json").path
        let htmlOutputPath = outputDirectory.appendingPathComponent("report.html").path

        // Beside the IPA, so a failed cleanup cannot leave a stray tree in the caller's
        // project root.
        let ipaURL = URL(fileURLWithPath: ipaPath)
        let ipaName = ipaURL.deletingPathExtension().lastPathComponent
        let unzippedPath = ipaURL.deletingLastPathComponent()
            .appendingPathComponent("\(ipaName)_unzipped").path

        if FileManager.default.fileExists(atPath: unzippedPath) {
            ProgressReporter.info("Removing existing unzipped directory: \(unzippedPath)")
            try? FileManager.default.removeItem(atPath: unzippedPath)
        }

        ProgressReporter.section("📦 Unzipping IPA to: \(unzippedPath)")
        try ipaService.unzip(ipaPath: ipaPath, destination: unzippedPath)
        ProgressReporter.success("IPA unzipped successfully")

        defer {
            ipaService.cleanup(path: unzippedPath)
        }

        ProgressReporter.section("📱 Extracting app information...")
        let appInfo = try? appInfoService.extractAppInfo(from: unzippedPath)
        appInfo?.appName.map { ProgressReporter.message("App Name: \($0)") }
        appInfo?.versionString.map { ProgressReporter.message("Version: \($0)") }
        appInfo?.bundleIdentifier.map { ProgressReporter.message("Bundle ID: \($0)") }

        let ownershipEntries = try loadOwnershipConfiguration()

        ProgressReporter.section("📋 Analyzing IPA contents...")
        let report = try ipaParser.generateReport(ipaPath: ipaPath)

        var appSizeReport = try ipaParser.buildAppSizeReport(
            report: report,
            unzippedPath: unzippedPath
        )

        if let linkMapPath {
            ProgressReporter.section("📊 Parsing LinkMap file...")
            ProgressReporter.message("LinkMap path: \(linkMapPath)")
            let linkMapDetails = try linkMapParser.parseDetailed(linkMapPath: linkMapPath)
            ProgressReporter.message("Found \(linkMapDetails.moduleSizes.count) modules in LinkMap")

            // Count total files
            let totalFiles = linkMapDetails.fileDetails.values.reduce(0) { $0 + $1.count }
            ProgressReporter.message("Found \(totalFiles) source files across all modules")

            ProgressReporter.message("Updating binary sizes...")
            sizeCalculator.updateBinarySizesDetailed(
                in: &appSizeReport,
                linkMapDetails: linkMapDetails
            )
            ProgressReporter.success("Binary sizes updated from LinkMap")
        }

        ProgressReporter.section("📏 Calculating total sizes...")
        let totalSize = try sizeCalculator.calculateTotalSize(
            ipaPath: ipaPath,
            unzippedPath: unzippedPath
        )
        ProgressReporter.message("Total IPA size: \(totalSize.packageSize) bytes")
        ProgressReporter.message("Total install size: \(totalSize.installSize) bytes")

        if let packageResolvedPath {
            ProgressReporter.section("📦 Parsing Package.resolved file...")
            ProgressReporter.message("Package.resolved path: \(packageResolvedPath)")
            let versionMapping = try packageResolvedParser.parse(path: packageResolvedPath)
            ProgressReporter.message("Found \(versionMapping.count) package versions")

            let packageNameMapping: [String: String]? = try packageMappingFile.map { mappingPath in
                ProgressReporter.section("🔗 Loading package name mappings...")
                ProgressReporter.message("Mapping file: \(mappingPath)")
                let mappings = try packageMappingService.loadMappingFile(from: mappingPath)
                return packageMappingService.buildMappingDictionary(from: mappings)
            }

            ProgressReporter.message("Assigning versions to modules...")
            versionService.assignVersions(
                to: appSizeReport,
                using: versionMapping,
                packageNameMapping: packageNameMapping
            )
            ProgressReporter.success("Package versions assigned")
        }

        if !ownershipEntries.isEmpty {
            ProgressReporter.section("👥 Assigning module ownership...")
            ProgressReporter.message("Using \(ownershipEntries.count) ownership rules")
            ownershipService.assignOwners(to: appSizeReport, using: ownershipEntries)
            ProgressReporter.success("Module ownership assigned")
        }

        ownershipService.tagAppModule(in: appSizeReport, appInfo: appInfo)

        ProgressReporter.section("Generating JSON output...")
        let jsonString = try jsonReporter.generate(
            appInfo: appInfo,
            modules: appSizeReport,
            totalSize: totalSize,
            outputPath: jsonOutputPath
        )

        ProgressReporter.section("📊 Generating HTML report...")
        do {
            try htmlReporter.generate(jsonString: jsonString, outputPath: htmlOutputPath)
            ProgressReporter.success("HTML report saved to: \(htmlOutputPath)")
        } catch {
            ProgressReporter.error("Failed to generate HTML report: \(error)")
            throw error
        }

        // Last, so the reports exist even when a run fails: a regression should still
        // leave the evidence behind it.
        try verifyThresholds(totalSize: totalSize)
    }

    private func verifyThresholds(totalSize: (packageSize: Int64, installSize: Int64)) throws {
        var failures: [String] = []

        if let limit = maxPackageSize, totalSize.packageSize > Int64(limit) {
            let over = totalSize.packageSize - Int64(limit)
            failures.append(
                "IPA size is \(over) bytes above the limit of \(limit) bytes "
                    + "(\(totalSize.packageSize) actual)."
            )
        }

        if let limit = maxInstallSize, totalSize.installSize > Int64(limit) {
            let over = totalSize.installSize - Int64(limit)
            failures.append(
                "Install size is \(over) bytes above the limit of \(limit) bytes "
                    + "(\(totalSize.installSize) actual)."
            )
        }

        guard failures.isEmpty else {
            ProgressReporter.error("Size threshold exceeded:")
            for failure in failures {
                ProgressReporter.error("  \(failure)")
            }
            throw CaliperError.sizeThresholdExceeded(failures.joined(separator: "\n"))
        }
    }

    private func loadOwnershipConfiguration() throws -> [OwnershipEntry] {
        guard let ownershipPath = ownershipFile else {
            return []
        }
        return try OwnershipService().loadOwnershipFile(from: ownershipPath)
    }
}
