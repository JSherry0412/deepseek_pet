param([int]$ProcessId)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase
Add-Type -Namespace U3 -Name W -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hwnd, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hwnd, out RECT rect);
public delegate bool EnumProc(System.IntPtr hwnd, System.IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
"@
$target = [uint32]$ProcessId
$script:pet = [System.IntPtr]::Zero
$cb = [U3.W+EnumProc]{
  param($hwnd, $p)
  $owner = [uint32]0
  [void][U3.W]::GetWindowThreadProcessId($hwnd, [ref]$owner)
  if ($owner -eq $target -and [U3.W]::IsWindowVisible($hwnd)) {
    $r = New-Object U3.W+RECT
    [void][U3.W]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -lt 300 -and $h -lt 400 -and $w -gt 100) { $script:pet = $hwnd }
  }
  return $true
}
[void][U3.W]::EnumWindows($cb, [System.IntPtr]::Zero)
if ($script:pet -eq [System.IntPtr]::Zero) { Write-Output 'pet window not found'; exit 2 }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($script:pet)
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
$buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
Write-Output ("buttons: {0}" -f $buttons.Count)
for ($i = 0; $i -lt $buttons.Count; $i++) {
  $b = $buttons.Item($i)
  $ip = $null
  try { $ip = $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern) } catch { }
  Write-Output ("  [{0}] name='{1}' invokable={2}" -f $i, $b.Current.Name, ($null -ne $ip))
  if ($null -ne $ip -and $i -eq 0) { $ip.Invoke(); Write-Output '  invoked' }
}
