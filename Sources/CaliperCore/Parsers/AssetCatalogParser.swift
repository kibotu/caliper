import Foundation

/// Parser for .car asset catalog files
public struct AssetCatalogParser {
    /// Parse an asset catalog file and add the results to the module
    public func parse(filePath: String, moduleSize: ModuleSize) throws {
        // Breadcrumb: Starting .car file parsing
        let fileName = (filePath as NSString).lastPathComponent
        fputs("    [assetutil] Starting parse of \(fileName)...\n", stderr)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", "iphoneos", "assetutil", "--info", filePath]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        // Accumulate output data asynchronously to prevent buffer blocking
        // Using nonisolated(unsafe) for Swift 6 concurrency: handlers are cleaned up before data access
        nonisolated(unsafe) var outputData = Data()
        nonisolated(unsafe) var errorData = Data()
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let availableData = handle.availableData
            if !availableData.isEmpty {
                outputData.append(availableData)
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let availableData = handle.availableData
            if !availableData.isEmpty {
                errorData.append(availableData)
            }
        }
        
        do {
            try process.run()
        } catch {
            fputs("    [assetutil] ⚠️  Failed to start: \(error)\n", stderr)
            throw CaliperError.assetCatalogParsingFailed("Failed to start assetutil: \(error)")
        }
        
        // Wait with timeout
        let timeout: TimeInterval = 10.0
        let startTime = Date()
        
        while process.isRunning && Date().timeIntervalSince(startTime) < timeout {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Clean up handlers
        pipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        
        // Terminate if still running
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            fputs("    [assetutil] ⚠️  Timed out after \(Int(timeout))s\n", stderr)
            throw CaliperError.assetCatalogParsingFailed("assetutil timed out after \(Int(timeout))s")
        }
        
        // Check exit code
        guard process.terminationStatus == 0 else {
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            fputs("    [assetutil] ⚠️  Failed with exit code \(process.terminationStatus): \(errorOutput)\n", stderr)
            throw CaliperError.assetCatalogParsingFailed("assetutil failed (exit: \(process.terminationStatus)): \(errorOutput)")
        }
        
        guard let output = String(data: outputData, encoding: .utf8) else {
            fputs("    [assetutil] ⚠️  Failed to decode output\n", stderr)
            throw CaliperError.assetCatalogParsingFailed("Failed to decode assetutil output")
        }
        
        fputs("    [assetutil] Parsing output...\n", stderr)
        try parseAssetOutput(output, moduleSize: moduleSize)
        fputs("    [assetutil] ✅ Completed\n", stderr)
    }
    
    // MARK: - Private Methods
    
    private func parseAssetOutput(_ output: String, moduleSize: ModuleSize) throws {
        // Drop first line (header) and parse JSON array
        let lines = output.components(separatedBy: .newlines)
        guard lines.count > 1 else { return }
        
        let jsonString = "[" + lines.dropFirst().joined(separator: " ")
        guard let jsonData = jsonString.data(using: .utf8) else { return }
        
        let assets = try JSONDecoder().decode([AssetInfo].self, from: jsonData)
        
        for asset in assets {
            guard let name = asset.RenditionName,
                  let sizeOnDisk = asset.SizeOnDisk else {
                continue
            }
            
            let size = Int64(sizeOnDisk)
            let components = name.split(separator: ".")
            guard let ext = components.last else { continue }
            let fileExtension = String(ext).lowercased()

            // `SizeOnDisk` is the rendition's size after the catalog is expanded, so
            // these are installed-size figures. They used to be added to `imageSize`,
            // `resources` and `top`, all of which record compressed sizes — which put
            // an uncompressed number into the download total and overstated it by the
            // catalog's compression ratio. `imageFileSize` is the uncompressed field,
            // so that is the only one they belong in; the download side is carried by
            // the .car entry the IPA listing adds.
            //
            // The sum is a breakdown of the catalog's contents, not the catalog itself:
            // it omits catalog overhead and renditions whose names do not end in a
            // recognised extension, so it does not reconcile to the .car on disk.
            guard ["svg", "png", "pdf"].contains(fileExtension) else { continue }
            moduleSize.imageFileSize += size
        }
    }
    public init() {}
}
