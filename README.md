# Caliper 

[![Build](https://github.com/kibotu/caliper/actions/workflows/build.yml/badge.svg)](https://github.com/kibotu/caliper/actions/workflows/build.yml) [![GitHub Release](https://img.shields.io/github/v/release/kibotu/caliper)](https://github.com/kibotu/caliper/releases)
[![Static Badge](https://img.shields.io/badge/iOS-26-blue)](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes)
[![Static Badge](https://img.shields.io/badge/Swift%206.0%20-%20orange)](https://www.swift.org/blog/announcing-swift-6/)

**Your iOS app's size under control.** Caliper analyzes bundle sizes down to the module level, tracks team ownership, and generates beautiful interactive reports. Know exactly what's taking up space, who owns it, and where to optimize—all from a single command.

## [Demo HTML report](https://kibotu.github.io/caliper/)

<table>
  <tr>
    <td width="33%">
      <a href="docs/breakdown.png">
        <img src="docs/breakdown.png" alt="Module Size Breakdown" width="100%">
      </a>
      <p align="center"><em>Module Size Breakdown</em></p>
    </td>
    <td width="33%">
      <a href="docs/insights.png">
        <img src="docs/insights.png" alt="Size Insights" width="100%">
      </a>
      <p align="center"><em>Size Insights</em></p>
    </td>
    <td width="33%">
      <a href="docs/ownership.png">
        <img src="docs/ownership.png" alt="Module Ownership" width="100%">
      </a>
      <p align="center"><em>Module Ownership</em></p>
    </td>
  </tr>
</table>

## Quick Start

```bash
# Build
swift build -c release

# Analyze IPA with all features
.build/release/caliper \
  --ipa-path MyApp.ipa \
  --link-map-path MyApp-LinkMap.txt \
  --ownership-file module-ownership.yml \
  --package-resolved-path Package.resolved
```

Generates `report.json` and `report.html` in the current directory.

## Features

- **Binary Size Analysis** - Accurate per-module binary sizes from LinkMap files
- **Asset Tracking** - Detailed breakdown of images, storyboards, and resources
- **Module Ownership** - Track which team owns which modules
- **Version Tracking** - Swift package version information from Package.resolved
- **Interactive Reports** - Searchable HTML reports with filtering and sorting
- **Size Metrics** - Both compressed (IPA) and uncompressed (installed) sizes
- **Automatic App Detection** - Identifies and tags main app module automatically

## Installation

### Build from Source

```bash
git clone https://github.com/kibotu/caliper.git
cd caliper
swift build -c release

# Binary will be at: .build/release/caliper
```

### System-wide Install

```bash
make install
# Installs to /usr/local/bin/caliper
```

### Swift Mint

```bash
# Install
mint install kibotu/caliper

# Run
mint run kibotu/caliper --ipa-path MyApp.ipa

# Or install globally
mint install kibotu/caliper@main
caliper --ipa-path MyApp.ipa
```

> **Mint installs cannot write an HTML report.** The HTML template and the vendored d3
> live in a resource bundle beside the executable, and Mint installs from release assets
> without unpacking it. Mint runs produce a JSON report; for HTML, build from source or
> download a release and extract the bundle yourself. See [Downloading a release](#downloading-a-release).

### Downloading a release

Each release has two assets: `caliper` and `caliper_CaliperCore.bundle.tar.gz`. The bundle
holds the HTML template and the vendored d3, so the two must sit in the same directory —
that is where the binary looks for it.

```bash
# Download both assets into one directory, then:
tar -xzf caliper_CaliperCore.bundle.tar.gz
chmod +x caliper
./caliper --ipa-path MyApp.ipa
```

Without the bundle, the JSON report is still written and the HTML report cannot be
produced.

## Usage

### Basic IPA Analysis

Minimum required input - analyzes bundle structure and resources:

```bash
.build/release/caliper --ipa-path MyApp.ipa
```

### With Binary Size Data

Add LinkMap for accurate per-module binary sizes:

```bash
.build/release/caliper \
  --ipa-path MyApp.ipa \
  --link-map-path MyApp-LinkMap.txt
```

**How to generate LinkMap:**
1. Xcode → Build Settings
2. Search for "Write Link Map File"
3. Set to `YES`
4. Build your app
5. Find LinkMap at: `~/Library/Developer/Xcode/DerivedData/YourApp-xxx/Build/Intermediates.noindex/YourApp.build/Release-iphoneos/YourApp.build/YourApp-LinkMap-normal-arm64.txt`

[![Screenshot](docs/xcode-link-map.png)](docs/xcode-link-map.png)

### With Module Ownership

Track which team owns which modules:

```bash
.build/release/caliper \
  --ipa-path MyApp.ipa \
  --link-map-path MyApp-LinkMap.txt \
  --ownership-file module-ownership.yml
```

**module-ownership.yml example:**

```yaml
# Pattern matching with wildcards
- identifier: "*CoreFeature*"
  owner: Core Team
  internal: true

- identifier: "MyApp"
  owner: App Team
  internal: true

- identifier: "ThirdParty*"
  owner: External
```

**Multiple owners:**

A module can belong to more than one team. Use `owners` for a list; the first entry is the
primary owner and the rest are co-owners:

```yaml
- identifier: "SharedUI"
  owners:
    - ui-team
    - design-systems
```

Every owner is badged on the module card, co-owners in a lighter gradient, and each badge
filters the Breakdown tab to that team. The `All teams` dropdown beside the search box is
the same filter: it offers every team named anywhere in the report, including teams that
only ever co-own something, and filtering matches on any owner rather than the primary
alone — so a shared module stays visible to each team that owns it.

**The Ownership tab counts shared modules twice, on purpose.** Its chart groups by primary
owner, so the teams partition the app and the bars add up to it. The per-team list below
counts a shared module in full for every team that owns it, so those totals add up to more
than the app. There is no honest way to split a framework's bytes between two teams, so
the list over-counts rather than inventing a share. Compare the chart against the app total,
and read the list as "what this team is responsible for".

**Note:** The main app module is automatically tagged with `owner: "App"` and `internal: true`
even without an ownership file. An ownership file that writes `owners: [app, ...]` therefore
produces two teams differing only in case, and both appear in the team filter. Write `App`
in the file if you want it to be the same team.

**Pattern syntax:**
- `*` = any characters
- `?` = single character
- `internal: true` = marks as first-party code
- `owner` = team/group name for reporting
- `owners` = list of teams for co-owned modules

Everything that is not a wildcard is matched literally, so `Foundation.tbd` matches only
itself. The **first** matching entry wins, so put specific patterns above general ones.

### With Package Versions

Include Swift package version information:

```bash
.build/release/caliper \
  --ipa-path MyApp.ipa \
  --link-map-path MyApp-LinkMap.txt \
  --package-resolved-path Package.resolved
```

**Where to find Package.resolved:**
- Xcode projects: `YourProject.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- SPM projects: `Package.resolved` in project root

### With Package Name Mapping

For namespaced packages (e.g., internal packages):

```bash
.build/release/caliper \
  --ipa-path MyApp.ipa \
  --link-map-path MyApp-LinkMap.txt \
  --package-resolved-path Package.resolved \
  --package-mapping-file package-name-mapping.yml
```

**package-name-mapping.yml example:**

```yaml
- moduleName: AdjustSDK
  packageIdentity: com.company.adjust-sdk

- moduleName: InternalCore
  packageIdentity: internal.core-framework
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--ipa-path` | ✅ Yes | Path to the IPA file to analyze |
| `--link-map-path` | ⬜ No | Path to LinkMap file for accurate binary sizes |
| `--ownership-file` | ⬜ No | YAML file with module ownership patterns |
| `--package-resolved-path` | ⬜ No | Path to Package.resolved for version tracking |
| `--package-mapping-file` | ⬜ No | YAML file for namespaced package mappings |
| `--output-dir` | ⬜ No | Directory to write the reports into (default: current directory) |
| `--max-package-size` | ⬜ No | Fail if the IPA exceeds this many bytes |
| `--max-install-size` | ⬜ No | Fail if the installed size exceeds this many bytes |

### Size thresholds

Pass a limit and Caliper exits non-zero when the build exceeds it, which makes it usable
as a CI gate:

```bash
caliper --ipa-path MyApp.ipa \
  --max-package-size $((100 * 1024 * 1024)) \
  --max-install-size $((150 * 1024 * 1024))
```

Both reports are written before the check runs, so a failed build still leaves you the
evidence behind it.

## Data Sources

| Data Type | Source | Compression | Notes |
|-----------|--------|-------------|-------|
| **Module Names** | IPA structure (.framework, .bundle) | - | Extracted from bundle hierarchy |
| **Binary Sizes** | LinkMap file | Uncompressed | Compiled code size per module |
| **Asset Sizes** | IPA + .car files | Both | Images: compressed (IPA) + uncompressed (installed) |
| **Resource Files** | IPA archive | Compressed | .plist, .strings, .nib, .storyboardc, etc. |
| **Package Versions** | Package.resolved | - | Swift package dependency versions |
| **Total IPA Size** | IPA file | Compressed | Download/App Store size |
| **Total Install Size** | Unzipped IPA | Uncompressed | Actual installed app size |
| **Asset Catalog Details** | .car files via assetutil | Uncompressed | Per-asset breakdown of the expanded catalog, recorded as image detail (installed size). The download figure comes from the .car's own compressed size in the IPA listing |

### Asset catalogs: two different numbers

An `Assets.car` is a single file in the IPA, so it counts towards the download size at
exactly the compressed size `unzip -v` reports for it. `assetutil` is run as well, but
what it reports is each rendition's size *after* the catalog has been expanded — an
installed-size figure. Those per-asset numbers are recorded separately, in
`assetCatalogFiles`, and never added to any total, because treating them as compressed
bytes would overstate the download by the catalog's compression ratio.

A catalog is a bundle, and a bundle tells you nothing about what it costs, so the report
lists the assets *inside* it rather than listing the `.car` itself. That is what the
**Largest Resources** chart on the Insights tab shows: every file in the bundle that is
not compiled code — `.strop`, `.json`, `.strings`, images, and each unpacked catalog
asset — with the `.car` omitted so the container does not appear alongside its own
contents.

In the module panel these are two sections rather than one list, because they are two
different kinds of thing: **Resources** holds the files that are in the bundle, and
**Asset Catalog** holds the renditions unpacked from the catalog, headed by the `.car`'s
compressed size. That size is the one that reaches the download total; the renditions
beneath it are the same bytes expanded, so it is a note about their unit rather than a
figure to add to them.

The per-asset sum is a breakdown, not a total: it omits catalog overhead, so it will not
reconcile to the `.car` on disk. Compare `downloadSize` against the IPA listing and
`installSize` against the unzipped app.

> Source files (`.swift`, `.cpp` and the rest) are never in the IPA — they are compiled
> into the binary. LinkMap source-file sizes therefore contribute to install size only,
> and cannot contribute to download size at all.

### Compressed and uncompressed

Download size and install size are the same bytes in two states: what the user fetches,
compressed, and what the device stores, uncompressed. They differ by the app's
compression ratio, which is often a factor of three, so which one you are looking at
changes the answer. A control at the top right of the Insights tab switches between them.

It drives the charts that have both figures — **Largest Modules** and the **App Size
Treemap** — and it changes how a compiled asset catalog appears in **Largest Resources**,
which is the one resource with two honest representations.

Compressed, a catalog's contents are not in the download at all: the `.car` is a single
file in the archive, so the container is the only thing there is to show. It appears as
one row named for its container and carrying its asset count — `ProfisBus catalog`,
58.6 KB, 42 assets — so the figure reads as a price for those assets rather than a
mystery. The real path is in the tooltip, since the label is a description rather than a
filename. Uncompressed, the container says nothing and the renditions are the expanded
bytes, so the contents are listed individually instead. Showing both at once would count
the same bytes twice in one chart.

Three things deliberately do not follow it, and are labelled with their unit instead:

- **Largest Source Files** is uncompressed. Source files are compiled into the binary and
  never exist in the IPA, so there is no compressed figure to switch to — not a gap in
  the report, the bytes do not exist.
- **The Resource Type Breakdown** is compressed. No per-type uncompressed figure is
  recorded, only per-type compressed. Its "Other" wedge is the residual against that
  compressed total, so it is the files no category claims — the `.car` files and the
  untyped remainder — and not the app's compression delta.
- **Neither User Impact card** follows it. A transfer happens over the compressed IPA and
  an install occupies the uncompressed one, so each card has exactly one honest figure.

A statically linked module does not move between the two, because it has no compressed
size of its own; it shows its LinkMap figure in both, which is the same trade described
under [Statically linked modules](#statically-linked-modules).

Note that switching the whole page does not make the module list reconcile against
`totalPackageSize`: summing download sizes across modules over-counts the IPA, because a
statically linked module's bytes are already inside the app binary's compressed size.

### Statically linked modules

A module with no container in the IPA — a Swift package linked straight into the app
binary, or a system library such as `libdispatch.dylib` — has no compressed size of its
own, so there is no download figure to measure. These are reported using their LinkMap
size instead, which is uncompressed.

That figure is real, but note what it means: the bytes are physically inside the app
binary and are already counted in *its* compressed download size. **Summing download
sizes across an app therefore over-counts against the IPA**, by the combined size of its
statically linked modules. A SwiftPM-heavy app will show a total noticeably larger than
the archive. This is a deliberate trade: a per-module figure you can act on is worth more
here than a sum that reconciles, since the per-module number is what tells you which
module to go and shrink. Use `totalPackageSize` — read straight from the IPA file — when
you need the real download size of the app.

### Compressed vs Uncompressed

- **Compressed** (in IPA): What users download from App Store
- **Uncompressed**: Actual size on device after installation
- **Binary sizes** (from LinkMap): Always uncompressed executable code
- **Asset compression**: Varies by file type (PNG, JPEG, etc.)

## Output

### JSON Report (`report.json`)

```json
{
  "appInfo": {
    "appName": "MyApp",
    "appModuleName": "MyApp",
    "version": "1.2.3",
    "buildNumber": "45",
    "bundleIdentifier": "com.company.myapp"
  },
  "modules": {
    "CoreModule": {
      "name": "CoreModule",
      "owner": "Core Team",
      "additionalOwners": ["Design Systems"],
      "internal": true,
      "version": "2.1.0",
      "binarySize": 1234567,
      "imageSize": 234567,
      "imageFileSize": 345678,
      "proguard": 2345678,
      "resources": {
        "png": { "size": 123456, "count": 42 },
        "storyboardc": { "size": 45678, "count": 3 }
      },
      "top": {
        "Assets.car": 98765,
        "Background.png": 12345
      }
    }
  },
  "totalPackageSize": 12345678,
  "totalInstallSize": 23456789
}
```

**Field descriptions:**

| Field | Unit | Description |
|-------|------|-------------|
| `binarySize` | bytes | Compiled code size (from LinkMap, so uncompressed; the IPA's compressed size without one) |
| `binaryCompressedSize` | bytes | Compressed size of the main binary, straight from the IPA |
| `imageSize` | bytes | Compressed image assets in IPA |
| `imageFileSize` | bytes | Uncompressed image assets, including the per-asset breakdown of any `.car` |
| `proguard` | bytes | Total uncompressed module size |
| `resources` | object | File types with size and count |
| `top` | object | Files in the module, keyed by path, with their compressed size. Excludes the main binary, which is reported as `binaryCompressedSize` |
| `additionalOwners` | array | Co-owners, when an entry lists more than one |
| `staticallyLinked` | bool | The module has no container in the IPA; its code is linked into the app binary. It has no compressed size of its own, so `downloadSize` falls back to `binarySize` (uncompressed) rather than reporting 0 |
| `assetCatalogFiles` | object | Assets unpacked from this module's `.car` catalogs, keyed by name, uncompressed. Display only — never part of any total |
| `totalPackageSize` | bytes | IPA file size (compressed) |
| `totalInstallSize` | bytes | Installed app size (uncompressed) |

### HTML Report (`report.html`)

A single self-contained file. Everything it needs, including the charting library, is
embedded, so it opens offline with no network access.

Interactive web interface with:
- 🔍 Search and filter modules by name
- 📊 Sort by download size, install size, or name
- 📂 Expandable module details with per-file breakdowns
- 🎨 Resource breakdowns by file type
- 📈 App-wide top-20 lists for largest modules, source files and assets
- 👥 Owner breakdown with drill-down
- 🏷️ Internal vs external module filtering

## CI/CD Integration

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    
    stages {
        stage('Build App') {
            steps {
                // Your app build steps here
                sh 'xcodebuild -configuration Release ...'
            }
        }
        
        stage('Analyze App Size') {
            steps {
                // Clone and build Caliper
                dir('caliper') {
                    git url: 'https://github.com/kibotu/caliper.git'
                    sh 'swift build -c release'
                }
                
                // Run analysis
                sh '''
                    caliper/.build/release/caliper \
                        --ipa-path build/MyApp.ipa \
                        --link-map-path build/LinkMap.txt \
                        --ownership-file config/module-ownership.yml \
                        --package-resolved-path Package.resolved
                '''
                
                // Archive reports
                archiveArtifacts artifacts: 'report.json,report.html', allowEmptyArchive: false
                
                // Publish HTML report
                publishHTML([
                    reportDir: '.',
                    reportFiles: 'report.html',
                    reportName: 'App Size Report',
                    keepAll: true,
                    alwaysLinkToLastBuild: true
                ])
            }
        }
        
        stage('Check Size Thresholds') {
            steps {
                script {
                    // Parse JSON and check thresholds
                    def report = readJSON file: 'report.json'
                    def maxSize = 100 * 1024 * 1024 // 100 MB
                    
                    if (report.totalPackageSize > maxSize) {
                        error "App size ${report.totalPackageSize} exceeds threshold ${maxSize}"
                    }
                }
            }
        }
    }
}
```

### GitHub Actions

```yaml
name: App Size Analysis

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  analyze:
    runs-on: macos-13
    
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4
      
      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '15.0'
      
      - name: Build App
        run: |
          xcodebuild -workspace MyApp.xcworkspace \
            -scheme MyApp \
            -configuration Release \
            -archivePath build/MyApp.xcarchive \
            archive
          
          xcodebuild -exportArchive \
            -archivePath build/MyApp.xcarchive \
            -exportPath build \
            -exportOptionsPlist ExportOptions.plist
      
      - name: Checkout Caliper
        uses: actions/checkout@v4
        with:
          repository: kibotu/caliper
          path: caliper
      
      - name: Build Caliper
        run: |
          cd caliper
          swift build -c release
      
      - name: Analyze App Size
        run: |
          caliper/.build/release/caliper \
            --ipa-path build/MyApp.ipa \
            --link-map-path build/LinkMap.txt \
            --ownership-file config/module-ownership.yml \
            --package-resolved-path MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
      
      - name: Upload Reports
        uses: actions/upload-artifact@v4
        with:
          name: size-reports
          path: |
            report.json
            report.html
          retention-days: 90
      
      - name: Comment PR with Size
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const report = JSON.parse(fs.readFileSync('report.json', 'utf8'));
            const sizeMB = (report.totalPackageSize / 1024 / 1024).toFixed(2);
            const installMB = (report.totalInstallSize / 1024 / 1024).toFixed(2);
            
            const body = `## 📊 App Size Report
            
            - **IPA Size:** ${sizeMB} MB
            - **Install Size:** ${installMB} MB
            - **Modules:** ${Object.keys(report.modules).length}
            
            [View detailed report](../actions/runs/${context.runId})`;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });
```

## Required Tools

Caliper requires the following command-line tools to be installed:

| Tool | Usage | Installation | Version Check |
|------|-------|--------------|---------------|
| **Swift** | Build Caliper | Xcode Command Line Tools | `swift --version` |
| **unzip** | Extract IPA files | Pre-installed on macOS | `unzip -v` |
| **xcrun** | Run Xcode tools | Xcode Command Line Tools | `xcrun --version` |
| **assetutil** | Parse .car asset catalogs | Part of iOS SDK | `xcrun --sdk iphoneos assetutil --version` |

### Install Xcode Command Line Tools

```bash
xcode-select --install
```

### Verify Installation

```bash
# Check Swift
swift --version
# Should show: Swift version 6.0 or later

# Check unzip
which unzip
# Should show: /usr/bin/unzip

# Check xcrun
xcrun --version
# Should show: xcrun version X.X

# Check assetutil availability
xcrun --sdk iphoneos assetutil --version 2>/dev/null && echo "✅ assetutil available" || echo "❌ assetutil not found"
```

## Requirements

- **macOS** 14.0 or later
- **Xcode** 16.0 or later
- **Swift** 6.0 or later
- **Xcode Command Line Tools** (includes unzip, xcrun, assetutil)


### Pre-Flight Checklist

Before diving into analysis, make sure you have the right build configuration. Here's a quick checklist to maximize the value you'll get from Caliper:

**Build Settings (for Release configuration):**
- [ ] `LD_GENERATE_MAP_FILE` = `YES` (enables LinkMap)
- [ ] `DEAD_CODE_STRIPPING` = `YES` (removes unused code)
- [ ] `STRIP_INSTALLED_PRODUCT` = `YES` (strips debug symbols)
- [ ] `STRIP_SWIFT_SYMBOLS` = `YES` (removes reflection metadata)
- [ ] `SWIFT_OPTIMIZATION_LEVEL` = `-Osize` (if size > speed)
- [ ] Build configuration = **Release** (Debug builds are much larger!)

**Build Command:**
- [ ] Using `CODE_SIGNING_REQUIRED=NO` for faster CI builds
- [ ] Building with `ONLY_ACTIVE_ARCH=NO` to include all architectures
- [ ] Using `-sdk iphoneos` (not simulator)

**Optional but Valuable:**
- [ ] Create `module-ownership.yml` to map modules to teams
- [ ] Create `package-name-mapping.yml` if you use forked dependencies
- [ ] Save Package.resolved for version tracking

### Common Issues & Solutions

**"I can't find the LinkMap file!"**
- Make sure you built with **Release** configuration (not Debug)
- Check that `LD_GENERATE_MAP_FILE` is set to `YES` in Build Settings
- Clean your build folder and rebuild to ensure it generates fresh
- Use this command to locate it: `find ~/Library/Developer/Xcode/DerivedData -name "*LinkMap-normal-arm64.txt" -type f`
- The path varies between regular builds and archives—check both locations mentioned earlier
- Verify you're building for device (`-sdk iphoneos`), not simulator

**"My build fails with code signing errors"**
- If using unsigned builds, check for required entitlements (HealthKit, Apple Pay, iCloud, etc.)
- These entitlements require proper code signing—you can't skip it
- Options:
  1. Create a separate "size-analysis" scheme without these entitlements
  2. Use proper code signing (slower but necessary)
  3. Temporarily remove the capabilities for analysis builds

**"My binary size seems wrong or too small"**
- LinkMap only shows compiled code, not resources or embedded frameworks
- Make sure you're analyzing arm64 (device), not x86_64/arm64 (simulator)
- Debug builds are 2-3x larger than Release—always use Release for analysis
- If the number seems too small, you might be missing dynamic frameworks
- Universal builds include multiple architectures—check you're analyzing the right one

**"Asset sizes don't match what I expect"**
- Asset catalog sizes shown by `assetutil` are **uncompressed** (installed size on device)
- IPA sizes are **compressed** (download size from App Store)
- Both numbers are correct, they just measure different things
- App Thinning further reduces what users actually download
- Example: 50 MB assets → 30 MB in IPA → 20 MB after thinning for specific device

**"Modules aren't matching teams in the ownership report"**
- Check your `module-ownership.yml` patterns—are they specific enough?
- Module names might not match what you expect—check the report to see actual names first
- Wildcards are your friend: `*Feature*` is more forgiving than exact matches
- Order matters: more specific patterns should come before generic ones
- SPM packages often have different module names than repository names

**"The HTML report won't open or looks broken"**
- Make sure you're opening `report.html` in a modern browser (Chrome, Firefox, Safari)
- The report is self-contained; `report.json` does not need to sit beside it
- Some browsers block local file access—try hosting it with `python3 -m http.server` and open via localhost
- If the JSON is very large (>50 MB), it might be slow to load—be patient

**"Caliper crashes or hangs"**
- Very large LinkMap files (>500 MB) can be slow to parse—give it time
- Make sure you have enough RAM (LinkMap parsing can use 2-3 GB for large apps)
- Check that your input files aren't corrupted (try opening them manually)
- If analyzing a massive app (>1 GB), expect analysis to take several minutes

## Troubleshooting

### "assetutil not found" or .car parsing fails

**Solution:** Install full Xcode (not just Command Line Tools):
```bash
# Install from Mac App Store or:
xcode-select --install
sudo xcode-select --switch /Applications/Xcode.app
```

### LinkMap file not found

**Solution:** Enable LinkMap generation in Xcode:
1. Project Settings → Build Settings
2. Search: "Write Link Map File"
3. Set to: `YES`
4. Clean and rebuild

### Module names don't match Package.resolved

**Solution:** Use `--package-mapping-file` to map module names to package identities.

### Large IPA takes too long

**Solution:** The tool processes files sequentially. Progress is shown in the terminal. For very large IPAs (>500MB), analysis may take 2-5 minutes.

## Inspiration

Inspired by [Spotify's Ruler](https://github.com/spotify/ruler) - adapted for iOS with native Swift implementation and iOS-specific features like asset catalog parsing and LinkMap analysis.

## Contributing

Contributions welcome! This tool helps iOS teams monitor and optimize app size metrics.

## License

```
Copyright 2025 Jan Rabe & CHECK24

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
