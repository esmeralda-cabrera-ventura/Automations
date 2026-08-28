#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
param(
  [int]$StaleDays = 90,
  [switch]$DryRun,
  [string]$LogPath = (Join-Path $env:TEMP ("ProfileCleanup_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))),
  [string[]]$ExcludeNames = @("Administrator", "Default", "Default User", "Public", "All Users"),
  [string[]]$ExcludeSids = @(
    "S-1-5-18", # LocalSystem
    "S-1-5-19", # LocalService
    "S-1-5-20"  # NetworkService
  )
)

$ErrorActionPreference = "Stop"

function Write-Log {
  param([string]$Message, [ValidateSet("INFO","WARN","ERROR")] [string]$Level="INFO")
  $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
  $line | Tee-Object -FilePath $LogPath -Append | Out-Host
}

function Convert-LastUseTime {
  param($WmiTime)
  # Win32_UserProfile.LastUseTime is WMI datetime; convert safely
  if (-not $WmiTime) { return $null }
  try { return [System.Management.ManagementDateTimeConverter]::ToDateTime($WmiTime) }
  catch { return $null }
}

function Get-ProfileSizeBytes {
  param([string]$Path)
  if (-not $Path -or -not (Test-Path $Path)) { return 0 }
  try {
    (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
      Measure-Object -Property Length -Sum).Sum
  } catch { 0 }
}

function Resolve-AccountNameFromSid {
  param([string]$Sid)
  try {
    $objSid = New-Object System.Security.Principal.SecurityIdentifier($Sid)
    $nt = $objSid.Translate([System.Security.Principal.NTAccount])
    return $nt.Value
  } catch {
    return $null
  }
}

Write-Log "Starting stale profile cleanup"
Write-Log "Computer: $env:COMPUTERNAME  User running: $env:USERNAME"
Write-Log "StaleDays: $StaleDays  Mode: $((if($DryRun){'DRYRUN'}else{'LIVE'}))"
Write-Log "Log: $LogPath"

$cutoff = (Get-Date).AddDays(-1 * $StaleDays)
Write-Log "Cutoff date: $cutoff"

# Pull local profiles
$profiles = Get-CimInstance -ClassName Win32_UserProfile

if (-not $profiles) {
  Write-Log "No profiles returned from Win32_UserProfile" "WARN"
  return
}

$totalCandidates = 0
$totalDeleted = 0
$totalBytesFreedEstimate = 0

foreach ($p in $profiles) {
  $sid = $p.SID
  $path = $p.LocalPath
  $loaded = [bool]$p.Loaded
  $special = [bool]$p.Special

  # Exclusions: system/service SIDs and special profiles
  if ($ExcludeSids -contains $sid) { continue }
  if ($special) { continue }

  # Exclusions: common built-in profile folder names
  if ($path) {
    $leaf = Split-Path $path -Leaf
    if ($ExcludeNames -contains $leaf) { continue }
  }

  # Don't delete currently loaded profiles
  if ($loaded) {
    Write-Log "Skipping loaded profile: SID=$sid Path=$path" "INFO"
    continue
  }

  $lastUse = Convert-LastUseTime -WmiTime $p.LastUseTime

  # If LastUseTime is missing, skip (safer)
  if (-not $lastUse) {
    Write-Log "Skipping profile with unknown LastUseTime: SID=$sid Path=$path" "WARN"
    continue
  }

  # Only delete if older than cutoff
  if ($lastUse -gt $cutoff) { continue }

  $acct = Resolve-AccountNameFromSid -Sid $sid
  $size = Get-ProfileSizeBytes -Path $path

  $totalCandidates++
  Write-Log "Candidate: Account=$acct SID=$sid Path=$path LastUse=$lastUse SizeBytes=$size"

  if ($DryRun) {
    Write-Log "DRYRUN would delete profile: $acct ($sid) at $path"
    continue
  }

  if ($PSCmdlet.ShouldProcess($path, "Delete user profile (stale $StaleDays+ days)")) {
    try {
      # Using CIM deletion of the Win32_UserProfile instance (proper profile removal)
      Remove-CimInstance -InputObject $p -ErrorAction Stop
      $totalDeleted++
      $totalBytesFreedEstimate += ($size ? $size : 0)
      Write-Log "Deleted profile: Account=$acct SID=$sid Path=$path"
    } catch {
      Write-Log "FAILED to delete profile: SID=$sid Path=$path Error=$($_.Exception.Message)" "ERROR"
    }
  }
}

Write-Log "Done. Candidates: $totalCandidates  Deleted: $totalDeleted  ApproxBytesFreed: $totalBytesFreedEstimate"
