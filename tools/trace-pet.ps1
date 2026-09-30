param(
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [Parameter(Mandatory=$true)][string]$Out,
  [ValidateSet('click', 'drag')][string]$Mode = 'click',
  [int]$X,
  [int]$Y
)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace RT -Name In -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, System.IntPtr extra);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hwnd, out RECT rect);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hwnd, out uint pid);
public delegate bool EnumProc(System.IntPtr hwnd, System.IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
"@

$LEFTDOWN = 0x0002
$LEFTUP = 0x0004
$target = [uint32]$ProcessId
$script:handles = @()

function Refresh-Handles {
  $script:handles = @()
  $cb = [RT.In+EnumProc]{
    param($hwnd, $p)
    $owner = [uint32]0
    [void][RT.In]::GetWindowThreadProcessId($hwnd, [ref]$owner)
    if ($owner -eq $target) {
      $r = New-Object RT.In+RECT
      [void][RT.In]::GetWindowRect($hwnd, [ref]$r)
      $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
      if ($w -gt 120 -and $h -gt 120 -and $w -lt 320) {
        $script:handles += [pscustomobject]@{ hwnd = $hwnd }
      }
    }
    return $true
  }
  [void][RT.In]::EnumWindows($cb, [System.IntPtr]::Zero)
}

function Report {
  param([string]$Tag)
  Refresh-Handles
  $parts = @()
  foreach ($hd in $script:handles) {
    $r = New-Object RT.In+RECT
    [void][RT.In]::GetWindowRect($hd.hwnd, [ref]$r)
    $parts += ("hwnd={0} at {1},{2} {3}x{4} vis={5} min={6}" -f $hd.hwnd, $r.Left, $r.Top, ($r.Right - $r.Left), ($r.Bottom - $r.Top), [RT.In]::IsWindowVisible($hd.hwnd), [RT.In]::IsIconic($hd.hwnd))
  }
  if ($parts.Count -eq 0) { $parts = @('(no pet-sized visible window found)') }
  $line = "$Tag  " + ($parts -join ' | ')
  Write-Output $line
  Add-Content -LiteralPath $Out -Value $line
}

Set-Content -LiteralPath $Out -Value ("=== trace {0} ===" -f $Mode)
Report -Tag 'before   '

[void][RT.In]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 400
Report -Tag 'hovered  '

if ($Mode -eq 'click') {
  [RT.In]::mouse_event($LEFTDOWN, 0, 0, 0, [System.IntPtr]::Zero)
  Start-Sleep -Milliseconds 70
  [RT.In]::mouse_event($LEFTUP, 0, 0, 0, [System.IntPtr]::Zero)
  foreach ($ms in 120, 300, 600, 1200, 2500) {
    Start-Sleep -Milliseconds $ms
    Report -Tag ("after {0,5}ms" -f $ms)
  }
} else {
  [RT.In]::mouse_event($LEFTDOWN, 0, 0, 0, [System.IntPtr]::Zero)
  Start-Sleep -Milliseconds 150
  # Walk the cursor and sample the window rect at every step to expose jitter.
  for ($i = 1; $i -le 14; $i++) {
    $nx = $X - $i * 12
    $ny = $Y - $i * 6
    [void][RT.In]::SetCursorPos($nx, $ny)
    Start-Sleep -Milliseconds 60
    Report -Tag ("drag step {0,2} cursor {1},{2}" -f $i, $nx, $ny)
  }
  [RT.In]::mouse_event($LEFTUP, 0, 0, 0, [System.IntPtr]::Zero)
  Start-Sleep -Milliseconds 500
  Report -Tag 'released '
  Start-Sleep -Seconds 2
  Report -Tag 'settled  '
}
