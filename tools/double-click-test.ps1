param(
  [Parameter(Mandatory=$true)][int]$X,
  [Parameter(Mandatory=$true)][int]$Y,
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [string]$Out,
  [switch]$List
)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace DC -Name In -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, System.IntPtr extra);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hwnd, out RECT rect);
[DllImport("user32.dll")] public static extern bool PrintWindow(System.IntPtr hwnd, System.IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hwnd, out uint pid);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hwnd);
public delegate bool EnumProc(System.IntPtr hwnd, System.IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
"@

$LEFTDOWN = 0x0002
$LEFTUP = 0x0004
[void][DC.In]::SetCursorPos($X, $Y)
Start-Sleep -Milliseconds 250
for ($click = 0; $click -lt 2; $click++) {
  [DC.In]::mouse_event($LEFTDOWN, 0, 0, 0, [System.IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [DC.In]::mouse_event($LEFTUP, 0, 0, 0, [System.IntPtr]::Zero)
  Start-Sleep -Milliseconds 130
}
Start-Sleep -Milliseconds 1400

$target = [uint32]$ProcessId
$found = New-Object System.Collections.ArrayList
$cb = [DC.In+EnumProc]{
  param($hwnd, $p)
  $owner = [uint32]0
  [void][DC.In]::GetWindowThreadProcessId($hwnd, [ref]$owner)
  if ($owner -eq $target) {
    $r = New-Object DC.In+RECT
    [void][DC.In]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -gt 60 -and $h -gt 60) {
      [void]$found.Add([pscustomobject]@{ hwnd = $hwnd; x = $r.Left; y = $r.Top; w = $w; h = $h; visible = [DC.In]::IsWindowVisible($hwnd) })
    }
  }
  return $true
}
[void][DC.In]::EnumWindows($cb, [System.IntPtr]::Zero)
$found | Sort-Object { $_.w * $_.h } -Descending | Format-Table -AutoSize | Out-String | Write-Output
if ($List -or -not $Out) { exit 0 }

$i = 0
foreach ($f in ($found | Sort-Object { $_.w * $_.h } -Descending)) {
  $i++
  $bmp = New-Object System.Drawing.Bitmap($f.w, $f.h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
  $ok = [DC.In]::PrintWindow($f.hwnd, $hdc, 2)
  $g.ReleaseHdc($hdc); $g.Dispose()
  $file = Join-Path (Split-Path $Out -Parent) ("dbl-{0}-{1}x{2}.png" -f $i, $f.w, $f.h)
  $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  Write-Output ("saved {0} visible={1} at {2},{3} printwindow={4}" -f (Split-Path $file -Leaf), $f.visible, $f.x, $f.y, $ok)
}
