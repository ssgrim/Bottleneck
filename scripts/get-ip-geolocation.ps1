# get-ip-geolocation.ps1
# Lookup geographic location for IP addresses using free API

function Get-IpGeolocation {
    param(
        [Parameter(Mandatory)][string[]]$IpAddresses,
        [int]$MaxResults = 10
    )

    $results = @()
    $count = 0

    foreach ($ip in ($IpAddresses | Select-Object -Unique -First $MaxResults)) {
        $count++
        Write-Progress -Activity "Looking up IP locations" -Status "$ip" -PercentComplete (($count / [math]::Min($IpAddresses.Count, $MaxResults)) * 100)

        try {
            # Using ip-api.com free tier (45 requests/minute)
            $response = Invoke-RestMethod -Uri "http://ip-api.com/json/$ip" -Method Get -TimeoutSec 5

            if ($response.status -eq 'success') {
                $results += [pscustomobject]@{
                    ip = $ip
                    city = $response.city
                    region = $response.regionName
                    country = $response.country
                    countryCode = $response.countryCode
                    lat = $response.lat
                    lon = $response.lon
                    isp = $response.isp
                    org = $response.org
                    as = $response.as
                }
            }

            # Rate limiting - free tier allows 45/min
            Start-Sleep -Milliseconds 1500
        } catch {
            Write-Warning "Failed to lookup $ip : $_"
        }
    }

    Write-Progress -Activity "Looking up IP locations" -Completed
    return $results
}

function Get-TracerouteIpAddresses {
    param([string]$TracerouteDir)

    $ips = @()
    $traceFiles = Get-ChildItem $TracerouteDir -Filter "traceroute-*.txt" -ErrorAction SilentlyContinue

    foreach ($file in ($traceFiles | Select-Object -First 10)) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $lines = $content -split "`n"
            foreach ($line in $lines) {
                if ($line -match '(\d+\.\d+\.\d+\.\d+)') {
                    $ip = $Matches[1]
                    # Skip private IPs
                    if ($ip -notmatch '^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.)') {
                        $ips += $ip
                    }
                }
            }
        }
    }

    return ($ips | Select-Object -Unique)
}

# Export for use in other scripts
if ($MyInvocation.InvocationName -ne '.') {
    # Running as standalone script
    param(
        [string]$TracerouteDir = (Join-Path $PSScriptRoot '..' 'Reports'),
        [string]$OutputJson
    )

    Write-Host "🌍 Analyzing traceroute files for IP locations..." -ForegroundColor Cyan

    $ips = Get-TracerouteIpAddresses -TracerouteDir $TracerouteDir
    Write-Host "Found $($ips.Count) unique public IP addresses" -ForegroundColor Green

    if ($ips.Count -gt 0) {
        Write-Host "Looking up geographic locations..." -ForegroundColor Cyan
        $locations = Get-IpGeolocation -IpAddresses $ips -MaxResults 20

        Write-Host "`nResults:" -ForegroundColor Green
        $locations | Format-Table ip, city, region, country, isp -AutoSize

        if ($OutputJson) {
            $locations | ConvertTo-Json -Depth 3 | Out-File $OutputJson -Encoding UTF8
            Write-Host "`n✅ Saved to: $OutputJson" -ForegroundColor Green
        }
    } else {
        Write-Host "No public IPs found in traceroute files" -ForegroundColor Yellow
    }
}
