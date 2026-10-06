import Foundation

public struct HTMLReporter {
    public init() {}

    /// One self-contained file: d3 is inlined and the data embedded, so the report
    /// opens with no network access.
    public func generate(jsonString: String, outputPath: String) throws {
        let html = htmlTemplate
            .replacingOccurrences(of: "__D3__", with: try Self.vendoredD3())
            .replacingOccurrences(of: "__DATA__", with: jsonString.htmlSafe())
        try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    static func vendoredD3() throws -> String {
        guard let url = vendoredD3URL(),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw CaliperError.invalidOutput
        }
        return contents
    }

    private static let bundleName = "caliper_CaliperCore"
    private static let d3ResourceName = "d3.v7.min"

    private final class BundleMarker {}

    private static var candidatesForBundle: [URL] {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources) }
        if let resources = Bundle(for: BundleMarker.self).resourceURL { candidates.append(resources) }
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent())
        }
        candidates.append(Bundle.main.bundleURL)
        return candidates
    }

    /// Resolved through `Bundle`, which knows both layouts this package ships in:
    /// `swift build` and the release archive put resources in the bundle's root, while
    /// `mint install` builds an Apple bundle with them under `Contents/Resources`.
    static func d3URL(inBundleAt root: URL) -> URL? {
        Bundle(url: root)?.url(forResource: d3ResourceName, withExtension: "js")
    }

    /// The first candidate that resolves d3 itself. `Bundle(url:)` answers for any
    /// directory that exists, so testing the directory would accept an empty leftover
    /// and shadow the real bundle.
    ///
    /// `Bundle.module` is the fallback, not a peer: SwiftPM bakes the bundle's absolute
    /// path into the accessor, which is the only way `swift test` finds it. It traps
    /// when the bundle is absent, so it must be reached last.
    static func vendoredD3URL() -> URL? {
        for candidate in candidatesForBundle {
            let url = candidate.appendingPathComponent(bundleName + ".bundle")
            if let d3 = d3URL(inBundleAt: url) { return d3 }
        }
        return Bundle.module.url(forResource: d3ResourceName, withExtension: "js")
    }
    
    private let htmlTemplate = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>App Size Report</title>
    <script>/* d3 v7.9.0, vendored so this report works offline. ISC licensed, (c) Mike Bostock. */__D3__</script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', 'Helvetica Neue', sans-serif; background: #f5f5f5; padding: 20px; line-height: 1.6; }
        .container { max-width: 1400px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
        header { background: linear-gradient(135deg, #063773 0%, #0a5aa8 100%); color: white; padding: 30px; }
        header h1 { font-size: 32px; margin-bottom: 10px; }
        
        .tabs { display: flex; background: #f8f9fa; border-bottom: 2px solid #e0e0e0; }
        .tab { padding: 15px 30px; cursor: pointer; font-weight: 600; color: #666; border-bottom: 3px solid transparent; transition: all 0.2s; }
        .tab:hover { color: #063773; background: rgba(6, 55, 115, 0.05); }
        .tab.active { color: #063773; border-bottom-color: #063773; background: white; }
        
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; padding: 30px; background: #f8f9fa; border-bottom: 1px solid #e0e0e0; }
        .summary-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        .summary-card h3 { font-size: 14px; color: #666; margin-bottom: 10px; text-transform: uppercase; letter-spacing: 0.5px; }
        .summary-card .value { font-size: 28px; font-weight: bold; color: #333; }
        .summary-card .label { font-size: 11px; color: #999; margin-top: 5px; }
        .summary-card .internal-info { font-size: 12px; color: #9b59b6; margin-top: 8px; font-weight: 600; }
        
        .controls { padding: 20px 30px; background: white; border-bottom: 1px solid #e0e0e0; display: flex; gap: 15px; flex-wrap: wrap; align-items: center; }
        .controls input { padding: 10px 15px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; flex: 1; min-width: 200px; }
        .controls select { padding: 10px 15px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; background: white; cursor: pointer; }
        
        .filter-chips { display: flex; gap: 10px; flex-wrap: wrap; }
        .filter-chip { padding: 8px 16px; border: 2px solid #e0e0e0; border-radius: 20px; font-size: 13px; font-weight: 600; color: #666; background: white; cursor: pointer; transition: all 0.2s; user-select: none; }
        .filter-chip:hover { border-color: #063773; color: #063773; background: #f0f6ff; }
        .filter-chip.active { background: linear-gradient(135deg, #063773 0%, #0a5aa8 100%); color: white; border-color: #063773; }
        .filter-chip.active:hover { background: linear-gradient(135deg, #0a5aa8 0%, #063773 100%); }
        
        .modules-grid { padding: 30px; }
        .module-card { background: white; border: 1px solid #e0e0e0; border-radius: 8px; margin-bottom: 16px; overflow: hidden; transition: all 0.2s ease; }
        .module-card:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.08); border-color: #063773; }
        .module-header { padding: 18px 24px; background: #fafafa; cursor: pointer; display: flex; justify-content: space-between; align-items: center; gap: 16px; transition: background 0.15s ease; }
        .module-header:hover { background: #f5f6fa; }
        .module-info { flex: 1; min-width: 0; display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
        .module-name-row { font-size: 16px; font-weight: 600; color: #2d3748; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .module-version { color: #063773; }
        .owner-badge { display: inline-flex; align-items: center; padding: 4px 10px; background: linear-gradient(135deg, #063773 0%, #0a5aa8 100%); color: white; border-radius: 10px; font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; box-shadow: 0 2px 4px rgba(6, 55, 115, 0.2); flex-shrink: 0; }
        /* A co-owner: lighter, so the order reads without a second label saying "also". */
        .owner-badge.additional { background: linear-gradient(135deg, #0a5aa8 0%, #3498db 100%); }
        .owner-badge.owner-badge-filter { cursor: pointer; }
        .owner-badge.owner-badge-filter:hover { filter: brightness(1.15); }
        .owner-badge.team-selected { outline: 2px solid #f39c12; outline-offset: 1px; }
        .internal-badge { display: inline-flex; align-items: center; padding: 4px 10px; background: linear-gradient(135deg, #9b59b6 0%, #8e44ad 100%); color: white; border-radius: 10px; font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; box-shadow: 0 2px 4px rgba(155, 89, 182, 0.2); flex-shrink: 0; }
        .module-stats { display: flex; align-items: center; gap: 20px; flex-shrink: 0; }
        .module-stat { display: flex; flex-direction: column; align-items: flex-end; }
        .module-stat-label { font-size: 10px; color: #999; text-transform: uppercase; letter-spacing: 0.5px; }
        .module-stat-value { font-size: 14px; color: #063773; font-weight: 700; white-space: nowrap; }
        .module-size { font-size: 16px; color: #063773; font-weight: 700; white-space: nowrap; }
        .expand-icon { color: #063773; font-size: 12px; transition: transform 0.2s; }
        .expand-icon.open { transform: rotate(180deg); }
        
        .module-details { padding: 20px 24px; display: none; background: #fafafa; }
        .module-details.open { display: block; }
        
        .size-bars { margin-bottom: 30px; }
        .size-bar { margin-bottom: 15px; }
        .size-bar-label { display: flex; justify-content: space-between; margin-bottom: 5px; font-size: 14px; }
        .size-bar-label .name { color: #333; font-weight: 500; }
        .size-bar-label .value { color: #666; }
        .size-bar-fill { height: 8px; background: #e0e0e0; border-radius: 4px; overflow: hidden; }
        .size-bar-progress { height: 100%; background: linear-gradient(90deg, #063773 0%, #0a5aa8 100%); transition: width 0.3s; }
        
        .resources-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }
        .resource-card { background: white; padding: 15px; border-radius: 6px; border: 1px solid #e0e0e0; }
        .resource-type { font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 5px; }
        .resource-size { font-size: 18px; font-weight: bold; color: #333; }
        .resource-count { font-size: 12px; color: #999; }
        
        .files-section { margin-top: 30px; }
        .files-section h4 { font-size: 16px; margin-bottom: 15px; color: #333; display: flex; align-items: center; gap: 10px; }
        .count-badge { background: #063773; color: white; padding: 2px 8px; border-radius: 10px; font-size: 12px; }
        .files-table { width: 100%; background: white; border-radius: 6px; overflow: hidden; border: 1px solid #e0e0e0; }
        .files-table-header { display: grid; grid-template-columns: 1fr auto; gap: 15px; padding: 12px 15px; background: #f8f9fa; font-weight: 600; font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; border-bottom: 1px solid #e0e0e0; }
        .file-row { display: grid; grid-template-columns: 1fr auto; gap: 15px; padding: 12px 15px; border-bottom: 1px solid #f0f0f0; transition: background 0.15s; align-items: center; }
        .file-row:last-child { border-bottom: none; }
        .file-row:hover { background: #f8f9fa; }
        .file-name { color: #2d3748; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', 'Helvetica Neue', sans-serif; font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; text-align: left; }
        .file-size { color: #063773; font-weight: 600; font-size: 13px; text-align: right; white-space: nowrap; }
        
        .top-files { margin-top: 20px; }
        .top-files h4 { font-size: 16px; margin-bottom: 15px; color: #333; display: flex; align-items: center; gap: 10px; }
        /* Compressed size of the compiled catalog the rows beneath were unpacked from.
           Already in `top`, so already in the download total: annotate, do not add. */
        .top-files h4 .catalog-note { color: #666; font-size: 12px; font-weight: 400; }
        .file-item { display: flex; justify-content: space-between; padding: 10px; background: white; margin-bottom: 5px; border-radius: 4px; font-size: 13px; border-left: 4px solid #e0e0e0; transition: all 0.2s; }
        .file-item:hover { box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .file-path { color: #666; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', 'Helvetica Neue', sans-serif; }
        .file-size-value { color: #333; font-weight: 500; margin-left: 15px; }
        .file-type-badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 10px; font-weight: 600; text-transform: uppercase; margin-right: 8px; }
        
        .file-type-image { border-left-color: #3498db; }
        .file-type-image .file-type-badge { background: #e3f2fd; color: #1976d2; }
        
        .file-type-lottie { border-left-color: #9b59b6; }
        .file-type-lottie .file-type-badge { background: #f3e5f5; color: #7b1fa2; }
        
        .file-type-pdf { border-left-color: #e74c3c; }
        .file-type-pdf .file-type-badge { background: #ffebee; color: #c62828; }
        
        .file-type-video { border-left-color: #e67e22; }
        .file-type-video .file-type-badge { background: #fff3e0; color: #e65100; }
        
        .file-type-audio { border-left-color: #1abc9c; }
        .file-type-audio .file-type-badge { background: #e0f2f1; color: #00695c; }
        
        .file-type-font { border-left-color: #34495e; }
        .file-type-font .file-type-badge { background: #eceff1; color: #37474f; }
        
        .file-type-other { border-left-color: #95a5a6; }
        .file-type-other .file-type-badge { background: #f5f5f5; color: #616161; }
        
        .no-results { text-align: center; padding: 60px 20px; color: #999; font-size: 16px; }
        .no-data { padding: 15px; color: #999; font-style: italic; text-align: center; }
        
        .d3-tooltip {
            position: absolute;
            background: rgba(0, 0, 0, 0.9);
            color: white;
            padding: 12px 16px;
            border-radius: 6px;
            font-size: 13px;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.2s;
            z-index: 1000;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        }
        .d3-tooltip.visible { opacity: 1; }
        .d3-tooltip-owner { font-weight: bold; margin-bottom: 6px; font-size: 14px; }
        .d3-tooltip-row { margin: 3px 0; display: flex; align-items: center; gap: 8px; }
        .d3-tooltip-color { width: 12px; height: 12px; border-radius: 2px; display: inline-block; }
        .ownership-chart-container { position: relative; width: 100%; overflow-x: auto; }
        .axis text { font-size: 12px; fill: #666; }
        .axis line, .axis path { stroke: #e0e0e0; }
        .grid line { stroke: #e0e0e0; stroke-dasharray: 3,3; }
        .bar { cursor: pointer; transition: opacity 0.2s; }
        .bar:hover { opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1 id="headerTitle">📱 App Size Report</h1>
            <p id="headerSubtitle">Detailed analysis of app module sizes and resources</p>
        </header>
        
        <div class="tabs">
            <div class="tab active" onclick="switchTab('breakdown', this)">Breakdown</div>
            <div class="tab" onclick="switchTab('insights', this)">Insights</div>
            <div class="tab" onclick="switchTab('ownership', this)">Ownership</div>
        </div>
        
        <!-- Breakdown Tab -->
        <div id="breakdown" class="tab-content active">
            <div class="summary" id="summary"></div>
            <div class="controls">
                <input type="text" id="searchInput" placeholder="Search modules..." />
                <!-- Populated from the owners actually present, so a team that owns
                     nothing cannot be selected. An owner badge filters to the same
                     value; see selectTeamFilter. -->
                <select id="teamFilterSelect">
                    <option value="">All teams</option>
                </select>
                <div class="filter-chips">
                    <div class="filter-chip active" data-filter="internal" onclick="toggleBreakdownFilter('internal')">Internal</div>
                    <div class="filter-chip active" data-filter="external" onclick="toggleBreakdownFilter('external')">External</div>
                    <div class="filter-chip active" data-filter="owned" onclick="toggleBreakdownFilter('owned')">Owned</div>
                    <div class="filter-chip active" data-filter="unowned" onclick="toggleBreakdownFilter('unowned')">Unowned</div>
                </div>
                <select id="sortSelect">
                    <option value="downloadSize">Sort by: Download Size</option>
                    <option value="installSize">Sort by: Install Size</option>
                    <option value="name">Sort by: Name</option>
                </select>
            </div>
            <div class="modules-grid" id="modulesGrid"></div>
        </div>
        
        <!-- Insights Tab -->
        <div id="insights" class="tab-content">
            <!-- Filter Controls -->
            <div style="padding: 20px 30px; background: white; border-bottom: 1px solid #e0e0e0; display: flex; justify-content: space-between; align-items: center; gap: 15px; flex-wrap: wrap;">
                <div class="filter-chips">
                    <div class="filter-chip active" data-filter="internal" onclick="toggleInsightsFilter('internal')">Internal</div>
                    <div class="filter-chip active" data-filter="external" onclick="toggleInsightsFilter('external')">External</div>
                </div>
                <!-- Download is what the user fetches, install is what lands on the
                     device. Both readings of "size", and they differ by the app's
                     compression ratio, so the page can show either. It drives the
                     sections that have both figures; the ones that do not are labelled
                     with their unit instead. -->
                <select id="insightsSizeSelect" style="padding: 10px 15px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; background: white; cursor: pointer;">
                    <option value="installSize">Size: Install (uncompressed)</option>
                    <option value="downloadSize">Size: Download (compressed)</option>
                </select>
            </div>

            <!-- Top Offenders Dashboard -->
            <div style="padding: 30px; background: white; border-bottom: 1px solid #e0e0e0;">
                <h2 style="font-size: 20px; color: #333; margin-bottom: 20px;">🔥 Top Offenders</h2>
                <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 30px;">
                    <div style="min-width: 0; overflow: hidden;">
                        <h3 style="font-size: 16px; color: #666; margin-bottom: 15px;">Largest Modules</h3>
                        <div id="topModulesChart"></div>
                    </div>
                    <div style="min-width: 0; overflow: hidden;">
                        <h3 style="font-size: 16px; color: #666; margin-bottom: 15px;">Largest Source Files <span style="font-size: 11px; color: #999; font-weight: 400;">uncompressed</span></h3>
                        <div id="topFilesChart"></div>
                    </div>
                    <div style="min-width: 0; overflow: hidden;">
                        <h3 style="font-size: 16px; color: #666; margin-bottom: 15px;">Largest Resources</h3>
                        <div id="topResourcesChart"></div>
                    </div>
                </div>
            </div>

            <!-- Treemap Visualization -->
            <div style="padding: 30px; background: #f8f9fa; border-bottom: 1px solid #e0e0e0;">
                <h2 style="font-size: 20px; color: #333; margin-bottom: 10px;">🗺️ App Size Treemap</h2>
                <p style="color: #666; font-size: 14px; margin-bottom: 20px;">Interactive visualization of all modules sized proportionally. Click to explore.</p>
                <div id="treemapChart" style="background: white; border-radius: 8px; overflow: hidden;"></div>
            </div>

            <!-- Resource Type Breakdown -->
            <div style="padding: 30px; background: white; border-bottom: 1px solid #e0e0e0;">
                <h2 style="font-size: 20px; color: #333; margin-bottom: 20px;">📦 Resource Type Breakdown</h2>
                <p style="font-size: 12px; color: #999; margin: -10px 0 20px 0;">Compressed — the size each file contributes to the download. Per-type uncompressed figures are not recorded, so this section does not follow the size control above.</p>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); gap: 30px; justify-items: center;">
                    <div style="width: 100%; max-width: 400px;">
                        <h3 style="font-size: 16px; color: #666; margin-bottom: 15px; text-align: center;">By Count</h3>
                        <div id="resourceCountChart"></div>
                    </div>
                    <div style="width: 100%; max-width: 400px;">
                        <h3 style="font-size: 16px; color: #666; margin-bottom: 15px; text-align: center;">By Size (Compressed)</h3>
                        <div id="resourceSizeChart"></div>
                    </div>
                </div>
                <div id="resourceLegend" style="margin-top: 30px; display: flex; flex-wrap: wrap; justify-content: center; gap: 20px;"></div>
            </div>
            
            <!-- User Impact Score -->
            <div style="padding: 30px; background: #f8f9fa;">
                <h2 style="font-size: 20px; color: #333; margin-bottom: 20px;">👤 User Impact</h2>
                <div id="userImpactSection"></div>
            </div>
        </div>
        
        <!-- Ownership Tab -->
        <div id="ownership" class="tab-content">
            <div style="padding: 30px; background: white;">
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 30px; flex-wrap: wrap; gap: 20px;">
                    <div>
                        <h2 style="font-size: 20px; color: #333; margin-bottom: 10px;">Ownership overview</h2>
                        <p style="color: #666; font-size: 14px;">Shows how much of the overall app size is owned by each owner.</p>
                        <p style="color: #999; font-size: 12px; margin-top: 8px; max-width: 640px;">The chart counts each module once, under its first owner, so the teams add up to the app. The list below counts a shared module in full for every team that owns it, so its totals add up to more than the app — there is no honest way to split a framework's bytes between two teams.</p>
                    </div>
                    <div style="display: flex; gap: 15px; align-items: center;">
                        <div class="filter-chips">
                            <div class="filter-chip active" data-filter="internal" onclick="toggleOwnershipFilter('internal')">Internal</div>
                            <div class="filter-chip active" data-filter="external" onclick="toggleOwnershipFilter('external')">External</div>
                        </div>
                        <select id="ownershipSortSelect" style="padding: 10px 15px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; background: white; cursor: pointer;">
                            <option value="downloadSize">Sort by: Download Size</option>
                            <option value="installSize">Sort by: Install Size</option>
                        </select>
                    </div>
                </div>
                <div class="ownership-chart-container">
                    <div id="ownershipChart"></div>
                </div>
            </div>
            <div style="padding: 30px; background: #f8f9fa; border-top: 1px solid #e0e0e0;">
                <h2 style="font-size: 20px; color: #333; margin-bottom: 20px;">Components and files grouped by owner</h2>
                <select id="ownerDropdown" style="width: 100%; padding: 12px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px; background: white; cursor: pointer;">
                    <option value="">Select an owner...</option>
                </select>
            </div>
            <div id="ownerDetailSection" style="display: none;">
                <div id="ownerDetailSummary" style="padding: 30px; background: white; border-top: 1px solid #e0e0e0; display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 30px;"></div>
                <div style="padding: 0 30px 30px 30px; background: white;">
                    <div class="modules-grid" id="ownerModulesGrid"></div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        const data = __DATA__;
        let currentTab = 'breakdown';
        let currentSort = 'downloadSize';
        let breakdownFilters = { internal: true, external: true, owned: true, unowned: true };
        // '' means no team filter. Drives the dropdown and the badges together.
        let breakdownTeamFilter = '';
        let insightsFilters = { internal: true, external: true };
        let ownershipFilters = { internal: true, external: true };
        
        function updateHeader() {
            if (data.appInfo) {
                const appInfo = data.appInfo;
                let title = '📱 ';
                let subtitle = 'Detailed analysis of app module sizes and resources';
                
                if (appInfo.appName) {
                    title += appInfo.appName;
                } else {
                    title += 'App Size Report';
                }
                
                const subtitleParts = [];
                if (appInfo.version) {
                    subtitleParts.push('Version ' + appInfo.version);
                }
                if (appInfo.bundleIdentifier) {
                    subtitleParts.push(appInfo.bundleIdentifier);
                }
                
                if (subtitleParts.length > 0) {
                    subtitle = subtitleParts.join(' • ');
                }
                
                document.getElementById('headerTitle').textContent = title;
                document.getElementById('headerSubtitle').textContent = subtitle;
            }
        }
        
        function switchTab(tabName, el) {
            currentTab = tabName;
            document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
            if (el) el.classList.add('active');
            document.getElementById(tabName).classList.add('active');

            // Rendered once: the charts are static, and re-rendering on every visit
            // appended a fresh set of tooltips each time. The flag is set before the
            // timer, so a second click cannot queue a duplicate render.
            if (tabName === 'insights' && !insightsRendered) {
                insightsRendered = true;
                // Deferred so the tab is laid out and the charts can measure it.
                setTimeout(renderInsights, 100);
            }
        }
        
        function formatBytes(bytes) {
            if (bytes === 0) return '0 B';
            const k = 1024;
            const sizes = ['B', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
        }
        
        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        
        function toggleBreakdownFilter(filter) {
            breakdownFilters[filter] = !breakdownFilters[filter];
            document.querySelectorAll('#breakdown .filter-chip').forEach(chip => {
                if (chip.dataset.filter === filter) {
                    chip.classList.toggle('active', breakdownFilters[filter]);
                }
            });
            renderModules(document.getElementById('searchInput').value, currentSort);
        }
        
        function toggleInsightsFilter(filter) {
            insightsFilters[filter] = !insightsFilters[filter];
            document.querySelectorAll('#insights .filter-chip').forEach(chip => {
                if (chip.dataset.filter === filter) {
                    chip.classList.toggle('active', insightsFilters[filter]);
                }
            });
            renderInsights();
        }

        document.getElementById('insightsSizeSelect').addEventListener('change', (e) => {
            setInsightsSizeBasis(e.target.value);
        });

        function toggleOwnershipFilter(filter) {
            ownershipFilters[filter] = !ownershipFilters[filter];
            document.querySelectorAll('#ownership .filter-chip').forEach(chip => {
                if (chip.dataset.filter === filter) {
                    chip.classList.toggle('active', ownershipFilters[filter]);
                }
            });
            ownershipChartData = prepareOwnershipChartData(currentOwnershipSort);
            ownerGroupData = prepareOwnerGroupData(currentOwnershipSort);
            renderOwnershipChart();
            populateOwnerDropdown();
            document.getElementById('ownerDropdown').value = '';
            document.getElementById('ownerDetailSection').style.display = 'none';
        }

        // Primary first, de-duplicated: a hand-written file can repeat the primary in
        // `additionalOwners`.
        function allOwners(module) {
            const owners = [];
            if (module.owner) owners.push(module.owner);
            (module.additionalOwners || []).forEach(owner => {
                if (owner && !owners.includes(owner)) owners.push(owner);
            });
            return owners;
        }

        // Includes co-owners, who are never a module's primary.
        function collectAllTeams() {
            const teams = new Set();
            Object.values(data.modules).forEach(module => {
                allOwners(module).forEach(team => teams.add(team));
            });
            return [...teams].sort((a, b) => a.localeCompare(b));
        }

        // Clicking the selected team clears the filter, so a badge toggles.
        function selectTeamFilter(team) {
            breakdownTeamFilter = breakdownTeamFilter === team ? '' : (team || '');
            document.getElementById('teamFilterSelect').value = breakdownTeamFilter;
            renderModules(document.getElementById('searchInput').value, currentSort);
        }

        function populateTeamFilterSelect() {
            const select = document.getElementById('teamFilterSelect');
            const current = breakdownTeamFilter;
            select.innerHTML = '<option value="">All teams</option>';
            collectAllTeams().forEach(team => {
                const option = document.createElement('option');
                option.value = team;
                option.textContent = team;
                select.appendChild(option);
            });
            // A filter elsewhere can empty a team out and drop its option, which would leave
            // the select blank rather than showing the filter that is active.
            select.value = current;
            if (select.value !== current) breakdownTeamFilter = '';
        }

        // `filterable` is off for the owner detail cards: those sit on the Ownership tab,
        // where the breakdown filter does not apply, so a badge that looked clickable
        // there would do nothing.
        function renderOwnerBadges(module, filterable = true) {
            const owners = allOwners(module);
            if (!owners.length) return '';
            return owners.map((owner, index) => {
                const additional = index > 0 ? ' additional' : '';
                if (!filterable) {
                    return `<span class="owner-badge${additional}" title="${escapeHtml(owner)}">${escapeHtml(owner)}</span>`;
                }
                const selected = owner === breakdownTeamFilter ? ' team-selected' : '';
                const why = owner === breakdownTeamFilter ? 'Clear the team filter' : `Filter to ${owner}`;
                return `<span class="owner-badge owner-badge-filter${additional}${selected}" data-owner="${escapeHtml(owner)}" title="${escapeHtml(why)}">${escapeHtml(owner)}</span>`;
            }).join('');
        }

        function moduleMatchesBreakdownFilters(module) {
            const isInternal = module.internal === true;
            const internalMatch = (isInternal && breakdownFilters.internal) || (!isInternal && breakdownFilters.external);
            if (!internalMatch) return false;

            const isOwned = module.owner && module.owner.toLowerCase() !== 'others';
            const ownedMatch = (isOwned && breakdownFilters.owned) || (!isOwned && breakdownFilters.unowned);
            if (!ownedMatch) return false;

            // Matches on any owner, so a shared module stays visible to both teams.
            if (breakdownTeamFilter && !allOwners(module).includes(breakdownTeamFilter)) return false;

            return true;
        }
        
        function moduleMatchesInsightsFilters(module) {
            const isInternal = module.internal === true;
            return (isInternal && insightsFilters.internal) || (!isInternal && insightsFilters.external);
        }
        
        function moduleMatchesOwnershipFilters(module) {
            const isInternal = module.internal === true;
            return (isInternal && ownershipFilters.internal) || (!isInternal && ownershipFilters.external);
        }
        
        // Two sections, not one list with a marker on the catalog rows: a marker has to
        // be glued to the file name, and the name is what the type badge is derived from,
        // so "bus.svg (in catalog)" matched no file type and lost every asset its colour.
        function renderModuleResources(module) {
    const files = Object.entries(module.top || {})
        .filter(([path]) => !path.toLowerCase().endsWith('.car') && !path.endsWith('/'))
        .sort((a, b) => b[1] - a[1]);
    const catalog = Object.entries(module.assetCatalogFiles || {})
        .sort((a, b) => b[1] - a[1]);

    if (files.length === 0 && catalog.length === 0) return '';

    return `
        ${files.length > 0 ? `
        <div class="top-files">
            <h4>Resources <span class="count-badge">${files.length}</span></h4>
            ${files.map(renderResourceRow).join('')}
        </div>` : ''}
        ${catalog.length > 0 ? `
        <div class="top-files">
            <h4>
                Asset Catalog
                <span class="count-badge">${catalog.length}</span>
                <span class="catalog-note">${compiledCatalogNote(module)}</span>
            </h4>
            ${catalog.map(renderResourceRow).join('')}
        </div>` : ''}
    `;
}

function renderResourceRow([path, size]) {
    const fileInfo = getFileTypeInfo(path);
    return `<div class="file-item ${fileInfo.class}"><span class="file-path" title="${escapeHtml(path)}"><span class="file-type-badge">${fileInfo.label}</span>${escapeHtml(path)}</span><span class="file-size-value">${formatBytes(size)}</span></div>`;
}

// Compressed size of the .car these rows were unpacked from. The rows are the same
// bytes expanded, so this annotates their unit rather than adding to them.
function compiledCatalogNote(module) {
    const compiled = Object.entries(module.top || {})
        .filter(([path]) => path.toLowerCase().endsWith('.car'))
        .reduce((sum, [, size]) => sum + (size || 0), 0);
    return compiled > 0 ? `${formatBytes(compiled)} compiled` : 'compiled size unknown';
}

// The extension is dropped so the axis's ~20-character truncation does not cut the
// word that says what the row is. The full path is in the tooltip either way.
function catalogLabel(carPath) {
    const parts = carPath.split('/').filter(Boolean);
    const container = parts.length >= 2 ? parts[parts.length - 2] : 'app';
    const dot = container.lastIndexOf('.');
    return `${dot > 0 ? container.slice(0, dot) : container} catalog`;
}

// The module's total across all of its catalogs, not a per-catalog count:
// `assetCatalogFiles` is flat. Exact for the usual one-catalog bundle.
function catalogAssetCount(module) {
    return Object.keys(module.assetCatalogFiles || {}).length;
}

function getFileTypeInfo(filePath) {
            // `split('.').pop()` would return a dotless name whole, badging AccentColor
            // as ACCENTCOLOR.
            const name = filePath.split('/').pop();
            const dot = name.lastIndexOf('.');
            const ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : '';
            
            if (['png', 'jpg', 'jpeg', 'gif', 'svg', 'heic', 'heif', 'webp', 'bmp', 'tiff', 'tif'].includes(ext)) {
                return { type: 'image', label: ext.toUpperCase(), class: 'file-type-image' };
            }
            
            if (ext === 'json') {
                // Name is the only signal: a .json in a bundle is usually Lottie.
                if (filePath.toLowerCase().includes('lottie') || filePath.toLowerCase().includes('animation')) {
                    return { type: 'lottie', label: 'LOTTIE', class: 'file-type-lottie' };
                }
                return { type: 'lottie', label: 'JSON', class: 'file-type-lottie' };
            }
            
            if (ext === 'pdf') {
                return { type: 'pdf', label: 'PDF', class: 'file-type-pdf' };
            }
            
            if (['mp4', 'mov', 'avi', 'mkv', 'm4v', 'mpg', 'mpeg', 'wmv', 'webm'].includes(ext)) {
                return { type: 'video', label: ext.toUpperCase(), class: 'file-type-video' };
            }
            
            if (['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'aiff', 'wma'].includes(ext)) {
                return { type: 'audio', label: ext.toUpperCase(), class: 'file-type-audio' };
            }
            
            if (['ttf', 'otf', 'woff', 'woff2', 'eot'].includes(ext)) {
                return { type: 'font', label: ext.toUpperCase(), class: 'file-type-font' };
            }
            
            // A dotless name is not a file type, so it is labelled by where it came from.
            return { type: 'other', label: ext ? ext.toUpperCase() : 'ASSET', class: 'file-type-other' };
        }
        
        function calculateModuleDownload(module) {
            // Compressed where a compressed figure exists. `binarySize` is excluded: with a
            // LinkMap it holds uncompressed output. `top` omits the main binary, so
            // `binaryCompressedSize` is counted here or a binary-only framework reports
            // zero. A statically linked module has no container, so that sum is zero and
            // says nothing; its LinkMap size is uncompressed and is reported instead.
            if (module.staticallyLinked === true) return module.binarySize || 0;
            let total = (module.binaryCompressedSize || 0);
            if (!module.top) return total;
            return total + Object.values(module.top).reduce((sum, v) => sum + (v || 0), 0);
        }

        function calculateModuleTotal(module) {
            // Already the uncompressed sum, computed once on the Swift side. It must not be
            // recomputed here as `binarySize + imageFileSize + sum(resources)`, which
            // double-counts images: the parsers record each in both places.
            return module.proguard || 0;
        }
        
        function renderSummary() {
            const totalPackageSize = data.totalPackageSize || 0;
            const totalInstallSize = data.totalInstallSize || 0;
            const allModules = Object.values(data.modules);
            const moduleCount = allModules.length;

            const internalModules = allModules.filter(m => m.internal === true);
            const internalCount = internalModules.length;
            const internalInstallSize = internalModules.reduce((sum, m) => sum + calculateModuleTotal(m), 0);

            const internalDownloadSize = internalModules.reduce((sum, m) => sum + calculateModuleDownload(m), 0);
            
            document.getElementById('summary').innerHTML = `
                <div class="summary-card">
                    <h3>Download Size</h3>
                    <div class="value">${formatBytes(totalPackageSize)}</div>
                    <div class="label">Compressed IPA</div>
                    ${internalCount > 0 ? `<div class="internal-info">Internal: ${formatBytes(internalDownloadSize)}</div>` : ''}
                </div>
                <div class="summary-card">
                    <h3>Install Size</h3>
                    <div class="value">${formatBytes(totalInstallSize)}</div>
                    <div class="label">Uncompressed</div>
                    ${internalCount > 0 ? `<div class="internal-info">Internal: ${formatBytes(internalInstallSize)}</div>` : ''}
                </div>
                <div class="summary-card">
                    <h3>Modules</h3>
                    <div class="value">${moduleCount}</div>
                    <div class="label">Total Count</div>
                    ${internalCount > 0 ? `<div class="internal-info">Internal: ${internalCount}</div>` : ''}
                </div>
            `;
        }
        
        function renderModules(searchTerm = '', sortBy = 'downloadSize') {
            currentSort = sortBy;
            let modules = Object.values(data.modules);
            
            if (searchTerm) {
                modules = modules.filter(m => m.name.toLowerCase().includes(searchTerm.toLowerCase()));
            }
            
            modules = modules.filter(m => moduleMatchesBreakdownFilters(m));
            
            modules.sort((a, b) => {
                switch(sortBy) {
                    case 'downloadSize':
                        return calculateModuleDownload(b) - calculateModuleDownload(a);
                    case 'installSize':
                        return calculateModuleTotal(b) - calculateModuleTotal(a);
                    case 'name':
                        return a.name.localeCompare(b.name);
                    default:
                        return 0;
                }
            });
            
            const grid = document.getElementById('modulesGrid');
            if (modules.length === 0) {
                grid.innerHTML = '<div class="no-results">No modules found</div>';
                return;
            }
            
            const maxSize = Math.max(...modules.map(m => calculateModuleTotal(m)));
            
            grid.innerHTML = modules.map((module, index) => {
                const totalSize = calculateModuleTotal(module);
                const binaryPercent = maxSize > 0 ? (module.binarySize || 0) / maxSize * 100 : 0;
                const imagePercent = maxSize > 0 ? (module.imageFileSize || 0) / maxSize * 100 : 0;
                
                // Named "Resource Types" to keep it distinct from the "Resources" list below.
                const resourcesHTML = Object.keys(module.resources || {}).length > 0 ? `
                    <h4 style="margin-top: 20px; margin-bottom: 15px; color: #333;">Resource Types</h4>
                    <div class="resources-grid">
                        ${Object.entries(module.resources).map(([type, res]) => `
                            <div class="resource-card">
                                <div class="resource-type">${escapeHtml(type)}</div>
                                <div class="resource-size">${formatBytes(res.size)}</div>
                                <div class="resource-count">${res.count} files</div>
                            </div>
                        `).join('')}
                    </div>
                ` : '';

                const topFilesHTML = renderModuleResources(module);

                const sourceFiles = module.files || [];
                const filesHTML = sourceFiles.length > 0 ? `
                    <div class="files-section">
                        <h4>
                            Source Files
                            <span class="count-badge">${sourceFiles.length}</span>
                        </h4>
                        <div class="files-table">
                            <div class="files-table-header">
                                <div>File Name</div>
                                <div>Size</div>
                            </div>
                            ${sourceFiles.map(file => `<div class="file-row"><div class="file-name" title="${escapeHtml(file.fileName)}">${escapeHtml(file.fileName)}</div><div class="file-size">${formatBytes(file.size)}</div></div>`).join('')}
                        </div>
                    </div>
                ` : '';
                
                // Must come from the same function the sort used, or the column
                // contradicts its own ordering.
                const displaySize = currentSort === 'installSize'
                    ? calculateModuleTotal(module)
                    : calculateModuleDownload(module);
                const displayLabel = currentSort === 'installSize' ? 'Install' : 'Download';
                
                return `
                    <div class="module-card">
                        <div class="module-header" onclick="toggleModule(${index})">
                            <div class="module-info">
                                <div class="module-name-row">
                                    ${escapeHtml(module.name)}
                                    ${module.version ? `<span class="module-version">:${module.version}</span>` : ''}
                                </div>
                                ${renderOwnerBadges(module)}
                                ${module.internal ? `<span class="internal-badge">Internal</span>` : ''}
                            </div>
                            <div class="module-stats">
                                <div class="module-stat">
                                    <span class="module-stat-label">${displayLabel}</span>
                                    <span class="module-size">${formatBytes(displaySize)}</span>
                                </div>
                                <span class="expand-icon" id="icon-${index}">▼</span>
                            </div>
                        </div>
                        <div class="module-details" id="module-${index}">
                            <div class="size-bars">
                                <div class="size-bar">
                                    <div class="size-bar-label">
                                        <span class="name">Binary Size</span>
                                        <span class="value">${formatBytes(module.binarySize || 0)}</span>
                                    </div>
                                    <div class="size-bar-fill">
                                        <div class="size-bar-progress" style="width: ${binaryPercent}%"></div>
                                    </div>
                                </div>
                                <div class="size-bar">
                                    <div class="size-bar-label">
                                        <span class="name">Image Assets</span>
                                        <span class="value">${formatBytes(module.imageFileSize || 0)}</span>
                                    </div>
                                    <div class="size-bar-fill">
                                        <div class="size-bar-progress" style="width: ${imagePercent}%"></div>
                                    </div>
                                </div>
                                <div class="size-bar">
                                    <div class="size-bar-label">
                                        <span class="name">Total (Install Size)</span>
                                        <span class="value">${formatBytes(totalSize)}</span>
                                    </div>
                                    <div class="size-bar-fill">
                                        <div class="size-bar-progress" style="width: 100%"></div>
                                    </div>
                                </div>
                            </div>
                            ${resourcesHTML}
                            ${topFilesHTML}
                            ${filesHTML}
                        </div>
                    </div>
                `;
            }).join('');
        }
        
        function toggleModule(index) {
            document.getElementById(`module-${index}`).classList.toggle('open');
            document.getElementById(`icon-${index}`).classList.toggle('open');
        }
        
        document.getElementById('searchInput').addEventListener('input', (e) => {
            renderModules(e.target.value, document.getElementById('sortSelect').value);
        });
        
        document.getElementById('sortSelect').addEventListener('change', (e) => {
            renderModules(document.getElementById('searchInput').value, e.target.value);
        });
        
        // Two groupings, on purpose: the chart partitions the app by primary owner so
        // its bars sum to the app, while the per-team list attributes a shared module
        // in full to every team that owns it, so its totals exceed the app. Collapsing
        // them would mean either double-counting or under-reporting a team.
        let ownershipChartData = [];
        let ownerGroupData = [];
        let currentOwnershipSort = 'downloadSize';

        // Same two size functions the breakdown tab uses, so the totals agree.
        function summariseOwner(name, moduleList) {
            return {
                name: name,
                modules: moduleList,
                moduleCount: moduleList.length,
                fileCount: moduleList.reduce((sum, m) => sum + (m.files ? m.files.length : 0), 0),
                totalDownloadSize: moduleList.reduce((sum, m) => sum + calculateModuleDownload(m), 0),
                totalInstallSize: moduleList.reduce((sum, m) => sum + calculateModuleTotal(m), 0)
            };
        }

        function sortOwners(ownerData, sortBy) {
            if (sortBy === 'installSize') {
                return ownerData.sort((a, b) => b.totalInstallSize - a.totalInstallSize);
            }
            return ownerData.sort((a, b) => b.totalDownloadSize - a.totalDownloadSize);
        }

        function prepareOwnershipChartData(sortBy = 'downloadSize') {
            const modulesByOwner = {};
            let hasOwners = false;

            Object.values(data.modules).forEach(module => {
                if (!moduleMatchesOwnershipFilters(module)) return;

                const owner = module.owner || 'others';
                if (module.owner) hasOwners = true;

                if (!modulesByOwner[owner]) modulesByOwner[owner] = [];
                modulesByOwner[owner].push(module);
            });

            if (!hasOwners) return [];

            return sortOwners(
                Object.entries(modulesByOwner).map(([name, list]) => summariseOwner(name, list)),
                sortBy
            );
        }

        function prepareOwnerGroupData(sortBy = 'downloadSize') {
            const modulesByOwner = {};

            Object.values(data.modules).forEach(module => {
                if (!moduleMatchesOwnershipFilters(module)) return;

                const owners = allOwners(module);
                if (!owners.length) return;

                owners.forEach(owner => {
                    if (!modulesByOwner[owner]) modulesByOwner[owner] = [];
                    modulesByOwner[owner].push(module);
                });
            });

            return sortOwners(
                Object.entries(modulesByOwner).map(([name, list]) => summariseOwner(name, list)),
                sortBy
            );
        }
        
        function renderOwnershipChart() {
            const chartContainer = document.getElementById('ownershipChart');
            
            if (ownershipChartData.length === 0) {
                chartContainer.innerHTML = `
                    <div class="no-results">
                        <p>No ownership data available.</p>
                        <p style="font-size: 14px; margin-top: 10px; color: #666;">Run Caliper with the --ownership-file option to enable ownership tracking.</p>
                    </div>
                `;
                document.getElementById('ownerDropdown').disabled = true;
                return;
            }
            
            chartContainer.innerHTML = '';
            
            const margin = { top: 20, right: 30, bottom: 120, left: 80 };
            const barWidth = 40;
            const barGap = 10;
            const groupGap = 30;
            const groupWidth = (barWidth * 2) + barGap;
            const width = ownershipChartData.length * (groupWidth + groupGap) + margin.left + margin.right;
            const height = 450;
            const chartHeight = height - margin.top - margin.bottom;
            
            const totalDownloadSize = ownershipChartData.reduce((sum, d) => sum + d.totalDownloadSize, 0);
            const totalInstallSize = ownershipChartData.reduce((sum, d) => sum + d.totalInstallSize, 0);
            
            const tooltip = d3.select('body').append('div')
                .attr('class', 'd3-tooltip');
            
            const svg = d3.select('#ownershipChart')
                .append('svg')
                .attr('width', width)
                .attr('height', height)
                .style('display', 'block')
                .style('margin', '0 auto');
            
            const g = svg.append('g')
                .attr('transform', `translate(${margin.left},${margin.top})`);
            
            const x = d3.scaleBand()
                .domain(ownershipChartData.map(d => d.name))
                .range([0, width - margin.left - margin.right])
                .padding(0.3);
            
            const maxSize = d3.max(ownershipChartData, d => Math.max(d.totalDownloadSize, d.totalInstallSize));
            const y = d3.scaleLinear()
                .domain([0, maxSize])
                .nice()
                .range([chartHeight, 0]);
            
            g.append('g')
                .attr('class', 'grid')
                .call(d3.axisLeft(y)
                    .tickSize(-width + margin.left + margin.right)
                    .tickFormat('')
                );
            
            const yAxis = g.append('g')
                .attr('class', 'axis')
                .call(d3.axisLeft(y)
                    .tickFormat(d => formatBytes(d))
                    .ticks(5)
                );
            
            const xAxis = g.append('g')
                .attr('class', 'axis')
                .attr('transform', `translate(0,${chartHeight})`)
                .call(d3.axisBottom(x));
            
            xAxis.selectAll('text')
                .attr('transform', 'rotate(-55)')
                .style('text-anchor', 'end')
                .attr('dx', '-0.5em')
                .attr('dy', '0.5em')
                .style('font-size', '11px');
            
            const ownerGroups = g.selectAll('.owner-group')
                .data(ownershipChartData)
                .enter()
                .append('g')
                .attr('class', 'owner-group')
                .attr('transform', d => `translate(${x(d.name)},0)`);
            
            ownerGroups.append('rect')
                .attr('class', 'bar download-bar')
                .attr('x', 0)
                .attr('width', barWidth)
                .attr('y', chartHeight)
                .attr('height', 0)
                .attr('fill', '#063773')
                .attr('rx', 3)
                .on('mouseover', function(event, d) {
                    d3.select(this).style('opacity', 0.7);
                    const percentage = totalDownloadSize > 0 ? ((d.totalDownloadSize / totalDownloadSize) * 100).toFixed(1) : 0;
                    tooltip.html(`
                        <div class="d3-tooltip-owner">${escapeHtml(d.name)}</div>
                        <div class="d3-tooltip-row">
                            <span class="d3-tooltip-color" style="background: #063773;"></span>
                            <span>Download: ${formatBytes(d.totalDownloadSize)} (${percentage}%)</span>
                        </div>
                        <div class="d3-tooltip-row">
                            <span>${d.moduleCount} module(s)</span>
                        </div>
                    `)
                    .classed('visible', true)
                    .style('left', (event.pageX + 10) + 'px')
                    .style('top', (event.pageY - 10) + 'px');
                })
                .on('mouseout', function() {
                    d3.select(this).style('opacity', 1);
                    tooltip.classed('visible', false);
                })
                .on('click', function(event, d) {
                    showOwnerDetails(d.name);
                })
                .transition()
                .duration(800)
                .ease(d3.easeCubicOut)
                .attr('y', d => y(d.totalDownloadSize))
                .attr('height', d => chartHeight - y(d.totalDownloadSize));
            
            ownerGroups.append('rect')
                .attr('class', 'bar install-bar')
                .attr('x', barWidth + barGap)
                .attr('width', barWidth)
                .attr('y', chartHeight)
                .attr('height', 0)
                .attr('fill', '#2ecc71')
                .attr('rx', 3)
                .on('mouseover', function(event, d) {
                    d3.select(this).style('opacity', 0.7);
                    const percentage = totalInstallSize > 0 ? ((d.totalInstallSize / totalInstallSize) * 100).toFixed(1) : 0;
                    tooltip.html(`
                        <div class="d3-tooltip-owner">${escapeHtml(d.name)}</div>
                        <div class="d3-tooltip-row">
                            <span class="d3-tooltip-color" style="background: #2ecc71;"></span>
                            <span>Install: ${formatBytes(d.totalInstallSize)} (${percentage}%)</span>
                        </div>
                        <div class="d3-tooltip-row">
                            <span>${d.moduleCount} module(s), ${d.fileCount} file(s)</span>
                        </div>
                    `)
                    .classed('visible', true)
                    .style('left', (event.pageX + 10) + 'px')
                    .style('top', (event.pageY - 10) + 'px');
                })
                .on('mouseout', function() {
                    d3.select(this).style('opacity', 1);
                    tooltip.classed('visible', false);
                })
                .on('click', function(event, d) {
                    showOwnerDetails(d.name);
                })
                .transition()
                .duration(800)
                .ease(d3.easeCubicOut)
                .delay(100)
                .attr('y', d => y(d.totalInstallSize))
                .attr('height', d => chartHeight - y(d.totalInstallSize));
            
            const legend = svg.append('g')
                .attr('transform', `translate(${width / 2 - 100},${height - 25})`);
            
            legend.append('rect')
                .attr('x', 0)
                .attr('y', 0)
                .attr('width', 20)
                .attr('height', 12)
                .attr('fill', '#063773')
                .attr('rx', 2);
            
            legend.append('text')
                .attr('x', 25)
                .attr('y', 10)
                .style('font-size', '12px')
                .style('fill', '#333')
                .text('Download size');
            
            legend.append('rect')
                .attr('x', 130)
                .attr('y', 0)
                .attr('width', 20)
                .attr('height', 12)
                .attr('fill', '#2ecc71')
                .attr('rx', 2);
            
            legend.append('text')
                .attr('x', 155)
                .attr('y', 10)
                .style('font-size', '12px')
                .style('fill', '#333')
                .text('Install size');
        }
        
        // By name, not by index: the chart and the dropdown are built from different
        // groupings, so they do not share indices.
        function showOwnerDetails(ownerName) {
            const index = ownerGroupData.findIndex(owner => owner.name === ownerName);
            if (index === -1) return;
            document.getElementById('ownerDropdown').value = index;
            renderOwnerDetails(index);
            document.getElementById('ownerDetailSection').scrollIntoView({ behavior: 'smooth' });
        }

        function populateOwnerDropdown(autoSelectApp = false) {
            const dropdown = document.getElementById('ownerDropdown');
            
            if (ownerGroupData.length === 0) {
                dropdown.disabled = true;
                return;
            }
            
            dropdown.innerHTML = '<option value="">Select an owner...</option>';
            
            const ownerWithIndices = ownerGroupData.map((owner, index) => ({
                owner: owner,
                index: index
            }));
            
            const othersEntries = ownerWithIndices.filter(item => 
                item.owner.name.toLowerCase() === 'others' || 
                item.owner.name.toLowerCase() === 'other'
            );
            const regularEntries = ownerWithIndices.filter(item => 
                item.owner.name.toLowerCase() !== 'others' && 
                item.owner.name.toLowerCase() !== 'other'
            );
            
            regularEntries.sort((a, b) => a.owner.name.localeCompare(b.owner.name));
            
            const sortedEntries = [...regularEntries, ...othersEntries];
            
            let appOwnerIndex = null;
            sortedEntries.forEach(item => {
                const option = document.createElement('option');
                option.value = item.index;
                option.textContent = item.owner.name;
                dropdown.appendChild(option);
                
                    if (item.owner.name === 'App') {
                    appOwnerIndex = item.index;
                }
            });
            
            if (autoSelectApp && appOwnerIndex !== null) {
                dropdown.value = appOwnerIndex;
                renderOwnerDetails(appOwnerIndex);
            }
        }
        
        function renderOwnerDetails(ownerIndex) {
            const detailSection = document.getElementById('ownerDetailSection');
            
            if (ownerIndex === '') {
                detailSection.style.display = 'none';
                return;
            }
            
            const owner = ownerGroupData[ownerIndex];
            detailSection.style.display = 'block';
            
            const summaryDiv = document.getElementById('ownerDetailSummary');
            summaryDiv.innerHTML = `
                <div style="text-align: center;">
                    <div style="font-size: 36px; font-weight: bold; color: #333;">${owner.moduleCount}</div>
                    <div style="font-size: 14px; color: #666; margin-top: 5px;">Component(s)</div>
                </div>
                <div style="text-align: center;">
                    <div style="font-size: 36px; font-weight: bold; color: #333;">${owner.fileCount}</div>
                    <div style="font-size: 14px; color: #666; margin-top: 5px;">File(s)</div>
                </div>
                <div style="text-align: center;">
                    <div style="font-size: 36px; font-weight: bold; color: #063773;">${formatBytes(owner.totalDownloadSize)}</div>
                    <div style="font-size: 14px; color: #666; margin-top: 5px;">Download size</div>
                </div>
                <div style="text-align: center;">
                    <div style="font-size: 36px; font-weight: bold; color: #2ecc71;">${formatBytes(owner.totalInstallSize)}</div>
                    <div style="font-size: 14px; color: #666; margin-top: 5px;">Install size</div>
                </div>
            `;
            
            const modulesGrid = document.getElementById('ownerModulesGrid');
            // A list, not a map: a module can appear under several teams.
            const modules = owner.modules
                .slice()
                .sort((a, b) => calculateModuleDownload(b) - calculateModuleDownload(a));

            const maxModuleSize = modules.length
                ? Math.max(...modules.map(m => calculateModuleTotal(m)))
                : 0;

            modulesGrid.innerHTML = modules.map((module, index) => {
                const moduleName = module.name;
                const totalSize = calculateModuleTotal(module);
                const binaryPercent = maxModuleSize > 0 ? (module.binarySize || 0) / maxModuleSize * 100 : 0;
                const imagePercent = maxModuleSize > 0 ? (module.imageFileSize || 0) / maxModuleSize * 100 : 0;
                
                // Named "Resource Types" to keep it distinct from the "Resources" list below.
                const resourcesHTML = Object.keys(module.resources || {}).length > 0 ? `
                    <h4 style="margin-top: 20px; margin-bottom: 15px; color: #333;">Resource Types</h4>
                    <div class="resources-grid">
                        ${Object.entries(module.resources).map(([type, res]) => `
                            <div class="resource-card">
                                <div class="resource-type">${escapeHtml(type)}</div>
                                <div class="resource-size">${formatBytes(res.size)}</div>
                                <div class="resource-count">${res.count} files</div>
                            </div>
                        `).join('')}
                    </div>
                ` : '';

                const topFilesHTML = renderModuleResources(module);

                const sourceFiles = module.files || [];
                const filesHTML = sourceFiles.length > 0 ? `
                    <div class="files-section">
                        <h4>
                            Source Files
                            <span class="count-badge">${sourceFiles.length}</span>
                        </h4>
                        <div class="files-table">
                            <div class="files-table-header">
                                <div>File Name</div>
                                <div>Size</div>
                            </div>
                            ${sourceFiles.map(file => `<div class="file-row"><div class="file-name" title="${escapeHtml(file.fileName)}">${escapeHtml(file.fileName)}</div><div class="file-size">${formatBytes(file.size)}</div></div>`).join('')}
                        </div>
                    </div>
                ` : '';
                
                return `
                    <div class="module-card">
                        <div class="module-header" onclick="toggleOwnerModule(${ownerIndex}, ${index})">
                            <div class="module-info">
                                <div class="module-name-row">
                                    ${moduleName}
                                    ${module.version ? `<span class="module-version">:${module.version}</span>` : ''}
                                </div>
                                ${renderOwnerBadges(module, false)}
                                ${module.internal ? `<span class="internal-badge">Internal</span>` : ''}
                            </div>
                            <div class="module-stats">
                                <div class="module-stat">
                                    <span class="module-stat-label">Download</span>
                                    <span class="module-size">${formatBytes(calculateModuleDownload(module))}</span>
                                </div>
                                <span class="expand-icon" id="owner-module-icon-${ownerIndex}-${index}">▼</span>
                            </div>
                        </div>
                        <div class="module-details" id="owner-module-${ownerIndex}-${index}">
                            <div class="size-bars">
                                <div class="size-bar">
                                    <div class="size-bar-label">
                                        <span class="name">Binary Size</span>
                                        <span class="value">${formatBytes(module.binarySize || 0)}</span>
                                    </div>
                                    <div class="size-bar-fill">
                                        <div class="size-bar-progress" style="width: ${binaryPercent}%"></div>
                                    </div>
                                </div>
                                <div class="size-bar">
                                    <div class="size-bar-label">
                                        <span class="name">Image Assets</span>
                                        <span class="value">${formatBytes(module.imageFileSize || 0)}</span>
                                    </div>
                                    <div class="size-bar-fill">
                                        <div class="size-bar-progress" style="width: ${imagePercent}%"></div>
                                    </div>
                                </div>
                                <div class="size-bar">
                                    <div class="size-bar-label">
                                        <span class="name">Total (Install Size)</span>
                                        <span class="value">${formatBytes(totalSize)}</span>
                                    </div>
                                    <div class="size-bar-fill">
                                        <div class="size-bar-progress" style="width: 100%"></div>
                                    </div>
                                </div>
                            </div>
                            ${resourcesHTML}
                            ${topFilesHTML}
                            ${filesHTML}
                        </div>
                    </div>
                `;
            }).join('');
        }
        
        function toggleOwnerModule(ownerIndex, moduleIndex) {
            document.getElementById(`owner-module-${ownerIndex}-${moduleIndex}`).classList.toggle('open');
            document.getElementById(`owner-module-icon-${ownerIndex}-${moduleIndex}`).classList.toggle('open');
        }
        
        document.getElementById('ownerDropdown').addEventListener('change', (e) => {
            renderOwnerDetails(e.target.value);
        });
        
        document.getElementById('ownershipSortSelect').addEventListener('change', (e) => {
            currentOwnershipSort = e.target.value;
            ownershipChartData = prepareOwnershipChartData(currentOwnershipSort);
            ownerGroupData = prepareOwnerGroupData(currentOwnershipSort);
            renderOwnershipChart();
            populateOwnerDropdown();
            document.getElementById('ownerDropdown').value = '';
            document.getElementById('ownerDetailSection').style.display = 'none';
        });

        document.getElementById('teamFilterSelect').addEventListener('change', (e) => {
            breakdownTeamFilter = e.target.value;
            renderModules(document.getElementById('searchInput').value, currentSort);
        });

        // Delegated: the cards are rebuilt on every render, so a per-card handler would
        // have to be reattached each time.
        document.querySelector('.container').addEventListener('click', (e) => {
            const badge = e.target.closest('.owner-badge-filter');
            if (!badge) return;
            // The card header also toggles.
            e.stopPropagation();
            selectTeamFilter(badge.dataset.owner);
        });

        updateHeader();
        renderSummary();
        populateTeamFilterSelect();
        renderModules();
        ownershipChartData = prepareOwnershipChartData(currentOwnershipSort);
        ownerGroupData = prepareOwnerGroupData(currentOwnershipSort);
        renderOwnershipChart();
        populateOwnerDropdown(true); // Auto-select "App" on initial page load
        
        // Declared here because `switchTab` runs before the DOM-ready block below.
        let insightsRendered = false;

        // Compressed download or uncompressed install.
        let insightsSizeBasis = 'installSize';

        // Read by every section that has both figures, so the control cannot leave two
        // charts disagreeing about what they are measuring.
        function moduleSizeForInsights(module) {
            return insightsSizeBasis === 'downloadSize'
                ? calculateModuleDownload(module)
                : calculateModuleTotal(module);
        }

        function setInsightsSizeBasis(basis) {
            if (insightsSizeBasis === basis) return;
            insightsSizeBasis = basis;
            // Nothing on the page to redraw before the first visit; the render-once flag
            // picks the basis up when it does.
            if (insightsRendered) renderInsights();
        }

        function renderInsights() {
            // Each chart appends its own tooltip and User Impact writes into a
            // container it never cleared, so re-rendering grows the DOM without bound.
            d3.select('body').selectAll('.d3-tooltip').remove();
            document.getElementById('userImpactSection').innerHTML = '';

            renderTopOffenders();
            renderTreemap();
            renderResourceBreakdown();
            renderUserImpact();
        }

        function renderTopOffenders() {
            const allModules = Object.values(data.modules);

            const modules = allModules.filter(m => moduleMatchesInsightsFilters(m));

            const topModules = modules
                .map(m => ({ name: m.name, size: moduleSizeForInsights(m), owner: m.owner }))
                .sort((a, b) => b.size - a.size)
                .slice(0, 20);
            
            const allFiles = [];
            modules.forEach(module => {
                if (module.files) {
                    module.files.forEach(file => {
                        allFiles.push({
                            name: file.fileName,
                            size: file.size,
                            module: module.name
                        });
                    });
                }
            });
            const topFiles = allFiles.sort((a, b) => b.size - a.size).slice(0, 20);
            
            // A catalog is the one resource with two honest representations, and which is
            // correct depends on the unit: the `.car` is one archive file and its
            // contents are not in the download, while the renditions are the installed
            // bytes and the container says nothing about them. So compressed, one row
            // per catalog carrying the asset count, since a bare path at 58.6 KB is not
            // actionable; uncompressed, the renditions individually. Listing both would
            // count the same bytes twice. The rest of the list has only a compressed
            // per-file figure, so the toggle moves the catalog alone.
            const allResources = [];
            const byDownload = insightsSizeBasis === 'downloadSize';
            modules.forEach(module => {
                // A framework's resources belong to its own module, not the app's list.
                if (module.internal !== true) return;

                if (module.top) {
                    Object.entries(module.top).forEach(([path, size]) => {
                        // The archive lists directory entries at 0 B.
                        if (path.endsWith('/')) return;
                        if (!path.toLowerCase().endsWith('.car')) {
                            allResources.push({
                                name: path,
                                size: size,
                                module: module.name
                            });
                            return;
                        }
                        if (!byDownload) return;
                        allResources.push({
                            name: catalogLabel(path),
                            size: size,
                            module: module.name,
                            catalog: true,
                            path: path,
                            assets: catalogAssetCount(module)
                        });
                    });
                }

                if (!byDownload && module.assetCatalogFiles) {
                    Object.entries(module.assetCatalogFiles).forEach(([name, size]) => {
                        allResources.push({
                            name: name,
                            size: size,
                            module: module.name,
                            inCatalog: true
                        });
                    });
                }
            });
            const topResources = allResources.sort((a, b) => b.size - a.size).slice(0, 20);
            
            renderHorizontalBarChart('topModulesChart', topModules, 'size', 'name', '#063773');
            
            renderHorizontalBarChart('topFilesChart', topFiles, 'size', 'name', '#e74c3c');
            
            renderHorizontalBarChart('topResourcesChart', topResources, 'size', 'name', '#3498db');
        }
        
        function renderHorizontalBarChart(containerId, data, sizeKey, nameKey, color) {
            const container = document.getElementById(containerId);
            container.innerHTML = '';
            
            if (data.length === 0) {
                container.innerHTML = '<div class="no-data">No data available</div>';
                return;
            }
            
            const containerWidth = container.offsetWidth || 400;
            const margin = { top: 10, right: 60, bottom: 30, left: 140 };
            const width = Math.max(containerWidth, 300);
            const height = data.length * 35 + margin.top + margin.bottom;
            
            const svg = d3.select('#' + containerId)
                .append('svg')
                .attr('width', '100%')
                .attr('height', height)
                .attr('viewBox', `0 0 ${width} ${height}`)
                .attr('preserveAspectRatio', 'xMidYMid meet');
            
            const g = svg.append('g')
                .attr('transform', `translate(${margin.left},${margin.top})`);
            
            const x = d3.scaleLinear()
                .domain([0, d3.max(data, d => d[sizeKey])])
                .range([0, width - margin.left - margin.right]);
            
            const y = d3.scaleBand()
                .domain(data.map((d, i) => i))
                .range([0, height - margin.top - margin.bottom])
                .padding(0.2);
            
            const tooltip = d3.select('body').append('div')
                .attr('class', 'd3-tooltip');
            
            g.selectAll('.bar')
                .data(data)
                .enter()
                .append('rect')
                .attr('class', 'bar')
                .attr('x', 0)
                .attr('y', (d, i) => y(i))
                .attr('width', 0)
                .attr('height', y.bandwidth())
                .attr('fill', color)
                .attr('rx', 3)
                .on('mouseover', function(event, d) {
                    d3.select(this).style('opacity', 0.7);
                    let tooltipContent = `
                        <div style="font-weight: bold; margin-bottom: 5px;">${escapeHtml(d[nameKey])}</div>
                        <div>Size: ${formatBytes(d[sizeKey])}</div>
                    `;
                    if (d.module) {
                        tooltipContent += `<div style="margin-top: 5px; color: #ffd700;">Module: ${escapeHtml(d.module)}</div>`;
                    }
                    if (d.inCatalog) {
                        tooltipContent += `<div style="margin-top: 5px; color: #ffd700;">In compiled asset catalog, uncompressed</div>`;
                    }
                    if (d.catalog) {
                        // The label names a container, so the count is what makes the row worth
                        // reading and the path is where to go looking.
                        tooltipContent += `<div style="margin-top: 5px; color: #ffd700;">Compiled asset catalog, ${d.assets} asset${d.assets === 1 ? '' : 's'}, compressed</div>`;
                        if (d.path) {
                            tooltipContent += `<div style="margin-top: 5px; color: #999; word-break: break-all;">${escapeHtml(d.path)}</div>`;
                        }
                    }
                    tooltip.html(tooltipContent)
                        .classed('visible', true)
                        .style('left', (event.pageX + 10) + 'px')
                        .style('top', (event.pageY - 10) + 'px');
                })
                .on('mouseout', function() {
                    d3.select(this).style('opacity', 1);
                    tooltip.classed('visible', false);
                })
                .transition()
                .duration(800)
                .attr('width', d => x(d[sizeKey]));
            
            g.selectAll('.label')
                .data(data)
                .enter()
                .append('text')
                .attr('class', 'label')
                .attr('x', -10)
                .attr('y', (d, i) => y(i) + y.bandwidth() / 2)
                .attr('text-anchor', 'end')
                .attr('dominant-baseline', 'middle')
                .style('font-size', '11px')
                .style('fill', '#333')
                .text(d => {
                    const name = d[nameKey];
                    const maxLen = Math.floor((margin.left - 20) / 6); // Approximate characters that fit
                    return name.length > maxLen ? name.substring(0, maxLen) + '...' : name;
                })
                .append('title')
                // The path a catalog row was collapsed from; the label is not a real filename.
                .text(d => d.path || d[nameKey]);
            
            g.selectAll('.size-label')
                .data(data)
                .enter()
                .append('text')
                .attr('class', 'size-label')
                .attr('x', d => x(d[sizeKey]) + 5)
                .attr('y', (d, i) => y(i) + y.bandwidth() / 2)
                .attr('text-anchor', 'start')
                .attr('dominant-baseline', 'middle')
                .style('font-size', '10px')
                .style('fill', '#666')
                .style('font-weight', 'bold')
                .text(d => formatBytes(d[sizeKey]));
        }
        
        function renderTreemap() {
            const container = document.getElementById('treemapChart');
            container.innerHTML = '';
            
            const allModules = Object.values(data.modules);
            
            const modules = allModules.filter(m => moduleMatchesInsightsFilters(m));
            
            // The tooltip's binary and asset figures follow the cell's unit, or a
            // compressed total sits above an uncompressed breakdown.
            const byDownload = insightsSizeBasis === 'downloadSize';
            const treemapData = {
                name: 'App',
                children: modules.map(m => ({
                    name: m.name,
                    value: moduleSizeForInsights(m),
                    binarySize: byDownload ? (m.binaryCompressedSize || 0) : (m.binarySize || 0),
                    imageSize: byDownload ? (m.imageSize || 0) : (m.imageFileSize || 0),
                    owner: m.owner
                }))
            };

            // Relative to what the treemap draws, not the whole-app total: the insights
            // filters can hide modules.
            const treemapTotal = d3.sum(treemapData.children, d => d.value);
            
            const containerWidth = container.offsetWidth || 1340;
            const width = containerWidth;
            const height = 600;
            
            const svg = d3.select('#treemapChart')
                .append('svg')
                .attr('width', '100%')
                .attr('height', height)
                .attr('viewBox', `0 0 ${width} ${height}`)
                .attr('preserveAspectRatio', 'xMidYMid meet');
            
            const color = d3.scaleOrdinal()
                .domain(modules.map(m => m.owner || 'others'))
                .range(d3.schemeTableau10);
            
            const root = d3.hierarchy(treemapData)
                .sum(d => d.value)
                .sort((a, b) => b.value - a.value);
            
            d3.treemap()
                .size([width, height])
                .padding(2)
                .round(true)
                (root);
            
            const tooltip = d3.select('body').append('div')
                .attr('class', 'd3-tooltip');
            
            const leaf = svg.selectAll('g')
                .data(root.leaves())
                .enter()
                .append('g')
                .attr('transform', d => `translate(${d.x0},${d.y0})`);
            
            leaf.append('rect')
                .attr('width', d => d.x1 - d.x0)
                .attr('height', d => d.y1 - d.y0)
                .attr('fill', d => color(d.data.owner || 'others'))
                .attr('opacity', 0.8)
                .attr('stroke', 'white')
                .attr('stroke-width', 2)
                .style('cursor', 'pointer')
                .on('mouseover', function(event, d) {
                    d3.select(this).attr('opacity', 1);
                    const percentage = treemapTotal > 0 ? ((d.value / treemapTotal) * 100).toFixed(1) : '0.0';
                    tooltip.html(`
                        <div style="font-weight: bold; margin-bottom: 5px;">${escapeHtml(d.data.name)}</div>
                        <div>Total: ${formatBytes(d.value)} (${percentage}%)</div>
                        <div>Binary: ${formatBytes(d.data.binarySize)}</div>
                        <div>Assets: ${formatBytes(d.data.imageSize)}</div>
                        <div style="margin-top: 5px; color: #999;">${byDownload ? 'Compressed' : 'Uncompressed'}</div>
                        ${d.data.owner ? `<div style="margin-top: 5px; color: #ffd700;">Owner: ${escapeHtml(d.data.owner)}</div>` : ''}
                    `)
                    .classed('visible', true)
                    .style('left', (event.pageX + 10) + 'px')
                    .style('top', (event.pageY - 10) + 'px');
                })
                .on('mouseout', function() {
                    d3.select(this).attr('opacity', 0.8);
                    tooltip.classed('visible', false);
                })
                .transition()
                .duration(800)
                .attrTween('width', function(d) {
                    const i = d3.interpolate(0, d.x1 - d.x0);
                    return t => i(t);
                })
                .attrTween('height', function(d) {
                    const i = d3.interpolate(0, d.y1 - d.y0);
                    return t => i(t);
                });
            
            leaf.append('text')
                .attr('x', 4)
                .attr('y', 16)
                .text(d => {
                    const width = d.x1 - d.x0;
                    const height = d.y1 - d.y0;
                    if (width > 80 && height > 30) {
                        return d.data.name.length > 15 ? d.data.name.substring(0, 15) + '...' : d.data.name;
                    }
                    return '';
                })
                .style('font-size', '11px')
                .style('fill', 'white')
                .style('font-weight', 'bold')
                .style('pointer-events', 'none');
            
            leaf.append('text')
                .attr('x', 4)
                .attr('y', 30)
                .text(d => {
                    const width = d.x1 - d.x0;
                    const height = d.y1 - d.y0;
                    if (width > 80 && height > 45) {
                        return formatBytes(d.value);
                    }
                    return '';
                })
                .style('font-size', '10px')
                .style('fill', 'rgba(255,255,255,0.9)')
                .style('pointer-events', 'none');
        }
        
        function renderResourceBreakdown() {
            const allModules = Object.values(data.modules);
            
            const modules = allModules.filter(m => moduleMatchesInsightsFilters(m));
            
            const resourceStats = {};

            // Every category here is compressed: `resources` and `binaryCompressedSize`
            // both record compressed sizes, and the residual is measured to match.
            let totalBinarySize = 0;
            let binaryModuleCount = 0;
            modules.forEach(m => {
                const binarySize = m.binaryCompressedSize || 0;
                if (binarySize > 0) {
                    totalBinarySize += binarySize;
                    binaryModuleCount++;
                }
            });
            if (totalBinarySize > 0) {
                resourceStats['Binary'] = { size: totalBinarySize, count: binaryModuleCount };
            }

            // No "Images" rollup: `imageSize` accumulates the same files that populate
            // `resources['png']` and friends, at the same compressed size, so such a
            // category would double-count them and push the total past the app's real
            // size. The per-type entries already separate the formats, with real counts.
            modules.forEach(module => {
                Object.entries(module.resources || {}).forEach(([type, res]) => {
                    if (!resourceStats[type]) {
                        resourceStats[type] = { size: 0, count: 0 };
                    }
                    resourceStats[type].size += res.size;
                    resourceStats[type].count += res.count;
                });
            });

            const resourceData = Object.entries(resourceStats).map(([type, stats]) => ({
                type,
                size: stats.size,
                count: stats.count
            }));

            // Must not be `calculateModuleTotal`: the categories are compressed, so an
            // uncompressed total makes "Other" absorb the app's whole compression delta
            // instead of the files no category claimed. Statically linked modules are
            // excluded for the same reason — their code is inside the app binary, already
            // counted under Binary.
            const compressedModules = modules.filter(m => m.staticallyLinked !== true);
            const calculatedTotal = compressedModules.reduce((sum, m) => sum + calculateModuleDownload(m), 0);
            const resourceTotal = resourceData.reduce((sum, r) => sum + r.size, 0);

            // The `.car` files and the untyped remainder, neither of which `resources` records.
            if (calculatedTotal > resourceTotal) {
                const otherSize = calculatedTotal - resourceTotal;
                if (otherSize > 0) {
                    resourceData.push({
                        type: 'Other',
                        size: otherSize,
                        count: 1
                    });
                }
            }
            
            resourceData.sort((a, b) => b.size - a.size);
            
            const resourceColorScale = d3.scaleOrdinal()
                .domain(resourceData.map(d => d.type))
                .range(d3.schemeSet3);
            
            renderDonutChart('resourceCountChart', resourceData, 'count', 'type', 'files', resourceColorScale, false);
            
            renderDonutChart('resourceSizeChart', resourceData, 'size', 'type', 'bytes', resourceColorScale, false);
            
            renderResourceLegend(resourceData, resourceColorScale);
        }
        
        function renderDonutChart(containerId, data, valueKey, labelKey, unit, colorScale, showLegend = true) {
            const container = document.getElementById(containerId);
            container.innerHTML = '';
            
            if (data.length === 0) {
                container.innerHTML = '<div class="no-data">No data available</div>';
                return;
            }
            
            const wrapper = d3.select('#' + containerId)
                .append('div')
                .style('display', 'flex')
                .style('align-items', 'center')
                .style('justify-content', 'center');
            
            const chartWidth = 280;
            const chartHeight = 280;
            const radius = Math.min(chartWidth, chartHeight) / 2 - 20;
            
            const svg = wrapper
                .append('svg')
                .attr('width', chartWidth)
                .attr('height', chartHeight);
            
            const g = svg.append('g')
                .attr('transform', `translate(${chartWidth / 2},${chartHeight / 2})`);
            
            const color = colorScale || d3.scaleOrdinal()
                .domain(data.map(d => d[labelKey]))
                .range(d3.schemeSet3);
            
            const pie = d3.pie()
                .value(d => d[valueKey])
                .sort(null);
            
            const arc = d3.arc()
                .innerRadius(radius * 0.6)
                .outerRadius(radius);
            
            const arcHover = d3.arc()
                .innerRadius(radius * 0.6)
                .outerRadius(radius * 1.05);
            
            const tooltip = d3.select('body').append('div')
                .attr('class', 'd3-tooltip');
            
            const total = d3.sum(data, d => d[valueKey]);
            
            const arcs = g.selectAll('.arc')
                .data(pie(data))
                .enter()
                .append('g')
                .attr('class', 'arc');
            
            arcs.append('path')
                .attr('d', arc)
                .attr('fill', d => color(d.data[labelKey]))
                .attr('stroke', 'white')
                .attr('stroke-width', 2)
                .style('cursor', 'pointer')
                .on('mouseover', function(event, d) {
                    d3.select(this)
                        .transition()
                        .duration(200)
                        .attr('d', arcHover);
                    
                    const percentage = ((d.data[valueKey] / total) * 100).toFixed(1);
                    const displayValue = unit === 'bytes' ? formatBytes(d.data[valueKey]) : d.data[valueKey].toLocaleString();
                    
                    tooltip.html(`
                        <div style="font-weight: bold; margin-bottom: 5px;">${escapeHtml(d.data[labelKey])}</div>
                        <div>${displayValue} ${unit === 'bytes' ? '' : unit}</div>
                        <div>${percentage}% of total</div>
                    `)
                    .classed('visible', true)
                    .style('left', (event.pageX + 10) + 'px')
                    .style('top', (event.pageY - 10) + 'px');
                })
                .on('mouseout', function() {
                    d3.select(this)
                        .transition()
                        .duration(200)
                        .attr('d', arc);
                    tooltip.classed('visible', false);
                })
                .transition()
                .duration(800)
                .attrTween('d', function(d) {
                    const i = d3.interpolate({ startAngle: 0, endAngle: 0 }, d);
                    return t => arc(i(t));
                });
            
            g.append('text')
                .attr('text-anchor', 'middle')
                .attr('dy', '-0.5em')
                .style('font-size', '24px')
                .style('font-weight', 'bold')
                .style('fill', '#333')
                .text(unit === 'bytes' ? formatBytes(total) : total.toLocaleString());
            
            g.append('text')
                .attr('text-anchor', 'middle')
                .attr('dy', '1.2em')
                .style('font-size', '12px')
                .style('fill', '#666')
                .text('Total ' + (unit === 'bytes' ? 'Size' : 'Count'));
        }
        
        function renderResourceLegend(resourceData, colorScale) {
            const legendContainer = document.getElementById('resourceLegend');
            legendContainer.innerHTML = '';
            
            const sortedData = [...resourceData].sort((a, b) => b.size - a.size);
            
            sortedData.forEach(d => {
                const legendItem = document.createElement('div');
                legendItem.style.cssText = 'display: flex; align-items: center; gap: 8px; padding: 8px 12px; background: #f8f9fa; border-radius: 6px;';
                
                const colorBox = document.createElement('div');
                colorBox.style.cssText = `width: 16px; height: 16px; background-color: ${colorScale(d.type)}; border-radius: 3px; flex-shrink: 0;`;
                legendItem.appendChild(colorBox);
                
                const textContainer = document.createElement('div');
                textContainer.style.cssText = 'display: flex; align-items: center; gap: 12px;';
                
                const typeName = document.createElement('span');
                typeName.style.cssText = 'font-size: 13px; color: #333; font-weight: 600; min-width: 60px;';
                typeName.textContent = d.type;
                textContainer.appendChild(typeName);
                
                const sizeText = document.createElement('span');
                sizeText.style.cssText = 'font-size: 12px; color: #666;';
                sizeText.textContent = formatBytes(d.size);
                textContainer.appendChild(sizeText);
                
                const countText = document.createElement('span');
                countText.style.cssText = 'font-size: 11px; color: #999;';
                countText.textContent = `(${d.count.toLocaleString()} ${d.count === 1 ? 'item' : 'items'})`;
                textContainer.appendChild(countText);
                
                legendItem.appendChild(textContainer);
                legendContainer.appendChild(legendItem);
            });
        }
        
        function renderUserImpact() {
            const container = document.getElementById('userImpactSection');
            const downloadSize = data.totalPackageSize || 0;
            const installSize = data.totalInstallSize || 0;
            
            const networks = [
                { name: 'WiFi', speed: 100, icon: '📶', color: '#2ecc71' },
                { name: '5G', speed: 50, icon: '📱', color: '#3498db' },
                { name: '4G', speed: 10, icon: '📱', color: '#f39c12' },
                { name: '3G', speed: 1, icon: '📱', color: '#e74c3c' }
            ];
            
            const downloadSizeMB = downloadSize / (1024 * 1024);
            const downloadTimes = networks.map(net => ({
                ...net,
                time: (downloadSizeMB * 8) / net.speed, // Convert to seconds
                size: downloadSize
            }));
            
            const iPhone64GB = 64 * 1024 * 1024 * 1024;
            const iPhone128GB = 128 * 1024 * 1024 * 1024;
            const iPhone256GB = 256 * 1024 * 1024 * 1024;
            
            const storagePercentages = [
                { capacity: '64GB', size: iPhone64GB, percent: (installSize / iPhone64GB) * 100 },
                { capacity: '128GB', size: iPhone128GB, percent: (installSize / iPhone128GB) * 100 },
                { capacity: '256GB', size: iPhone256GB, percent: (installSize / iPhone256GB) * 100 }
            ];
            
            function formatTime(seconds) {
                if (seconds < 60) return Math.round(seconds) + 's';
                const minutes = Math.floor(seconds / 60);
                const secs = Math.round(seconds % 60);
                return `${minutes}m ${secs}s`;
            }
            
            container.innerHTML = `
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 30px;">
                    ${downloadTimes.map(net => `
                        <div style="background: white; padding: 20px; border-radius: 8px; border-left: 4px solid ${net.color};">
                            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                                <div style="font-size: 24px;">${net.icon}</div>
                                <div style="font-size: 14px; color: #666; font-weight: 600;">${net.name}</div>
                            </div>
                            <div style="font-size: 32px; font-weight: bold; color: ${net.color}; margin-bottom: 5px;">${formatTime(net.time)}</div>
                            <div style="font-size: 12px; color: #999;">Download time for ${formatBytes(downloadSize)}, compressed</div>
                        </div>
                    `).join('')}
                </div>

                <h3 style="font-size: 16px; color: #333; margin-bottom: 15px;">📱 iPhone Storage Impact</h3>
                <p style="font-size: 12px; color: #999; margin: -8px 0 15px 0;">Uncompressed, of ${formatBytes(installSize)} installed. This section does not follow the size control: a transfer happens over the compressed IPA and an install occupies the uncompressed one, so each card has only one honest figure.</p>
                <div style="background: white; padding: 25px; border-radius: 8px;">
                    ${storagePercentages.map(storage => `
                        <div style="margin-bottom: 20px;">
                            <div style="display: flex; justify-content: space-between; margin-bottom: 8px;">
                                <span style="font-size: 14px; color: #333; font-weight: 500;">iPhone ${storage.capacity}</span>
                                <span style="font-size: 14px; color: #063773; font-weight: bold;">${storage.percent.toFixed(3)}%</span>
                            </div>
                            <div style="background: #e0e0e0; height: 20px; border-radius: 10px; overflow: hidden;">
                                <div style="background: linear-gradient(90deg, #063773 0%, #0a5aa8 100%); height: 100%; width: ${Math.min(storage.percent, 100)}%; transition: width 0.8s ease;"></div>
                            </div>
                            <div style="font-size: 11px; color: #999; margin-top: 5px;">${formatBytes(installSize)} of ${storage.capacity}</div>
                        </div>
                    `).join('')}
                </div>
            `;
        }
    </script>
</body>
</html>
"""
}

