import Foundation

/// The version this binary reports via `--version`.
///
/// Kept in one place so the CLI and the packaging workflows cannot drift apart the
/// way a hardcoded literal in the command definition did.
public enum CaliperVersion {
    /// Released versions of this tool. Update alongside CHANGELOG.md.
    public static let current = "1.3.0"
}