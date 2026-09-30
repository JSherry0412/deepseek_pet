param([int]$ProcessId, [double]$NewScale = -1)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase
Add-Type -Namespace U2 -Name W -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hwnd, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hwnd, out RECT rect);
public delegate bool EnumProc(System.IntPtr hwnd, System.IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
"@
$target = [uint32]$ProcessId
$script:settings = [System.IntPtr]::Zero
$cb = [U2.W+EnumProc]{
  param($hwnd, $p)
  $owner = [uint32]0
  [void][U2.W]::GetWindowThreadProcessId($hwnd, [ref]$owner)
  if ($owner -eq $target -and [U2.W]::IsWindowVisible($hwnd)) {
    $r = New-Object U2.W+RECT
    [void][U2.W]::GetWindowRect($hwnd, [ref]$r)
    if (($r.Right - $r.Left) -gt 300 -and ($r.Bottom - $r.Top) -gt 300) { $script:settings = $hwnd }
  }
  return $true
}
[void][U2.W]::EnumWindows($cb, [System.IntPtr]::Zero)
if ($script:settings -eq [System.IntPtr]::Zero) { Write-Output 'settings window not found'; exit 2 }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($script:settings)
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Slider)
$sliders = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
Write-Output ("sliders: {0}" -f $sliders.Count)
for ($i = 0; $i -lt $sliders.Count; $i++) {
  $s = $sliders.Item($i)
  $rv = $null
  try { $rv = $s.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern) } catch { }
  if ($null -ne $rv) {
    Write-Output ("  [{0}] value={1} min={2} max={3}" -f $i, $rv.Current.Value, $rv.Current.Minimum, $rv.Current.Maximum)
  } else {
    Write-Output ("  [{0}] no RangeValuePattern" -f $i)
  }
}
if ($NewScale -gt 0 -and $sliders.Count -gt 0) {
  $rv = $sliders.Item(0).GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
  Write-Output ("setting slider[0] {0} -> {1}" -f $rv.Current.Value, $NewScale)
  $rv.SetValue($NewScale)
  Start-Sleep -Seconds 2
  Write-Output ("slider[0] now {0}" -f $rv.Current.Value)
}
