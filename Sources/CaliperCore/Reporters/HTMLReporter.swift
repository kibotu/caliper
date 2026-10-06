import Foundation

/// Reporter for generating HTML output
public struct HTMLReporter {
    public init() {}

    /// Generate HTML report from JSON data.
    ///
    /// The result is a single self-contained file: d3 is inlined from the package's
    /// own resources and the report data is embedded, so the report opens with no
    /// network access at all.
    public func generate(jsonString: String, outputPath: String) throws {
        let html = htmlTemplate
            .replacingOccurrences(of: "__D3__", with: try Self.vendoredD3())
            // Escaping `<` keeps a module name containing `</script>` from closing
            // the enclosing tag and injecting markup.
            .replacingOccurrences(of: "__DATA__", with: jsonString.htmlSafe())
        try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    /// The vendored d3 bundle.
    static func vendoredD3() throws -> String {
        guard let url = Bundle.module.url(forResource: "d3.v7.min", withExtension: "js"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw CaliperError.invalidOutput
        }
        return contents
    }
    
    // MARK: - HTML Template
    
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
        
        /* Tabs */
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
        
        /* Filter Chips */
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
        /* A co-owner rather than the primary one. Lighter, so the order reads without a
           second label saying "also". */
        .owner-badge.additional { background: linear-gradient(135deg, #0a5aa8 0%, #3498db 100%); }
        .owner-badge.owner-badge-filter { cursor: pointer; }
        /* The team this click would filter to, so the badge does not just look clickable. */
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
        /* The compressed size of the compiled catalog the rows beneath were unpacked
           from. A note rather than a figure of its own: `top` already counts the .car in
           the download total, and this is those same bytes, not an addition to them. */
        .top-files h4 .catalog-note { color: #666; font-size: 12px; font-weight: 400; }
        .file-item { display: flex; justify-content: space-between; padding: 10px; background: white; margin-bottom: 5px; border-radius: 4px; font-size: 13px; border-left: 4px solid #e0e0e0; transition: all 0.2s; }
        .file-item:hover { box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .file-path { color: #666; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Cantarell', 'Helvetica Neue', sans-serif; }
        .file-size-value { color: #333; font-weight: 500; margin-left: 15px; }
        .file-type-badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 10px; font-weight: 600; text-transform: uppercase; margin-right: 8px; }
        
        /* File type colors */
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
        
        /* D3 Chart Styles */
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
        // The team the breakdown is filtered to, or '' for all of them. Drives both the
        // dropdown and the owner badges, so the two cannot disagree.
        let breakdownTeamFilter = '';
        let insightsFilters = { internal: true, external: true };
        let ownershipFilters = { internal: true, external: true };
        
        // Update header with app info if available
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

            // The Insights charts are static, so render them once. Re-rendering on every
            // visit appended a fresh set of tooltip elements each time, growing the DOM
            // without bound. The flag is set before the timer is scheduled, so a second
            // click while this one is pending cannot queue a duplicate render.
            if (tabName === 'insights' && !insightsRendered) {
                insightsRendered = true;
                // Wait for the tab to become visible so the charts can measure it.
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
        
        // Filter functions
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
            // Reset detail view
            document.getElementById('ownerDropdown').value = '';
            document.getElementById('ownerDetailSection').style.display = 'none';
        }
        
        // Every owner of a module, primary first and de-duplicated.
        //
        // `additionalOwners` comes from the `owners: [a, b]` form of an ownership entry;
        // a module with a single owner carries no such field. The primary is skipped when
        // it repeats, which a hand-written file can easily do.
        function allOwners(module) {
            const owners = [];
            if (module.owner) owners.push(module.owner);
            (module.additionalOwners || []).forEach(owner => {
                if (owner && !owners.includes(owner)) owners.push(owner);
            });
            return owners;
        }

        // Every team named anywhere in the report, for the team filter's options.
        function collectAllTeams() {
            const teams = new Set();
            Object.values(data.modules).forEach(module => {
                allOwners(module).forEach(team => teams.add(team));
            });
            return [...teams].sort((a, b) => a.localeCompare(b));
        }

        // The team the breakdown is filtered to, shared by the dropdown and the badges.
        // Clicking the team that is already selected clears the filter, so a badge
        // toggles rather than latching.
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
            // An option can disappear when a filter elsewhere empties a team out, which
            // would leave the select blank rather than showing the filter that is active.
            select.value = current;
            if (select.value !== current) breakdownTeamFilter = '';
        }

        // The owner badges on a module card: one per owner, co-owners in a lighter
        // gradient.
        //
        // `filterable` adds the behaviour that turns a badge into the team filter. It is
        // on for the breakdown cards and off for the owner detail cards: those are on the
        // Ownership tab, where the breakdown filter does not apply, so a badge that looked
        // clickable there would do nothing when clicked. As a plain badge it still answers
        // the question the reader has — this module is also owned by another team.
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
            // Check internal/external filter
            const isInternal = module.internal === true;
            const internalMatch = (isInternal && breakdownFilters.internal) || (!isInternal && breakdownFilters.external);
            if (!internalMatch) return false;

            // Check owned/unowned filter
            const isOwned = module.owner && module.owner.toLowerCase() !== 'others';
            const ownedMatch = (isOwned && breakdownFilters.owned) || (!isOwned && breakdownFilters.unowned);
            if (!ownedMatch) return false;

            // Check the team filter. A module matches on any of its owners, so a shared
            // module stays visible to both teams rather than being hidden from whichever
            // one is not listed first.
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
        
        // The files a module ships, split by kind, as the module panel lists them.
//
// `top` holds the real files in the bundle. A `.car` is a compiled asset catalog, and a
// directory entry is a 0 B artefact of the archive listing, so neither is a file worth
// listing. The catalog's own contents are listed in its place instead, because a
// container tells you nothing about what it costs.
//
// Two sections rather than one list with a marker on the catalog rows. A marker has to
// be glued to the file name to be visible, and the name is what the type badge is
// derived from: appending "(in catalog)" to "bus.svg" made the extension parse as
// "svg (in catalog)", which matched nothing, so every asset lost its type and its
// colour. Separate sections need no marker, so the name stays a name.
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

// The size of the compiled catalog these rows were unpacked from, at the compressed
// size the IPA listing reports for it. That is the figure that reaches the download
// total, and the rows beneath it are the same bytes expanded — so this is a note
// explaining their unit, not a figure to add to them.
function compiledCatalogNote(module) {
    const compiled = Object.entries(module.top || {})
        .filter(([path]) => path.toLowerCase().endsWith('.car'))
        .reduce((sum, [, size]) => sum + (size || 0), 0);
    return compiled > 0 ? `${formatBytes(compiled)} compiled` : 'compiled size unknown';
}

// How a catalog is named when it has to appear as a single entry rather than a list of
// its contents. The path on its own reads as a file, and a file is the wrong thing to
// point someone at: the entry is a container, and saying so is what keeps it from being
// mistaken for something that can be deleted.
//
// The container's extension is dropped because the chart's axis truncates labels to
// about twenty characters, and `ProfisBus.bundle asset catalog` loses the one word that
// says what the row is. The full path is in the tooltip either way.
function catalogLabel(carPath) {
    const parts = carPath.split('/').filter(Boolean);
    const container = parts.length >= 2 ? parts[parts.length - 2] : 'app';
    const dot = container.lastIndexOf('.');
    return `${dot > 0 ? container.slice(0, dot) : container} catalog`;
}

// How many assets a module's catalog holds. This is the module's total across all of
// its catalogs, not a per-catalog count, because `assetCatalogFiles` is a flat dictionary
// keyed by rendition name. A module with one catalog — the usual shape, since a bundle
// ships one `Assets.car` — is exact. A module with two reports the sum, which is the
// number that would be actionable anyway.
function catalogAssetCount(module) {
    return Object.keys(module.assetCatalogFiles || {}).length;
}

function getFileTypeInfo(filePath) {
            // A name with no dot has no extension. `split('.').pop()` hands back the whole
            // name in that case, so a colour set named AccentColor was badged ACCENTCOLOR.
            const name = filePath.split('/').pop();
            const dot = name.lastIndexOf('.');
            const ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : '';
            
            // Image files
            if (['png', 'jpg', 'jpeg', 'gif', 'svg', 'heic', 'heif', 'webp', 'bmp', 'tiff', 'tif'].includes(ext)) {
                return { type: 'image', label: ext.toUpperCase(), class: 'file-type-image' };
            }
            
            // Lottie/JSON files (check if JSON is likely an animation)
            if (ext === 'json') {
                // Assume JSON files in asset catalogs are likely Lottie animations
                if (filePath.toLowerCase().includes('lottie') || filePath.toLowerCase().includes('animation')) {
                    return { type: 'lottie', label: 'LOTTIE', class: 'file-type-lottie' };
                }
                return { type: 'lottie', label: 'JSON', class: 'file-type-lottie' };
            }
            
            // PDF files
            if (ext === 'pdf') {
                return { type: 'pdf', label: 'PDF', class: 'file-type-pdf' };
            }
            
            // Video files
            if (['mp4', 'mov', 'avi', 'mkv', 'm4v', 'mpg', 'mpeg', 'wmv', 'webm'].includes(ext)) {
                return { type: 'video', label: ext.toUpperCase(), class: 'file-type-video' };
            }
            
            // Audio files
            if (['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'aiff', 'wma'].includes(ext)) {
                return { type: 'audio', label: ext.toUpperCase(), class: 'file-type-audio' };
            }
            
            // Font files
            if (['ttf', 'otf', 'woff', 'woff2', 'eot'].includes(ext)) {
                return { type: 'font', label: ext.toUpperCase(), class: 'file-type-font' };
            }
            
            // Other files. A name with no extension is labelled by where it came from
            // rather than by the name itself, which is not a file type.
            return { type: 'other', label: ext ? ext.toUpperCase() : 'ASSET', class: 'file-type-other' };
        }
        
        function calculateModuleDownload(module) {
            // Compressed size of every file this module owns: the main binary plus the
            // files in `top`. `binarySize` is excluded because with a LinkMap it holds
            // uncompressed output, which would mix units in one figure.
            //
            // `binaryCompressedSize` is counted here because `top` deliberately omits
            // the main binary, so a framework that ships nothing but a binary would
            // otherwise report zero download bytes.
            //
            // A statically linked module has no container, so that sum is legitimately
            // zero and the figure would say nothing. It has a measured size, so report
            // it. The two branches are different units — compressed where a compressed
            // size exists, uncompressed otherwise — which is why the flag is checked
            // rather than the two being summed together.
            if (module.staticallyLinked === true) return module.binarySize || 0;
            let total = (module.binaryCompressedSize || 0);
            if (!module.top) return total;
            return total + Object.values(module.top).reduce((sum, v) => sum + (v || 0), 0);
        }

        function calculateModuleTotal(module) {
            // `proguard` is the module's install size: the sum of the uncompressed
            // size of every file attributed to it, plus the LinkMap binary size for
            // modules that ship no bundle. It is computed once on the Swift side.
            //
            // This used to be `binarySize + imageFileSize + sum(resources)`, which
            // double-counted images, because the parsers record each image in both
            // `imageFileSize` and `resources`.
            return module.proguard || 0;
        }
        
        function renderSummary() {
            const totalPackageSize = data.totalPackageSize || 0;
            const totalInstallSize = data.totalInstallSize || 0;
            const allModules = Object.values(data.modules);
            const moduleCount = allModules.length;

            // Calculate internal totals
            const internalModules = allModules.filter(m => m.internal === true);
            const internalCount = internalModules.length;
            const internalInstallSize = internalModules.reduce((sum, m) => sum + calculateModuleTotal(m), 0);
            
            // Download size is the sum of each module's download size.
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
            
            // Apply breakdown filters
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
                
                // Resource breakdown by type. Named apart from the "Resources" list below,
                // which is the resources themselves: the two are different things and one
                // heading cannot carry both.
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
                
                // The module's resources, and its asset catalog's contents
                const topFilesHTML = renderModuleResources(module);
                
                // Source files from LinkMap (show ALL files)
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
                
                // Determine which size to display based on current sort. The displayed figure
                // must come from the same function the sort used, or the column
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
        
        // Ownership Tab Functions
        // Two groupings, deliberately different.
        //
        // The chart answers "how is the app split", so it counts each module once, under
        // its primary owner. The teams partition the app and the bars sum to its total.
        //
        // The per-team list answers "what is this team responsible for", so it counts a
        // shared module in full for every team that owns it. Those totals deliberately sum
        // to more than the app, because splitting a framework between two teams would
        // need a share of the bytes that does not exist. Collapsing the two groupings into
        // one would mean either the chart double-counts or the list under-reports a team,
        // so they stay apart and the tab says which is which.
        let ownershipChartData = [];
        let ownerGroupData = [];
        let currentOwnershipSort = 'downloadSize';

        // Sums a team's modules. Same two functions the breakdown tab uses, so a team's
        // totals agree with the module cards beneath them.
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

        // Primary owner only, so the chart's bars add up to the app.
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

        // Every owner, so a shared module is attributed to each team in full.
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
            
            // Clear any existing chart
            chartContainer.innerHTML = '';
            
            // Chart dimensions
            const margin = { top: 20, right: 30, bottom: 120, left: 80 };
            const barWidth = 40;
            const barGap = 10;
            const groupGap = 30;
            const groupWidth = (barWidth * 2) + barGap;
            const width = ownershipChartData.length * (groupWidth + groupGap) + margin.left + margin.right;
            const height = 450;
            const chartHeight = height - margin.top - margin.bottom;
            
            // Calculate totals for percentages
            const totalDownloadSize = ownershipChartData.reduce((sum, d) => sum + d.totalDownloadSize, 0);
            const totalInstallSize = ownershipChartData.reduce((sum, d) => sum + d.totalInstallSize, 0);
            
            // Create tooltip
            const tooltip = d3.select('body').append('div')
                .attr('class', 'd3-tooltip');
            
            // Create SVG
            const svg = d3.select('#ownershipChart')
                .append('svg')
                .attr('width', width)
                .attr('height', height)
                .style('display', 'block')
                .style('margin', '0 auto');
            
            const g = svg.append('g')
                .attr('transform', `translate(${margin.left},${margin.top})`);
            
            // Scales
            const x = d3.scaleBand()
                .domain(ownershipChartData.map(d => d.name))
                .range([0, width - margin.left - margin.right])
                .padding(0.3);
            
            const maxSize = d3.max(ownershipChartData, d => Math.max(d.totalDownloadSize, d.totalInstallSize));
            const y = d3.scaleLinear()
                .domain([0, maxSize])
                .nice()
                .range([chartHeight, 0]);
            
            // Grid lines
            g.append('g')
                .attr('class', 'grid')
                .call(d3.axisLeft(y)
                    .tickSize(-width + margin.left + margin.right)
                    .tickFormat('')
                );
            
            // Y axis with formatted bytes
            const yAxis = g.append('g')
                .attr('class', 'axis')
                .call(d3.axisLeft(y)
                    .tickFormat(d => formatBytes(d))
                    .ticks(5)
                );
            
            // X axis
            const xAxis = g.append('g')
                .attr('class', 'axis')
                .attr('transform', `translate(0,${chartHeight})`)
                .call(d3.axisBottom(x));
            
            // Rotate x-axis labels for better readability with long text
            xAxis.selectAll('text')
                .attr('transform', 'rotate(-55)')
                .style('text-anchor', 'end')
                .attr('dx', '-0.5em')
                .attr('dy', '0.5em')
                .style('font-size', '11px');
            
            // Create groups for each owner
            const ownerGroups = g.selectAll('.owner-group')
                .data(ownershipChartData)
                .enter()
                .append('g')
                .attr('class', 'owner-group')
                .attr('transform', d => `translate(${x(d.name)},0)`);
            
            // Download size bars (blue)
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
            
            // Install size bars (green)
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
            
            // Legend
            const legend = svg.append('g')
                .attr('transform', `translate(${width / 2 - 100},${height - 25})`);
            
            // Download legend
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
            
            // Install legend
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
        
        // Open a team's detail section by name.
        //
        // The chart and the dropdown are built from different groupings now — primary
        // owner versus every owner — so they do not share indices. Resolving by name is
        // what keeps a click on a bar working: the bar's team is looked up in the list
        // the dropdown was populated from, wherever that team happens to sit in it.
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
            
            // Create array with owner and original index
            const ownerWithIndices = ownerGroupData.map((owner, index) => ({
                owner: owner,
                index: index
            }));
            
            // Separate "others" from regular owners
            const othersEntries = ownerWithIndices.filter(item => 
                item.owner.name.toLowerCase() === 'others' || 
                item.owner.name.toLowerCase() === 'other'
            );
            const regularEntries = ownerWithIndices.filter(item => 
                item.owner.name.toLowerCase() !== 'others' && 
                item.owner.name.toLowerCase() !== 'other'
            );
            
            // Sort regular owners alphabetically
            regularEntries.sort((a, b) => a.owner.name.localeCompare(b.owner.name));
            
            // Combine: regular owners first, then "others"
            const sortedEntries = [...regularEntries, ...othersEntries];
            
            // Populate dropdown
            let appOwnerIndex = null;
            sortedEntries.forEach(item => {
                const option = document.createElement('option');
                option.value = item.index;
                option.textContent = item.owner.name;
                dropdown.appendChild(option);
                
                // Track "App" owner for auto-selection
                if (item.owner.name === 'App') {
                    appOwnerIndex = item.index;
                }
            });
            
            // Auto-select "App" owner if it exists and autoSelectApp is true
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
            
            // Render summary
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
            
            // Render modules
            const modulesGrid = document.getElementById('ownerModulesGrid');
            // `owner.modules` is a list of modules, not a name-keyed map: a module can
            // appear under several teams, and the array does not care that. It used to be
            // a map, and reading it as one made every card below show its own index as the
            // module name.
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
                
                // Resource breakdown by type. Named apart from the "Resources" list below,
                // which is the resources themselves: the two are different things and one
                // heading cannot carry both.
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
                
                // The module's resources, and its asset catalog's contents
                const topFilesHTML = renderModuleResources(module);
                
                // Source files from LinkMap
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
            // Reset detail view
            document.getElementById('ownerDropdown').value = '';
            document.getElementById('ownerDetailSection').style.display = 'none';
        });

        document.getElementById('teamFilterSelect').addEventListener('change', (e) => {
            breakdownTeamFilter = e.target.value;
            renderModules(document.getElementById('searchInput').value, currentSort);
        });

        // Owner badges are filters, on both the module card and the owner detail card.
        // Delegated, because the cards are rebuilt on every render and a per-card
        // handler would have to be reattached each time.
        document.querySelector('.container').addEventListener('click', (e) => {
            const badge = e.target.closest('.owner-badge-filter');
            if (!badge) return;
            // The card header also toggles, so the badge must not fall through to it.
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
        
        // Insights renders once, on first visit. Declared here because `switchTab` runs
        // before the DOM-ready block below.
        let insightsRendered = false;

        // Which of the two size figures the Insights page is showing. Download is
        // compressed and is what the user fetches; install is uncompressed and is what
        // the device stores. Defaults to install, which is what the page showed before
        // the control existed.
        let insightsSizeBasis = 'installSize';

        // A module's size in whichever unit the page is currently showing. Every section
        // that has both figures reads this rather than picking one, so the control cannot
        // leave two charts disagreeing about what they are measuring.
        function moduleSizeForInsights(module) {
            return insightsSizeBasis === 'downloadSize'
                ? calculateModuleDownload(module)
                : calculateModuleTotal(module);
        }

        function setInsightsSizeBasis(basis) {
            if (insightsSizeBasis === basis) return;
            insightsSizeBasis = basis;
            // Before the first visit there is nothing on the page to redraw, and the
            // render-once flag will pick the basis up when it does.
            if (insightsRendered) renderInsights();
        }

        // Insights Tab Functions
        function renderInsights() {
            // Every chart appends its own tooltip to the body, and User Impact writes
            // into a container it never cleared. Re-rendering therefore grew the DOM
            // without bound, which is what the render-once guard was working around.
            // The size control needs re-render, so clear both here.
            d3.select('body').selectAll('.d3-tooltip').remove();
            document.getElementById('userImpactSection').innerHTML = '';

            renderTopOffenders();
            renderTreemap();
            renderResourceBreakdown();
            renderUserImpact();
        }

        // 1. Top Offenders Dashboard
        function renderTopOffenders() {
            const allModules = Object.values(data.modules);

            // Apply insights filters
            const modules = allModules.filter(m => moduleMatchesInsightsFilters(m));

            // Top 20 Modules by size
            const topModules = modules
                .map(m => ({ name: m.name, size: moduleSizeForInsights(m), owner: m.owner }))
                .sort((a, b) => b.size - a.size)
                .slice(0, 20);
            
            // Top 20 Source Files across all modules
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
            
            // Top 20 resources across all modules (excluding frameworks)
            //
            // Everything in the bundle that is not compiled code is a resource, not just
            // images. Directory entries are excluded: the archive lists them at 0 B.
            //
            // A compiled asset catalog is the one resource with two honest
            // representations, and which one is correct depends on the unit in view.
            // Download: the `.car` is one file in the archive, and its contents are not in
            // the download at all, so the container is the figure. Install: the container
            // says nothing about what it costs, and the renditions are the expanded bytes,
            // so the contents are the figure. Listing both would count the same bytes
            // twice in one chart, which is what this avoids.
            //
            // Neither is a list of files, and the compressed case used to be a plain
            // container row: `Payload/…/ProfisBus.bundle/Assets.car` at 58.6 KB says a
            // catalog exists and what it cost, which is nothing anyone can act on. So
            // compressed, it is one row per catalog carrying the asset count — 12 assets
            // for 58.6 KB is a catalog worth opening, 400 for the same is not. Uncompressed,
            // the renditions are listed individually, because that is where the actionable
            // names are.
            //
            // Non-catalog resources have only a compressed per-file figure — `top` records
            // compressed sizes, and the sole uncompressed per-file numbers in the model
            // are catalog renditions and images. So the toggle moves the catalog and
            // leaves the rest of the list as it is.
            const allResources = [];
            const byDownload = insightsSizeBasis === 'downloadSize';
            modules.forEach(module => {
                // Exclude external modules (frameworks) from resource files
                if (module.internal !== true) return;

                if (module.top) {
                    Object.entries(module.top).forEach(([path, size]) => {
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
            
            // Render Top Modules Bar Chart
            renderHorizontalBarChart('topModulesChart', topModules, 'size', 'name', '#063773');
            
            // Render Top Files Bar Chart
            renderHorizontalBarChart('topFilesChart', topFiles, 'size', 'name', '#e74c3c');
            
            // Render Top Resources Bar Chart
            renderHorizontalBarChart('topResourcesChart', topResources, 'size', 'name', '#3498db');
        }
        
        function renderHorizontalBarChart(containerId, data, sizeKey, nameKey, color) {
            const container = document.getElementById(containerId);
            container.innerHTML = '';
            
            if (data.length === 0) {
                container.innerHTML = '<div class="no-data">No data available</div>';
                return;
            }
            
            // Get container width and make chart responsive
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
            
            // Create tooltip
            const tooltip = d3.select('body').append('div')
                .attr('class', 'd3-tooltip');
            
            // Bars
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
                        // The label says this is a container, so the count is what makes
                        // the row worth reading, and the path is where to go looking.
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
            
            // Labels (names)
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
                // A catalog row is labelled as a container, so its native tooltip shows
                // the path it was collapsed from — otherwise the label reads as a name
                // that does not exist anywhere in the bundle.
                .text(d => d.path || d[nameKey]);
            
            // Size labels
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
        
        // 2. Treemap Visualization
        function renderTreemap() {
            const container = document.getElementById('treemapChart');
            container.innerHTML = '';
            
            const allModules = Object.values(data.modules);
            
            // Apply insights filters
            const modules = allModules.filter(m => moduleMatchesInsightsFilters(m));
            
            // Prepare hierarchical data
            //
            // The cell value follows the size control, and the tooltip's binary and
            // asset figures follow it too. They used to be pinned to the uncompressed
            // pair, which is only correct while the cell is uncompressed: showing a
            // compressed cell total above an uncompressed breakdown is the same unit
            // mismatch the module card had. Both pairs exist — `binarySize` is LinkMap
            // output and `binaryCompressedSize` the archive listing, `imageFileSize` is
            // uncompressed and `imageSize` compressed.
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

            // Percentages are relative to what the treemap actually draws. Dividing a
            // module's size by the whole-app total understated every cell whenever the
            // insights filters hide modules.
            const treemapTotal = d3.sum(treemapData.children, d => d.value);
            
            // Use container's full width for better fit
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
            
            // Add text labels for larger rectangles
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
        
        // 3. Resource Type Breakdown
        function renderResourceBreakdown() {
            const allModules = Object.values(data.modules);
            
            // Apply insights filters
            const modules = allModules.filter(m => moduleMatchesInsightsFilters(m));
            
            // Aggregate all resources
            const resourceStats = {};

            // Every category below is a compressed size, because `resources` and
            // `binaryCompressedSize` both record compressed sizes. The "Other" residual
            // is measured against a compressed total to match — see below.
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

            // Add every resource by type: images, fonts, plists, PDFs and the rest.
            //
            // There is no separate "Images" rollup, and there could not be a correct
            // one. `imageSize` is accumulated from the same files that also populate
            // `resources['png']`, `resources['jpg']` and so on, at the same compressed
            // size — so an Images category summed the same bytes a second time and
            // inflated the donut's total past the app's real size. Its count was worse:
            // it counted every key in `top`, which is every file in the bundle whatever
            // its type. The per-type breakdown already separates the image formats, and
            // it carries the counts those formats actually have.
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

            // The total the residual is measured against has to be in the same unit as
            // the categories, which are all compressed. This used to be
            // `calculateModuleTotal` — uncompressed install size — so "Other" absorbed
            // the app's entire compression delta rather than the files no category
            // claimed, and on a typical app that was the largest wedge in the chart.
            //
            // A statically linked module is excluded: it has no compressed size of its
            // own, because the linker put its code inside the app binary, which is
            // already counted once under Binary. Its `downloadSize` is the uncompressed
            // LinkMap fallback, so including it would add its entire code size to the
            // residual.
            const compressedModules = modules.filter(m => m.staticallyLinked !== true);
            const calculatedTotal = compressedModules.reduce((sum, m) => sum + calculateModuleDownload(m), 0);
            const resourceTotal = resourceData.reduce((sum, r) => sum + r.size, 0);

            // Anything not covered by a named category above lands in "Other": the
            // `.car` files and the untyped remainder, neither of which `resources`
            // records.
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
            
            // Sort by size descending
            resourceData.sort((a, b) => b.size - a.size);
            
            // Create shared color scale
            const resourceColorScale = d3.scaleOrdinal()
                .domain(resourceData.map(d => d.type))
                .range(d3.schemeSet3);
            
            // Render Count Donut Chart (without legend)
            renderDonutChart('resourceCountChart', resourceData, 'count', 'type', 'files', resourceColorScale, false);
            
            // Render Size Donut Chart (without legend)
            renderDonutChart('resourceSizeChart', resourceData, 'size', 'type', 'bytes', resourceColorScale, false);
            
            // Render shared legend below both charts
            renderResourceLegend(resourceData, resourceColorScale);
        }
        
        function renderDonutChart(containerId, data, valueKey, labelKey, unit, colorScale, showLegend = true) {
            const container = document.getElementById(containerId);
            container.innerHTML = '';
            
            if (data.length === 0) {
                container.innerHTML = '<div class="no-data">No data available</div>';
                return;
            }
            
            // Create wrapper - simple div for chart only
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
            
            // Use provided color scale or create default
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
            
            // Center text
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
            
            // Sort data by size descending for legend
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
        
        // 4. User Impact Score
        function renderUserImpact() {
            const container = document.getElementById('userImpactSection');
            const downloadSize = data.totalPackageSize || 0;
            const installSize = data.totalInstallSize || 0;
            
            // Network speeds in Mbps
            const networks = [
                { name: 'WiFi', speed: 100, icon: '📶', color: '#2ecc71' },
                { name: '5G', speed: 50, icon: '📱', color: '#3498db' },
                { name: '4G', speed: 10, icon: '📱', color: '#f39c12' },
                { name: '3G', speed: 1, icon: '📱', color: '#e74c3c' }
            ];
            
            // Calculate download times (in seconds)
            const downloadSizeMB = downloadSize / (1024 * 1024);
            const downloadTimes = networks.map(net => ({
                ...net,
                time: (downloadSizeMB * 8) / net.speed, // Convert to seconds
                size: downloadSize
            }));
            
            // iPhone storage comparison (using 64GB as baseline)
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

