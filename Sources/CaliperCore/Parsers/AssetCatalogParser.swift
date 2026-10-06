import Foundation

public struct AssetCatalogParser {
    public func parse(filePath: String, moduleSize: ModuleSize) throws {
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
        
        let timeout: TimeInterval = 10.0
        let startTime = Date()
        
        while process.isRunning && Date().timeIntervalSince(startTime) < timeout {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        pipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            fputs("    [assetutil] ⚠️  Timed out after \(Int(timeout))s\n", stderr)
            throw CaliperError.assetCatalogParsingFailed("assetutil timed out after \(Int(timeout))s")
        }
        
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
    
    private func parseAssetOutput(_ output: String, moduleSize: ModuleSize) throws {
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

            // `SizeOnDisk` is the rendition expanded, so these figures are uncompressed
            // and must not reach the compressed dictionaries that feed `downloadSize`.
            moduleSize.assetCatalogFiles[name, default: 0] += size

            let components = name.split(separator: ".")
            guard let ext = components.last else { continue }
            let fileExtension = String(ext).lowercased()
            if ["svg", "png", "pdf"].contains(fileExtension) {
                moduleSize.imageFileSize += size
            }
        }
    }
    public init() {}
}
