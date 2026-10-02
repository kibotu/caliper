import Foundation

extension String {
    /// Escapes `<` so this string can be embedded inside a `<script>` element
    /// without being able to terminate it.
    ///
    /// Module and file names come out of the IPA and the LinkMap, so they are not
    /// under the tool's control. A name such as `</script><script>alert(1)</script>`
    /// would otherwise break out of the script block and execute. Replacing `<` with
    /// its `\u003c` escape is valid inside a JavaScript string literal and inside
    /// JSON, and leaves the decoded value untouched.
    func htmlSafe() -> String {
        replacingOccurrences(of: "<", with: "\\u003c")
    }
}