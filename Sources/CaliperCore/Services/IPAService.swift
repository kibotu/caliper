import Foundation

public struct IPAService {
    public func verifyIPAExists(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CaliperError.invalidIPA
        }
    }
    
    public func unzip(ipaPath: String, destination: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", ipaPath, "-d", destination]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            fputs("❌ Failed to unzip IPA: \(errorOutput)\n", stderr)
            throw CaliperError.unzipFailed
        }
    }
    
    public func cleanup(path: String) {
        fputs("\n🧹 Cleaning up temporary directory: \(path)\n", stderr)
        try? FileManager.default.removeItem(atPath: path)
    }
    public init() {}
}
