import Foundation

typealias SwiftDemangle = @convention(c) (
    _ mangledName: UnsafePointer<CChar>?,
    _ mangledNameLength: Int,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<Int>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?

public struct FileInfo {
    public let fileName: String
    public let moduleName: String
}

public struct LinkMapDetails {
    public var moduleSizes: [String: Int64] = ["other": 0]
    public var fileDetails: [String: [String: Int64]] = [:] // [moduleName: [fileName: size]]
}

public struct LinkMapParser {
    private static let demangleFunction: SwiftDemangle? = {
        guard let handle = dlopen(nil, RTLD_NOW) else {
            return nil
        }
        guard let symbol = dlsym(handle, "swift_demangle") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SwiftDemangle.self)
    }()
    
    public func parse(linkMapPath: String) throws -> [String: Int64] {
        let details = try parseDetailed(linkMapPath: linkMapPath)
        return details.moduleSizes
    }

    public func parseDetailed(linkMapPath: String) throws -> LinkMapDetails {
        fputs("  [LinkMap] Reading file...\n", stderr)
        var details = LinkMapDetails()
        var fileIndices: [String: FileInfo] = [:]
        
        let content = try readLinkMapFile(at: linkMapPath)
        let lines = content.components(separatedBy: .newlines)
        
        fputs("  [LinkMap] Parsing \(lines.count) lines...\n", stderr)
        var currentSection = ""
        var filesCount = 0
        var symbolsCount = 0
        var lastProgressUpdate = 0
        
        for (index, line) in lines.enumerated() {
            let progress = (index * 100) / lines.count
            if progress >= lastProgressUpdate + 10 && progress > 0 {
                lastProgressUpdate = progress
                fputs("  [LinkMap] Progress: \(progress)% (\(index)/\(lines.count) lines, \(filesCount) files, \(symbolsCount) symbols)\n", stderr)
            }
            
            if line.hasPrefix("#") {
                let newSection = identifySection(from: line)
                if newSection == "dead" {
                    currentSection = "dead"
                    fputs("  [LinkMap] Entering section: dead stripped (ignored)\n", stderr)
                } else if !newSection.isEmpty {
                    currentSection = newSection
                    fputs("  [LinkMap] Entering section: \(newSection)\n", stderr)
                }
                continue
            }
            
            switch currentSection {
            case "files":
                parseFileLine(line: line, fileIndices: &fileIndices)
                filesCount = fileIndices.count
            case "symbols":
                parseSymbolLine(line: line, fileIndices: fileIndices, details: &details)
                symbolsCount += 1
            default:
                break
            }
        }
        
        fputs("  [LinkMap] Completed: \(filesCount) files, \(symbolsCount) symbols, \(details.moduleSizes.count) modules\n", stderr)
        return details
    }
    
    private func readLinkMapFile(at path: String) throws -> String {
        let fileURL = URL(fileURLWithPath: path)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? Int64 {
            let sizeMB = Double(fileSize) / 1024.0 / 1024.0
            fputs("  [LinkMap] File size: \(String(format: "%.2f", sizeMB)) MB\n", stderr)
            if sizeMB > 100 {
                fputs("  [LinkMap] ⚠️  Large file detected, this may take a while...\n", stderr)
            }
        }
        
        // Latin 1 decodes any byte, so it is the last resort rather than an error.
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return content
        }

        fputs("  [LinkMap] UTF-8 failed, trying ASCII...\n", stderr)
        if let content = try? String(contentsOfFile: path, encoding: .ascii) {
            return content
        }

        fputs("  [LinkMap] ASCII failed, trying ISO Latin 1...\n", stderr)
        let data = try Data(contentsOf: fileURL)
        guard let content = String(data: data, encoding: .utf8) ??
                           String(data: data, encoding: .ascii) ??
                           String(data: data, encoding: .isoLatin1) else {
            fputs("  [LinkMap] ❌ Cannot read file with any known encoding\n", stderr)
            throw CaliperError.linkMapParsingFailed("Cannot read file with any known encoding")
        }
        
        return content
    }
    
    private func identifySection(from line: String) -> String {
        let lowercased = line.lowercased()

        // A dead-stripped section switches parsing off rather than leaving the previous
        // section active: the linker removed those bytes, so counting them inflates
        // every module that defines one.
        if lowercased.contains("dead stripped") || lowercased.contains("dead-stripped") {
            return "dead"
        }

        if lowercased.contains("object files") {
            return "files"
        } else if lowercased.contains("symbols") && !lowercased.contains("dead") {
            return "symbols"
        }
        return ""
    }
    
    private func parseFileLine(line: String, fileIndices: inout [String: FileInfo]) {
        let components = line.components(separatedBy: "]")
        guard components.count > 1 else { return }
        
        let indexPart = components[0]
            .replacingOccurrences(of: "[", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        let pathPart = components[1].trimmingCharacters(in: .whitespaces)
        let pathComponents = pathPart.components(separatedBy: "/")
        
        guard let fileName = pathComponents.last?.trimmingCharacters(in: .whitespaces) else {
            return
        }
        
        let baseName = fileName
            .replacingOccurrences(of: ".o", with: "")
            .replacingOccurrences(of: ".a", with: "")

        let moduleName = findModuleName(baseName: baseName, pathComponents: pathComponents)
        fileIndices[indexPart] = FileInfo(fileName: baseName, moduleName: moduleName)
    }
    
    private func findModuleName(baseName: String, pathComponents: [String]) -> String {
        // SPM builds name the object path after the package, so that segment is the module.
        if let buildDir = pathComponents.first(where: { $0.hasSuffix(".build") }) {
            return buildDir.replacingOccurrences(of: ".build", with: "")
        }

        return baseName
    }
    
    private func parseSymbolLine(line: String, fileIndices: [String: FileInfo], details: inout LinkMapDetails) {
        let components = line.components(separatedBy: "\t")
        guard components.count > 2 else { return }
        
        let sizeComponents = components[1].components(separatedBy: "x")
        guard sizeComponents.count > 1,
              let size = Int64(sizeComponents[1], radix: 16) else {
            return
        }
        
        let indexComponents = components[2].components(separatedBy: "]")
        let indexPart = indexComponents[0]
            .replacingOccurrences(of: "[", with: "")
            .trimmingCharacters(in: .whitespaces)

        let symbolName = indexComponents.count > 1 ?
            indexComponents[1].trimmingCharacters(in: .whitespaces) : ""

        if let fileInfo = fileIndices[indexPart] {
            details.moduleSizes[fileInfo.moduleName, default: 0] += size

            let extractedFileName = extractClassNameFromSymbol(symbolName) ?? fileInfo.fileName

            if details.fileDetails[fileInfo.moduleName] == nil {
                details.fileDetails[fileInfo.moduleName] = [:]
            }

            details.fileDetails[fileInfo.moduleName]?[extractedFileName, default: 0] += size
        } else {
            details.moduleSizes["other", default: 0] += size
        }
    }
    
    private func extractClassNameFromSymbol(_ symbol: String) -> String? {
        if symbol.hasPrefix("l_get_witness_table ") {
            let afterPrefix = String(symbol.dropFirst("l_get_witness_table ".count))
            if let demangled = extractFromCompilerSymbol(afterPrefix) {
                return "WitnessTable<\(demangled)>"
            }
        }
        
        if symbol.hasPrefix("_symbolic ") {
            let afterPrefix = String(symbol.dropFirst("_symbolic ".count))
            if let demangled = extractFromCompilerSymbol(afterPrefix) {
                return "Symbolic<\(demangled)>"
            }
        }
        
        if symbol.hasPrefix("_associated conformance ") {
            let afterPrefix = String(symbol.dropFirst("_associated conformance ".count))
            if let demangled = extractFromCompilerSymbol(afterPrefix) {
                return "AssociatedConformance<\(demangled)>"
            }
        }
        
        if symbol.hasPrefix("_$s") || symbol.hasPrefix("$s") || symbol.hasPrefix("_$S") || symbol.hasPrefix("$S") {
            return demangleSwiftSymbol(symbol) ?? extractSwiftClassName(from: symbol)
        }

        // Objective-C: -[ClassName method] or +[ClassName method]
        if symbol.hasPrefix("-[") || symbol.hasPrefix("+[") {
            let withoutPrefix = String(symbol.dropFirst(2))
            if let spaceIndex = withoutPrefix.firstIndex(of: " ") {
                return String(withoutPrefix[..<spaceIndex])
            }
        }
        
        return nil
    }
    
    private func extractFromCompilerSymbol(_ symbolPart: String) -> String? {
        // Length-prefixed: 24C24ProfisNativeMessenger8PageItem
        if let firstChar = symbolPart.first, firstChar.isNumber {
            return extractLengthPrefixedName(from: symbolPart)
        }

        return nil
    }
    
    /// Module, type, subtype at most; the last one read is the type name.
    private func extractLengthPrefixedName(from symbol: String) -> String? {
        var index = symbol.startIndex
        var components: [String] = []

        for _ in 0..<3 {
            guard index < symbol.endIndex else { break }

            guard let length = extractLength(from: symbol, at: &index),
                  length > 0 && length < 100 else {
                break
            }

            let endIndex = symbol.index(index, offsetBy: length, limitedBy: symbol.endIndex) ?? symbol.endIndex
            let component = String(symbol[index..<endIndex])

            if component.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                components.append(component)
                index = endIndex
            } else {
                break
            }
        }
        
        return components.last
    }

    private func demangleSwiftSymbol(_ symbol: String) -> String? {
        guard let demangle = Self.demangleFunction else {
            return nil
        }
        
        return symbol.withCString { cString in
            var size: Int = 0
            let length = strlen(cString)
            let result = demangle(cString, length, nil, &size, 0)
            
            guard let demangledPtr = result else {
                return nil
            }
            
            defer { free(demangledPtr) }
            let demangledString = String(cString: demangledPtr)

            return extractClassNameFromDemangled(demangledString)
        }
    }
    
    /// Handles "Module.Class.method() -> ()" and "(extension in Module):name.member".
    private func extractClassNameFromDemangled(_ demangled: String) -> String? {
        let cleaned = demangled.components(separatedBy: " -> ").first ?? demangled
        let components = cleaned.components(separatedBy: ".")

        if cleaned.hasPrefix("(extension in ") {
            let afterExtension = cleaned.replacingOccurrences(of: "(extension in ", with: "")
            if let colonIndex = afterExtension.firstIndex(of: ":") {
                let remaining = String(afterExtension[afterExtension.index(after: colonIndex)...])
                let parts = remaining.components(separatedBy: ".")
                if parts.count >= 2 {
                    return parts[1].components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }

        if components.count >= 2 {
            let className = components[1].components(separatedBy: "(").first?
                .trimmingCharacters(in: .whitespaces)

            if let className = className,
               !className.isEmpty,
               !className.hasPrefix("_"),
               className.count < 100,  // Sanity check
               className.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                return className
            }
        }
        
        return nil
    }
    
    /// _$s<ModuleLen><Module><ClassLen><Class>... , used only when demangling fails.
    private func extractSwiftClassName(from symbol: String) -> String? {
        let cleanSymbol = symbol.hasPrefix("_$s") ? String(symbol.dropFirst(3)) : String(symbol.dropFirst(2))

        var index = cleanSymbol.startIndex

        if let moduleLength = extractLength(from: cleanSymbol, at: &index) {
            index = cleanSymbol.index(index, offsetBy: moduleLength, limitedBy: cleanSymbol.endIndex) ?? cleanSymbol.endIndex

            if index < cleanSymbol.endIndex,
               let classLength = extractLength(from: cleanSymbol, at: &index),
               classLength > 0,
               classLength < 200 {
                let endIndex = cleanSymbol.index(index, offsetBy: classLength, limitedBy: cleanSymbol.endIndex) ?? cleanSymbol.endIndex
                let className = String(cleanSymbol[index..<endIndex])

                if className.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    return className
                }
            }
        }
        
        return nil
    }
    
    private func extractLength(from string: String, at index: inout String.Index) -> Int? {
        var length = 0
        var digitCount = 0
        
        while index < string.endIndex && string[index].isNumber {
            if let digit = string[index].wholeNumberValue {
                length = length * 10 + digit
                digitCount += 1
            }
            index = string.index(after: index)
        }
        
        return digitCount > 0 ? length : nil
    }
    public init() {}
}
