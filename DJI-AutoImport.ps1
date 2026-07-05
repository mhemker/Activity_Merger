<#
.SYNOPSIS
    Auto-imports video and LRF files from a DJI Osmo Action 5 Pro (or similar
    DJI camera in mass-storage mode) to a local folder, verifies each copy by
    hash, and deletes the source files from the camera once verified.

.PARAMETER DestinationFolder
    Optional. Where to copy files to. Defaults to "Videos\DJI" under the
    current user's profile if not specified.

.EXAMPLE
    .\DJI-AutoImport.ps1
    Uses the default destination (%USERPROFILE%\Videos\DJI).

.EXAMPLE
    .\DJI-AutoImport.ps1 -DestinationFolder "D:\Footage\DJI"
    Copies files to D:\Footage\DJI instead.

.NOTES
    Designed to be triggered automatically via Task Scheduler when the camera
    is connected (see SETUP-INSTRUCTIONS.md), but can also be run manually by
    double-clicking DJI-AutoImport.bat or right-click > Run with PowerShell.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$DestinationFolder
)

$ErrorActionPreference = 'Stop'

if ($DestinationFolder) {
    $DestRoot = $DestinationFolder
}
else {
    $DestRoot = Join-Path $env:USERPROFILE 'Videos\DJI'
}
$LogFile    = Join-Path $env:TEMP 'DJI_AutoImport.log'
$Extensions = @('.mp4', '.mov', '.lrf')

# --- Restrict to a specific camera --------------------------------------
# Fill in one or both of these using Get-DriveInfo.ps1 (run it with the
# camera plugged in, note the Volume Label and/or PNPDeviceID). If both are
# left blank, the script falls back to $RequireDjiManufacturer below.
#
#   CameraVolumeLabel: exact volume label shown in File Explorer / Get-DriveInfo.ps1
#   CameraSerialMatch: a substring of the PNPDeviceID unique to this camera
#                      (this stays fixed even if the SD card is reformatted)
$CameraVolumeLabel = ''
$CameraSerialMatch = ''

# If the two settings above are blank, this decides the fallback behavior:
#   $true  = accept any drive whose USB device reports "DJI" in its model
#            string (i.e. any DJI camera, not just one specific unit).
#            NOTE: many DJI cameras (including this one) report generic
#            USB mass-storage identifiers (Manufacturer "Linux", Model
#            "File-Stor Gadget") with no "DJI" string anywhere, so this
#            option will find nothing on those cameras. Confirmed via
#            Get-DriveInfo.ps1 / Event Viewer before relying on this.
#   $false = accept any drive at all with a matching DCIM\DJI* media folder,
#            regardless of manufacturer (default, since manufacturer
#            matching doesn't work for this camera)
$RequireDjiManufacturer = $false
# -------------------------------------------------------------------------

# How long to keep retrying drive detection before giving up. When triggered
# by a disk-arrival event, the drive letter may not be mounted yet at the
# instant the task fires - retrying for a bit avoids a false "not detected"
# on a camera that's actually there.
$DetectionRetryAttempts = 10
$DetectionRetryDelaySeconds = 3

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

function Get-AssociatedDiskDrives {
    param([Microsoft.Management.Infrastructure.CimInstance]$LogicalDisk)

    $results = @()
    $partitionQuery = "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='$($LogicalDisk.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition"
    $partitions = Get-CimInstance -Query $partitionQuery -ErrorAction SilentlyContinue
    foreach ($p in $partitions) {
        $diskQuery = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($p.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition"
        $results += Get-CimInstance -Query $diskQuery -ErrorAction SilentlyContinue
    }
    return $results
}

function Test-IsTargetCamera {
    param([Microsoft.Management.Infrastructure.CimInstance]$LogicalDisk)

    # Priority 1: specific-camera match, if configured.
    if ($CameraVolumeLabel -or $CameraSerialMatch) {
        if ($CameraVolumeLabel -and $LogicalDisk.VolumeName -eq $CameraVolumeLabel) {
            return $true
        }
        if ($CameraSerialMatch) {
            $disks = Get-AssociatedDiskDrives -LogicalDisk $LogicalDisk
            foreach ($disk in $disks) {
                if ($disk.PNPDeviceID -like "*$CameraSerialMatch*") {
                    return $true
                }
            }
        }
        return $false
    }

    # Priority 2: general "any DJI camera" match, if enabled.
    if ($RequireDjiManufacturer) {
        $disks = Get-AssociatedDiskDrives -LogicalDisk $LogicalDisk
        foreach ($disk in $disks) {
            if ($disk.Model -like '*DJI*' -or $disk.PNPDeviceID -like '*DJI*') {
                return $true
            }
        }
        return $false
    }

    # Priority 3: no identity filter at all - accept any drive with matching
    # media folders (caller still checks for DCIM\DJI* structure separately).
    return $true
}

function Find-DjiDrive {
    # Look across drives for a DCIM folder containing DJI* folders that
    # actually hold video/LRF files, so we don't accidentally grab an
    # unrelated drive. If CameraVolumeLabel/CameraSerialMatch are set, also
    # require the drive to match this specific camera.
    #
    # DriveType 2 = Removable, DriveType 3 = Fixed. Most USB flash drives
    # report as Removable, but some USB mass-storage "gadget" devices
    # (common on cameras/phones using a generic Linux USB gadget stack)
    # don't set the removable-media flag and show up as Fixed instead -
    # so both types are checked here. This is safe because the DCIM\DJI*
    # folder check below still filters out unrelated fixed drives (e.g.
    # the actual C: drive).
    $drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -in @(2, 3) }
    Write-Log "Scanning $($drives.Count) drive(s): $(($drives | ForEach-Object { "$($_.DeviceID) (Type=$($_.DriveType), Label='$($_.VolumeName)')" }) -join '; ')"
    foreach ($d in $drives) {
        $root = "$($d.DeviceID)\"
        if (-not (Test-Path $root)) {
            Write-Log "Skipping $root - not accessible."
            continue
        }
        if (-not (Test-IsTargetCamera -LogicalDisk $d)) {
            Write-Log "Skipping $root - does not match configured camera identity."
            continue
        }

        $dcim = Join-Path $root 'DCIM'
        if (-not (Test-Path $dcim)) {
            Write-Log "Skipping $root - no DCIM folder."
            continue
        }

        $djiFolders = Get-DjiMediaFolders -DcimPath $dcim
        if (-not $djiFolders) {
            Write-Log "Skipping $root - DCIM exists but no DJI* folders inside."
            continue
        }

        $hasMedia = $djiFolders | ForEach-Object {
            Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $Extensions -contains $_.Extension.ToLower() }
        } | Select-Object -First 1

        if ($hasMedia) {
            return $root
        }
        else {
            Write-Log "Skipping $root - DJI* folder(s) found but no matching video/LRF files inside."
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
if ($CameraVolumeLabel -or $CameraSerialMatch) {
    Write-Log "Camera identity filter active: specific camera (Label='$CameraVolumeLabel', SerialMatch='$CameraSerialMatch')."
}
elseif ($RequireDjiManufacturer) {
    Write-Log 'Camera identity filter active: any DJI-branded drive.'
}
else {
    Write-Log 'No manufacturer/identity filter - matching any drive with DCIM\DJI* media.'
}

$cameraRoot = $null
for ($attempt = 1; $attempt -le $DetectionRetryAttempts; $attempt++) {
    $cameraRoot = Find-DjiDrive
    if ($cameraRoot) { break }
    Write-Log "Camera not found yet (attempt $attempt of $DetectionRetryAttempts) - waiting $DetectionRetryDelaySeconds sec."
    Start-Sleep -Seconds $DetectionRetryDelaySeconds
}

if (-not $cameraRoot) {
    Write-Log "No DJI camera drive detected after $DetectionRetryAttempts attempts. Exiting." 'INFO'
    Write-Log '--- DJI auto-import finished (no camera detected) ---'
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
    Write-Log '--- DJI auto-import finished (no DJI* folders found) ---'
    exit 0
}
Write-Log "Found $($djiFolders.Count) DJI* folder(s): $($djiFolders.Name -join ', ')"

$sourceFiles = $djiFolders | ForEach-Object {
    Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $Extensions -contains $_.Extension.ToLower() }
}

if (-not $sourceFiles) {
    Write-Log 'No video or LRF files found inside DJI* folders. Exiting.'
    Write-Log '--- DJI auto-import finished (no files to import) ---'
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
