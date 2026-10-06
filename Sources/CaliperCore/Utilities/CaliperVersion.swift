import Foundation

/// The version this binary reports via `--version`.
///
/// Kept in one place so the CLI and the packaging workflows cannot drift apart the
/// way a hardcoded literal in the command definition did.
public enum CaliperVersion {
    /// Released versions of this tool. Update alongside CHANGELOG.md.
    ///
    /// 1.3.3 shipped with this still reading 1.3.2, so the constant drifted from the tag
    /// it exists to track. It moves with the release that follows, not backfilled.
    public static let current = "1.4.1"
}