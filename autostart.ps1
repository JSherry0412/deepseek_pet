# Install the desktop pet autostart entry, or remove it.
#
#   -Install         register the pet to start with Windows (hidden) and launch it now
#   -Uninstall       remove the entry and stop a running pet
#   -Status          report whether the entry exists
#
# The entry lives under HKCU Run, so no elevation is needed and nothing outside the user's own
# registry hive is touched. The value keeps a quoted path so that spaces and non-ASCII folder
# names survive.

[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$Restart
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pet = Join-Path $root 'pet.ps1'
$launcher = Join-Path $root 'launch-pet.cmd'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$valueName = 'DshDesktopPet'

function Get-Entry {
  try {
    return (Get-ItemProperty -Path $runKey -ErrorAction Stop).$valueName
  } catch {
    return $null
  }
}

function Stop-Pet {
  # Match only the pet's own invocation; matching "pet.ps1" would also match this script.
  $me = $PID
  $targets = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -like '*-File*pet.ps1*' })
  foreach ($t in $targets) {
    try { Invoke-CimMethod -InputObject $t -MethodName Terminate | Out-Null; Write-Host ("stopped pid {0}" -f $t.ProcessId) } catch { }
  }
  if ($targets.Count -eq 0) { Write-Host 'no running pet found' }
}

function Start-PetHidden {
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $pet) -WindowStyle Hidden
}

if ($Restart) {
  Stop-Pet
  Start-Sleep -Seconds 1
  Start-PetHidden
  Start-Sleep -Seconds 4
  $now = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*-File*pet.ps1*' })
  Write-Host ("pet running: {0}" -f $now.Count)
  Write-Host 'restart done'
  exit 0
}

if ($Status -or (-not $Install -and -not $Uninstall)) {
  $entry = Get-Entry
  if ($entry) { Write-Host ("autostart: installed -> {0}" -f $entry) }
  else { Write-Host 'autostart: not installed' }
  Write-Host ("pet script : {0} (exists={1})" -f $pet, (Test-Path -LiteralPath $pet))
  exit 0
}

if ($Uninstall) {
  $entry = Get-Entry
  if ($entry) {
    Remove-ItemProperty -Path $runKey -Name $valueName -ErrorAction Stop
    Write-Host 'autostart entry removed'
  } else {
    Write-Host 'autostart entry was not present'
  }
  Stop-Pet
  Write-Host 'uninstall done'
  exit 0
}

if ($Install) {
  if (-not (Test-Path -LiteralPath $pet)) { throw "pet script not found: $pet" }

  # The launcher hides the console window; the registry value just calls it.
  $launcherBody = @"
@echo off
start "" /b powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0pet.ps1"
"@
  Set-Content -LiteralPath $launcher -Value $launcherBody -Encoding UTF8
  Write-Host ("launcher written: {0}" -f $launcher)

  $command = '"{0}"' -f $launcher
  Set-ItemProperty -Path $runKey -Name $valueName -Value $command -Type String
  $verify = Get-Entry
  if ($verify -ne $command) { throw "autostart entry did not stick (got '$verify')" }
  Write-Host ("autostart installed: {0}" -f $command)

  Stop-Pet
  Start-Sleep -Milliseconds 300
  Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', ('"{0}"' -f $launcher)) -WindowStyle Hidden
  Start-Sleep -Seconds 3
  $running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*pet.ps1*' })
  Write-Host ("pet processes now: {0}" -f $running.Count)
  Write-Host 'install done'
  exit 0
}
