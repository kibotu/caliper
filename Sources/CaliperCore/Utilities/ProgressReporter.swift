import Foundation

public enum ProgressReporter {
    public static func success(_ message: String) {
        fputs("✅ \(message)\n", stderr)
    }
    
    public static func error(_ message: String) {
        fputs("❌ \(message)\n", stderr)
    }
    
    public static func info(_ message: String) {
        fputs("ℹ️  \(message)\n", stderr)
    }
    
    public static func warning(_ message: String) {
        fputs("⚠️  \(message)\n", stderr)
    }
    
    public static func message(_ message: String) {
        fputs("\(message)\n", stderr)
    }
    
    public static func section(_ title: String) {
        fputs("\n\(title)\n", stderr)
    }
}
