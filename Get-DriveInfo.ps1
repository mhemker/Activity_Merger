<#
.SYNOPSIS
    Diagnostic helper: lists connected removable drives along with their
    volume label and underlying USB device info, so you can identify exactly
    which values uniquely belong to your DJI Osmo Action 5 Pro.

    Run this with the camera plugged in, then run it again with the camera
    unplugged (and maybe a different USB drive plugged in) to compare -
    that confirms which values are unique to the camera.
#>

$drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }

foreach ($d in $drives) {
    Write-Host "==================================================="
    Write-Host "Drive Letter   : $($d.DeviceID)"
    Write-Host "Volume Label   : $($d.VolumeName)"
    Write-Host "Volume Serial  : $($d.VolumeSerialNumber)"

    # Walk from logical disk -> partition -> physical disk drive to get the
    # USB device's PNPDeviceID, which contains a hardware serial number
    # that stays the same even if the SD card is reformatted (since it
    # belongs to the camera's USB controller, not the storage/filesystem).
    $partitionQuery = "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='$($d.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition"
    $partitions = Get-CimInstance -Query $partitionQuery

    foreach ($p in $partitions) {
        $diskQuery = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($p.DeviceID)'} WHERE AssocClass=Win32_DiskDriveToDiskPartition"
        $disks = Get-CimInstance -Query $diskQuery
        foreach ($disk in $disks) {
            Write-Host "PNPDeviceID    : $($disk.PNPDeviceID)"
            Write-Host "Model          : $($disk.Model)"
        }
    }
}
Write-Host "==================================================="
Write-Host ""
Write-Host "Note the Volume Label and/or PNPDeviceID above while the camera"
Write-Host "is plugged in - you'll paste one of these into DJI-AutoImport.ps1."
