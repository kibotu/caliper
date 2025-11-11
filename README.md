# Caliper Sample

Minimal iOS app demonstrating Caliper binary size analysis with link map generation.

## Build

```bash
cd Sample
chmod +x build.sh
./build.sh
```

Output:
```
build/
├── CaliperSampleApp.ipa
└── CaliperSampleApp-LinkMap.txt
```

## Generate Caliper Report

```bash
../.build/release/caliper \
  --ipa-path build/CaliperSampleApp.ipa \
  --link-map-path build/CaliperSampleApp-LinkMap.txt \
  --package-resolved-path CaliperSampleApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
  --ownership-file module-ownership.yml
```

This generates `report.json` and `report.html` with detailed binary size analysis.

