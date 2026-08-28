$taskName  = "OneDrive FreeUp Space"
$script    = "$env:ENTER YOUR FILE PATH HERE\OneDrive_OnlineOnly.ps1"
$target    = "$env:OneDrive\Desktop"

$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -TargetPaths `"$target`" -SkipModifiedWithinDays 3 -Force"
$trigger = New-ScheduledTaskTrigger -Daily -At 9:00AM
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Marks eligible OneDrive Desktop files online-only every 3 days to save disk space."

$taskName = "OneDrive FreeUp Space"
$task = Get-ScheduledTask -TaskName $taskName
$task.Triggers[0].DaysInterval = 3
Set-ScheduledTask -TaskName $taskName -Trigger $task.Triggers

Start-ScheduledTask -TaskName "OneDrive FreeUp Space"
