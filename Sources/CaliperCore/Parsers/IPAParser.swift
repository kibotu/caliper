import Foundation

/// Parser for IPA files to extract module information
public struct IPAParser {
    private let assetCatalogParser = AssetCatalogParser()

    public init() {}

    /// Generate a report of IPA contents
    public func generateReport(ipaPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-v", ipaPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        // Accumulate output data asynchronously to prevent buffer blocking
        // Using nonisolated(unsafe) for Swift 6 concurrency: handlers are cleaned up before data access
        nonisolated(unsafe) var outputData = Data()
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let availableData = handle.availableData
            if !availableData.isEmpty {
                outputData.append(availableData)
            }
        }
        
        try process.run()
        process.waitUntilExit()
        
        // Clean up handler
        pipe.fileHandleForReading.readabilityHandler = nil
        
        let output = String(data: outputData, encoding: .utf8)
            ?? String(decoding: outputData, as: UTF8.self)
        
        return parseUnzipOutput(output)
    }
    
    /// Build a comprehensive app size report from IPA contents
    public func buildAppSizeReport(
        report: String,
        unzippedPath: String
    ) throws -> [String: ModuleSize] {
        var result: [String: ModuleSize] = [:]
        let lines = report.components(separatedBy: .newlines)

        let totalLines = lines.count
        var processedLines = 0
        var lastProgressUpdate = 0

        fputs("Analyzing \(totalLines) files from IPA...\n", stderr)

        for line in lines {
            processedLines += 1

            // Print progress every 10%
            let progress = totalLines > 0 ? (processedLines * 100) / totalLines : 100
            if progress >= lastProgressUpdate + 10 {
                lastProgressUpdate = progress
                fputs("  Progress: \(progress)% (\(processedLines)/\(totalLines) files)\n", stderr)
            }

            try processLine(
                line,
                unzippedPath: unzippedPath,
                result: &result
            )
        }
        
        // Finalize top files for each module
        for (_, moduleSize) in result {
            moduleSize.finalizeTop()
        }
        
        return result
    }
    
    // MARK: - Private Methods
    
    private func parseUnzipOutput(_ output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        var report: [String] = []
        
        // Skip header (first 3 lines) and footer (last 2 lines)
        let dataLines = lines.dropFirst(3).dropLast(2)
        
        for line in dataLines {
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            if components.count >= 8 {
                let uncompressedSize = components[0]
                let compressedSize = components[2]
                let filePath = components[7...].joined(separator: " ")
                report.append("\(uncompressedSize) \(compressedSize) \(filePath)")
            }
        }
        
        return report.joined(separator: "\n")
    }
    
    private func processLine(
        _ line: String,
        unzippedPath: String,
        result: inout [String: ModuleSize]
    ) throws {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3 else { return }
        
        guard let uncompressedSize = Int64(parts[0]),
              let compressedSize = Int64(parts[1]) else {
            return
        }
        
        let filePath = String(parts[2])
        
        // Extract module name from path
        guard let moduleName = extractModuleName(from: filePath) else {
            return
        }
        
        // Initialize module if needed
        if result[moduleName] == nil {
            result[moduleName] = ModuleSize(name: moduleName)
        }
        
        guard let moduleSize = result[moduleName] else { return }
        
        // Categorize and process file
        try categorizeFile(
            filePath: filePath,
            unzippedPath: unzippedPath,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            moduleSize: moduleSize,
            containerName: extractContainerName(from: filePath)
        )
        
        // Update total uncompressed size
        moduleSize.proguard += uncompressedSize
    }
    
    private func extractModuleName(from filePath: String) -> String? {
        // Try framework
        if let frameworkRange = filePath.range(of: ".framework") {
            let beforeFramework = filePath[..<frameworkRange.lowerBound]
            if let lastSlash = beforeFramework.lastIndex(of: "/") {
                return String(beforeFramework[beforeFramework.index(after: lastSlash)...])
            }
        }

        // Try bundle
        if let bundleRange = filePath.range(of: ".bundle") {
            let beforeBundle = filePath[..<bundleRange.lowerBound]
            if let lastSlash = beforeBundle.lastIndex(of: "/") {
                let fullBundleName = String(beforeBundle[beforeBundle.index(after: lastSlash)...])
                // Bundle names like "ProfisPartnerCore_ProfisPartnerCore"
                if let underscoreIndex = fullBundleName.firstIndex(of: "_") {
                    return String(fullBundleName[..<underscoreIndex])
                }
                return fullBundleName
            }
        }
        
        // Try main app (.app directory, but not within a framework or bundle)
        if filePath.contains(".app/") && 
           !filePath.contains(".framework/") && 
           !filePath.contains(".bundle/") {
            // Extract the .app name
            if let appRange = filePath.range(of: ".app/") {
                let beforeApp = filePath[..<appRange.lowerBound]
                if let lastSlash = beforeApp.lastIndex(of: "/") {
                    let appName = String(beforeApp[beforeApp.index(after: lastSlash)...])
                    return appName
                }
            }
        }
        
        return nil
    }
    
    private func extractContainerName(from filePath: String) -> String? {
        // Extract framework name
        if let frameworkRange = filePath.range(of: ".framework") {
            let beforeFramework = filePath[..<frameworkRange.lowerBound]
            if let lastSlash = beforeFramework.lastIndex(of: "/") {
                return String(beforeFramework[beforeFramework.index(after: lastSlash)...])
            }
        }
        
        // Extract bundle name
        if let bundleRange = filePath.range(of: ".bundle") {
            let beforeBundle = filePath[..<bundleRange.lowerBound]
            if let lastSlash = beforeBundle.lastIndex(of: "/") {
                let fullBundleName = String(beforeBundle[beforeBundle.index(after: lastSlash)...])
                if let underscoreIndex = fullBundleName.firstIndex(of: "_") {
                    return String(fullBundleName[..<underscoreIndex])
                }
                return fullBundleName
            }
        }
        
        // Extract app name (.app directory, but not within a framework or bundle)
        if filePath.contains(".app/") && 
           !filePath.contains(".framework/") && 
           !filePath.contains(".bundle/") {
            if let appRange = filePath.range(of: ".app/") {
                let beforeApp = filePath[..<appRange.lowerBound]
                if let lastSlash = beforeApp.lastIndex(of: "/") {
                    return String(beforeApp[beforeApp.index(after: lastSlash)...])
                }
            }
        }
        
        return nil
    }
    
    private func categorizeFile(
        filePath: String,
        unzippedPath: String,
        compressedSize: Int64,
        uncompressedSize: Int64,
        moduleSize: ModuleSize,
        containerName: String?
    ) throws {
        let components = filePath.split(separator: ".")
        guard let ext = components.last else { return }
        let fileExtension = String(ext).lowercased()

        // Is this file the container's own executable?
        //
        // Checked before the extension switch below, because a framework binary is
        // named after the framework and can legitimately end in an extension that
        // switch treats as a resource: `Data.framework/Data.json` is a 90 KB binary,
        // not a JSON payload. Classifying it by extension filed it as a resource, so
        // the framework's Binary Size read 0 B.
        //
        // The test is on the filename with its extension removed, not the whole path.
        // A bare `hasSuffix(containerName)` cannot match a binary that carries an
        // extension — `"Data.json".hasSuffix("Data")` is false — which is precisely the
        // case that went wrong.
        //
        // Trailing slashes are excluded because the archive lists the container's own
        // directory too, and `Data.framework/` has a stem of `Data` as well: same test,
        // 0 bytes. It is a directory, not a binary, and recording it would overwrite the
        // real figure whenever the archive happens to list it last.
        let fileName = (filePath as NSString).lastPathComponent
        let stem = (fileName as NSString).deletingPathExtension
        let isDirectory = filePath.hasSuffix("/")
        let isMainBinary = !isDirectory
            && !stem.isEmpty
            && containerName != nil
            && stem == containerName

        if isMainBinary {
            moduleSize.binarySize = compressedSize
            // `binarySize` gets overwritten with uncompressed LinkMap output later,
            // so keep the compressed figure separately for the download-size total.
            moduleSize.binaryCompressedSize = compressedSize
            // Breadcrumb: Log main binary detection
            fputs("  [Binary] Detected main binary: \(containerName ?? "unknown") (\(compressedSize) bytes)\n", stderr)
            // Don't add the main binary to top files - it's already analyzed via linkmap
            return
        }

        switch fileExtension {
        case "pdf", "gif", "jpg", "jpeg", "png":
            moduleSize.imageSize += compressedSize
            moduleSize.imageFileSize += uncompressedSize
            moduleSize.addResource(type: fileExtension, size: compressedSize)
            moduleSize.addToTop(file: filePath, size: compressedSize)
            
        case "nib":
            let resourceType = filePath.contains(".storyboardc") ? "storyboardc" : "nib"
            moduleSize.addResource(type: resourceType, size: compressedSize)
            moduleSize.addToTop(file: filePath, size: compressedSize)
            
        case "plist", "mov", "strings", "json":
            moduleSize.addResource(type: fileExtension, size: compressedSize)
            moduleSize.addToTop(file: filePath, size: compressedSize)
            
        case "car":
            // The .car is a file in the IPA, so it counts towards the download exactly
            // like any other: at its compressed size from the archive listing. Without
            // this the catalog was absent from the download total entirely, and
            // `assetutil`'s per-asset figures were standing in for it — those are
            // uncompressed, which overstated the download of compressible catalogs.
            moduleSize.addToTop(file: filePath, size: compressedSize)

            // assetutil breaks the catalog's contents down per asset. Those figures are
            // uncompressed and describe the installed size, so they are recorded as
            // image detail rather than added to the compressed dictionaries.
            let fullPath = "\(unzippedPath)/\(filePath)"
            // Breadcrumb: Log .car file processing
            fputs("  [Asset Catalog] Processing: \(filePath)\n", stderr)
            do {
                try assetCatalogParser.parse(filePath: fullPath, moduleSize: moduleSize)
            } catch {
                fputs("  [Asset Catalog] ⚠️  Failed to parse \(filePath): \(error)\n", stderr)
            }
            
        default:
            // Not the container's own executable, and no rule above claimed it, so it
            // is an ordinary bundled resource.
            moduleSize.addToTop(file: filePath, size: compressedSize)
        }
    }
}
