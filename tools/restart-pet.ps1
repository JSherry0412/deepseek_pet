param([string]$Pet, [int]$WaitSeconds = 6)
# Kill any running pet, then start a fresh hidden one, in a process that is not the caller.
$me = $PID
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -like '*-File*pet.ps1*' } |
  ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }
Start-Sleep -Seconds 1
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $Pet) -WindowStyle Hidden
Start-Sleep -Seconds $WaitSeconds
$now = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -like '*-File*pet.ps1*' })
Write-Output ("pet running: {0}  pid: {1}" -f $now.Count, ($now.ProcessId -join ','))
Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'dsh-desktop-pet\pet.log') -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Last 5
