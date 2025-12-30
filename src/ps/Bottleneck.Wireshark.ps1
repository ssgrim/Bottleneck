function Analyze-WiresharkCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $Path,
        [ValidateSet('pcapng','json','csv')]
        [string] $Format = 'pcapng'
    )
    if (-not (Test-Path $Path)) { throw "Wireshark file not found: $Path" }
    $summary = [ordered]@{ Packets=0; Drops=0; AvgLatencyMs=0; MaxLatencyMs=0; MinLatencyMs=0 }
    switch ($Format) {
        'pcapng' {
            # Use tshark to export to JSON if available
            $tshark = (Get-Command tshark -ErrorAction SilentlyContinue)
            if (-not $tshark) { throw "tshark not found. Install Wireshark (includes tshark) or export JSON from Wireshark (File > Export Packet Dissections > As JSON)." }
            $tmp = New-TemporaryFile
            Remove-Item $tmp -Force
            $tmpJson = [System.IO.Path]::ChangeExtension($tmp.FullName, '.json')
            # Export minimal fields to JSON
            & $tshark.Source -r $Path -T json > $tmpJson
            $json = Get-Content -Path $tmpJson -Raw | ConvertFrom-Json
            Remove-Item $tmpJson -Force -ErrorAction SilentlyContinue
            if (-not $json) { return ($summary | ConvertTo-Json | ConvertFrom-Json) }
            $summary.Packets = ($json | Measure-Object).Count
            $latencies = @()
            foreach ($pkt in $json) {
                $frame = $pkt._source.layers.'frame.frame_frame_time_delta_displayed'
                if (-not $frame) { $frame = $pkt._source.layers.'frame.frame_frame_time_delta' }
                if ($frame -and ($frame -as [double])) { $latencies += [double]$frame }
                $tcp = $pkt._source.layers.tcp
                if ($tcp) {
                    $flags = @($tcp.'tcp.analysis.flags')
                    if ($flags -match 'retransmission|duplicate_ack|out_of_order') { $summary.Drops++ }
                }
            }
            if ($latencies.Count -gt 0) {
                $summary.AvgLatencyMs = [math]::Round((($latencies | Measure-Object -Average).Average) * 1000, 2)
                $summary.MaxLatencyMs = [math]::Round(((($latencies | Measure-Object -Maximum).Maximum) * 1000), 2)
                $summary.MinLatencyMs = [math]::Round(((($latencies | Measure-Object -Minimum).Minimum) * 1000), 2)
            }
        }
        'csv' {
            $rows = Import-Csv -Path $Path
            if (-not $rows) { return ($summary | ConvertTo-Json | ConvertFrom-Json) }
            $summary.Packets = $rows.Count
            # Expect columns like: Time,Source,Destination,Protocol,Length,Info,Delta
            $latencies = @()
            foreach ($r in $rows) {
                if ($r.Delta -and ($r.Delta -as [double])) { $latencies += [double]$r.Delta }
                if ($r.Info -match 'Retransmission|Dup ACK|Out-of-order') { $summary.Drops++ }
            }
            if ($latencies.Count -gt 0) {
                $summary.AvgLatencyMs = [math]::Round((($latencies | Measure-Object -Average).Average) * 1000, 2)
                $summary.MaxLatencyMs = [math]::Round(((($latencies | Measure-Object -Maximum).Maximum) * 1000), 2)
                $summary.MinLatencyMs = [math]::Round(((($latencies | Measure-Object -Minimum).Minimum) * 1000), 2)
            }
        }
        'json' {
            $obj = Get-Content -Path $Path -Raw | ConvertFrom-Json
            if ($obj -is [array]) { $summary.Packets = $obj.Count }
            # Heuristic placeholders
        }
    }
    return ($summary | ConvertTo-Json | ConvertFrom-Json)
}

function Get-LatestWiresharkCapture {
    [CmdletBinding()]
    param(
        [Parameter()][string] $Directory,
        [Parameter()][string] $DefaultDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'WireSharkLogs')
    )
    $dir = if ($Directory) { $Directory } else { $DefaultDirectory }
    if (-not (Test-Path $dir)) { return $null }
    $files = Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue |
        Where-Object { @('.pcapng','.json','.csv') -contains $_.Extension } |
        Sort-Object LastWriteTime -Descending
    return ($files | Select-Object -First 1)
}

function Add-WiresharkSummaryToReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Summary
    )
    try {
        New-WiresharkSection -Summary $Summary
    } catch {
        # Fallback: write to host
        Write-Host ("Wireshark: packets={0}, drops={1}, avg={2}ms, max={3}ms" -f $Summary.Packets, $Summary.Drops, $Summary.AvgLatencyMs, $Summary.MaxLatencyMs)
    }
}
