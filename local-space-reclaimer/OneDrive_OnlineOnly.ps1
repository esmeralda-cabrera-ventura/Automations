#requires -version 5.1
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="High")]
param(
  [ValidateSet("Auto","Personal","Business")]
  [string]$Account = "Auto",

  [string[]]$TargetPaths,

  [int]$SkipModifiedWithinDays = 3,

  [switch]$DryRun,

  [switch]$Force,

  [string]$LogPath = (Join-Path $env:TEMP ("OneDrive_FreeUp_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date)))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log {
  param([string]$Message, [ValidateSet("INFO","WARN","ERROR")] [string]$Level="INFO")
  $line = "[{0:yyyy-MM-dd HH:mm:ss}] [{1}] {2}" -f (Get-Date), $Level, $Message
  $line | Tee-Object -FilePath $LogPath -Append | Out-Host
}

function Get-OneDriveRoots {
  $roots = New-Object System.Collections.Generic.List[string]

  $candidates = @(
    $env:OneDrive,
    $env:OneDriveConsumer,
    $env:OneDriveCommercial
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

  foreach ($c in $candidates) { $roots.Add($c) }

  if ($roots.Count -eq 0) {
    $reg = "HKCU:\Software\Microsoft\OneDrive\Accounts"
    if (Test-Path $reg) {
      Get-ChildItem $reg -ErrorAction SilentlyContinue | ForEach-Object {
        $uf = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).UserFolder
        if ($uf -and (Test-Path $uf) -and -not $roots.Contains($uf)) { $roots.Add($uf) }
      }
    }
  }

  return @($roots.ToArray())
}

function Filter-AccountRoots {
  param([string[]]$Roots, [string]$Account)

  switch ($Account) {
    "Personal" { return @($Roots | Where-Object { $_ -match "\\OneDrive($|\\)" -and $_ -notmatch "\\OneDrive\s-\s" }) }
    "Business" { return @($Roots | Where-Object { $_ -match "\\OneDrive\s-\s" }) }
    default   { return @($Roots) }
  }
}

function Test-FilesOnDemandEnabled {

  # OneDrive settings/registry keys vary across Windows builds.
  # If the expected registry flag is missing, do NOT block execution.
  $key = "HKCU:\Software\Microsoft\OneDrive"

  if (-not (Test-Path $key)) { return $true }

  try {
    $props = Get-ItemProperty -Path $key

    foreach ($p in $props.PSObject.Properties) {
      if ($p.Name -match "Demand" -and $p.Value -in 1,"1",$true,"True") {
        return $true
      }
    }

    return $true
  } catch {
    return $true
  }
}

function Get-Targets {
  param([string[]]$Roots)

  if (@($TargetPaths).Count -gt 0) { return @($TargetPaths) }
  return @($Roots)
}

function Get-SkipNamePatterns {
  @("*.tmp","*.partial","*.download","~$*","*.odtmp","*.onecache")
}

function Is-ProbablySyncingFile {
  param([System.IO.FileInfo]$File)

  $name = $File.Name
  foreach ($p in (Get-SkipNamePatterns)) {
    if ($name -like $p) { return $true }
  }

  if ($File.LastWriteTime -gt (Get-Date).AddMinutes(-10)) { return $true }

  return $false
}

function Get-EligibleFiles {
  param([string]$Root, [int]$SkipDays)

  $cutoff = (Get-Date).AddDays(-1 * $SkipDays)

  $files = Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction Stop

  $eligible = foreach ($f in $files) {
    if ($f.LastWriteTime -gt $cutoff) { continue }
    if (Is-ProbablySyncingFile -File $f) { continue }
    $f
  }

  return @($eligible)
}

function Get-SizeBytes {
  param([System.IO.FileInfo[]]$Files)

  if (-not $Files -or @($Files).Count -eq 0) { return 0 }
  $sum = ($Files | Measure-Object -Property Length -Sum).Sum
  if ($sum) { return [long]$sum }
  return 0
}

function Set-OnlineOnly {
  param([System.IO.FileInfo]$File)

  $full = $File.FullName

  if ($DryRun) {
    Write-Log "DRYRUN would free up: $full"
    return
  }

  if ($PSCmdlet.ShouldProcess($full, "Mark Online-only (Free up space)")) {
    & attrib +U -P $full 2>$null | Out-Null
  }
}

Write-Log "Starting OneDrive storage free-up"
Write-Log "User: $env:USERNAME  Computer: $env:COMPUTERNAME"
Write-Log "Log: $LogPath"

$roots = Get-OneDriveRoots
if (@($roots).Count -eq 0) { throw "No OneDrive root folders detected for this user." }

$roots = Filter-AccountRoots -Roots $roots -Account $Account
if (@($roots).Count -eq 0) { throw "No OneDrive roots matched Account='$Account'." }

Write-Log ("Detected OneDrive roots: " + ($roots -join " | "))

if (-not (Test-FilesOnDemandEnabled)) {
  throw "Files On-Demand is NOT enabled. Turn it on in OneDrive settings, then re-run. This is required to free local storage without deleting cloud data."
}

$targets = Get-Targets -Roots $roots
Write-Log ("Targets: " + ($targets -join " | "))
Write-Log ("SkipModifiedWithinDays: $SkipModifiedWithinDays")
Write-Log ("Mode: " + ($(if ($DryRun) { "DRYRUN" } else { "LIVE" })))

if (-not $Force -and -not $DryRun) {
  Write-Warning "This will mark eligible OneDrive files Online-only (free space). It does NOT delete cloud data. Ctrl+C to cancel."
  Start-Sleep -Seconds 4
}

$totalEligible = 0
$totalBytes = 0

foreach ($t in $targets) {
  if (-not (Test-Path $t)) {
    Write-Log "Target missing: $t" "WARN"
    continue
  }

  Write-Log "Scanning: $t"
  $eligible = Get-EligibleFiles -Root $t -SkipDays $SkipModifiedWithinDays

  $count = @($eligible).Count
  $bytes = Get-SizeBytes -Files $eligible

  $totalEligible += $count
  $totalBytes += $bytes

  Write-Log "Eligible files: $count  Approx bytes eligible: $bytes"

  foreach ($f in $eligible) {
    Set-OnlineOnly -File $f
  }
}

Write-Log "Done. Total eligible files: $totalEligible  Approx bytes: $totalBytes"


