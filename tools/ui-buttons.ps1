param([int]$ProcessId, [string]$Name)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase
Add-Type -Namespace UC -Name W -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hwnd, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hwnd, out RECT rect);
public delegate bool EnumProc(System.IntPtr hwnd, System.IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
"@
$target = [uint32]$ProcessId
$script:settings = [System.IntPtr]::Zero
$cb = [UC.W+EnumProc]{
  param($hwnd, $p)
  $owner = [uint32]0
  [void][UC.W]::GetWindowThreadProcessId($hwnd, [ref]$owner)
  if ($owner -eq $target -and [UC.W]::IsWindowVisible($hwnd)) {
    $r = New-Object UC.W+RECT
    [void][UC.W]::GetWindowRect($hwnd, [ref]$r)
    if (($r.Right - $r.Left) -gt 300) { $script:settings = $hwnd }
  }
  return $true
}
[void][UC.W]::EnumWindows($cb, [System.IntPtr]::Zero)
$root = [System.Windows.Automation.AutomationElement]::FromHandle($script:settings)
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
$buttons = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
for ($i = 0; $i -lt $buttons.Count; $i++) {
  if ($buttons.Item($i).Current.Name -eq $Name) {
    Write-Output ("invoking [{0}] {1}" -f $i, $Name)
    $ip = $buttons.Item($i).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $ip.Invoke()
  }
}
