# Changelog

## [1.2.2] - 2026-05-26

### Fixed
- **IPA parsing bug**: Fixed misleading "Failed to unzip IPA file" error when `/usr/bin/unzip -v` command succeeds but UTF-8 string conversion of output fails. Changed from `guard let String(data:outputData, encoding: .utf8)` to `String(data:outputData, encoding: .utf8) ?? String(decoding:outputData, as: UTF8.self)` in `IPAParser.generateReport()`. This ensures reliable output reading even with certain IPA file formats.
s