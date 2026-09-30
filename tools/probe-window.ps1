# Test helper: report a process's windows and save a PrintWindow capture of the largest one.
#   powershell -File probe-window.ps1 -ProcessId 1234 -Out shot.png [-List]
param(
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [string]$Out,
  [switch]$List
)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace PW -Name Cap -MemberDefinition @"
[DllImport("user32.dll")] public static extern bool PrintWindow(System.IntPtr hwnd, System.IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hwnd, out RECT rect);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hwnd);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr p);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hwnd, out uint pid);
public delegate bool EnumProc(System.IntPtr hwnd, System.IntPtr p);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
"@

$target = [uint32]$ProcessId
$found = New-Object System.Collections.ArrayList
$cb = [PW.Cap+EnumProc]{
  param($hwnd, $p)
  $owner = [uint32]0
  [void][PW.Cap]::GetWindowThreadProcessId($hwnd, [ref]$owner)
  if ($owner -eq $target) {
    $r = New-Object PW.Cap+RECT
    [void][PW.Cap]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -gt 40 -and $h -gt 40) {
      [void]$found.Add([pscustomobject]@{
        hwnd = $hwnd; x = $r.Left; y = $r.Top; w = $w; h = $h
        visible = [PW.Cap]::IsWindowVisible($hwnd)
      })
    }
  }
  return $true
}
[void][PW.Cap]::EnumWindows($cb, [System.IntPtr]::Zero)

$ordered = $found | Sort-Object { $_.w * $_.h } -Descending
$ordered | Format-Table -AutoSize | Out-String | Write-Output
if ($List -or -not $Out) { exit 0 }
if ($ordered.Count -eq 0) { Write-Output 'no windows'; exit 2 }

$target2 = $ordered | Select-Object -First 1
$bmp = New-Object System.Drawing.Bitmap($target2.w, $target2.h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [PW.Cap]::PrintWindow($target2.hwnd, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output ("printwindow={0} saved {1} {2}x{3} at {4},{5}" -f $ok, $Out, $target2.w, $target2.h, $target2.x, $target2.y)
