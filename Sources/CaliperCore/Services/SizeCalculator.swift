import Foundation

public struct SizeCalculator {
    public func calculateTotalSize(
        ipaPath: String,
        unzippedPath: String
    ) throws -> (packageSize: Int64, installSize: Int64) {
        let ipaURL = URL(fileURLWithPath: ipaPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: ipaURL.path)
        let packageSize = attributes[.size] as? Int64 ?? 0

        let installSize = try directorySize(at: unzippedPath)
        
        return (packageSize, installSize)
    }
    
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
    
    public func updateBinarySizes(
        in appSizeReport: inout [String: ModuleSize],
        moduleSizes: [String: Int64]
    ) {
        for (moduleName, size) in moduleSizes {
            if moduleName == "other" {
                continue
            }

            if let existingModule = appSizeReport[moduleName] {
                // A bundle-only module has no binary yet, so its install size has
                // never seen these bytes.
                if existingModule.binarySize == 0 {
                    existingModule.proguard += size
                }
                existingModule.binarySize = size
            } else {
                let newModule = ModuleSize(name: moduleName)
                newModule.binarySize = size
                newModule.proguard = size
                newModule.staticallyLinked = true
                appSizeReport[moduleName] = newModule
            }
        }
    }
    
    public func updateBinarySizesDetailed(
        in appSizeReport: inout [String: ModuleSize],
        linkMapDetails: LinkMapDetails
    ) {
        updateBinarySizes(
            in: &appSizeReport,
            moduleSizes: linkMapDetails.moduleSizes
        )

        for (moduleName, files) in linkMapDetails.fileDetails {
            if moduleName == "other" {
                continue
            }

            if let moduleSize = appSizeReport[moduleName] {
                for (fileName, size) in files {
                    moduleSize.addFileSize(fileName: fileName, size: size)
                }

                moduleSize.finalizeFiles()
            }
        }
    }
    public init() {}
}
