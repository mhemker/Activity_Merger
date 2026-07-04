<#
.SYNOPSIS
    Auto-imports video and LRF files from a DJI Osmo Action 5 Pro (or similar
    DJI camera in mass-storage mode) to the local Videos\DJI folder, verifies
    each copy by hash, and deletes the source files from the camera once
    verified.

.NOTES
    Designed to be triggered automatically via Task Scheduler when the camera
    is connected (see SETUP-INSTRUCTIONS.md), but can also be run manually by
    double-clicking DJI-AutoImport.bat or right-click > Run with PowerShell.
#>

$ErrorActionPreference = 'Stop'

$DestRoot   = Join-Path $env:USERPROFILE 'Videos\DJI'
$LogFile    = Join-Path $env:TEMP 'DJI_AutoImport.log'
$Extensions = @('.mp4', '.mov', '.lrf')

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp [$Level] $Message"
    $line | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host $line
}

function Get-DjiMediaFolders {
    param([string]$DcimPath)

    # DJI cameras store media in one or more folders named like "DJI_001",
    # "DJI_002", etc. directly under DCIM. Only look inside those.
    return Get-ChildItem -Path $DcimPath -Directory -Filter 'DJI*' -ErrorAction SilentlyContinue
}

function Find-DjiDrive {
    # Look across removable drives for a DCIM folder containing DJI* folders
    # that actually hold video/LRF files, so we don't accidentally grab an
    # unrelated USB stick.
    $drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
    foreach ($d in $drives) {
        $root = "$($d.DeviceID)\"
        if (-not (Test-Path $root)) { continue }
        $dcim = Join-Path $root 'DCIM'
        if (-not (Test-Path $dcim)) { continue }

        $djiFolders = Get-DjiMediaFolders -DcimPath $dcim
        if (-not $djiFolders) { continue }

        $hasMedia = $djiFolders | ForEach-Object {
            Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $Extensions -contains $_.Extension.ToLower() }
        } | Select-Object -First 1

        if ($hasMedia) {
            return $root
        }
    }
    return $null
}

function Get-UniqueDestinationPath {
    param([string]$DestFolder, [string]$FileName)

    $candidate = Join-Path $DestFolder $FileName
    if (-not (Test-Path $candidate)) { return $candidate }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $ext  = [System.IO.Path]::GetExtension($FileName)
    $i = 1
    do {
        $candidate = Join-Path $DestFolder "$base`_$i$ext"
        $i++
    } while (Test-Path $candidate)

    return $candidate
}

Write-Log '--- DJI auto-import started ---'

$cameraRoot = Find-DjiDrive
if (-not $cameraRoot) {
    Write-Log 'No DJI camera drive detected. Exiting.' 'INFO'
    exit 0
}
Write-Log "Camera detected at $cameraRoot"

if (-not (Test-Path $DestRoot)) {
    New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
    Write-Log "Created destination folder $DestRoot"
}

$dcim = Join-Path $cameraRoot 'DCIM'
$djiFolders = Get-DjiMediaFolders -DcimPath $dcim

if (-not $djiFolders) {
    Write-Log 'No DJI* folders found under DCIM. Exiting.'
    exit 0
}
Write-Log "Found $($djiFolders.Count) DJI* folder(s): $($djiFolders.Name -join ', ')"

$sourceFiles = $djiFolders | ForEach-Object {
    Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $Extensions -contains $_.Extension.ToLower() }
}

if (-not $sourceFiles) {
    Write-Log 'No video or LRF files found inside DJI* folders. Exiting.'
    exit 0
}
Write-Log "Found $($sourceFiles.Count) file(s) to process."

$copyResults = @()

foreach ($file in $sourceFiles) {
    try {
        $destPath = Get-UniqueDestinationPath -DestFolder $DestRoot -FileName $file.Name

        Write-Log "Copying '$($file.FullName)' -> '$destPath'"
        Copy-Item -Path $file.FullName -Destination $destPath -Force

        $srcHash  = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
        $destHash = (Get-FileHash -Path $destPath -Algorithm SHA256).Hash

        if ($srcHash -eq $destHash) {
            Write-Log "Validated OK: $($file.Name)"
            $copyResults += [PSCustomObject]@{
                Source   = $file.FullName
                Dest     = $destPath
                Verified = $true
            }
        }
        else {
            Write-Log "HASH MISMATCH for $($file.Name) - will NOT delete source." 'ERROR'
            $copyResults += [PSCustomObject]@{
                Source   = $file.FullName
                Dest     = $destPath
                Verified = $false
            }
        }
    }
    catch {
        Write-Log "Error processing $($file.FullName): $($_.Exception.Message)" 'ERROR'
        $copyResults += [PSCustomObject]@{
            Source   = $file.FullName
            Dest     = $null
            Verified = $false
        }
    }
}

$verifiedCount = ($copyResults | Where-Object { $_.Verified }).Count
$failedCount   = ($copyResults | Where-Object { -not $_.Verified }).Count

Write-Log "Copy/validation complete: $verifiedCount verified, $failedCount failed."

foreach ($result in $copyResults | Where-Object { $_.Verified }) {
    try {
        Remove-Item -Path $result.Source -Force
        Write-Log "Deleted from camera: $($result.Source)"
    }
    catch {
        Write-Log "Failed to delete $($result.Source): $($_.Exception.Message)" 'ERROR'
    }
}

if ($failedCount -gt 0) {
    Write-Log "$failedCount file(s) failed validation and were left on the camera. Check $LogFile for details." 'WARN'
}

Write-Log '--- DJI auto-import finished ---'
