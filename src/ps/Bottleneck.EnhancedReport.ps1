# Bottleneck.EnhancedReport.ps1
# Enhanced visual network report with charts, maps, and animations

function New-BottleneckEnhancedNetworkReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$JsonPath,
        [Parameter()][string]$CsvPath,
        [Parameter()][string]$OutputPath,
        [Parameter()][string]$TracerouteDir,
        [Parameter()][switch]$OpenBrowser,
        [Parameter()][switch]$Offline  # Embed Chart.js/Leaflet inline (no CDN)
    )

    # Load data
    if (-not (Test-Path $JsonPath)) { throw "JSON file not found: $JsonPath" }
    $data = Get-Content $JsonPath -Raw | ConvertFrom-Json

    # Auto-detect CSV and traceroutes if not provided
    if (-not $CsvPath) {
        $CsvPath = $data.artifacts.csv
    }
    if (-not $TracerouteDir) {
        $TracerouteDir = Split-Path $JsonPath
    }
    if (-not $OutputPath) {
        $basename = [System.IO.Path]::GetFileNameWithoutExtension($JsonPath)
        $OutputPath = Join-Path (Split-Path $JsonPath) "$basename-enhanced.html"
    }

    # Prepare CDN or embedded assets
    if ($Offline) {
        Write-Host "Offline mode: downloading and embedding Chart.js and Leaflet..." -ForegroundColor Cyan
        try {
            $chartJs = (Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js' -UseBasicParsing -TimeoutSec 10).Content
            $leafletJs = (Invoke-WebRequest -Uri 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js' -UseBasicParsing -TimeoutSec 10).Content
            $leafletCss = (Invoke-WebRequest -Uri 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css' -UseBasicParsing -TimeoutSec 10).Content
            Write-Host "✓ Libraries embedded successfully" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to download libraries for offline mode: $($_.Exception.Message)"
            Write-Warning "Falling back to CDN links (report will require internet)"
            $Offline = $false
        }
    }

    # Parse CSV for timeline data
    $csvData = Import-Csv $CsvPath
    $timelineData = @()
    $dropEvents = @()
    $currentDrop = $null

    foreach ($row in $csvData) {
        $timestamp = $row.Timestamp
        $status = $row.Status
        $latency = if ($row.ResponseTime) { [int]$row.ResponseTime } else { 0 }

        $timelineData += [pscustomobject]@{
            time = $timestamp
            status = $status
            latency = $latency
            dns = $row.DNS
            router = $row.Router
        }

        # Track drops
        if ($status -eq 'FAILED' -and -not $currentDrop) {
            $currentDrop = [pscustomobject]@{
                start = $timestamp
                end = $null
                duration = 0
            }
        } elseif ($status -eq 'Success' -and $currentDrop) {
            $currentDrop.end = $timestamp
            $startTime = [datetime]::Parse($currentDrop.start)
            $endTime = [datetime]::Parse($timestamp)
            $currentDrop.duration = ($endTime - $startTime).TotalSeconds
            $dropEvents += $currentDrop
            $currentDrop = $null
        }
    }

    # Parse traceroute files for hop data
    $hopData = Get-TracerouteHopData -TracerouteDir $TracerouteDir

    # Generate HTML
    # Build CDN or embedded script/style tags
    if ($Offline) {
        $scriptTags = @"
    <script>$chartJs</script>
    <script>$leafletJs</script>
    <style>$leafletCss</style>
"@
    } else {
        $scriptTags = @"
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
"@
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Journey Report 🌐</title>
$scriptTags
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        .header h1 {
            font-size: 3em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        .story-section {
            padding: 40px;
            background: linear-gradient(to right, #f8f9fa, #e9ecef);
            border-left: 5px solid #667eea;
        }
        .story-section h2 {
            color: #667eea;
            font-size: 2em;
            margin-bottom: 20px;
        }
        .story-section p {
            font-size: 1.1em;
            line-height: 1.8;
            margin-bottom: 15px;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            padding: 40px;
        }
        .stat-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 15px;
            text-align: center;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
            transition: transform 0.3s;
        }
        .stat-card:hover {
            transform: translateY(-5px);
        }
        .stat-value {
            font-size: 3em;
            font-weight: bold;
            margin: 10px 0;
        }
        .stat-label {
            font-size: 1.1em;
            opacity: 0.9;
        }
        .chart-section {
            padding: 40px;
        }
        .chart-container {
            position: relative;
            height: 400px;
            margin-bottom: 40px;
            background: white;
            border-radius: 15px;
            padding: 20px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }
        .map-container {
            height: 500px;
            margin: 40px;
            border-radius: 15px;
            overflow: hidden;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }
        .drop-timeline {
            padding: 40px;
            background: #f8f9fa;
        }
        .drop-event {
            background: white;
            border-left: 4px solid #dc3545;
            padding: 20px;
            margin: 20px 0;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        .drop-event.recovered {
            border-left-color: #28a745;
        }
        .section-title {
            font-size: 2em;
            color: #667eea;
            margin-bottom: 30px;
            padding: 0 40px;
        }
        .pulse-animation {
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .footer {
            background: #2c3e50;
            color: white;
            text-align: center;
            padding: 30px;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 Network Performance Analysis Report</h1>
            <p>Comprehensive Connectivity Monitoring</p>
            <p>📅 $(([datetime]$data.startTime).ToString('yyyy-MM-dd')) | ⏱️ $(([datetime]$data.startTime).ToString('h:mm tt')) - $(([datetime]$data.endTime).ToString('h:mm tt'))</p>
        </div>

        <div class="story-section">
            <h2>📊 Executive Summary</h2>
            <p>
                This report documents an 8-hour continuous network monitoring session analyzing connectivity performance
                and identifying potential bottlenecks in the network path between your system and target hosts.
            </p>
            <p>
                During the monitoring period, <strong>$($data.totals.pings) connectivity probes</strong> were transmitted
                at regular intervals. The overall connection success rate was <strong>$($data.totals.successPercent)%</strong>,
                indicating generally stable network conditions.
            </p>
            <p>
                <strong>$($data.drops.count) connection interruptions</strong> were detected during the monitoring window,
                with an average duration of $([math]::Round($data.drops.averageSeconds, 1)) seconds.
                The maximum outage lasted $([math]::Round($data.drops.maxSeconds, 1)) seconds.
            </p>
            <p>
                <strong>Root Cause Analysis:</strong> The majority of connectivity failures ($($data.failures.dnsPercent)%)
                were attributed to DNS resolution issues, indicating potential problems with the Domain Name System infrastructure
                rather than core network routing or ISP connectivity.
            </p>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-label">Total Probes</div>
                <div class="stat-value">$($data.totals.pings)</div>
                <div class="stat-label">connectivity tests</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Success Rate</div>
                <div class="stat-value">$($data.totals.successPercent)%</div>
                <div class="stat-label">uptime achieved</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Connection Drops</div>
                <div class="stat-value">$($data.drops.count)</div>
                <div class="stat-label">interruptions detected</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Max Outage</div>
                <div class="stat-value">$([math]::Round($data.drops.maxSeconds, 1))s</div>
                <div class="stat-label">longest interruption</div>
            </div>
        </div>

        <div class="chart-section">
            <h2 class="section-title">📊 Visual Journey</h2>

            <div class="chart-container">
                <canvas id="timelineChart"></canvas>
            </div>

            <div class="chart-container">
                <canvas id="failureChart"></canvas>
            </div>

            <div class="chart-container">
                <canvas id="hourlyChart"></canvas>
            </div>
        </div>

        <div class="drop-timeline">
            <h2 class="section-title">⏰ Connection Interruption Timeline</h2>
            $(
                if ($dropEvents.Count -gt 0) {
                    $dropEvents | ForEach-Object {
                        $startTime = ([datetime]::Parse($_.start)).ToString('h:mm:ss tt')
                        $duration = [math]::Round($_.duration, 1)
                        "<div class='drop-event'>
                            <strong>🔴 Outage at $startTime</strong><br/>
                            Duration: $duration seconds<br/>
                            <small>Connectivity restored automatically</small>
                        </div>"
                    }
                } else {
                    "<p>No significant connection drops detected during the monitoring period. Network stability was excellent.</p>"
                }
            )
        </div>

        <div class="chart-section">
            <h2 class="section-title">🌐 Network Path Visualization</h2>
            <div class="chart-container">
                <canvas id="networkPath" style="background: linear-gradient(135deg, #667eea20 0%, #764ba220 100%);"></canvas>
            </div>
        </div>

        <div class="map-container">
            <div id="map" style="height: 100%;"></div>
        </div>

        <div class="footer">
            <p>🚀 Report generated by Bottleneck Network Diagnostics Suite</p>
            <p>Advanced network performance monitoring and analysis</p>
        </div>
    </div>

    <script>
        // Defensive checks: if CDN libraries fail to load (offline), show placeholders
        function showPlaceholder(id, message) {
            const canvas = document.getElementById(id);
            if (!canvas) return;
            const container = canvas.parentElement;
            const p = document.createElement('div');
            p.style.display = 'flex';
            p.style.alignItems = 'center';
            p.style.justifyContent = 'center';
            p.style.height = canvas.height ? (canvas.height + 'px') : '300px';
            p.style.color = '#6c757d';
            p.style.font = '14px sans-serif';
            p.innerText = message;
            container.replaceChild(p, canvas);
        }

        const _ChartAvailable = typeof Chart !== 'undefined';
        const _LeafletAvailable = typeof L !== 'undefined';
        // Timeline Chart
        const timelineCanvas = document.getElementById('timelineChart');
        const timelineData = $($timelineData | ConvertTo-Json -Compress -Depth 3);
        if (_ChartAvailable && timelineCanvas) {
        const timelineCtx = timelineCanvas.getContext('2d');
        new Chart(timelineCtx, {
            type: 'line',
            data: {
                labels: timelineData.map(d => new Date(d.time).toLocaleTimeString()),
                datasets: [{
                    label: 'Connection Status',
                    data: timelineData.map(d => d.status === 'Success' ? 1 : 0),
                    borderColor: '#28a745',
                    backgroundColor: 'rgba(40, 167, 69, 0.1)',
                    fill: true,
                    stepped: true
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    title: {
                        display: true,
                        text: '📈 Network Connectivity Status Timeline',
                        font: { size: 18 }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 1,
                        ticks: {
                            callback: function(value) {
                                return value === 1 ? '✅ Online' : '❌ Offline';
                            }
                        }
                    }
                }
            }
        });
        } else { showPlaceholder('timelineChart', 'Chart.js not available (offline?).'); }

        // Failure Type Pie Chart
        const failureCanvas = document.getElementById('failureChart');
        if (_ChartAvailable && failureCanvas) {
        const failureCtx = failureCanvas.getContext('2d');
        new Chart(failureCtx, {
            type: 'doughnut',
            data: {
                labels: ['DNS Issues', 'Router Problems', 'ISP Issues'],
                datasets: [{
                    data: [$($data.failures.dns), $($data.failures.router), $($data.failures.isp)],
                    backgroundColor: ['#ff6384', '#36a2eb', '#ffce56']
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    title: {
                        display: true,
                        text: '🔍 Failure Attribution Analysis',
                        font: { size: 18 }
                    },
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });
        } else { showPlaceholder('failureChart', 'Chart.js not available (offline?).'); }

        // Hourly Activity Chart
        const hourlyCanvas = document.getElementById('hourlyChart');
        const hourlyData = {};
        timelineData.forEach(d => {
            const hour = new Date(d.time).getHours();
            if (!hourlyData[hour]) hourlyData[hour] = { success: 0, fail: 0 };
            if (d.status === 'Success') hourlyData[hour].success++;
            else hourlyData[hour].fail++;
        });

        const hours = Object.keys(hourlyData).sort((a,b) => a-b);
        if (_ChartAvailable && hourlyCanvas) {
        const hourlyCtx = hourlyCanvas.getContext('2d');
        new Chart(hourlyCtx, {
            type: 'bar',
            data: {
                labels: hours.map(h => h + ':00'),
                datasets: [
                    {
                        label: 'Successful',
                        data: hours.map(h => hourlyData[h].success),
                        backgroundColor: '#28a745'
                    },
                    {
                        label: 'Failed',
                        data: hours.map(h => hourlyData[h].fail),
                        backgroundColor: '#dc3545'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    title: {
                        display: true,
                        text: '⏰ Hourly Connection Activity',
                        font: { size: 18 }
                    }
                },
                scales: {
                    x: { stacked: true },
                    y: { stacked: true }
                }
            }
        });
        } else { showPlaceholder('hourlyChart', 'Chart.js not available (offline?).'); }

        // Initialize Map (placeholder - would need actual hop data)
        if (_LeafletAvailable) {
            const map = L.map('map').setView([39.8283, -98.5795], 4);
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '© OpenStreetMap contributors'
            }).addTo(map);

            L.marker([39.8283, -98.5795]).addTo(map)
                .bindPopup('<b>Monitoring Source</b><br/>Target: $($data.targetHost)')
                .openPopup();
        } else {
            const mapContainer = document.getElementById('map');
            if (mapContainer) {
                mapContainer.innerHTML = '<div style="display:flex;align-items:center;justify-content:center;height:100%;color:#6c757d;font:14px sans-serif;">Leaflet maps not available (offline?).</div>';
            }
        }

        // Animated Network Path Visualization
        const pathCanvas = document.getElementById('networkPath');
        const ctx = pathCanvas.getContext('2d');

        function resizeCanvas() {
            pathCanvas.width = pathCanvas.offsetWidth;
            pathCanvas.height = pathCanvas.offsetHeight;
        }
        resizeCanvas();
        window.addEventListener('resize', resizeCanvas);

        const nodes = [
            { x: 50, y: 200, label: '💻 Local System', color: '#28a745' },
            { x: 200, y: 180, label: '🌐 Gateway', color: '#17a2b8' },
            { x: 350, y: 220, label: '🏢 ISP Network', color: '#ffc107' },
            { x: 500, y: 160, label: '🌍 Internet Backbone', color: '#6f42c1' },
            { x: 650, y: 200, label: '🎯 $($data.targetHost)', color: '#dc3545' }
        ];

        const particles = [];
        class Packet {
            constructor() {
                this.reset();
            }
            reset() {
                this.nodeIndex = 0;
                this.progress = 0;
                this.speed = 0.01 + Math.random() * 0.02;
                this.size = 4 + Math.random() * 4;
                this.color = ``hsl($([char]0x24){Math.random() * 360}, 70%, 60%)``;
            }
            update() {
                this.progress += this.speed;
                if (this.progress >= 1) {
                    this.nodeIndex++;
                    this.progress = 0;
                    if (this.nodeIndex >= nodes.length - 1) {
                        this.reset();
                    }
                }
            }
            draw() {
                const from = nodes[this.nodeIndex];
                const to = nodes[this.nodeIndex + 1];
                const x = from.x + (to.x - from.x) * this.progress;
                const y = from.y + (to.y - from.y) * this.progress;

                ctx.beginPath();
                ctx.arc(x, y, this.size, 0, Math.PI * 2);
                ctx.fillStyle = this.color;
                ctx.shadowBlur = 15;
                ctx.shadowColor = this.color;
                ctx.fill();
                ctx.shadowBlur = 0;
            }
        }

        // Create particles
        for (let i = 0; i < 15; i++) {
            particles.push(new Packet());
        }

        function animate() {
            ctx.clearRect(0, 0, pathCanvas.width, pathCanvas.height);

            // Draw connections
            ctx.strokeStyle = '#667eea40';
            ctx.lineWidth = 2;
            for (let i = 0; i < nodes.length - 1; i++) {
                ctx.beginPath();
                ctx.moveTo(nodes[i].x, nodes[i].y);
                ctx.lineTo(nodes[i + 1].x, nodes[i + 1].y);
                ctx.stroke();
            }

            // Draw nodes
            nodes.forEach(node => {
                ctx.beginPath();
                ctx.arc(node.x, node.y, 20, 0, Math.PI * 2);
                ctx.fillStyle = node.color;
                ctx.fill();
                ctx.strokeStyle = 'white';
                ctx.lineWidth = 3;
                ctx.stroke();

                ctx.fillStyle = 'white';
                ctx.font = 'bold 14px sans-serif';
                ctx.textAlign = 'center';
                ctx.fillText(node.label, node.x, node.y - 35);
            });

            // Update and draw particles
            particles.forEach(p => {
                p.update();
                p.draw();
            });

            requestAnimationFrame(animate);
        }
        animate();
    </script>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "✨ Enhanced report created: $OutputPath" -ForegroundColor Green

    if ($OpenBrowser) {
        Start-Process $OutputPath
    }

    return $OutputPath
}

function Get-TracerouteHopData {
    param([string]$TracerouteDir)

    $hops = @()
    $traceFiles = Get-ChildItem $TracerouteDir -Filter "traceroute-*.txt" | Select-Object -First 5

    foreach ($file in $traceFiles) {
        $content = Get-Content $file.FullName -Raw
        $lines = $content -split "`n" | Where-Object { $_ -match '^\s+\d+' }

        foreach ($line in $lines) {
            if ($line -match '(\d+\.\d+\.\d+\.\d+)') {
                $ip = $Matches[1]
                if ($ip -notmatch '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)') {
                    $hops += [pscustomobject]@{
                        ip = $ip
                        hostname = if ($line -match '\[([^\]]+)\]') { $Matches[1] } else { $ip }
                    }
                }
            }
        }
    }

    return ($hops | Select-Object -Unique -Property ip)
}
