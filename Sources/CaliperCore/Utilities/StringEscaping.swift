import Foundation

extension String {
    /// Names come out of the IPA, so a `</script>` in one would break out of the
    /// enclosing element. `\u003c` is valid inside a JS string literal and JSON.
    func htmlSafe() -> String {
        replacingOccurrences(of: "<", with: "\\u003c")
    }
}