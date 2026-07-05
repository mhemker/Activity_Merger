<#
.SYNOPSIS
    Creates (or removes) the Windows Task Scheduler task that runs
    DJI-AutoImport.ps1 automatically whenever a USB device is connected.

    This automates the manual Task Scheduler steps described in
    SETUP-INSTRUCTIONS.md.

.PARAMETER DestinationFolder
    Optional. Passed through to DJI-AutoImport.ps1 as -DestinationFolder.
    If omitted, DJI-AutoImport.ps1 uses its own default (Videos\DJI).

.PARAMETER TaskName
    Optional. Name of the scheduled task. Defaults to "DJI Auto Import".

.PARAMETER Remove
    If specified, deletes the scheduled task instead of creating it.

.EXAMPLE
    .\New-DjiAutoImportTask.ps1
    Creates the task using the default destination folder.

.EXAMPLE
    .\New-DjiAutoImportTask.ps1 -DestinationFolder "D:\Footage\DJI"
    Creates the task with a custom destination folder.

.EXAMPLE
    .\New-DjiAutoImportTask.ps1 -Remove
    Deletes the previously created task.

.NOTES
    Must be run from (or alongside) the folder containing DJI-AutoImport.ps1.
    Run PowerShell as Administrator - creating a task with an event-log
    trigger requires elevation.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$DestinationFolder,

    [Parameter(Mandatory = $false)]
    [string]$TaskName = 'DJI Auto Import',

    [Parameter(Mandatory = $false)]
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ScheduledTaskExists {
    param([string]$Name)

    # schtasks exits non-zero (and writes to stderr) when the task doesn't
    # exist, which is expected here - not a real error. Temporarily relax
    # $ErrorActionPreference so PowerShell doesn't turn that into a
    # terminating exception.
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        schtasks /query /tn "$Name" *> $null
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $prevPref
    }
}

if (-not (Test-IsAdmin)) {
    Write-Host "This script must be run as Administrator (creating an event-triggered task requires elevation)." -ForegroundColor Yellow
    Write-Host "Right-click PowerShell and choose 'Run as Administrator', then run this script again." -ForegroundColor Yellow
    exit 1
}

if ($Remove) {
    if (Test-ScheduledTaskExists -Name $TaskName) {
        schtasks /delete /tn "$TaskName" /f | Out-Null
        Write-Host "Removed scheduled task '$TaskName'." -ForegroundColor Green
    }
    else {
        Write-Host "No scheduled task named '$TaskName' was found." -ForegroundColor Yellow
    }
    exit 0
}

$scriptDir = $PSScriptRoot
$importScript = Join-Path $scriptDir 'DJI-AutoImport.ps1'

if (-not (Test-Path $importScript)) {
    Write-Host "Could not find DJI-AutoImport.ps1 next to this script (expected at '$importScript')." -ForegroundColor Red
    Write-Host "Make sure New-DjiAutoImportTask.ps1 lives in the same folder as DJI-AutoImport.ps1." -ForegroundColor Red
    exit 1
}

$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$importScript`""
if ($DestinationFolder) {
    $arguments += " -DestinationFolder `"$DestinationFolder`""
}

# Remove any pre-existing task with the same name so this script is safe to
# re-run (e.g. after changing -DestinationFolder).
if (Test-ScheduledTaskExists -Name $TaskName) {
    Write-Host "Existing task '$TaskName' found - removing it before recreating." -ForegroundColor Yellow
    schtasks /delete /tn "$TaskName" /f | Out-Null
}

# /sc onevent + /ec + /mo creates an event-triggered task. Event ID 400 in
# the Kernel-PnP/Configuration log fires every time a device is enumerated -
# i.e. every physical connection - unlike the DriverFrameworks-UserMode
# "install" event, which only fires the first time Windows installs a
# driver for a given device.
$eventChannel = 'Microsoft-Windows-Kernel-PnP/Configuration'
$eventQuery   = '*[System[(EventID=400 or EventID=410)]]'

$prevPref = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
schtasks /create `
    /tn "$TaskName" `
    /tr "powershell.exe $arguments" `
    /sc onevent `
    /ec "$eventChannel" `
    /mo "$eventQuery" `
    /rl highest `
    /f | Out-Null
$createExitCode = $LASTEXITCODE
$ErrorActionPreference = $prevPref

if ($createExitCode -eq 0) {
    Write-Host "Created scheduled task '$TaskName'." -ForegroundColor Green
    Write-Host "It will run DJI-AutoImport.ps1 automatically whenever a USB device is connected."
    if ($DestinationFolder) {
        Write-Host "Destination folder: $DestinationFolder"
    }
    Write-Host ""
    Write-Host "To test: plug in the camera, then check %TEMP%\DJI_AutoImport.log after a few seconds."
    Write-Host "To remove this task later, run: .\New-DjiAutoImportTask.ps1 -Remove"
}
else {
    Write-Host "Failed to create the scheduled task (schtasks exit code $createExitCode). Try running SETUP-INSTRUCTIONS.md's manual steps instead." -ForegroundColor Red
    exit 1
}
