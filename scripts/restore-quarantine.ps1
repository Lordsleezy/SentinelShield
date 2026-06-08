# Restore files from data/quarantine/ using shield.log entries.
# Format: Quarantined SOURCE -> DEST

param(
    [string]$LogPath = "$PSScriptRoot\..\data\logs\shield.log",
    [string]$QuarantineDir = "$PSScriptRoot\..\data\quarantine"
)

$restored = 0
$skipped = 0
$failed = 0

if (-not (Test-Path $LogPath)) {
    Write-Error "Log not found: $LogPath"
    exit 1
}

$lines = Get-Content $LogPath | Where-Object { $_ -match 'Quarantined (.+) -> (.+)' }

foreach ($line in $lines) {
    if ($line -match 'Quarantined (.+?) -> (.+)$') {
        $source = $Matches[1].Trim()
        $dest = $Matches[2].Trim()

        if (-not (Test-Path $dest)) {
            Write-Warning "Quarantine file missing, skipping: $dest"
            $skipped++
            continue
        }

        $parent = Split-Path $source -Parent
        if ($parent -and -not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        if (Test-Path $source) {
            Write-Warning "Original already exists, skipping: $source"
            $skipped++
            continue
        }

        try {
            Move-Item -LiteralPath $dest -Destination $source -Force
            Write-Host "Restored: $source"
            $restored++
        } catch {
            Write-Warning "Failed to restore $source : $_"
            $failed++
        }
    }
}

Write-Host ""
Write-Host "Done. Restored: $restored | Skipped: $skipped | Failed: $failed"
