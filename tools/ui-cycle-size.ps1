param([int]$ProcessId, [string]$Values)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase
Add-Type -Namespace UC2 -Name W -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hwnd, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hwnd, out RECT rect);
public delegate bool EnumProc(System.IntPtr hwnd, System.IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
"@
$target = [uint32]$ProcessId
$script:settings = [System.IntPtr]::Zero
$cb = [UC2.W+EnumProc]{
  param($hwnd, $p)
  $owner = [uint32]0
  [void][UC2.W]::GetWindowThreadProcessId($hwnd, [ref]$owner)
  if ($owner -eq $target -and [UC2.W]::IsWindowVisible($hwnd)) {
    $r = New-Object UC2.W+RECT
    [void][UC2.W]::GetWindowRect($hwnd, [ref]$r)
    if (($r.Right - $r.Left) -gt 300) { $script:settings = $hwnd }
  }
  return $true
}
[void][UC2.W]::EnumWindows($cb, [System.IntPtr]::Zero)
if ($script:settings -eq [System.IntPtr]::Zero) { Write-Output 'settings window not open'; exit 2 }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($script:settings)
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Slider)
$sliders = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
$rv = $sliders.Item(0).GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
foreach ($part in $Values.Split(',')) {
  $v = [double]$part
  $rv.SetValue($v)
  Start-Sleep -Milliseconds 700
  Write-Output ("set {0} -> {1}" -f $v, $rv.Current.Value)
}
