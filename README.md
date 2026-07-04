# Activity Merger & Garmin Automation
Automatically transfer the videos from your camera, download the Garmin activities and then merge them together

A lightweight Python suite designed to handle local file manipulations and automate the headless retrieval of fitness activities directly from Garmin Connect. 

The download tool bypasses strict WAF/TLS fingerprint blocks natively using `curl_cffi` to mimic browser profiles, utilizes persistent local tokens to bypass Multi-Factor Authentication (MFA) on subsequent runs, and dumps workout exports directly into your active execution folder.

---

## 📦 Installation & Setup

1. **Clone the Repository**
   Clone the workspace directly from your GitHub profile repository and enter the local directory:
   ```bash
   git clone https://github.com/mhemker/Activity_Merger
   cd Activity_Merger
   ```

2. **Install Dependencies**
   Install the required libraries listed in the project requirements file:
   ```bash
   pip install -r requirements.txt
   ```

3. **Configure Your Credentials**
   Create a file named `.env` in the root of the project directory (the same folder as the scripts) and add your Garmin Connect login credentials:
   ```env
   GARMIN_EMAIL=your_email@example.com
   GARMIN_PASSWORD=your_secure_password
   ```
   *Note: Your `.env` file is protected locally and explicitly blocked from being tracked via the `.gitignore` rule.*

---

## 🏃‍♂️ Usage: Garmin Downloader

The downloader script (`garmin_downloader.py`) searches your Garmin profile history and downloads matching activities simultaneously in **GPX**, **TCX**, and **FIT** (packed within a zip folder) formats.

### Running for a Specific Date
Pass a targeted calendar date in `YYYY-MM-DD` format as a trailing argument:
```bash
python garmin_downloader.py 2026-07-03
```

### Running for the Current Date
If you omit the date argument entirely, the script automatically defaults to fetching current calendar activities:
```bash
python garmin_downloader.py
```

### 🔒 Multi-Factor Authentication (MFA) & Sessions
* **First Run:** If MFA is active on your account, the script will halt and prompt you inside your terminal console: `Enter the MFA verification code sent to your phone/email:`. Type your 6-digit code and press **Enter**.
* **Subsequent Runs:** The script saves authenticated sessions to `~/.garminconnect/garmin_tokens.json`. Future runs will automatically log in using this secure token profile and entirely bypass the MFA checkpoint.

---

## 🎥 Camera Import: DJI Auto-Import

Scripts to automatically pull video and LRF files off a DJI camera (tested
with the DJI Osmo Action 5 Pro) when it's connected via USB, verify the
copy, and clear the files off the camera once verified. This is the first
step in the pipeline — camera footage in, then Garmin activities down, then
merge.

### What it does

When the camera is connected as a USB drive:

1. Detects the camera drive (with configurable strictness — see
   [Camera identification](#camera-identification) below).
2. Finds all `.mp4`, `.mov`, and `.lrf` files inside the `DJI*` folders under
   `DCIM` (only the files are copied, not the folder structure).
3. Copies them to a destination folder (default: `%USERPROFILE%\Videos\DJI`).
4. Verifies each copy with a SHA-256 hash comparison against the source.
5. Deletes only the files that passed verification from the camera. Anything
   that fails is left on the camera and logged.

Everything is logged to `%TEMP%\DJI_AutoImport.log`.

### Files

| File | Purpose |
|---|---|
| `DJI-AutoImport.ps1` | Main script: detect, copy, verify, delete. |
| `DJI-AutoImport.bat` | Double-clickable wrapper around the PowerShell script. Also accepts an optional destination folder argument. |
| `Get-DriveInfo.ps1` | Diagnostic helper that lists connected removable drives with their volume label and USB hardware ID, used to identify a specific camera. |
| `New-DjiAutoImportTask.ps1` | Creates (or removes) the Task Scheduler task that runs `DJI-AutoImport.ps1` automatically when a USB device is connected. |
| `New-DjiAutoImportTask.bat` | Double-clickable, self-elevating wrapper around `New-DjiAutoImportTask.ps1`. |
| `SETUP-INSTRUCTIONS.md` | Full setup walkthrough, including automatic triggering via Task Scheduler. |

### Quick start

1. Plug in the camera and double-click `DJI-AutoImport.bat` to test it
   manually. Confirm files land in `Videos\DJI` and are removed from the
   camera.
2. Double-click `New-DjiAutoImportTask.bat` (it will prompt for
   Administrator permission) to set up the Task Scheduler task
   automatically. See `SETUP-INSTRUCTIONS.md` for details and a manual
   alternative.

### Camera identification

By default, the script accepts any USB drive whose underlying device
reports "DJI" in its model info — so it works with this camera (or any DJI
camera) out of the box. Two other modes are available by editing the
variables at the top of `DJI-AutoImport.ps1`:

- **This exact camera only** — set `$CameraVolumeLabel` and/or
  `$CameraSerialMatch` (found via `Get-DriveInfo.ps1`).
- **Any drive with matching folders, any manufacturer** — set
  `$RequireDjiManufacturer = $false`.

See `SETUP-INSTRUCTIONS.md` for full details on each option.

### Custom destination folder

The destination folder can be overridden without editing the script:

```powershell
.\DJI-AutoImport.ps1 -DestinationFolder "D:\Footage\DJI"
```

```
DJI-AutoImport.bat "D:\Footage\DJI"
```

Requires Windows with PowerShell (built in on Windows 10/11) and the camera
connected in USB mass-storage mode (appears as a drive letter in File
Explorer).

---

## 🤖 AI Assistance

Portions of this repository (including the DJI auto-import scripts and this
README) were developed with the help of AI coding assistants — Claude
(Anthropic) and Gemini (Google).

---

## 📂 Repository File Structure

```text
Activity_Merger/
│
├── .env                    # Secret credentials file (ignored by git)
├── .gitignore              # Tells git to block tracking tracking sensitive logs/.env
├── requirements.txt        # Holds structural package dependencies
├── README.md               # Setup guidelines and operations manual
├── garmin_downloader.py    # Headless session automated download utility
├── DJI-AutoImport.ps1      # Camera import: detect, copy, verify, delete
├── DJI-AutoImport.bat      # Double-clickable wrapper for DJI-AutoImport.ps1
├── Get-DriveInfo.ps1       # Diagnostic helper to identify a specific camera
├── New-DjiAutoImportTask.ps1 # Creates/removes the Task Scheduler task
├── New-DjiAutoImportTask.bat # Double-clickable wrapper for New-DjiAutoImportTask.ps1
└── SETUP-INSTRUCTIONS.md   # Full DJI auto-import setup walkthrough
```
