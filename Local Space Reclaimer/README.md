# Local Space Reclaimer

Local Space Reclaimer is a PowerShell automation project designed to reclaim local disk space by converting eligible Microsoft OneDrive files to **online-only** status while preserving their cloud copies.

The solution combines a OneDrive storage-management script with Windows Task Scheduler automation so the cleanup process can run automatically on a recurring schedule without requiring manual intervention.

## Scripts

### `OneDrive_OnlineOnly.ps1`

This is the primary storage-reclamation script.

It scans configured OneDrive locations and identifies files that are eligible to be converted to online-only storage based on configurable conditions.

Eligible files are released from local storage while remaining available in OneDrive.

### Key Features

- Detects available OneDrive locations.
- Supports OneDrive Personal and Business directories.
- Recursively scans configured folders.
- Excludes recently modified files based on a configurable age threshold.
- Skips common temporary and incomplete-download files.
- Helps avoid processing files that may still be syncing.
- Converts eligible files to OneDrive online-only status.
- Preserves cloud-hosted copies of files.
- Supports a dry-run mode for testing.
- Generates execution logs.
- Reports eligible files and approximate reclaimed storage.
- Supports Windows PowerShell 5.1 and later.

## Example Usage

Run the script against a specific OneDrive location:

```powershell
.\OneDrive_OnlineOnly.ps1 `
    -TargetPaths "$env:OneDrive\Desktop" `
    -SkipModifiedWithinDays 3 `
    -Force
```

Test the script without making changes:

```powershell
.\OneDrive_OnlineOnly.ps1 -DryRun
```

---

### `Daily_Script_Autostart.ps1`

This script automates execution of `OneDrive_OnlineOnly.ps1` by registering a Windows Scheduled Task.

The scheduled task launches the OneDrive cleanup process automatically according to a recurring schedule.

The task is configured to:

- Run the OneDrive storage-reclamation script automatically.
- Execute on a recurring schedule.
- Target the user's OneDrive Desktop directory.
- Skip files modified within the configured number of days.
- Run missed executions when the computer becomes available.
- Run while the device is operating on battery power.
- Continue running if the computer switches to battery power.
- Start the scheduled task after registration.

The scheduled task is registered under the name:

```text
OneDrive FreeUp Space
```

## How It Works

```text
Windows Task Scheduler
        |
        v
Daily_Script_Autostart.ps1
        |
        v
OneDrive_OnlineOnly.ps1
        |
        v
Scan configured OneDrive folders
        |
        v
Identify eligible files
        |
        v
Exclude recent or temporary files
        |
        v
Convert eligible files to online-only
        |
        v
Release local disk storage
```

Files remain stored in OneDrive and can be downloaded automatically again when accessed.

## Project Structure

```text
Local Space Reclaimer/
├── Daily_Script_Autostart.ps1
├── OneDrive_OnlineOnly.ps1
└── README.md
```

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later
- Microsoft OneDrive
- OneDrive Files On-Demand enabled
- Permission to create Windows Scheduled Tasks

## Configuration

Before running `Daily_Script_Autostart.ps1`, verify that the script points to the correct location of `OneDrive_OnlineOnly.ps1`.

For example:

```powershell
$script = "C:\Scripts\OneDrive_OnlineOnly.ps1"
```

The target OneDrive directory can also be configured.

Example:

```powershell
$target = "$env:OneDrive\Desktop"
```

This can be changed to another OneDrive-backed directory as needed.

## Safety Features

The solution is designed to reclaim local disk space rather than delete cloud data.

`OneDrive_OnlineOnly.ps1` includes safeguards such as:

- No intentional deletion of files from OneDrive.
- Exclusion of recently modified files.
- Exclusion of common temporary files.
- Dry-run support before making changes.
- Execution logging.
- Controlled conversion to OneDrive online-only storage.

## Use Case

This automation is useful for systems where OneDrive synchronization gradually consumes significant local storage.

Instead of manually selecting files and choosing **Free up space**, the scripts automate the process and apply consistent rules for determining which files can safely be released from local disk storage.

## Skills Demonstrated

This project demonstrates practical experience with:

- PowerShell automation
- Windows endpoint administration
- OneDrive Files On-Demand
- Windows Task Scheduler
- File-system management
- Storage lifecycle automation
- Conditional file processing
- Logging and operational safeguards
- Recurring unattended execution

## Purpose

Local Space Reclaimer was developed to demonstrate how a repetitive endpoint-management task can be transformed into a reusable and automated administrative workflow.

The project combines file-system logic, cloud storage behavior, scheduling, and PowerShell automation to reduce manual maintenance while preserving user access to cloud-hosted data.
