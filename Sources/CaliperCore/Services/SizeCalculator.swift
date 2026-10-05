import Foundation

/// Service for calculating sizes of files and directories
public struct SizeCalculator {
    /// Calculate total package and install sizes
    public func calculateTotalSize(
        ipaPath: String,
        unzippedPath: String
    ) throws -> (packageSize: Int64, installSize: Int64) {
        // Package size (compressed IPA)
        let ipaURL = URL(fileURLWithPath: ipaPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: ipaURL.path)
        let packageSize = attributes[.size] as? Int64 ?? 0
        
        // Install size (uncompressed)
        let installSize = try directorySize(at: unzippedPath)
        
        return (packageSize, installSize)
    }
    
    /// Calculate the total size of a directory recursively
    public func directorySize(at path: String) throws -> Int64 {
        var totalSize: Int64 = 0
        
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            for case let file as String in enumerator {
                let filePath = (path as NSString).appendingPathComponent(file)
                let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                totalSize += attributes[.size] as? Int64 ?? 0
            }
        }
        
        return totalSize
    }
    
    /// Update binary sizes from LinkMap data
    public func updateBinarySizes(
        in appSizeReport: inout [String: ModuleSize],
        moduleSizes: [String: Int64]
    ) {
        for (moduleName, size) in moduleSizes {
            // Skip synthetic "other" module
            if moduleName == "other" {
                continue
            }

            if let existingModule = appSizeReport[moduleName] {
                // If the old binarySize was 0, it means no binary was found during IPA parsing
                // (e.g., statically linked modules with only resource bundles).
                // In this case, we need to ADD the binary size to proguard.
                if existingModule.binarySize == 0 {
                    existingModule.proguard += size
                }
                // Update binary size with accurate LinkMap data
                existingModule.binarySize = size
            } else {
                // Create new module from LinkMap (for statically linked modules without bundles)
                let newModule = ModuleSize(name: moduleName)
                newModule.binarySize = size
                newModule.proguard = size
                // Reaching this branch means the IPA parser never produced this module,
                // so it has no container of its own — the linker put its code inside the
                // app binary. Recorded so the report can say so instead of showing 0 B.
                newModule.staticallyLinked = true
                appSizeReport[moduleName] = newModule
            }
        }
    }
    
    /// Update binary sizes with detailed file information from LinkMap
    public func updateBinarySizesDetailed(
        in appSizeReport: inout [String: ModuleSize],
        linkMapDetails: LinkMapDetails
    ) {
        // First update basic binary sizes
        updateBinarySizes(
            in: &appSizeReport,
            moduleSizes: linkMapDetails.moduleSizes
        )

        // Then add file-level details
        for (moduleName, files) in linkMapDetails.fileDetails {
            // Skip synthetic "other" module
            if moduleName == "other" {
                continue
            }

            if let moduleSize = appSizeReport[moduleName] {
                // Add file sizes to the module
                for (fileName, size) in files {
                    moduleSize.addFileSize(fileName: fileName, size: size)
                }

                // Finalize to sort and clean up
                moduleSize.finalizeFiles()
            }
        }
    }
    public init() {}
}
