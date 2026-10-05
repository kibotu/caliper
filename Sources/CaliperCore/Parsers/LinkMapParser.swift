import Foundation

/// Function signature for swift_demangle
typealias SwiftDemangle = @convention(c) (
    _ mangledName: UnsafePointer<CChar>?,
    _ mangledNameLength: Int,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<Int>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?

/// Structure to hold file information from LinkMap
public struct FileInfo {
    public let fileName: String
    public let moduleName: String
}

/// Structure to hold detailed parsing results
public struct LinkMapDetails {
    public var moduleSizes: [String: Int64] = ["other": 0]
    public var fileDetails: [String: [String: Int64]] = [:] // [moduleName: [fileName: size]]
}

/// Parser for LinkMap files to extract module sizes
public struct LinkMapParser {
    /// Lazy-loaded swift_demangle function
    private static let demangleFunction: SwiftDemangle? = {
        guard let handle = dlopen(nil, RTLD_NOW) else {
            return nil
        }
        guard let symbol = dlsym(handle, "swift_demangle") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SwiftDemangle.self)
    }()
    
    /// Parse a LinkMap file and return module sizes
    public func parse(linkMapPath: String) throws -> [String: Int64] {
        let details = try parseDetailed(linkMapPath: linkMapPath)
        return details.moduleSizes
    }
    
    /// Parse a LinkMap file and return detailed module and file sizes
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
            // Progress breadcrumb every 10%
            let progress = (index * 100) / lines.count
            if progress >= lastProgressUpdate + 10 && progress > 0 {
                lastProgressUpdate = progress
                fputs("  [LinkMap] Progress: \(progress)% (\(index)/\(lines.count) lines, \(filesCount) files, \(symbolsCount) symbols)\n", stderr)
            }
            
            if line.hasPrefix("#") {
                let newSection = identifySection(from: line)
                if newSection == "dead" {
                    // Stop counting until another section header appears.
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
    
    // MARK: - Private Methods
    
    private func readLinkMapFile(at path: String) throws -> String {
        // Breadcrumb: Check file size
        let fileURL = URL(fileURLWithPath: path)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? Int64 {
            let sizeMB = Double(fileSize) / 1024.0 / 1024.0
            fputs("  [LinkMap] File size: \(String(format: "%.2f", sizeMB)) MB\n", stderr)
            if sizeMB > 100 {
                fputs("  [LinkMap] ⚠️  Large file detected, this may take a while...\n", stderr)
            }
        }
        
        // Try reading with UTF-8, fallback to ASCII, then ISO Latin 1
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return content
        }
        
        fputs("  [LinkMap] UTF-8 failed, trying ASCII...\n", stderr)
        if let content = try? String(contentsOfFile: path, encoding: .ascii) {
            return content
        }
        
        fputs("  [LinkMap] ASCII failed, trying ISO Latin 1...\n", stderr)
        // Last resort: read as data and convert
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

        // A dead-stripped section must switch parsing off, not leave the previous
        // section active. Its bytes were removed by the linker, so counting them
        // inflates every module that defines one.
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
        
        // Remove file extension to get base name
        let baseName = fileName
            .replacingOccurrences(of: ".o", with: "")
            .replacingOccurrences(of: ".a", with: "")
        
        // Find module name
        let moduleName = findModuleName(baseName: baseName, pathComponents: pathComponents)
        
        // Store both file name and module name
        fileIndices[indexPart] = FileInfo(fileName: baseName, moduleName: moduleName)
    }
    
    private func findModuleName(baseName: String, pathComponents: [String]) -> String {
        // Check for .build directory in path (Swift Package Manager modules)
        if let buildDir = pathComponents.first(where: { $0.hasSuffix(".build") }) {
            return buildDir.replacingOccurrences(of: ".build", with: "")
        }
        
        // Default to base filename
        return baseName
    }
    
    private func parseSymbolLine(line: String, fileIndices: [String: FileInfo], details: inout LinkMapDetails) {
        let components = line.components(separatedBy: "\t")
        guard components.count > 2 else { return }
        
        // Parse hex size
        let sizeComponents = components[1].components(separatedBy: "x")
        guard sizeComponents.count > 1,
              let size = Int64(sizeComponents[1], radix: 16) else {
            return
        }
        
        // Parse file index
        let indexComponents = components[2].components(separatedBy: "]")
        let indexPart = indexComponents[0]
            .replacingOccurrences(of: "[", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        // Get symbol name (rest of the line after the file index)
        let symbolName = indexComponents.count > 1 ? 
            indexComponents[1].trimmingCharacters(in: .whitespaces) : ""
        
        // Add size to appropriate module and file
        if let fileInfo = fileIndices[indexPart] {
            // Update module size
            details.moduleSizes[fileInfo.moduleName, default: 0] += size
            
            // Extract type/class name from symbol to get finer granularity
            // Falls back to module name if we can't extract a name
            let extractedFileName = extractClassNameFromSymbol(symbolName) ?? fileInfo.fileName
            
            // Update file size within module
            if details.fileDetails[fileInfo.moduleName] == nil {
                details.fileDetails[fileInfo.moduleName] = [:]
            }
            
            // Track both size and count - we aggregate later
            details.fileDetails[fileInfo.moduleName]?[extractedFileName, default: 0] += size
        } else {
            details.moduleSizes["other", default: 0] += size
        }
    }
    
    /// Extract class/type name from a mangled Swift or Objective-C symbol
    private func extractClassNameFromSymbol(_ symbol: String) -> String? {
        // Handle compiler-generated symbols with embedded Swift names
        if symbol.hasPrefix("l_get_witness_table ") {
            // Extract and demangle the type after "l_get_witness_table "
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
        
        // Try using swift-demangle first for better accuracy
        if symbol.hasPrefix("_$s") || symbol.hasPrefix("$s") || symbol.hasPrefix("_$S") || symbol.hasPrefix("$S") {
            if let demangled = demangleSwiftSymbol(symbol) {
                return demangled
            }
            // Fallback to manual parsing
            return extractSwiftClassName(from: symbol)
        }
        
        // Handle Objective-C symbols (e.g., -[ClassName methodName:] or +[ClassName methodName:])
        if symbol.hasPrefix("-[") || symbol.hasPrefix("+[") {
            let withoutPrefix = String(symbol.dropFirst(2))
            if let spaceIndex = withoutPrefix.firstIndex(of: " ") {
                return String(withoutPrefix[..<spaceIndex])
            }
        }
        
        return nil
    }
    
    /// Extract type name from compiler-generated symbols
    private func extractFromCompilerSymbol(_ symbolPart: String) -> String? {
        // Try to find a mangled Swift name pattern in the symbol
        // Look for patterns like: 24C24ProfisNativeMessenger8PageItem
        // This means: 24 chars for "C24ProfisNativeMessenger", then 8 chars for "PageItem"
        
        // First try to demangle if it starts with a digit (length-prefixed)
        if let firstChar = symbolPart.first, firstChar.isNumber {
            // Try to extract and demangle the embedded type name
            if let extractedName = extractLengthPrefixedName(from: symbolPart) {
                return extractedName
            }
        }
        
        return nil
    }
    
    /// Extract type name from length-prefixed mangled names
    private func extractLengthPrefixedName(from symbol: String) -> String? {
        var index = symbol.startIndex
        var components: [String] = []
        
        // Try to extract up to 3 components (module, type, subtype)
        for _ in 0..<3 {
            guard index < symbol.endIndex else { break }
            
            // Extract length
            guard let length = extractLength(from: symbol, at: &index),
                  length > 0 && length < 100 else { // Sanity check
                break
            }
            
            // Extract name
            let endIndex = symbol.index(index, offsetBy: length, limitedBy: symbol.endIndex) ?? symbol.endIndex
            let component = String(symbol[index..<endIndex])
            
            // Only add if it looks like valid Swift identifier
            if component.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                components.append(component)
                index = endIndex
            } else {
                break
            }
        }
        
        // Return the last meaningful component (usually the type name)
        return components.last
    }
    
    /// Demangle Swift symbol using runtime swift_demangle function
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
            
            // Extract class name from demangled string
            // Format: "ModuleName.ClassName.methodName(...)" or similar
            return extractClassNameFromDemangled(demangledString)
        }
    }
    
    /// Extract class name from a demangled Swift symbol
    private func extractClassNameFromDemangled(_ demangled: String) -> String? {
        // Common patterns:
        // "ProfisPartnerCore.PaymentCenterTutorialHostingController.viewDidLoad() -> ()"
        // "ProfisPartnerCore.PaymentCenterTutorialHostingController.init() -> ProfisPartnerCore.PaymentCenterTutorialHostingController"
        // "(extension in ProfisPartnerCore):__C.NSBundle.module.unsafeMutableAddressor : __C.NSBundle"
        
        // Remove generic parameters and return types for cleaner parsing
        let cleaned = demangled.components(separatedBy: " -> ").first ?? demangled
        
        // Try to find pattern: ModuleName.ClassName
        let components = cleaned.components(separatedBy: ".")
        
        // Handle extension syntax: "(extension in ModuleName):..."
        if cleaned.hasPrefix("(extension in ") {
            let afterExtension = cleaned.replacingOccurrences(of: "(extension in ", with: "")
            if let colonIndex = afterExtension.firstIndex(of: ":") {
                let remaining = String(afterExtension[afterExtension.index(after: colonIndex)...])
                let parts = remaining.components(separatedBy: ".")
                if parts.count >= 2 {
                    // Return the class/type name (usually the second component)
                    return parts[1].components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }
        
        // For regular symbols, extract ClassName (second component typically)
        if components.count >= 2 {
            let className = components[1].components(separatedBy: "(").first?
                .trimmingCharacters(in: .whitespaces)
            
            // Filter out noise
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
    
    /// Extract class name from Swift mangled symbol
    /// Format: _$s<ModuleNameLength><ModuleName><ClassNameLength><ClassName>...
    private func extractSwiftClassName(from symbol: String) -> String? {
        // Remove the _$s or $s prefix
        let cleanSymbol = symbol.hasPrefix("_$s") ? String(symbol.dropFirst(3)) : String(symbol.dropFirst(2))
        
        // Try to parse the mangled name format
        var index = cleanSymbol.startIndex
        
        // Skip module name
        if let moduleLength = extractLength(from: cleanSymbol, at: &index) {
            index = cleanSymbol.index(index, offsetBy: moduleLength, limitedBy: cleanSymbol.endIndex) ?? cleanSymbol.endIndex
            
            // Now extract class name
            if index < cleanSymbol.endIndex,
               let classLength = extractLength(from: cleanSymbol, at: &index),
               classLength > 0,
               classLength < 200 { // Sanity check
                let endIndex = cleanSymbol.index(index, offsetBy: classLength, limitedBy: cleanSymbol.endIndex) ?? cleanSymbol.endIndex
                let className = String(cleanSymbol[index..<endIndex])
                
                // Only return if it looks like a valid class name
                if className.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    return className
                }
            }
        }
        
        return nil
    }
    
    /// Extract a length value from the mangled symbol
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
