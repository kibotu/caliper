# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **The compressed `Largest Resources` chart listed `Assets.car` files.** With Download
  (compressed) selected, each catalog appeared as one row named for its container
  (`ProfisBus catalog`, 58.6 KB, 42 assets) — 1.4.1's fix for a chart that listed the raw
  paths. It still says what a catalog cost rather than what to change, and a container
  row only exists on the reading where the catalog's contents are absent from the download
  entirely. The chart now lists the assets unpacked from the catalog on both sizes, so the
  control does not reach it at all: the bundle's files have only a compressed per-file
  figure and a rendition only an uncompressed one, which is the same trade Largest Source
  Files makes.
  - The heading names both units — `bundle files compressed, catalog assets uncompressed` —
    so a ranked list of the two is not read as one. The rows' tooltips already said which
    was which.
  - Nothing is lost by dropping the container: its compressed size heads the Asset Catalog
    section of its module's panel, and it is still in the Resource Type Breakdown's
    residual.
  - `catalogLabel` and `catalogAssetCount` went with it; they only existed to name and
    count a container row.

## [1.5.3] - 2026-10-06

### Changed

- **Comments cut from 978 lines to 264.** No behaviour change and no output change: the
  JSON and HTML reports are byte-for-byte identical, comments in the emitted HTML aside.
  What went:
  - Comments restating the signature. `/// Add a resource to this module`, `// Parse hex
    size`, `// Center text`, and about forty more that named the line beneath them.
  - Comments narrating a bug that had already been fixed — which formula used to
    double-count images, why the d3 lookup once missed Mint installs, what a regression's
    reproduction looked like. That belongs in the commit that fixed it and the changelog
    entry it shipped in, both of which still exist. In the source it was a second copy of
    the git log, and it went stale: several such comments described behaviour that had
    since changed again.
  - Test comments restating the `@Test` name.
- Three `if` blocks collapsed into early returns while the comments around them were
  removed. No behaviour change, but the release is not comment-only in the diff.

What stayed is the part a reader cannot recover from the code: the compressed/uncompressed
unit split, which is the difference between a right number and a silently wrong one, and
`Bundle.module` being tried last because it traps when the bundle is missing.

## [1.5.2] - 2026-10-06

### Fixed

- **`mint install kibotu/caliper` wrote a JSON report and then failed the HTML one.**
  1.5.1 looked the vendored d3 up by appending its file name to the resource bundle's
  directory. That is correct for the layout a `swift build` produces and for the one the
  release archive ships, where the resources sit in the bundle's root. Mint produces a real
  Apple bundle with them under `Contents/Resources`, so the appended path was not there:

  ```
  ✅ Report saved to: out/report.json
  📊 Generating HTML report...
  ❌ Failed to generate HTML report: invalidOutput
  Error: Failed to generate output
  ```

  Reproduced against the installed 1.5.1 binary. d3 is now resolved through `Bundle`,
  which knows where a bundle keeps its resources in either layout, so the two install paths
  agree without either being special-cased.

  1.5.1 documented this as Mint not shipping the bundle at all. It does ship it — the
  bundle was found and read, at a path the lookup then ignored — so the note and the README
  section that repeated it are corrected above rather than left standing.
- **An empty `caliper_CaliperCore.bundle` beside the executable could shadow the real one.**
  The bundle search accepted a candidate on `Bundle(url:) != nil`, which Foundation answers
  for any directory that exists, empty or not — so an empty leftover was taken as the
  bundle and the search stopped, never reaching a good one. Candidates are now accepted on
  resolving d3 itself, which is the thing that has to be there.
- **The release verification could only see the layout its own build produced.** Every check
  ran against the flat bundle a `swift build` produces, so a lookup that broke the Mint
  layout passed CI while failing for everyone who installed that way — the same blind spot
  the previous release fix had, one level up. The workflow now assembles the Apple layout
  by hand and requires a report from it too. Confirmed to fail with the 1.5.1 binary and to
  pass with this one.

## [1.5.1] - 2026-10-06

### Fixed

- **Every release since 1.3.3 shipped a binary that could not write an HTML report.**
  The resource bundle — the HTML template and the vendored d3 — was added to the release
  workflow's file list, but a release asset cannot be a directory, so it was silently
  skipped and the executable uploaded alone. Downloaded 1.3.3, 1.4.0 and 1.5.0 and ran
  them against a real archive:

  ```
  ✅ Report saved to: out/report.json
  📊 Generating HTML report...
  CaliperCore/resource_bundle_accessor.swift:12: Fatal error: could not load resource bundle
  ```

  The JSON report was written; the HTML report killed the process. `--version` and
  `--help` worked, which is why it went unnoticed: neither touches the reporter.

  The bundle is now packaged as `caliper_CaliperCore.bundle.tar.gz` and uploaded beside
  the executable, with instructions in the release notes. It has to be extracted into the
  same directory as the binary, because that is where it is looked up.
- **The release workflow could not fail on a missing bundle.** The verification step
  printed "Build completed successfully!" whatever happened. It now asserts the bundle was
  built, asserts the archive actually contains `d3.v7.min.js` rather than just being
  non-empty, and runs the packaged artifact exactly as a user would — two files, bundle
  extracted, both reports written. This is the check whose absence let the original fix
  through.
  - The mirror-image assertion, that the binary *fails* without the bundle, cannot be made
    in CI: SwiftPM bakes the build machine's absolute path into the binary, so on a runner
    the bundle is always found and the failure never reproduces. That direction was
    verified by hand with the build tree removed. The first attempt at this check asserted
    it anyway and failed the 1.5.1 run.
- **The bundle is now found beside the executable.** SwiftPM bakes the bundle's absolute
  path into the binary at build time, so a release binary searched only its build machine
  and the downloaded copy was never considered. The documented layout — the bundle in the
  same directory as the executable — is searched first, with SwiftPM's lookup kept as a
  fallback so every build and test environment resolves as before.

### Known issues

- **A missing resource bundle still aborts the process rather than raising an error.**
  `Bundle.module` is SwiftPM's generated accessor and it ends in `fatalError`, which cannot
  be caught, and its message leaks the build machine's path. Replacing it means
  reimplementing SwiftPM's per-build-system resolution — under `swift test` the bundle is
  found via a path baked in at compile time, nowhere near the executable — so the fix is
  to make sure the bundle is actually shipped rather than to catch this. Not worth
  reimplementing a build system's internals to improve one error message.
- **`mint install kibotu/caliper` still cannot generate an HTML report.** Mint installs
  from release assets and has no way to unpack a side-car archive next to the executable,
  so the bundle is missing after a Mint install. Manual extraction works and the README says
  so. Removing the dependency entirely means embedding the template and d3 in the binary at
  compile time, which needs a generated Swift source and a build plugin; worth doing, but
  not in a patch.

## [1.5.0] - 2026-10-05

### Added

- **A module can be owned by more than one team, and the report now shows it.** The
  `owners: [a, b]` form of an ownership entry was parsed and encoded to JSON from 1.3.0,
  but nothing in the report read it: a module owned by `app` and `core` showed one badge
  and `core` was invisible. Every owner is now badged, co-owners in a lighter gradient so
  the order reads without a second label saying "also".
- **A team filter on the Breakdown tab.** An `All teams` dropdown beside the search box,
  populated from the owners actually present, so a team that owns nothing cannot be
  selected and a team that only ever co-owns something still can. Every owner badge is
  also clickable and filters to the same value; the two are driven by one variable, so
  they cannot disagree. Clicking the selected team again clears the filter, and the
  matching badge is outlined so the active filter is visible on the cards.
  - Filtering matches on **any** owner, not just the primary. Matching on the primary
    alone would hide a shared module from every team except the first one listed, which
    is the opposite of what someone filtering by team is asking.
- **The Ownership tab handles many teams.** A shared module is now attributed to every
  team that owns it, so a team that only co-owns still appears in the per-team list with
  a real figure. Each team's dropdown option carries its total, and its detail card badges
  the module's owners so a reader inside one team can see the module is shared.

### Changed

- **The Ownership tab's chart and its per-team list are now built differently, on
  purpose.** The chart counts each module once under its primary owner, so the teams
  partition the app and the bars add up to it. The list counts a shared module in full
  for every team that owns it, so its totals deliberately exceed the app. There is no
  honest way to split a framework's bytes between two teams, so the list over-counts
  rather than inventing a share; the tab says so. Collapsing the two into one grouping
  would mean either the chart double-counts or the list under-reports a team.
- A click on a bar in the Ownership chart resolves its team **by name** rather than by
  array index, since the chart and the dropdown are built from different groupings now
  and no longer share indices.

### Fixed

- **The owner detail cards showed each module's array index as its name.** Splitting the
  ownership grouping turned `owner.modules` from a name-keyed map into a list, because a
  module can appear under several teams. The detail card still read it with
  `Object.entries`, so every card in that section rendered `0`, `1`, `2` where a module
  name should have been. Found in a browser, not by the grouping tests — those check the
  totals, not the markup.
- Badges on the Ownership tab's module cards are informational rather than clickable. The
  team filter does not apply on that tab, so a badge that looked clickable there would do
  nothing when clicked.

### Known issues

- The app module is auto-tagged with the owner `App` (see `tagAppModule`). An ownership
  file that writes `owners: [app, core]` therefore produces two teams differing only in
  case, and the team filter offers both. Reconciling them is a question about how the
  auto-tag interacts with a hand-written file rather than a defect in the filter, so it is
  left alone here; writing `App` in the file makes them one team.

## [1.4.1] - 2026-10-05

### Fixed

- **The compressed `Largest Resources` chart listed `Assets.car` files, which say
  nothing actionable.** A compiled asset catalog is a container, and the compressed view
  had to show the container because a catalog's contents are not in the download at all.
  Labelled with its path, though, `Payload/…/ProfisBus.bundle/Assets.car` at 58.6 KB
  reports that a catalog exists and what it cost — which is not something anyone can go
  and do anything about. Each catalog is now one row named for its container
  (`ProfisBus catalog`) and carrying its asset count, so the figure reads as a price for
  N assets rather than a mystery. The real path is in the row's tooltip, since the label
  is a description and not a filename.
  - The container's extension is dropped from the label because the chart's axis truncates
    to about twenty characters, and `ProfisBus.bundle asset catalog` loses the one word
    that says what the row is.
  - The count is the module's total across all of its catalogs, not a per-catalog count,
    because `assetCatalogFiles` is a flat dictionary keyed by rendition name. A module
    with one catalog — the usual shape, since a bundle ships one `Assets.car` — is exact.

## [1.4.0] - 2026-10-05

### Added

- **The Insights tab can show compressed or uncompressed sizes.** A control at the top
  right switches the page between the two readings of "size", which differ by the app's
  compression ratio. Every chart with both figures reads one selector, so the control
  cannot leave two of them measuring different things on the same page.
  - **Largest Modules** and the **App Size Treemap** switch wholesale. The treemap's
    tooltip follows too: its binary and asset figures were pinned to the uncompressed pair,
    which is only correct while the cell is uncompressed.
  - **Largest Resources** switches how a compiled asset catalog is represented, which is
    the one resource with two honest figures. Compressed, the `.car` is a single file in
    the archive and its contents are not in the download at all, so the container is the
    figure. Uncompressed, the container says nothing about what it costs and the
    renditions are the expanded bytes, so the contents are the figure.
  - **Statically linked modules do not move.** They have no compressed size of their own —
    the linker put their code inside the app binary — so their figure is the uncompressed
    LinkMap fallback in both modes. This is the same trade documented for
    `downloadSize`, and the reason summing downloads over-counts the IPA.

  The sections with only one honest figure say which they are rather than appearing to
  ignore the control: Largest Source Files is uncompressed because source files are
  compiled into the binary and never exist in the IPA; the Resource Type Breakdown is
  compressed because no per-type uncompressed figure is recorded; and neither User Impact
  card follows, since a transfer happens over the compressed IPA while an install occupies
  the uncompressed one.

### Fixed

- **"Other" in the resource breakdown was the app's compression delta, not a remainder.**
  Every category in that chart is a compressed size, but the residual was measured against
  the uncompressed install total, so it absorbed the difference between the two for the
  whole app. On a three-module test app it reported 348 KB against a real remainder of
  94 KB, and was the largest wedge in the chart ahead of Binary. It is now measured against
  the compressed total, which leaves it as the files no category claims — the `.car` files
  and the untyped remainder.
- **Images were counted twice in the resource breakdown.** `imageSize` accumulates the same
  files, at the same compressed size, that populate `resources['png']` and the other image
  types, so the "Images" rollup summed those bytes a second time and pushed the donut past
  the app's real size. Its count was worse: it counted every entry in `top`, which is every
  file in the bundle whatever its type. There is no correct version of that rollup, so it
  is gone; the per-type breakdown already separates the formats and carries their real
  counts. The heading now reads "By Size (Compressed)" rather than claiming install size
  of a chart that plots compressed bytes.
- **A statically linked module's code size reached the compressed breakdown.** Its download
  figure is the uncompressed LinkMap fallback, so including it in the total added its
  entire code size to "Other" — bytes that are already counted once, inside the app
  binary. Statically linked modules are now excluded from that total.
- **Every asset in a catalog was displayed twice and misfiled as an unknown file type.**
  The module panel marked catalog entries by appending `(in catalog)` to the file name,
  which put the marker in the row twice — once in the name, once in the type badge, which
  is derived from the name's extension. `"bus.svg (in catalog)"` ends in
  `"svg (in catalog)"`, which matched no file type, so each asset lost its colour coding
  and its `title` tooltip offered a path that does not exist in the bundle. Resources and
  catalog contents are now separate sections, so nothing has to be marked.
- **A name with no extension was badged with itself.** `getFileTypeInfo` took the last
  dot-separated component, which for an extensionless name is the whole name — a colour
  set named `AccentColor` was badged `ACCENTCOLOR`. Such entries are now badged `ASSET`.
- **The Insights chart labelled the same file differently from the module panels.** The
  panels appended `(in catalog)`; the chart did not. Both now use the bare name, and each
  bar's tooltip states whether it is a container or an unpacked rendition.
- **Re-rendering the Insights tab grew the DOM without bound.** Every chart appended its own
  tooltip to the body and User Impact wrote into a container it never cleared. That was
  tolerable while the tab rendered once on first visit, which is what the guard was for;
  the size control makes it a leak on every flip. Both are now cleared per render.
- The count badge in a module panel section heading had no styling, because the rule was
  scoped to the source-file section. It is now styled everywhere it appears.
- `CaliperVersion.current` read 1.3.2 in the 1.3.3 release, so `--version` disagreed with
  the tag. It tracks 1.4.0 from here; the missed bump is not backfilled.

### Changed

- **Headings follow Apple's vocabulary.** `Assets.car` is a *compiled asset catalog*, so
  the report calls it that rather than a "catalog" or a bundle; its contents are an
  *asset catalog* section, and the general list of non-code files in a container is
  *Resources* (Xcode's "Copy Bundle Resources"). The panel's "Asset Files" list is now
  "Resources", and the breakdown beside it — a different view of the same data — is now
  "Resource Types" rather than sharing the word. The Asset Catalog heading carries the
  catalog's compressed size, which is the figure that actually reaches the download
  total; the rows beneath it are the same bytes expanded, so the note explains their unit
  rather than adding to them.
- The Insights tab's "Largest Asset Files" chart is now "Largest Resources", matching the
  sections it draws from. It lists everything in the bundle that is not compiled code,
  not only images.

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