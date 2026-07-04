# DJI Osmo Action 5 Pro Auto-Import — Setup

## What it does
When your DJI Osmo Action 5 Pro is connected as a USB drive, this script:
1. Detects the camera by finding a `DCIM` folder containing video/LRF files.
2. Copies all `.mp4`, `.mov`, and `.lrf` files to `%USERPROFILE%\Videos\DJI`.
3. Verifies each copy with a SHA-256 hash comparison against the source.
4. Deletes only the files that passed verification from the camera. Anything
   that fails verification is left on the camera untouched, and logged.

Log file: `%TEMP%\DJI_AutoImport.log`

## 1. Choose how strictly to identify the camera
By default the script will import from *any* USB drive with a `DCIM\DJI*`
media folder, which would also pick up someone else's DJI camera. There are
three levels of restriction, configured at the top of `DJI-AutoImport.ps1`:

**Option A — Any DJI camera (recommended default, already set):**
```powershell
$CameraVolumeLabel = ''
$CameraSerialMatch = ''
$RequireDjiManufacturer = $true
```
Accepts any drive whose underlying USB device reports "DJI" in its model
info — so it works with this camera (or a replacement/second DJI camera)
without any per-device setup, but ignores non-DJI USB drives.

**Option B — This exact camera only:**
```powershell
$CameraVolumeLabel = 'YOUR_VOLUME_LABEL_HERE'
# or
$CameraSerialMatch = 'a_unique_substring_from_the_PNPDeviceID'
```
1. Plug in your camera.
2. Run `Get-DriveInfo.ps1` (right-click > Run with PowerShell, or
   `powershell -File Get-DriveInfo.ps1` from a terminal).
3. Note the **Volume Label** and/or **PNPDeviceID** it prints.
4. Fill in one of the two variables above. `CameraSerialMatch` is more
   reliable since it's tied to the camera's USB hardware rather than the SD
   card, so it survives reformatting. If either of these is filled in, it
   takes priority over Option A.

**Option C — Any drive with DJI-style folders (least restrictive):**
```powershell
$CameraVolumeLabel = ''
$CameraSerialMatch = ''
$RequireDjiManufacturer = $false
```
Only checks for a `DCIM\DJI*` folder structure with video/LRF files —
matches any camera or drive with that layout, DJI-branded or not.

## 2. Put the files somewhere permanent
Move `DJI-AutoImport.ps1` and `DJI-AutoImport.bat` to a folder that won't move
or get deleted, e.g. `C:\Scripts\DJI-AutoImport\`.

## 3. Test it manually first
Plug in the camera, then double-click `DJI-AutoImport.bat`. Check
`%TEMP%\DJI_AutoImport.log` and confirm the files land in `Videos\DJI` and get
removed from the camera as expected before automating it.

## 4. Make it run automatically when the camera is plugged in

### Option 1 — Automated (recommended)
Double-click **`New-DjiAutoImportTask.bat`** (it will prompt for
Administrator permission via a UAC popup — this is required because
event-triggered tasks need elevation). Or, if you'd rather run it directly:

```powershell
.\New-DjiAutoImportTask.ps1
```

> **Note:** Double-clicking a `.ps1` file directly opens it in a text editor
> instead of running it — that's a Windows default for all `.ps1` files, not
> specific to this script. Use the `.bat` wrapper for double-click use, or
> open PowerShell as Administrator first and run the `.ps1` from there.

With a custom destination folder:

```powershell
.\New-DjiAutoImportTask.ps1 -DestinationFolder "D:\Footage\DJI"
```
```
New-DjiAutoImportTask.bat "D:\Footage\DJI"
```

This creates a Task Scheduler task named "DJI Auto Import" with the same
event trigger described in Option 2 below (fires on USB device install,
Event ID 2003). It's safe to re-run — it removes and recreates the task each
time, so you can change the destination folder later by just running it
again.

To remove the task later:
```powershell
.\New-DjiAutoImportTask.ps1 -Remove
```
```
New-DjiAutoImportTask.bat -Remove
```

### Option 2 — Manual
If you'd rather set it up by hand (or the script above fails), Windows Task
Scheduler can trigger on the "device installed" event that fires when a USB
drive is connected:

1. Open **Task Scheduler** → **Create Task** (not "Basic Task", so you get
   full trigger options).
2. **General tab**: name it (e.g. "DJI Auto Import"). Check "Run whether user
   is logged on or not" if you want it to work even when locked, or leave the
   default to run only when logged in.
3. **Triggers tab** → **New** → set "Begin the task" to **On an event**:
   - Log: `Microsoft-Windows-DriverFrameworks-UserMode/Operational`
   - Source: `DriverFrameworks-UserMode`
   - Event ID: `2003`
   (This fires when a new USB storage device finishes installing.)
4. **Actions tab** → **New** → Action: "Start a program"
   - Program/script: `powershell.exe`
   - Add arguments:
     `-NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\DJI-AutoImport\DJI-AutoImport.ps1"`
5. **Conditions/Settings tabs**: uncheck "Start the task only if the computer
   is on AC power" if this is a laptop, so it also runs on battery.
6. Save. Plug the camera back in to test — it may take a few seconds after
   Windows finishes installing the device driver for the trigger to fire.

### Note on this trigger
The "DriverFrameworks-UserMode" event fires for USB device installation in
general, not specifically for this camera. The script itself checks for a
DCIM folder with matching files, so it's safe if the task fires for other USB
devices — it'll just detect nothing and exit quietly. But if you plug in
other USB drives often, it will run (harmlessly) each time.

## Adjusting behavior
- Destination folder: defaults to `%USERPROFILE%\Videos\DJI`. Override it
  either by editing the fallback in the script, or per-run without editing
  the script:
  - PowerShell: `.\DJI-AutoImport.ps1 -DestinationFolder "D:\Footage\DJI"`
  - Batch file: `DJI-AutoImport.bat "D:\Footage\DJI"`
  - Task Scheduler: add `-DestinationFolder "D:\Footage\DJI"` to the
    arguments in the Actions tab (step 4 above).
- File types: edit the `$Extensions` array.
- If you'd rather keep files on the camera even after a successful copy
  (skip deletion), comment out the `Remove-Item` line in the script.
