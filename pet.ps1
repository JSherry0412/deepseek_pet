# Desktop pet for DeepSeek Harness.
#
# A frameless, transparent, always-on-top WPF window that shows one of the prepared character
# states, keeps the DeepSeek account balance on screen, switches states on its own while idle and
# on demand from its right-click menu.
#
# The source is deliberately ASCII-only: Windows PowerShell 5.1 reads BOM-less script files as
# ANSI, so every Chinese string lives in config.json / assets\states.json and is loaded as UTF-8.
#
#   -Doctor   run checks and print results without opening the window
#   -Force    start even when DeepSeek Harness is not running

[CmdletBinding()]
param(
  [switch]$Doctor,
  [switch]$Force,
  [switch]$OpenSettings
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$assetDir = Join-Path $root 'assets'
$configPath = Join-Path $root 'config.json'
$logPath = Join-Path $env:LOCALAPPDATA 'dsh-desktop-pet\pet.log'

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
  if ($Doctor) { Write-Host $line }
  try {
    $dir = Split-Path -Parent $logPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ((Test-Path -LiteralPath $logPath) -and ((Get-Item -LiteralPath $logPath).Length -gt 512KB)) {
      Remove-Item -LiteralPath $logPath -Force
    }
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
  } catch {
    if ($Doctor) { Write-Host "log unavailable: $($_.Exception.Message)" }
  }
}

function Read-JsonFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $path)) { throw "missing file: $Path" }
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function ConvertTo-HashtableDeep {
  # Config and manifest arrive as JSON objects; hashtables let every lookup go through ContainsKey,
  # which stays safe under StrictMode when an optional key is absent.
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $h = @{}
    foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-HashtableDeep $p.Value }
    return $h
  }
  if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
    $out = @()
    foreach ($item in $Value) { $out += , (ConvertTo-HashtableDeep $item) }
    return $out
  }
  return $Value
}

function Get-Opt {
  # Read an optional entry without tripping StrictMode when the key or the table is absent.
  param($Table, [string]$Key, $Default = $null)
  if ($null -eq $Table) { return $Default }
  if ($Table -isnot [hashtable]) { return $Default }
  if (-not $Table.ContainsKey($Key)) { return $Default }
  $value = $Table[$Key]
  if ($null -eq $value) { return $Default }
  return $value
}

$config = ConvertTo-HashtableDeep (Read-JsonFile -Path $configPath)
$manifest = ConvertTo-HashtableDeep (Read-JsonFile -Path (Join-Path $assetDir 'states.json'))
$stateDefs = Get-Opt $config 'states' @{}
$ui = Get-Opt $config 'ui' @{}

$behaviour = Get-Opt $config 'behaviour' @{}
$windowCfg = Get-Opt $behaviour 'window' @{}
$winW = [int](Get-Opt $windowCfg 'width' 320)
$winH = [int](Get-Opt $windowCfg 'height' 400)

function Get-StateDef {
  # One state's metadata; missing keys simply read as absent.
  param([string]$Id)
  if ($null -eq $Id) { return @{} }
  if (-not $stateDefs.ContainsKey($Id)) { return @{} }
  return $stateDefs[$Id]
}

function Get-ManifestEntry {
  param([string]$Id)
  foreach ($m in $manifest) { if ($m.id -eq $Id) { return $m } }
  return $null
}

$attrBalanceLabel = Get-Opt $ui 'balanceLabel' 'Balance'
$attrSignedOut = Get-Opt $ui 'balanceSignedOut' 'signed out'
$attrLoading = Get-Opt $ui 'balanceLoading' '...'
$attrRechargeLabel = Get-Opt $ui 'rechargeLabel' 'recharge'
$attrBonusLabel = Get-Opt $ui 'bonusLabel' 'bonus'
$attrMenuQuitLabel = Get-Opt $ui 'menuQuitLabel' 'Quit'
$attrMenuSettingsLabel = Get-Opt $ui 'menuSettingsLabel' 'Settings'
$attrMenuAutoOn = Get-Opt $ui 'menuAutoOn' 'auto: on'
$attrMenuAutoOff = Get-Opt $ui 'menuAutoOff' 'auto: off'
$attrGreetings = @(Get-Opt $ui 'greetings' @())
$attrCallName = Get-Opt (Get-Opt $config 'character' @{}) 'callName' 'pet'
$script:attrLowBalance = [double](Get-Opt $ui 'lowBalance' 0)
$script:attrAutoMin = [double](Get-Opt $behaviour 'autoSwitchMinSeconds' 14)
$script:attrAutoMax = [double](Get-Opt $behaviour 'autoSwitchMaxSeconds' 30)
$script:attrFixedAfterManual = [double](Get-Opt $behaviour 'fixedAfterManualSeconds' 120)
$script:attrSleepAfterIdle = [double](Get-Opt $behaviour 'sleepAfterIdleSeconds' 90)
$script:attrBalanceRefresh = [double](Get-Opt $behaviour 'balanceRefreshSeconds' 90)
$script:attrDisplayScale = [double](Get-Opt $behaviour 'displayScale' 0.58)

# ---------------------------------------------------------------- user settings
# Persisted separately from config.json, so editing the shipped config never fights the UI. The
# settings window lives in settings.ps1 and calls back into Apply-Setting / Request-SettingsSave.

# settings.ps1 defines Read-PetSettings / Save-PetSettings / Show-SettingsWindow and builds the
# settings panel; it needs the config-derived attribute defaults above, so it loads here.
. (Join-Path $root 'settings.ps1')

$script:settings = Read-PetSettings
$script:attrDisplayScale = [double]$script:settings.displayScale
$script:attrAutoMin = [double]$script:settings.autoSwitchMin
$script:attrAutoMax = [double]$script:settings.autoSwitchMax
$script:attrFixedAfterManual = [double]$script:settings.fixedAfterManual
$script:attrSleepAfterIdle = [double]$script:settings.sleepAfterIdle
$script:attrBalanceRefresh = [double]$script:settings.balanceRefresh
$script:attrLowBalance = [double]$script:settings.lowBalance

$script:settingsWindow = $null
$script:settingsDirty = $false
$script:started = $false
$script:positionDirty = $false

# Interaction bookkeeping. These are assigned here because StrictMode treats a scoped variable
# that was never set as an error, which would take the whole pet down on the first click.
$script:lastClickAt = $null
$script:animHoldUntil = [DateTime]::MinValue

# Design canvas for the pet: the bubble and the character are laid out inside this, and one
# outer ScaleTransform resizes the lot. A taller pose grows the canvas height, never the ratio.
$script:canvasSpriteBase = 340.0
$script:canvasBubbleHeight = 48.0
$script:drag = $null
$script:dragMoved = $false
$script:dragging = $false

function Request-SettingsSave {
  $script:settingsDirty = $true
}

function Get-SpriteDisplaySize {
  # The sprite is rendered far denser than it is shown, so scale it down on the way to the screen.
  param($Sprite)
  return @{
    width = [double]$Sprite.PixelWidth * $script:attrDisplayScale
    height = [double]$Sprite.PixelHeight * $script:attrDisplayScale
  }
}

function Apply-Setting {
  param([string]$Key, $Value)
  # Every tunable lives in script scope so the animation, state machine and balance timers see the
  # change immediately, without restarting the pet.
  try {
    switch ($Key) {
      'displayScale'     { $script:attrDisplayScale = [double]$Value; Resize-PetWindow }
      'autoSwitchMin'    { $script:attrAutoMin = [double]$Value }
      'autoSwitchMax'    { $script:attrAutoMax = [double]$Value }
      'fixedAfterManual' { $script:attrFixedAfterManual = [double]$Value }
      'sleepAfterIdle'   { $script:attrSleepAfterIdle = [double]$Value }
      'balanceRefresh'   { $script:attrBalanceRefresh = [double]$Value }
      'lowBalance'       { $script:attrLowBalance = [double]$Value; $script:balance.warnedLow = $false }
      'autoEnabled' {
        $script:state.autoPaused = -not [bool]$Value
        $script:state.nextAutoSwitch = (Get-Date)
        Update-AutoMenuLabel
      }
      'rememberPosition' { }
    }
    Write-Log ("setting {0} = {1}" -f $Key, $Value)
  } catch {
    Write-Log ("apply {0} failed: {1}" -f $Key, $_.Exception.Message) 'WARN'
    Write-Log ("apply {0} stack: {1}" -f $Key, $_.ScriptStackTrace) 'WARN'
  }
}

function Resize-PetWindow {
  param($Sprite)
  # Resolve the controls here rather than closing over them: this function is defined before the
  # window and its named elements exist, so a captured reference would be null.
  $canvas = $window.FindName('CanvasGrid')
  if ($null -eq $canvas) { return }
  if ($null -eq $Sprite) {
    $layer = $script:frontLayer
    if ($null -eq $layer) { return }
    $Sprite = $layer.Source
  }
  if ($null -eq $Sprite) { return }

  # The bubble and the character share one design canvas; the Viewbox scales that canvas as a unit,
  # so text, padding and character always keep a single ratio.
  $spriteH = [double]$Sprite.PixelHeight
  $spriteW = [double]$Sprite.PixelWidth
  # Wide enough for the wider of the sprite and the bubble, so neither is cut off.
  $designW = [Math]::Max(320.0, $spriteW + 8)
  $designH = [Math]::Max([double]$script:canvasSpriteBase, $spriteH) + [double]$script:canvasBubbleHeight

  # Cap the factor so character plus bubble always fit the work area: overflowing the screen would
  # clip the character, which is worse than stopping just short of full size.
  $wa = [System.Windows.SystemParameters]::WorkArea
  $scale = [double]$script:attrDisplayScale
  if ($designH -gt 0) {
    $fit = ($wa.Height - 24) / $designH
    if ($fit -lt 0.25) { $fit = 0.25 }
    if ($scale -gt $fit) { $scale = $fit }
  }

  $newW = [Math]::Max(60, [Math]::Round($designW * $scale))
  $newH = [Math]::Max(60, [Math]::Round($designH * $scale))
  if ([double]::IsNaN($newW) -or [double]::IsInfinity($newW) -or $newW -le 0) { return }
  if ([double]::IsNaN($newH) -or [double]::IsInfinity($newH) -or $newH -le 0) { return }

  # Keep the pet's footprint anchored on its bottom-right corner while it changes size. A NaN or an
  # absurd current size would produce a placement Windows rejects, so fall back to the window itself.
  $anchorLeft = $window.Left
  $anchorTop = $window.Top
  $right = $anchorLeft + $window.Width
  $bottom = $anchorTop + $window.Height
  if ([double]::IsNaN($right) -or [double]::IsInfinity($right) -or [Math]::Abs($right) -gt 1.0e6) { $right = $anchorLeft + $newW }
  if ([double]::IsNaN($bottom) -or [double]::IsInfinity($bottom) -or [Math]::Abs($bottom) -gt 1.0e6) { $bottom = $anchorTop + $newH }

  # Sizing the canvas and the window to the same scaled box makes Stretch="Fill" land exactly on the
  # requested factor, with no letterboxing inside the window.
  $canvas.Width = $newW
  $canvas.Height = $newH
  $window.Width = $newW
  $window.Height = $newH

  $targetLeft = [Math]::Max($wa.Left, [Math]::Min($wa.Right - $newW, $right - $newW))
  $targetTop = [Math]::Max($wa.Top, [Math]::Min($wa.Bottom - $newH, $bottom - $newH))
  if (-not [double]::IsNaN($targetLeft) -and -not [double]::IsInfinity($targetLeft)) { $window.Left = $targetLeft }
  if (-not [double]::IsNaN($targetTop) -and -not [double]::IsInfinity($targetTop)) { $window.Top = $targetTop }
  Write-Log ("resized to {0}x{1} scale {2} design {3}x{4} sprite {5}x{6}" -f [int]$newW, [int]$newH, [Math]::Round($scale, 3), [int]$designW, [int]$designH, [int]$spriteW, [int]$spriteH)
}


# ---------------------------------------------------------------- process detection

$script:dshNames = @('DeepSeek Harness')

function Get-DshProcesses {
  $found = @()
  foreach ($n in $script:dshNames) {
    $found += @(Get-Process -Name $n -ErrorAction SilentlyContinue)
  }
  return $found
}

# ---------------------------------------------------------------- balance

Add-Type -AssemblyName System.Net.Http

$script:balanceEndpoint = 'https://platform.deepseek.com/api/v0/users/get_user_summary'
$script:stateDir = Join-Path $env:USERPROFILE '.dsh'
$script:balance = @{
  status = 'loading'
  total = $null
  currency = 'CNY'
  normal = @()
  bonus = @()
  detail = ''
  fetchedAt = $null
  warnedLow = $false
}

function Get-PlatformToken {
  $file = Join-Path $script:stateDir '.credentials.yaml'
  if (-not (Test-Path -LiteralPath $file)) { throw 'credentials file not found' }
  $lines = Get-Content -LiteralPath $file -Encoding UTF8
  $inDefault = $false
  foreach ($line in $lines) {
    if ($line -match '^\s{2}(\S.*?):\s*$') {
      $inDefault = ($Matches[1] -eq 'deepseek-account-platform/default')
      continue
    }
    if ($inDefault -and $line -match '^\s+token:\s*(\S+)\s*$') { return $Matches[1] }
  }
  throw 'no DeepSeek account token found'
}

function Format-Amount {
  # Keep small non-zero balances visible instead of rounding them to 0.00.
  param([double]$Value)
  $abs = [Math]::Abs($Value)
  if ($abs -gt 0 -and $abs -lt 0.01) { return ('{0:0.####}' -f $Value) }
  return ('{0:0.00}' -f $Value)
}

function Request-Balance {
  $token = Get-PlatformToken
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $client = New-Object System.Net.Http.HttpClient
  $client.Timeout = [TimeSpan]::FromSeconds(20)
  $client.DefaultRequestHeaders.Add('x-dsh-auth-token', $token)
  $client.DefaultRequestHeaders.Add('Accept', 'application/json')
  try {
    $resp = $client.GetAsync($script:balanceEndpoint).GetAwaiter().GetResult()
    if (-not $resp.IsSuccessStatusCode) { throw ('HTTP ' + [int]$resp.StatusCode) }
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  } finally {
    $client.Dispose()
  }
  $parsed = $body | ConvertFrom-Json
  if ($parsed.code -ne 0) { throw ('platform code ' + $parsed.code) }
  $data = $parsed.data.biz_data
  $normal = @()
  foreach ($w in @($data.normal_wallets)) { if ($null -ne $w) { $normal += [pscustomobject]@{ currency = $w.currency; balance = [double]$w.balance } } }
  $bonus = @()
  foreach ($w in @($data.bonus_wallets)) { if ($null -ne $w) { $bonus += [pscustomobject]@{ currency = $w.currency; balance = [double]$w.balance } } }
  $currency = 'CNY'
  if ($normal.Count -gt 0) { $currency = $normal[0].currency }
  elseif ($bonus.Count -gt 0) { $currency = $bonus[0].currency }
  $total = 0.0
  foreach ($w in $normal) { $total += $w.balance }
  foreach ($w in $bonus) { $total += $w.balance }
  return [pscustomobject]@{
    total = $total
    currency = $currency
    normal = $normal
    bonus = $bonus
    normalTotal = ($normal | Measure-Object -Property balance -Sum).Sum
    bonusTotal = ($bonus | Measure-Object -Property balance -Sum).Sum
  }
}

function New-BalanceDetail {
  param($Result)
  $sym = if ($Result.currency -eq 'CNY') { "$([char]0x00A5)" } else { '$' }
  $parts = @()
  if ([int]$Result.normalCount -gt 0) {
    $parts += ('{0} {1}{2}' -f $attrRechargeLabel, $sym, (Format-Amount ([double]$Result.normalTotal)))
  }
  if ([int]$Result.bonusCount -gt 0) {
    $parts += ('{0} {1}{2}' -f $attrBonusLabel, $sym, (Format-Amount ([double]$Result.bonusTotal)))
  }
  return ($parts -join '  ')
}

# ---------------------------------------------------------------- doctor mode

if ($Doctor) {
  Write-Host '--- desktop pet doctor ---'
  Write-Host ("root        : {0}" -f $root)
  Write-Host ("config      : {0}" -f $configPath)
  Write-Host ("manifest    : {0} entries" -f @($manifest).Count)
  $missing = @()
  foreach ($m in $manifest) {
    $f = Join-Path $assetDir $m.file
    if (-not (Test-Path -LiteralPath $f)) { $missing += $m.file }
  }
  Write-Host ("sprites     : {0} missing" -f $missing.Count)
  if ($missing.Count -gt 0) { Write-Host ("  missing: {0}" -f ($missing -join ', ')) }
  $procs = Get-DshProcesses
  Write-Host ("dsh running : {0} process(es)" -f @($procs).Count)
  try {
    $r = Request-Balance
    Write-Host ("balance     : {0} {1} total={2}" -f $r.currency, (Format-Amount $r.total), $r.total)
    $detailShape = @{
      currency = $r.currency
      normalCount = @($r.normal).Count
      bonusCount = @($r.bonus).Count
      normalTotal = $r.normalTotal
      bonusTotal = $r.bonusTotal
    }
    Write-Host ("  detail    : {0}" -f (New-BalanceDetail $detailShape))
  } catch {
    Write-Host ("balance     : FAILED {0}" -f $_.Exception.Message)
  }
  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  $entry = $null
  try { $entry = (Get-ItemProperty -Path $runKey -ErrorAction Stop).DshDesktopPet } catch { $entry = $null }
  Write-Host ("autostart   : {0}" -f ($(if ($entry) { $entry } else { 'not installed' })))
  Write-Host '--- end ---'
  exit 0
}

# ---------------------------------------------------------------- single instance

$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\DshDesktopPet.SingleInstance', [ref]$createdNew)
if (-not $createdNew) {
  Write-Log 'another instance is already running; exiting'
  exit 0
}

if (-not $Force) {
  if (@(Get-DshProcesses).Count -eq 0) {
    Write-Log 'DeepSeek Harness is not running; exiting'
    exit 0
  }
}

# ---------------------------------------------------------------- window

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Xaml

# Pointer placement must not use window-relative coordinates: the window itself is moving, so its
# frame of reference shifts under the gesture and the sprite visibly oscillates. Screen pixels are
# unaffected by where the window happens to be.
Add-Type -Namespace PetNative -Name Cursor -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
'@

function Get-CursorScreen {
  $p = New-Object PetNative.Cursor+POINT
  if ([PetNative.Cursor]::GetCursorPos([ref]$p)) {
    return [pscustomobject]@{ X = $p.X; Y = $p.Y }
  }
  return $null
}

function Get-DpiScale {
  # user32 reports physical pixels while WPF window placement is in device-independent units, so the
  # two must be converted or the pet jumps by the scale factor the moment a drag begins.
  try {
    $source = [System.Windows.PresentationSource]::FromVisual($window)
    if ($null -ne $source -and $null -ne $source.CompositionTarget) {
      return [double]$source.CompositionTarget.TransformToDevice.M11
    }
  } catch { }
  return 1.0
}

function Get-WindowOrigin {
  # WPF units; Convert-DipToPixels turns these into the physical pixels GetCursorPos reports.
  $origin = $window.PointToScreen((New-Object System.Windows.Point(0, 0)))
  return [pscustomobject]@{ X = $origin.X; Y = $origin.Y }
}

function Convert-DipToPixels {
  param([double]$Value, [double]$Scale)
  return $Value * $Scale
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DshDesktopPet"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        SizeToContent="Manual" WindowStartupLocation="Manual">
  <!-- A Viewbox scales the whole composition as one unit: the balance bubble, its text and padding,
       and the character keep a single ratio at every size. The design canvas inside is fixed; the
       window is sized to canvas x scale so the Viewbox lands exactly on the requested factor. -->
  <Grid x:Name="Root" Background="#01000000">
    <Viewbox x:Name="Scaler" Stretch="Fill" StretchDirection="Both"
             HorizontalAlignment="Left" VerticalAlignment="Top">
      <Grid x:Name="CanvasGrid" Width="320" Height="380">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <StackPanel x:Name="Bubble" Grid.Row="0" HorizontalAlignment="Center" VerticalAlignment="Top"
                    Margin="0,8,0,0" Opacity="0">
          <StackPanel.RenderTransform>
            <TranslateTransform x:Name="BubbleShift" Y="10"/>
          </StackPanel.RenderTransform>
          <Border CornerRadius="14" Background="#E61B2438" BorderBrush="#59FFFFFF" BorderThickness="1"
                  Padding="14,7,14,7">
            <StackPanel>
              <DockPanel LastChildFill="False">
                <Button x:Name="SettingsButton" DockPanel.Dock="Right" FontFamily="Microsoft YaHei UI"
                        FontSize="13" Foreground="#FFCFE0FF" Background="Transparent" BorderThickness="0"
                        Padding="6,0,0,0" Margin="8,0,0,0" Cursor="Hand" VerticalAlignment="Center" Content="&#x2699;"/>
                <TextBlock x:Name="BalanceText" DockPanel.Dock="Left" Text="..." FontFamily="Microsoft YaHei UI" FontSize="18"
                           FontWeight="SemiBold" Foreground="#FFF3F7FF" VerticalAlignment="Center"/>
              </DockPanel>
              <TextBlock x:Name="DetailText" Text="" FontFamily="Microsoft YaHei UI" FontSize="11"
                         Foreground="#FFBFD2F0" HorizontalAlignment="Center" Margin="0,3,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel>

        <Grid x:Name="Stage" Grid.Row="1" Background="#01000000" ClipToBounds="False">
          <Image x:Name="PetBack" Stretch="Uniform" VerticalAlignment="Bottom" HorizontalAlignment="Center" IsHitTestVisible="False"
                 RenderOptions.BitmapScalingMode="HighQuality" Opacity="0">
            <Image.Effect>
              <DropShadowEffect BlurRadius="14" ShadowDepth="0" Opacity="0.35" Color="#FF06111F"/>
            </Image.Effect>
            <Image.RenderTransform>
              <TransformGroup>
                <TranslateTransform x:Name="PetShift"/>
                <RotateTransform x:Name="PetRotate"/>
                <ScaleTransform x:Name="PetScale"/>
              </TransformGroup>
            </Image.RenderTransform>
          </Image>
          <Image x:Name="PetFront" Stretch="Uniform" VerticalAlignment="Bottom" HorizontalAlignment="Center" IsHitTestVisible="False"
                 RenderOptions.BitmapScalingMode="HighQuality" Opacity="0">
            <Image.Effect>
              <DropShadowEffect BlurRadius="14" ShadowDepth="0" Opacity="0.35" Color="#FF06111F"/>
            </Image.Effect>
            <Image.RenderTransform>
              <TransformGroup>
                <TranslateTransform/>
                <RotateTransform/>
                <ScaleTransform/>
              </TransformGroup>
            </Image.RenderTransform>
          </Image>
        </Grid>
      </Grid>
    </Viewbox>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$window.Width = $winW
$window.Height = $winH
$window.Left = -10000
$window.Top = -10000

$front = $window.FindName('PetFront')
$back = $window.FindName('PetBack')
$bubble = $window.FindName('Bubble')
$bubbleShift = $window.FindName('BubbleShift')
$balanceText = $window.FindName('BalanceText')
$detailText = $window.FindName('DetailText')
$stage = $window.FindName('Stage')
$rootElement = $window.FindName('Root')

# The gear on the balance bubble and the menu entry open the same settings panel.
$bubbleSettingsButton = $window.FindName('SettingsButton')
if ($null -ne $bubbleSettingsButton) {
  $bubbleSettingsButton.ToolTip = [string]$attrMenuSettingsLabel
  $bubbleSettingsButton.Add_Click({ Show-SettingsWindow })
}

# The front layer's transform group is unnamed in XAML, so reach the parts positionally and keep
# it as the single group that the animation loop drives.
$frontGroup = $front.RenderTransform
$frontShift = $frontGroup.Children[0]
$frontRotate = $frontGroup.Children[1]
$frontScale = $frontGroup.Children[2]
$front.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 1.0)
$back.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 1.0)
$script:frontLayer = $front
$script:backLayer = $back

# ---------------------------------------------------------------- sprites

$script:sprites = @{}
$script:spriteOrder = @()
foreach ($m in $manifest) { $script:spriteOrder += $m.id }

function Get-Sprite {
  param([string]$Id)
  if ($script:sprites.ContainsKey($Id)) { return $script:sprites[$Id] }
  $entry = Get-ManifestEntry -Id $Id
  if ($null -eq $entry) { return $null }
  $file = Join-Path $assetDir $entry.file
  $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
  $bmp.BeginInit()
  $bmp.UriSource = New-Object System.Uri($file)
  $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $bmp.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat
  $bmp.EndInit()
  $bmp.Freeze()
  $script:sprites[$Id] = $bmp
  return $bmp
}

# ---------------------------------------------------------------- state machine

$script:state = [pscustomobject]@{
  id = 'smile'
  motion = 'breathe'
  manualUntil = [DateTime]::MinValue
  lastInteraction = [DateTime]::Now
  nextAutoSwitch = [DateTime]::Now.AddSeconds($script:attrAutoMin)
  autoPaused = $false
}

$script:rng = New-Object System.Random

function Set-PetState {
  param([string]$Id, [switch]$Silent)
  $entry = Get-ManifestEntry -Id $Id
  if ($null -eq $entry) { return }
  $bmp = Get-Sprite -Id $Id
  if ($null -eq $bmp) { return }

  # The outgoing sprite fades out underneath while the incoming one is already in front, so the
  # swap has no flash; the animation loop keeps driving whichever layer is on top.
  $outgoing = $script:frontLayer
  $incoming = $script:backLayer
  $incoming.Source = $bmp
  $incoming.Width = [double]$bmp.PixelWidth * $script:attrDisplayScale
  $incoming.Height = [double]$bmp.PixelHeight * $script:attrDisplayScale
  # A fade clock left on this layer by an earlier transition outranks any local value,
  # so it has to be cleared before the layer can show a sprite again.
  $incoming.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $null)
  $outgoing.Width = $incoming.Width
  $outgoing.Height = $incoming.Height
  $incoming.Opacity = 1
  $fade = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, 0.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(260)))
  $outgoing.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $fade)
  $script:frontLayer = $incoming
  $script:backLayer = $outgoing
  # Poses differ in height, so refit the window around whichever one is now showing - unless a
  # drag is in progress, where moving the window would fight the cursor; it refits on release.
  if ($script:started) {
    if ($script:dragging -and $null -ne $script:drag) { $script:drag.resized = $true }
    else { Resize-PetWindow -Sprite $bmp }
  }

  $cfg = (Get-StateDef $Id)
  $motion = 'breathe'
  if ($null -ne $cfg -and $null -ne $cfg.motion) { $motion = [string]$cfg.motion }
  if ($null -ne $entry.motion) { $motion = [string]$entry.motion }
  $script:state.id = $Id
  $script:state.motion = $motion
  $script:state.lastInteraction = [DateTime]::Now
  Write-Log ("state -> {0} (motion {1})" -f $Id, $motion)
}

function Get-IdlePool {
  # Which states take part in the idle rotation is declared by the asset manifest, not by config.
  $pool = @()
  foreach ($m in $manifest) {
    if ($null -ne $m -and $m.ContainsKey('idle') -and $m['idle'] -eq $true) { $pool += $m['id'] }
  }
  if ($pool.Count -eq 0) { $pool = $script:spriteOrder }
  return $pool
}

$script:idlePool = Get-IdlePool

function Invoke-AutoSwitch {
  $state = $script:state
  if ($state.autoPaused) { return }
  if ((Get-Date) -lt $state.manualUntil) { return }
  if ((Get-Date) -lt $state.nextAutoSwitch) { return }
  $idleFor = ((Get-Date) - $state.lastInteraction).TotalSeconds
  $choice = $null
  if ($idleFor -ge $script:attrSleepAfterIdle) {
    $choice = 'sleep'
  } else {
    $pool = @($script:idlePool | Where-Object { $_ -ne $state.id })
    if ($pool.Count -eq 0) { $pool = $script:idlePool }
    $choice = $pool[$script:rng.Next(0, $pool.Count)]
  }
  Set-PetState -Id $choice
  $lo = $script:attrAutoMin
  $hi = $script:attrAutoMax
  $state.nextAutoSwitch = (Get-Date).AddSeconds($lo + $script:rng.NextDouble() * ($hi - $lo))
}

# ---------------------------------------------------------------- animation

$script:anim = [pscustomobject]@{
  watch = [System.Diagnostics.Stopwatch]::StartNew()
  phase = 0.0
}

function Update-Motion {
  $t = $script:anim.watch.Elapsed.TotalSeconds
  if ($script:dragging -or (Get-Date) -lt $script:animHoldUntil) {
    # While the user is dragging (or has just clicked) the pose sits still: a bobbing sprite inside a
    # window that is itself moving reads as twitching.
    $group = $script:frontLayer.RenderTransform
    $group.Children[2].ScaleX = 1.0
    $group.Children[2].ScaleY = 1.0
    $group.Children[0].X = 0
    $group.Children[0].Y = 0
    $group.Children[1].Angle = 0
    return
  }
  $m = $script:state.motion
  $sx = 1.0
  $sy = 1.0
  $dy = 0.0
  $rot = 0.0
  switch ($m) {
    'breathe' {
      $s = [Math]::Sin($t * 2.0 * [Math]::PI / 2.8)
      $sy = 1.0 + 0.022 * $s
      $sx = 1.0 - 0.016 * $s
      $dy = -0.6 * $s
    }
    'hop' {
      $u = ($t % 1.5) / 1.5
      $lift = [Math]::Max(0.0, [Math]::Sin($u * [Math]::PI))
      $dy = -9.0 * $lift
      $sy = 1.0 + 0.035 * $lift
      $sx = 1.0 - 0.03 * $lift
      $rot = 2.5 * [Math]::Sin($t * 2.0 * [Math]::PI / 1.5)
    }
    'sway' {
      $rot = 2.2 * [Math]::Sin($t * 2.0 * [Math]::PI / 3.6)
      $sx = 1.0 + 0.008 * [Math]::Sin($t * 2.0 * [Math]::PI / 1.8)
      $sy = 1.0 - 0.006 * [Math]::Sin($t * 2.0 * [Math]::PI / 1.8)
      $dy = -1.5 * [Math]::Abs([Math]::Sin($t * 2.0 * [Math]::PI / 3.6))
    }
    'tremble' {
      $rot = 1.4 * [Math]::Sin($t * 2.0 * [Math]::PI * 3.2)
      $dy = 0.8 * [Math]::Sin($t * 2.0 * [Math]::PI * 4.1)
    }
    'sleep' {
      $s = [Math]::Sin($t * 2.0 * [Math]::PI / 4.4)
      $sy = 1.0 + 0.03 * $s
      $sx = 1.0 - 0.02 * $s
      $rot = 3.0 + 0.7 * $s
      $dy = 1.0 - 0.8 * $s
    }
    default {
      $s = [Math]::Sin($t * 2.0 * [Math]::PI / 2.8)
      $sy = 1.0 + 0.02 * $s
      $sx = 1.0 - 0.014 * $s
    }
  }
  $group = $script:frontLayer.RenderTransform
  $group.Children[2].ScaleX = $sx
  $group.Children[2].ScaleY = $sy
  $group.Children[0].X = 0
  $group.Children[0].Y = $dy
  $group.Children[1].Angle = $rot
}

# ---------------------------------------------------------------- bubble text

function Show-BubbleText {
  param([string]$Text, [string]$Detail = '', [int]$Lines = 1)
  $balanceText.Text = $Text
  $fontSize = 18
  if ($Lines -eq 2 -or $Text.Length -gt 12) { $fontSize = 14 }
  $balanceText.FontSize = $fontSize
  $detailText.Text = $Detail
  $detailText.Visibility = if ($Detail) { 'Visible' } else { 'Collapsed' }
}

$script:greetingUntil = [DateTime]::MinValue

function Update-BalanceDisplay {
  if ($script:greetingUntil -gt (Get-Date)) { return }
  $b = $script:balance
  $sym = if ($b.currency -eq 'CNY') { "$([char]0x00A5)" } else { '$' }
  switch ($b.status) {
    'ready' {
      $amount = Format-Amount $b.total
      Show-BubbleText -Text ("{0} {1}{2}" -f $attrBalanceLabel, $sym, $amount) -Detail $b.detail
      # A low budget is worth reacting to once; the next auto-switch then picks a worried pose.
      $low = $script:attrLowBalance
      if ($b.total -lt $low -and $b.total -ge 0 -and -not $b.warnedLow) {
        $b.warnedLow = $true
        if (-not $script:state.autoPaused) { $script:state.nextAutoSwitch = (Get-Date) }
      }
    }
    'signedout' { Show-BubbleText -Text $attrSignedOut }
    'error' { Show-BubbleText -Text $attrBalanceUnavailable -Detail $b.detail }
    default { Show-BubbleText -Text $attrLoading }
  }
}

function Show-Bubble {
  param([double]$To = 1.0)
  $bubble.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation($To, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(280)))))
  $bubbleShift.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-Object System.Windows.Media.Animation.DoubleAnimation((10 * (1 - $To)), [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(280)))))
}

function Show-Greeting {
  param([string]$Text, [double]$Seconds = 3.5)
  $balanceText.Text = $Text
  $balanceText.FontSize = 14
  $detailText.Visibility = 'Collapsed'
  $script:greetingUntil = (Get-Date).AddSeconds($Seconds)
}

# ---------------------------------------------------------------- interactions

function Remember-Interaction {
  # The pose animation parks its vertical bob while the user is dragging or just clicked, which is
  # what made the pet look like it was twitching as it moved.
  $script:animHoldUntil = (Get-Date).AddMilliseconds(450)
  $script:state.lastInteraction = [DateTime]::Now
  if ($script:state.id -eq 'sleep') {
    Set-PetState -Id 'smile'
  }
}

# Dragging is handled on the outermost grid so anywhere in the window works, not just the sprite.
$rootElement.Add_MouseLeftButtonDown({
  param($sender, $e)
  Remember-Interaction
  $cursor = Get-CursorScreen
  if ($null -eq $cursor) { return }
  # GetCursorPos reports physical pixels; store the cursor and the window origin in the same unit so
  # the translation is exact. The window origin is taken as the authoritative screen position, which
  # also absorbs any mismatch between window placement and PointToScreen at non-100% scaling.
  $scale = Get-DpiScale
  if ($scale -le 0) { $scale = 1.0 }
  $origin = Get-WindowOrigin
  $unitOriginX = [double]$origin.X / $scale
  $unitOriginY = [double]$origin.Y / $scale
  $cursorUnitX = $cursor.X / $scale
  $cursorUnitY = $cursor.Y / $scale
  $script:drag = [pscustomobject]@{
    cursorUnitX = $cursorUnitX
    cursorUnitY = $cursorUnitY
    originUnitX = $unitOriginX
    originUnitY = $unitOriginY
    scale = $scale
    resized = $false
  }
  $script:dragMoved = $false
  $script:dragging = $true
  [void]$rootElement.CaptureMouse()
  $e.Handled = $true
})

$rootElement.Add_MouseMove({
  param($sender, $e)
  if ($null -eq $script:drag) { return }
  $cursor = Get-CursorScreen
  if ($null -eq $cursor) { return }
  $dx = ($cursor.X / $script:drag.scale) - $script:drag.cursorUnitX
  $dy = ($cursor.Y / $script:drag.scale) - $script:drag.cursorUnitY
  # A few pixels of slack keeps a double click from nudging the pet.
  if (-not $script:dragMoved -and ([Math]::Abs($dx) -gt 4 -or [Math]::Abs($dy) -gt 4)) { $script:dragMoved = $true }
  if (-not $script:dragMoved) { return }

  # Keep the pose parked for the whole gesture; a bobbing sprite inside a moving window reads as
  # twitching even when the translation itself is exact.
  $script:animHoldUntil = (Get-Date).AddMilliseconds(400)
  # Cursor and origin share one unit here, so this is a plain translation.
  $window.Left = $script:drag.originUnitX + $dx
  $window.Top = $script:drag.originUnitY + $dy
  $script:positionDirty = $true
})

$rootElement.Add_MouseLeftButtonUp({
  param($sender, $e)
  if ($null -ne $script:drag) {
    [void]$rootElement.ReleaseMouseCapture()
    $dragged = $script:dragMoved
    $refit = $script:drag.resized
    $script:drag = $null
  } else {
    $dragged = $false
    $refit = $false
  }
  $script:dragging = $false
  # A pose that changed mid-drag deferred its refit; apply it now that the window is parked.
  if ($refit -and $null -ne $script:frontLayer) { Resize-PetWindow -Sprite $script:frontLayer.Source }
  # A second click inside the double-click window opens the settings. Both WPF's ClickCount and a
  # plain time window are honoured so the gesture works however the click arrives.
  if (-not $dragged) {
    $now = [DateTime]::Now
    $quick = $false
    if ($null -ne $script:lastClickAt) {
      $quick = ($now - $script:lastClickAt).TotalMilliseconds -lt 600
    }
    if ($e.ClickCount -ge 2 -or $quick) {
      $script:lastClickAt = $null
      Show-SettingsWindow
    } else {
      $script:lastClickAt = $now
    }
  }
  $script:dragMoved = $false
})


# Right click opens the state menu; the wheel steps through states.
$rootElement.Add_MouseRightButtonUp({
  param($sender, $e)
  try {
    Remember-Interaction
    # Absolute placement needs screen coordinates: PointToScreen already includes the window origin.
    $origin = $window.PointToScreen((New-Object System.Windows.Point(0, 0)))
    $screenW = [System.Windows.SystemParameters]::WorkArea.Width
    $screenH = [System.Windows.SystemParameters]::WorkArea.Height
    $px = $origin.X + 20
    $py = $origin.Y + 20
    if ($px -gt ($screenW - 190)) { $px = $screenW - 190 }
    $menuHeight = 640
    if ($py -gt ($screenH - $menuHeight - 12)) { $py = [Math]::Max(8, $screenH - $menuHeight - 12) }
    Show-Menu -X ([double]$px) -Y ([double]$py)
  } catch {
    Write-Log ("right-click handler failed: {0}" -f $_.Exception.Message) 'WARN'
  }
})

$rootElement.Add_MouseWheel({
  param($sender, $e)
  try {
    Remember-Interaction
    $pool = @($script:idlePool + @('sleep', 'angry', 'cry', 'melon', 'rice', 'hold', 'eat'))
    $idx = $pool.IndexOf($script:state.id)
    $step = if ($e.Delta -gt 0) { 1 } else { -1 }
    $next = (($idx + $step) % $pool.Count + $pool.Count) % $pool.Count
    $script:state.manualUntil = (Get-Date).AddSeconds($script:attrFixedAfterManual)
    Set-PetState -Id $pool[$next]
  } catch {
    Write-Log ("wheel handler failed: {0}" -f $_.Exception.Message) 'WARN'
  }
})

# Escape closes the panels; Ctrl+Alt+S opens the settings too.
$window.Add_KeyDown({
  param($sender, $e)
  if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
    if ($menu.IsOpen) { $menu.IsOpen = $false }
  }
})

# ---------------------------------------------------------------- context menu

$menuFont = 'Microsoft YaHei UI'

$menuItems = @()
foreach ($id in $script:spriteOrder) {
  $cfg = (Get-StateDef $id)
  $label = $id
  $shortcut = ''
  if ($null -ne $cfg -and $null -ne $cfg.label) { $label = [string]$cfg.label }
  $entry = Get-ManifestEntry -Id $id
  if ($null -ne $entry -and $null -ne $entry.label) { $shortcut = [string]$entry.label }
  $menuItems += [pscustomobject]@{ id = $id; label = $label; alt = $shortcut }
}

$menu = New-Object System.Windows.Controls.Primitives.Popup
$menu.AllowsTransparency = $true
$menu.StaysOpen = $false
$menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Absolute

$menuBorder = New-Object System.Windows.Controls.Border
$menuBorder.CornerRadius = New-Object System.Windows.CornerRadius(12)
$menuBorder.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(242, 20, 28, 43))
$menuBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(102, 255, 255, 255))
$menuBorder.BorderThickness = New-Object System.Windows.Thickness(1)
$menuBorder.Padding = New-Object System.Windows.Thickness(6)
$shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$shadow.BlurRadius = 18
$shadow.ShadowDepth = 3
$shadow.Opacity = 0.55
$shadow.Color = [System.Windows.Media.Color]::FromArgb(255, 0, 0, 0)
$menuBorder.Effect = $shadow
$menu.Child = $menuBorder

$menuStack = New-Object System.Windows.Controls.StackPanel
$menuStack.Width = 140
$menuScroll = New-Object System.Windows.Controls.ScrollViewer
$menuScroll.VerticalScrollBarVisibility = 'Auto'
$menuScroll.HorizontalScrollBarVisibility = 'Disabled'
$menuScroll.MaxHeight = 620
$menuScroll.Content = $menuStack
$menuBorder.Child = $menuScroll

$menuButtons = @{}
foreach ($item in $menuItems) {
  $btn = New-Object System.Windows.Controls.Button
  $btn.Content = [string]$item.label
  $btn.HorizontalContentAlignment = 'Left'
  $btn.FontFamily = New-Object System.Windows.Media.FontFamily($menuFont)
  $btn.FontSize = 11
  $btn.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 240, 245, 255))
  $btn.Background = [System.Windows.Media.Brushes]::Transparent
  $btn.BorderThickness = New-Object System.Windows.Thickness(0)
  $btn.Padding = New-Object System.Windows.Thickness(10, 2, 10, 2)
  $btn.Margin = New-Object System.Windows.Thickness(0, 0, 0, 0)
  $btn.Cursor = [System.Windows.Input.Cursors]::Hand
  $id = $item.id
  Add-Member -InputObject $btn -MemberType NoteProperty -Name PetState -Value $id -Force
  $btn.Add_Click({
    param($sender, $e)
    $target = $sender.PetState
    $script:state.manualUntil = (Get-Date).AddSeconds($script:attrFixedAfterManual)
    $script:state.autoPaused = $false
    Set-PetState -Id $target
    Update-AutoMenuLabel
    $menu.IsOpen = $false
  })
  $menuStack.Children.Add($btn) | Out-Null
  $menuButtons[$item.id] = $btn
}

$autoToggle = New-Object System.Windows.Controls.Button
$autoToggle.HorizontalContentAlignment = 'Left'
$autoToggle.FontFamily = New-Object System.Windows.Media.FontFamily($menuFont)
$autoToggle.FontSize = 12
$autoToggle.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 178, 205, 255))
$autoToggle.Background = [System.Windows.Media.Brushes]::Transparent
$autoToggle.BorderThickness = New-Object System.Windows.Thickness(0)
$autoToggle.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
$autoToggle.Margin = New-Object System.Windows.Thickness(0, 4, 0, 1)
$autoToggle.Cursor = [System.Windows.Input.Cursors]::Hand

$quitButton = New-Object System.Windows.Controls.Button
$quitButton.Content = [string]$attrMenuQuitLabel
$quitButton.HorizontalContentAlignment = 'Left'
$quitButton.FontFamily = New-Object System.Windows.Media.FontFamily($menuFont)
$quitButton.FontSize = 12
$quitButton.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 255, 190, 190))
$quitButton.Background = [System.Windows.Media.Brushes]::Transparent
$quitButton.BorderThickness = New-Object System.Windows.Thickness(0)
$quitButton.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
$quitButton.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
$quitButton.Cursor = [System.Windows.Input.Cursors]::Hand
$quitButton.Add_Click({ $menu.IsOpen = $false; $window.Close() })

$settingsButton = New-Object System.Windows.Controls.Button
$settingsButton.Content = [string]$attrMenuSettingsLabel
$settingsButton.HorizontalContentAlignment = 'Left'
$settingsButton.FontFamily = New-Object System.Windows.Media.FontFamily($menuFont)
$settingsButton.FontSize = 12
$settingsButton.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 200, 226, 255))
$settingsButton.Background = [System.Windows.Media.Brushes]::Transparent
$settingsButton.BorderThickness = New-Object System.Windows.Thickness(0)
$settingsButton.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
$settingsButton.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
$settingsButton.Cursor = [System.Windows.Input.Cursors]::Hand
$settingsButton.Add_Click({
  $menu.IsOpen = $false
  Show-SettingsWindow
})

$menuStack.Children.Add($settingsButton) | Out-Null
$menuStack.Children.Add($autoToggle) | Out-Null
$menuStack.Children.Add($quitButton) | Out-Null

function Update-AutoMenuLabel {
  if ($script:state.autoPaused) { $autoToggle.Content = [string]$attrMenuAutoOff }
  else { $autoToggle.Content = [string]$attrMenuAutoOn }
}
Update-AutoMenuLabel

$autoToggle.Add_Click({
  $script:state.autoPaused = -not $script:state.autoPaused
  $script:state.nextAutoSwitch = (Get-Date)
  Update-AutoMenuLabel
})

function Show-Menu {
  param([double]$X, [double]$Y)
  $menu.HorizontalOffset = $X
  $menu.VerticalOffset = $Y
  $menu.IsOpen = $true
}



$settingsSaveTimer = New-Object System.Windows.Threading.DispatcherTimer
$settingsSaveTimer.Interval = [TimeSpan]::FromSeconds(1)
$settingsSaveTimer.Add_Tick({
  try {
    if ($script:settingsDirty -or $script:positionDirty) {
      $script:settingsDirty = $false
      $script:positionDirty = $false
      Save-PetSettings
    }
  } catch {
    Write-Log ("settings tick failed: {0}" -f $_.Exception.Message) 'WARN'
  }
})

# ---------------------------------------------------------------- timers

$animTimer = New-Object System.Windows.Threading.DispatcherTimer
$animTimer.Interval = [TimeSpan]::FromMilliseconds(16)
$animTimer.Add_Tick({
  try { Update-Motion } catch { Write-Log ("motion tick failed: {0}" -f $_.Exception.Message) 'WARN' }
})

$logicTimer = New-Object System.Windows.Threading.DispatcherTimer
$logicTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:tick = 0
$logicTimer.Add_Tick({
  try {
    $script:tick++
    Invoke-AutoSwitch
    if ($script:tick % 20 -eq 0) {
      if (@(Get-DshProcesses).Count -eq 0) {
        Write-Log 'DeepSeek Harness exited; closing pet'
        $window.Close()
      }
    }
  } catch {
    Write-Log ("logic tick failed: {0}" -f $_.Exception.Message) 'WARN'
  }
})

# ---------------------------------------------------------------- balance polling

# The HTTP read runs in a PowerShell background job: a script block handed to a raw Task has no
# runspace, and a blocking call on the dispatcher thread would freeze the animation.
$script:balanceJob = $null
$script:balanceJobStarted = [DateTime]::MinValue

function Start-BalanceFetch {
  if ($null -ne $script:balanceJob) { return }
  $uri = $script:balanceEndpoint
  $credFile = Join-Path $script:stateDir '.credentials.yaml'
  $script:balanceJob = Start-Job -ScriptBlock {
    param($Endpoint, $CredFile)
    $lines = Get-Content -LiteralPath $CredFile -Encoding UTF8
    $token = $null
    $inDefault = $false
    foreach ($line in $lines) {
      if ($line -match '^\s{2}(\S.*?):\s*$') {
        $inDefault = ($Matches[1] -eq 'deepseek-account-platform/default')
        continue
      }
      if ($inDefault -and $line -match '^\s+token:\s*(\S+)\s*$') { $token = $Matches[1]; break }
    }
    if (-not $token) { throw 'no DeepSeek account token found' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $resp = Invoke-WebRequest -Uri $Endpoint -Headers @{ 'x-dsh-auth-token' = $token; 'Accept' = 'application/json' } -UseBasicParsing -TimeoutSec 25
    $parsed = $resp.Content | ConvertFrom-Json
    if ($parsed.code -ne 0) { throw ('platform code ' + $parsed.code) }
    $data = $parsed.data.biz_data
    $normal = @()
    foreach ($w in @($data.normal_wallets)) { if ($null -ne $w) { $normal += @{ currency = [string]$w.currency; balance = [double]$w.balance } } }
    $bonus = @()
    foreach ($w in @($data.bonus_wallets)) { if ($null -ne $w) { $bonus += @{ currency = [string]$w.currency; balance = [double]$w.balance } } }
    $currency = 'CNY'
    if ($normal.Count -gt 0) { $currency = $normal[0].currency }
    elseif ($bonus.Count -gt 0) { $currency = $bonus[0].currency }
    $normalTotal = 0.0
    foreach ($w in $normal) { $normalTotal += $w.balance }
    $bonusTotal = 0.0
    foreach ($w in $bonus) { $bonusTotal += $w.balance }
    [pscustomobject]@{
      total = $normalTotal + $bonusTotal
      currency = $currency
      normalCount = $normal.Count
      bonusCount = $bonus.Count
      normalTotal = $normalTotal
      bonusTotal = $bonusTotal
    }
  } -ArgumentList $uri, $credFile
  $script:balanceJobStarted = Get-Date
  Write-Log 'balance fetch started'
}

function Complete-BalanceFetch {
  if ($null -eq $script:balanceJob) { return }
  $job = $script:balanceJob
  if ($job.State -eq 'Running') {
    # Give up on a hung request so polling can retry later.
    if (((Get-Date) - $script:balanceJobStarted).TotalSeconds -gt 45) {
      Stop-Job -Job $job -ErrorAction SilentlyContinue
      Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
      $script:balanceJob = $null
      $script:balance.status = 'error'
      $script:balance.detail = 'timeout'
      Update-BalanceDisplay
      Write-Log 'balance fetch timed out' 'WARN'
    }
    return
  }
  $script:balanceJob = $null
  $result = $null
  $failure = $null
  try {
    $received = Receive-Job -Job $job -ErrorAction Stop
    if ($null -ne $received) { $result = @($received)[-1] }
  } catch {
    $failure = $_.Exception.Message
  }
  if ($null -eq $result -and @($job.ChildJobs[0].JobStateInfo.Reason).Count -gt 0) {
    $reason = $job.ChildJobs[0].JobStateInfo.Reason
    if ($null -ne $reason) { $failure = $reason.Message }
  }
  Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

  if ($null -eq $result) {
    $script:balance.status = 'error'
    if (-not $failure) { $failure = 'no result' }
    $script:balance.detail = $failure
    Update-BalanceDisplay
    Write-Log ("balance fetch failed: {0}" -f $failure) 'WARN'
    return
  }
  $script:balance.status = 'ready'
  $script:balance.total = [double]$result.total
  $script:balance.currency = [string]$result.currency
  $script:balance.normalTotal = [double]$result.normalTotal
  $script:balance.bonusTotal = [double]$result.bonusTotal
  $script:balance.normalCount = [int]$result.normalCount
  $script:balance.bonusCount = [int]$result.bonusCount
  $script:balance.detail = (New-BalanceDetail $script:balance)
  $script:balance.fetchedAt = Get-Date
  Update-BalanceDisplay
  $sym = if ($script:balance.currency -eq 'CNY') { "$([char]0x00A5)" } else { '$' }
  Write-Log ("balance updated: {0}{1}" -f $sym, (Format-Amount $script:balance.total))
}

$balanceTimer = New-Object System.Windows.Threading.DispatcherTimer
$balanceTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:lastBalanceAttempt = [DateTime]::MinValue
$balanceTimer.Add_Tick({
  try {
    if ($null -ne $script:balanceJob) { Complete-BalanceFetch; return }
    # Refresh once the configured interval has elapsed since the last successful read.
    $age = [double]::MaxValue
    if ($null -ne $script:balance.fetchedAt) { $age = ((Get-Date) - $script:balance.fetchedAt).TotalSeconds }
    $stale = $age -ge $script:attrBalanceRefresh
    # Retry at most once every 2s so a hung or failing endpoint is not hammered.
    if ($stale -and ((Get-Date) - $script:lastBalanceAttempt).TotalSeconds -ge 2) {
      $script:lastBalanceAttempt = Get-Date
      Start-BalanceFetch
    }
  } catch {
    Write-Log ("balance tick failed: {0}" -f $_.Exception.Message) 'WARN'
  }
})

# ---------------------------------------------------------------- startup

$window.Add_Loaded({
  Update-BalanceDisplay
  Start-BalanceFetch

  # Size to the configured scale first, then restore the remembered spot or fall back to
  # the bottom-right of the primary work area, clear of the taskbar.
  $script:started = $true
  Resize-PetWindow
  $winW = $window.Width
  $winH = $window.Height
  $wa = [System.Windows.SystemParameters]::WorkArea
  $place = $true
  if ($script:settings.rememberPosition -and $null -ne $window.Left -and $null -ne $script:settings.windowLeft) {
    $wantLeft = [double]$script:settings.windowLeft
    $wantTop = [double]$script:settings.windowTop
    $window.Left = [Math]::Max($wa.Left, [Math]::Min($wa.Right - $winW, $wantLeft))
    $window.Top = [Math]::Max($wa.Top, [Math]::Min($wa.Bottom - $winH, $wantTop))
    $place = $false
  }
  if ($place) {
    $window.Left = $wa.Right - $winW - 24
    $window.Top = $wa.Bottom - $winH - 8
  }

  $hint = [string]$attrCallName
  $hello = [string]($attrGreetings[$script:rng.Next(0, $attrGreetings.Count)])
  Show-Greeting -Text $hello -Seconds 4

  Show-Bubble -To 1.0

  # Handy for checking the panel without touching the mouse.
  if ($OpenSettings) {
    try {
      Show-SettingsWindow
    } catch {
      Write-Log ("settings open failed: {0}" -f $_.Exception.Message) 'WARN'
      Write-Log ("settings stack: {0}" -f $_.ScriptStackTrace) 'WARN'
    }
  }

  # The greeting fades back into the live balance once it expires.
  $script:greetTimer = New-Object System.Windows.Threading.DispatcherTimer
  $script:greetTimer.Interval = [TimeSpan]::FromSeconds(4.2)
  $script:greetTimer.Add_Tick({
    $script:greetTimer.Stop()
    $script:greetingUntil = [DateTime]::MinValue
    Update-BalanceDisplay
  })
  $script:greetTimer.Start()

  # Warm the sprite cache in the background so the first switches never stutter.
  $script:warm = New-Object System.Windows.Threading.DispatcherTimer
  $script:warm.Interval = [TimeSpan]::FromMilliseconds(120)
  $script:warmIndex = 0
  $script:warm.Add_Tick({
    if ($script:warmIndex -ge $script:spriteOrder.Count) { $script:warm.Stop(); return }
    $id = $script:spriteOrder[$script:warmIndex]
    $script:warmIndex++
    Get-Sprite -Id $id | Out-Null
  })
  $script:warm.Start()

  $script:positionDirty = $false
  Write-Log ("window shown at {0},{1} size {2}x{3} scale {4}" -f [int]$window.Left, [int]$window.Top, [int]$window.Width, [int]$window.Height, $script:attrDisplayScale)
})

$window.Add_Closed({
  if ($script:settings.rememberPosition) { Save-PetSettings }
  $animTimer.Stop()
  $logicTimer.Stop()
  $balanceTimer.Stop()
  Write-Log 'window closed'
})

Set-PetState -Id 'smile'
$window.Show()
$animTimer.Start()
$logicTimer.Start()
$balanceTimer.Start()
$settingsSaveTimer.Start()

# Last line of defence: a callback that throws would otherwise take the whole pet down mid-session.
# Every failure is recorded and the pet keeps running with whatever state it already reached.
$dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
$dispatcher.Add_UnhandledException({
  param($sender, $e)
  try {
    Write-Log ("unhandled: {0}" -f $e.Exception.Message) 'WARN'
    Write-Log ("unhandled stack: {0}" -f $e.Exception.StackTrace) 'WARN'
  } catch { }
  $e.Handled = $true
})
$dispatcher.Add_UnhandledExceptionFilter({
  param($sender, $e)
  try {
    Write-Log ("unhandled filter: {0}" -f $e.Exception.Message) 'WARN'
  } catch { }
  $e.Handled = $true
})

[System.Windows.Threading.Dispatcher]::Run()

$mutex.ReleaseMutex()
$mutex.Dispose()
Write-Log 'pet exited'
