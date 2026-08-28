# Stale User Profile Cleanser

Stale User Profile Cleanser is a PowerShell-based Windows endpoint maintenance automation that identifies and removes local Windows user profiles that have not been used within a configurable period of time.

The project is designed to help administrators reclaim disk space, reduce profile accumulation, and automate routine workstation or shared-system maintenance while incorporating safeguards that reduce the risk of deleting active, system, or otherwise protected profiles.

The default stale-profile threshold is **90 days**, but the retention period can be changed when the script is executed.

## Included Script

### `ProfileCleanup.ps1`

`ProfileCleanup.ps1` is the primary automation script for this project.

It queries Windows for locally registered user profiles using the `Win32_UserProfile` CIM class, evaluates each profile against a configurable inactivity threshold, excludes protected or unsafe targets, estimates the local storage associated with eligible profiles, and removes qualifying stale profiles through CIM when running in live mode.

The script also supports dry-run testing, confirmation-aware execution, detailed logging, and configurable exclusions.

---

## What the Script Does

The script performs the following workflow:

```text
Start
  |
  v
Calculate stale-profile cutoff date
  |
  v
Query Win32_UserProfile
  |
  v
Evaluate each local profile
  |
  +--> Exclude system/service SID?
  |
  +--> Exclude special Windows profile?
  |
  +--> Exclude protected profile name?
  |
  +--> Profile currently loaded?
  |
  +--> LastUseTime unavailable?
  |
  +--> Used more recently than cutoff?
  |
  v
Profile qualifies as stale
  |
  v
Resolve account name from SID
  |
  v
Estimate profile directory size
  |
  v
Dry Run? ---- Yes ---> Log what would be deleted
  |
  No
  |
  v
PowerShell ShouldProcess confirmation
  |
  v
Remove profile through Win32_UserProfile CIM instance
  |
  v
Record result in log
  |
  v
Display cleanup summary
```

---

## Core Features

### Configurable Stale-Profile Threshold

The default inactivity threshold is:

```powershell
90 days
```

The value is controlled through the `StaleDays` parameter:

```powershell
[int]$StaleDays = 90
```

A profile becomes eligible for cleanup when its recorded `LastUseTime` is older than the calculated cutoff date.

For example:

```powershell
.\ProfileCleanup.ps1 -StaleDays 90
```

A different retention period can be supplied when needed:

```powershell
.\ProfileCleanup.ps1 -StaleDays 120
```

---

## Dry-Run Mode

The script includes a `DryRun` switch that allows administrators to identify which profiles would qualify for removal without actually deleting them.

Example:

```powershell
.\ProfileCleanup.ps1 -DryRun
```

When dry-run mode is enabled, qualifying profiles are logged as candidates but are not removed.

This is useful for validating the cleanup criteria before performing changes on production systems.

---

## PowerShell Confirmation Support

The script uses:

```powershell
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
```

This enables PowerShell's built-in `ShouldProcess` behavior for destructive operations.

Before a qualifying profile is removed, the script calls:

```powershell
$PSCmdlet.ShouldProcess(...)
```

This provides an additional control layer around profile deletion and allows the script to work with standard PowerShell confirmation behavior.

---

## Windows Profile Discovery

Local profiles are retrieved with:

```powershell
Get-CimInstance -ClassName Win32_UserProfile
```

Using `Win32_UserProfile` allows the script to work with Windows' registered profile information rather than simply deleting directories under `C:\Users`.

This is important because a Windows profile includes operating-system registration and metadata in addition to its file-system directory.

---

## Profile Safety Checks

Before a profile can become a deletion candidate, the script evaluates several protection conditions.

### System and Service SID Exclusions

The following well-known Windows service identities are excluded by default:

```text
S-1-5-18    LocalSystem
S-1-5-19    LocalService
S-1-5-20    NetworkService
```

These are stored in:

```powershell
$ExcludeSids
```

Administrators can add additional SIDs when needed.

---

### Special Windows Profiles

Profiles where:

```powershell
$p.Special
```

evaluates to true are automatically skipped.

This helps prevent the script from removing Windows-managed special profiles.

---

### Built-In Profile Folder Exclusions

The script excludes these profile names by default:

```text
Administrator
Default
Default User
Public
All Users
```

These values are stored in:

```powershell
$ExcludeNames
```

Additional names can be supplied when the script is executed.

---

### Loaded Profile Protection

The script does not delete profiles that Windows reports as currently loaded.

If:

```powershell
$p.Loaded
```

is true, the profile is skipped and the decision is written to the log.

This protects active user sessions from being removed during execution.

---

### Unknown Last-Use Protection

If Windows does not provide a valid `LastUseTime` for a profile, the script skips that profile rather than assuming that it is stale.

This is a deliberate safety behavior.

The script logs the condition as a warning:

```text
Skipping profile with unknown LastUseTime
```

---

## Last-Use-Time Conversion

Windows profile activity is evaluated through the `LastUseTime` property returned by `Win32_UserProfile`.

The script contains a helper function:

```powershell
Convert-LastUseTime
```

that attempts to convert WMI-formatted timestamps into standard .NET `DateTime` objects.

If the conversion fails, the function returns `$null`, causing the profile to be skipped.

---

## Stale-Profile Determination

At runtime, the script calculates a cutoff date using:

```powershell
$cutoff = (Get-Date).AddDays(-1 * $StaleDays)
```

For the default 90-day configuration:

```text
Current Date - 90 Days = Cleanup Cutoff
```

Profiles with a `LastUseTime` newer than the cutoff are ignored.

Profiles with a `LastUseTime` equal to or older than the cutoff can proceed through the remaining eligibility checks.

---

## Account Name Resolution

The script attempts to translate each qualifying profile's SID into a readable Windows account name.

This is handled through:

```powershell
Resolve-AccountNameFromSid
```

The function uses:

```powershell
System.Security.Principal.SecurityIdentifier
```

and translates the SID into an `NTAccount`.

If the SID cannot be resolved, the script continues safely and records the available profile information.

---

## Profile Size Estimation

Before removing a qualifying profile, the script estimates the size of the corresponding profile directory.

The `Get-ProfileSizeBytes` function recursively scans the profile path and totals file sizes using:

```powershell
Get-ChildItem
Measure-Object
```

The resulting estimate is used for reporting purposes.

This allows the script to provide an approximate amount of storage associated with deleted profiles.

Because inaccessible files and directories are ignored during the size scan, the reported storage value should be treated as an estimate rather than an exact disk-usage measurement.

---

## Proper Windows Profile Removal

The script removes profiles using:

```powershell
Remove-CimInstance -InputObject $p
```

against the corresponding `Win32_UserProfile` object.

This approach is preferable to simply deleting a folder such as:

```text
C:\Users\Username
```

because the CIM-based removal targets the registered Windows user-profile instance rather than only deleting its file-system contents.

---

## Logging

Every execution generates a timestamped log by default.

The log file is created in the current user's temporary directory using a name similar to:

```text
ProfileCleanup_20260828_101500.log
```

The default log path is generated with:

```powershell
$LogPath = Join-Path $env:TEMP (...)
```

Each log entry contains:

- Timestamp
- Severity level
- Message

Supported log levels include:

```text
INFO
WARN
ERROR
```

The script writes log output both to the console and to the log file.

---

## Information Recorded in the Log

The execution log includes information such as:

- Cleanup start time
- Computer name
- User executing the script
- Configured stale-day threshold
- Execution mode
- Log-file location
- Calculated cutoff date
- Loaded profiles that were skipped
- Profiles with unknown last-use timestamps
- Candidate profiles
- Account names
- SIDs
- Local profile paths
- Last-use timestamps
- Estimated profile sizes
- Dry-run decisions
- Successful deletions
- Failed deletions
- Final candidate count
- Final deletion count
- Approximate total bytes reclaimed

---

## Usage

### Standard Execution

Run with the default 90-day threshold:

```powershell
.\ProfileCleanup.ps1
```

Because the command is marked with a high confirmation impact, PowerShell confirmation behavior may apply before profile removal.

---

### Dry Run

Inspect qualifying profiles without deleting anything:

```powershell
.\ProfileCleanup.ps1 -DryRun
```

This is the recommended first execution on a new system.

---

### Custom Stale Period

Remove profiles that have not been used for at least 120 days:

```powershell
.\ProfileCleanup.ps1 -StaleDays 120
```

---

### Custom Log Location

Specify a different log file:

```powershell
.\ProfileCleanup.ps1 -LogPath "C:\Logs\ProfileCleanup.log"
```

---

### Additional Protected Profile Names

The default exclusions can be replaced or extended through `ExcludeNames`.

Example:

```powershell
.\ProfileCleanup.ps1 `
    -ExcludeNames "Administrator","Default","Default User","Public","All Users","Support","Kiosk"
```

---

### Additional Protected SIDs

Additional SIDs can also be supplied through `ExcludeSids`.

Example:

```powershell
.\ProfileCleanup.ps1 `
    -ExcludeSids "S-1-5-18","S-1-5-19","S-1-5-20","S-1-5-21-EXAMPLE"
```

---

## Parameters

### `-StaleDays`

Defines how many days a profile must remain unused before it becomes eligible for cleanup.

Default:

```text
90
```

---

### `-DryRun`

Runs the evaluation process without removing profiles.

Useful for:

- Validation
- Testing
- Change review
- Production safety checks

---

### `-LogPath`

Specifies where execution logs should be written.

By default, the script creates a timestamped `.log` file in the user's temporary directory.

---

### `-ExcludeNames`

Defines profile directory names that should never be removed.

Default values:

```text
Administrator
Default
Default User
Public
All Users
```

---

### `-ExcludeSids`

Defines Windows SIDs that should never be removed.

Default values protect:

```text
LocalSystem
LocalService
NetworkService
```

---

## Requirements

- Windows operating system
- Windows PowerShell 5.1 or later
- CIM/WMI access to `Win32_UserProfile`
- Appropriate permissions to enumerate and remove Windows user profiles
- Administrative privileges may be required for profile deletion

The script declares:

```powershell
#requires -version 5.1
```

to ensure it is executed with a supported PowerShell version.

---

## Recommended Deployment Process

For administrative environments, a cautious deployment workflow is recommended.

### 1. Run in Dry-Run Mode

```powershell
.\ProfileCleanup.ps1 -DryRun
```

Review the output and generated log.

### 2. Review Candidate Profiles

Confirm that:

- Active users are not included.
- Required administrative profiles are excluded.
- Service and special profiles are excluded.
- The stale threshold matches organizational policy.

### 3. Adjust Exclusions if Needed

Add organization-specific service, support, kiosk, application, or administrative accounts to the exclusion lists.

### 4. Execute in Live Mode

After validating the candidate list:

```powershell
.\ProfileCleanup.ps1
```

### 5. Review the Final Log

Confirm successful removals and investigate any entries recorded at the `ERROR` level.

---

## Example Use Cases

The automation can be useful for:

- Shared workstations
- Training-room computers
- Computer labs
- Help-desk managed endpoints
- Frequently reassigned devices
- Administrative workstations
- Environments with high user turnover
- Systems with limited local storage
- Endpoint lifecycle maintenance

Over time, Windows devices used by many different users can accumulate large profile directories. Removing profiles that are no longer required can recover disk capacity and reduce unnecessary local data retention.

---

## Security and Operational Considerations

Deleting a Windows user profile is a destructive administrative operation.

A profile may contain locally stored information that has not been synchronized or backed up elsewhere.

Before deploying this script broadly:

- Validate organizational retention requirements.
- Confirm users' required data is backed up or synchronized.
- Review candidate profiles using `-DryRun`.
- Protect administrative and application-specific accounts.
- Test the script on non-production systems.
- Review generated logs.
- Use an inactivity period appropriate for the environment.

The script's built-in exclusions reduce risk, but administrators remain responsible for determining whether a profile is safe to remove.

---

## Error Handling

The script sets:

```powershell
$ErrorActionPreference = "Stop"
```

for predictable terminating-error behavior.

Profile deletion is additionally wrapped in `try/catch`.

When a deletion fails, the script logs:

- Profile SID
- Profile path
- Exception message

and records the event using the `ERROR` severity level.

This provides useful information for troubleshooting permissions, locked files, profile corruption, or Windows management issues.

---

## Execution Summary

At the end of execution, the script reports:

```text
Candidates
Deleted
ApproxBytesFreed
```

This provides an operational summary showing:

- How many profiles met the stale criteria
- How many were actually removed
- The approximate amount of profile data associated with successfully deleted profiles

In dry-run mode, profiles may be counted as candidates without being deleted.

---

## Project Structure

```text
Stale User Profile Cleanser/
├── ProfileCleanup.ps1
└── README.md
```

---

## Skills Demonstrated

This project demonstrates practical experience with:

- PowerShell automation
- Windows endpoint administration
- Windows user-profile lifecycle management
- CIM and WMI
- `Win32_UserProfile`
- Windows SID handling
- .NET identity translation
- File-system traversal
- Storage utilization analysis
- Parameterized automation
- Defensive scripting
- Dry-run workflows
- `SupportsShouldProcess`
- Error handling
- Operational logging
- Administrative safety controls
- Endpoint storage optimization

---

## Design Philosophy

Stale User Profile Cleanser is intentionally designed around conservative profile removal.

Instead of treating every old directory in `C:\Users` as disposable, the script uses Windows profile metadata to make cleanup decisions and rejects profiles when important information is unavailable or when the profile is currently active.

The workflow follows a safety-first sequence:

```text
Discover
   ↓
Validate
   ↓
Exclude
   ↓
Evaluate
   ↓
Preview
   ↓
Confirm
   ↓
Remove
   ↓
Log
```

This makes the automation more appropriate for managed Windows environments than an approach based solely on recursively deleting old directories.

---

## Purpose

Stale User Profile Cleanser was created to automate a common Windows endpoint administration task: identifying local user profiles that have remained inactive beyond an established retention period and safely removing eligible profiles to recover disk space.

The project demonstrates how PowerShell, CIM, Windows profile metadata, configurable retention policies, defensive checks, and structured logging can be combined into a reusable endpoint-maintenance workflow.
