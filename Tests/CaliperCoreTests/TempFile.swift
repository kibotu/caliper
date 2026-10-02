import Foundation

/// Writes `contents` to a uniquely-named temporary file, runs `body` with its path,
/// then removes the file. Returns whatever `body` returns.
func withTempFile<T>(_ contents: String, _ body: (String) throws -> T) throws -> T {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("caliper-test-\(UUID().uuidString)")
        .appendingPathExtension("txt")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url.path)
}