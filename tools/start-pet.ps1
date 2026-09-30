param([string]$Pet, [string]$Extra = '')
$me = $PID
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -like '*-File*pet.ps1*' } |
  ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }
Start-Sleep -Seconds 1
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$Pet,'-Force')
if ($Extra) { $args += $Extra }
Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden
