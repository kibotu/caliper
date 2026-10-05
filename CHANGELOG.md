# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.3] - 2026-10-05

### Fixed

- **A framework binary whose name ends in a resource extension was read as a resource.**
  A framework's executable is named after the framework, so it can legitimately end in
  `.json`, `.plist`, `.strings` and the rest. The extension switch ran first, so
  `Data.framework/Data.json` was filed as a 90 KB JSON payload and the framework's binary
  size stayed at 0 B. The binary is now identified before its extension is considered.
  The check compares the filename without its extension against the container name — a
  plain suffix comparison cannot match `"Data.json"` against `Data`, which is exactly the
  case that went wrong.
- **A framework's container directory could overwrite its binary size with 0 B.** The
  archive lists both `Foo.framework/` and `Foo.framework/Foo`, and both reduce to the
  same name, so a name comparison alone cannot tell them apart. Directory entries are now
  excluded. Archive ordering is not stable across IPA builds, so this could appear and
  disappear between runs on the same binary.
- **`.car` files were still listed in the module panel.** The Insights chart already
  listed a catalog's contents instead of the catalog, but a module's own "Asset Files"
  list had not been changed, so `C24ProfisCraftsmen.bundle/Assets.car 58.6 KB` appeared
  under a module whose only other file was a 4 B plist — the same bytes shown twice, once
  as the container and once as the images inside it. Both panel sites duplicated that
  markup; they now share one function, so the two views cannot drift again. Catalog
  contents are listed in their place, and a module holding only a catalog is no longer
  rendered blank.

### Changed

- **The release artifact could not produce an HTML report.** The HTML template and the
  vendored d3 bundle live in `caliper_CaliperCore.bundle`, but the release workflow
  uploaded only the `caliper` executable. Anyone who downloaded a release or installed
  via Mint got `Fatal error: could not load resource bundle` before a report was written —
  which is every install path the README documents. The bundle is now included. This
  affected 1.3.0 through 1.3.2.
- Test suite grown from 56 to 63, covering framework binary detection, container
  directory entries, and the `.car` exclusion in the module panel. The new tests were
  verified to fail against the previous behaviour.

### Fixed

- **A framework binary whose name ends in a resource extension was read as a resource.**
  A framework's executable is named after the framework, so it can legitimately end in
  `.json`, `.plist`, `.strings` and the rest. The extension switch ran first, so
  `Data.framework/Data.json` was filed as a 90 KB JSON payload and the framework's
  binary size stayed at 0 B. The binary is now identified before its extension is
  considered. The check compares the filename without its extension against the
  container name — a plain suffix comparison cannot match `"Data.json"` against `Data`,
  which is exactly the case that went wrong.

### Changed

- The archive lists both `Foo.framework/` and `Foo.framework/Foo`, and both reduce to
  the same name, so a name comparison alone cannot tell them apart. The container's own
  directory entry was therefore eligible to be recorded as its binary at 0 bytes, which
  would overwrite the real figure whenever the archive happened to list it last. It is
  now excluded. The ordering is not stable across IPA builds, so this could appear and
  disappear between runs on the same binary.

### Added

- 5 tests over framework parsing, covering the resource-extension case, the container
  directory entry, a versioned `Versions/A` layout, and the resources that must still be
  counted alongside a framework binary. Verified to fail against the previous behaviour.

## [1.3.2] - 2026-10-05

### Fixed

- **Download size read "0 B" for statically linked modules.** A module with no container
  in the IPA — the linker put its code inside the app binary, as with every Swift package
  and every system `.tbd`/`.dylib` — has no compressed size of its own, so it had nothing
  to report and said so with a zero. Most rows of a SwiftPM app are in this position, and
  for an internal module it read as "this package is free" while its size sat in plain
  sight a few lines below. Such modules now report their LinkMap size, which is a real
  measurement of code the team owns. It is uncompressed, and the bytes are already inside
  the app binary's compressed size, so **summing download sizes over-counts against the
  IPA** — noted in the README, with `totalPackageSize` given as the figure to use when
  the real download size is what matters. Per-module usefulness was preferred over a sum
  that reconciles, since the per-module number is the actionable one.
- **Asset catalogs were counted in the wrong units, overstating download size.** The
  `.car` itself was never added to the download total. In its place, `assetutil`'s
  per-asset figures — which report each rendition's size after the catalog has been
  expanded — were written into the dictionaries that record *compressed* sizes. A
  compiled catalog occupying 940 compressed bytes in the IPA was reported as 1,608.
  The error scales with how compressible the assets are, so the more PNGs an app had the
  worse its download figure got. The `.car` is now counted at its compressed size from
  the archive listing, and the per-asset figures are recorded in a separate,
  display-only field that feeds no total. Download size now reconciles exactly with the
  sum of the IPA listing.
- **The Insights tab no longer lists `.car` files as assets, and lists what is inside
  them instead.** A catalog is a bundle, and a bundle tells you nothing about what it
  costs. Every other file in the bundle — not just images — counts as an asset, so
  `.strop`, `.json` and `.strings` now appear in "Largest Asset Files" where they
  previously did not.

### Added

- **`assetCatalogFiles`.** The assets unpacked from a module's `.car` catalogs, keyed by
  name. Display only, and deliberately excluded from every total, since the figures are
  uncompressed.

### Changed

- **1.3.1's "in app binary" label has been removed.** It labelled statically linked
  modules rather than reporting a figure, which on a real app replaced one row with a
  placeholder and told the reader nothing they could act on. Such modules now report
  their LinkMap size instead, as described above. `staticallyLinked` is retained, as it
  is what makes that fallback applicable.
- Test suite grown from 43 to 56, covering the asset catalog accounting, the catalog
  listing, and the statically linked fallback. The new tests were verified to fail
  against the previous behaviour.

## [1.3.1] - 2026-10-05

### Fixed

- **Asset catalogs were counted in the wrong units, overstating download size.** The
  `.car` itself was never added to the download total. In its place, `assetutil`'s
  per-asset figures — which report each rendition's size after the catalog has been
  expanded — were written into the dictionaries that record *compressed* sizes. A
  compiled catalog occupying 940 compressed bytes in the IPA was reported as 1,608.
  The error scales with how compressible the assets are, so the more PNGs an app had the
  worse its download figure got. The `.car` is now counted at its compressed size from
  the archive listing, and the per-asset figures are recorded only as uncompressed image
  detail. Download size now reconciles exactly with the sum of the IPA listing.
- **Download size read "0 B" for statically linked modules.** A module with no container
  in the IPA — the linker put its code inside the app binary — owns no compressed bytes of
  its own, so its total is legitimately zero, but the report had no way to say so. Most
  rows of a SwiftPM app are in this position, including every `.tbd` and `.dylib` stub, and
  an owner's entire download bar collapsed to 0 B whenever all of its modules were static.
  Such modules are now flagged during LinkMap processing and shown as "in app binary".
  The numbers are unchanged: a module with a container still reports a real figure, and
  sorting still uses the measured value, since a static module genuinely contributes
  nothing to the download.

### Added

- **`staticallyLinked`.** A per-module flag recording that a module has no container in
  the IPA, so the report can explain a zero download figure instead of asserting one.

### Changed

- Test suite grown from 43 to 53, covering the asset catalog accounting and the
  statically linked flag. The new tests were verified to fail against the previous
  behaviour.

## [1.3.0] - 2026-10-05

### Added

- **Size thresholds.** `--max-package-size` and `--max-install-size` fail the run with a
  non-zero exit code and a message stating how far over the limit it is. Both reports are
  written before the check, so a regression still leaves the evidence behind it.
- **`--output-dir`.** Reports are no longer forced into the current directory.
- **Multiple owners.** An ownership entry may use `owners: [a, b]` as well as `owner: a`.
  The first entry is reported as `owner`, the rest as a new `additionalOwners` field.
- **`binaryCompressedSize`.** A new per-module field carrying the compressed size of the
  main binary, which `binarySize` cannot hold once a LinkMap overwrites it.
- **Test suite.** 43 tests over the LinkMap parser, ownership matching and service
  behaviour, the module size totals, and the HTML reporter. `Package.swift` now has a
  `CaliperCore` library target and a `CaliperCoreTests` test target; analysis code moved
  out of the executable. `swift test` runs in CI.

### Changed

- **The HTML report is now self-contained.** d3 v7.9.0 is vendored and inlined instead of
  being fetched from `d3js.org`, so the report opens with no network access — offline, on
  an air-gapped runner, or from a downloaded CI artifact. Previously every chart rendered
  empty when that request failed.
- Module totals read a single canonical install size instead of being recomputed in
  JavaScript, and a test now pins the report's copy of that arithmetic to the Swift
  definition.

### Fixed

- **Dead-stripped symbols were counted.** A `# Dead stripped symbols:` section did not end
  the symbol section, so the linker-removed bytes of every module that defined one were
  added to its total.
- **Download size was zero for most modules.** The total was computed from the per-file
  list, which deliberately omits the main binary, so a framework that ships nothing but a
  binary reported no download bytes. The compressed binary size is now recorded
  separately as `binaryCompressedSize` and counted.
- Per-module "download size" was documented as `binarySize`, which is uncompressed LinkMap
  output. It now uses the modules' real compressed file sizes.
- **The Download column contradicted its own sort.** The module card displayed
  `binarySize` while the list was sorted on a different figure. Both now read the same
  function, as does the Ownership tab, which had the same split.
- **Images were double-counted.** Module totals added `imageFileSize` and `resources`
  together, but the parsers record each image in both. Every image counted twice.
- **The resource breakdown mixed units.** Categories are recorded compressed, but the
  Binary and Images rows were summed from uncompressed figures, so the "Other" residual
  absorbed the mismatch instead of the unattributed files it represents.
- Treemap percentages divided a module's size by the whole-app total, understating every
  cell whenever a filter hid modules. They are now relative to what the treemap draws.
- **Ownership patterns treated `.` as a wildcard.** `Foundation.tbd` also matched
  `FoundationXtbd`. Identifiers are now escaped before `*` and `?` are translated.
- **Package versions were assigned non-deterministically.** Version matching iterated a
  dictionary and stopped at the first partial match, so a module matching several package
  identities could get a different version on each run. Matching is now ordered, and the
  longest partial match wins.
- **The version report was wrong.** `--version` reported `1.0.0` while the repository was
  at `1.2.2`.
- **HTML injection.** Module names, owners and resource types were interpolated into the
  page unescaped, and the report payload was embedded without escaping `<`, so a crafted
  name could break out of the script element.
- `switchTab` relied on the implicit global `event`, which fails under strict mode.
- Clicking the Insights tab re-rendered every chart each time and appended a new set of
  tooltip elements, growing the DOM without bound. It now renders once, from `switchTab`,
  with the guard set before the render is scheduled so a second click cannot queue a
  duplicate.
- The vendored d3 bundle shipped without its ISC licence text. `LICENSE-d3.txt` now sits
  beside it and is copied into the resource bundle.
- `finalizeTop()` sorted the file dictionary into a fresh dictionary, discarding the
  ordering it had just computed. It is now a no-op; consumers sort at display time.
- A duplicate `moduleName` in a package-mapping file crashed via
  `Dictionary(uniqueKeysWithValues:)`. It now warns and keeps the first entry.
- The unzipped IPA directory is created next to the IPA rather than in the working
  directory.
- `make analyze` and `make example` passed `--output`, `--group-by-owner` and
  `--filter-owner`, none of which existed, so both targets failed with a usage error.
  They pass the supported flags and gained `PACKAGE_RESOLVED`, `PACKAGE_MAPPING`,
  `OUTPUT_DIR` and the two threshold variables.
- A missing or malformed ownership file now reports which file failed and why.
- Progress calculation no longer divides by zero on an empty file list.

### Removed

- A dead module-renaming path. `buildAppSizeReport`, `extractModuleName` and both
  `SizeCalculator` passes accepted a `moduleMapping` dictionary that was always empty;
  the CLI stopped producing it when ownership moved to pattern matching, and the plumbing
  was never removed.
- Non-deterministic debug logging that fired on roughly 0.1% of frameworks and bundles.

## [1.2.2] - 2026-05-26

### Fixed

- **IPA parsing bug**: Fixed misleading "Failed to unzip IPA file" error when
  `/usr/bin/unzip -v` succeeds but UTF-8 conversion of its output fails. Changed from
  `guard let String(data:outputData, encoding: .utf8)` to
  `String(data:outputData, encoding: .utf8) ?? String(decoding:outputData, as: UTF8.self)`.