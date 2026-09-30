# Settings window for the desktop pet.
#
# Dot-sourced by pet.ps1. Everything here is ASCII: Chinese strings come from config.json at runtime,
# because Windows PowerShell 5.1 reads BOM-less script files as ANSI.
#
# Provides:
#   Read-PetSettings          load persisted settings, falling back to config defaults
#   Save-PetSettings          write settings.json next to config.json
#   Show-SettingsWindow       open (or focus) the settings window
#
# The window edits the same knobs as config.json but stores them separately, so regenerating or
# editing config.json never fights with what the user picked in the UI.

$settingsPath = Join-Path $root 'settings.json'


# Builders for one settings row.
#
# Each builder receives its own values as parameters, so the closures created in the caller capture
# per-row state rather than whatever the enclosing loop variable holds at call time. The Grid
# scaffolds come from XAML because column-width strings parse reliably there; two-argument
# GridLength construction through New-Object does not.
function New-GridFromXaml {
  param([string]$XamlText)
  $reader = New-Object System.Xml.XmlNodeReader ([xml]$XamlText)
  return [Windows.Markup.XamlReader]::Load($reader)
}

function New-RangeRow {
  param(
    [string]$LabelText, [string]$Key, [double]$Value,
    [double]$Min, [double]$Max, [double]$Step, [string]$Format
  )

  $row = New-GridFromXaml -XamlText '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="0,2,0,2"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="58"/></Grid.ColumnDefinitions></Grid>'

  $label = New-Object System.Windows.Controls.TextBlock
  $label.Text = $LabelText
  $label.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
  $label.FontSize = 13
  $label.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 226, 236, 252))
  $label.VerticalAlignment = 'Center'
  [System.Windows.Controls.Grid]::SetColumn($label, 0)
  $row.Children.Add($label) | Out-Null

  $readout = New-Object System.Windows.Controls.TextBlock
  $readout.Text = ($Format -f $Value)
  $readout.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
  $readout.FontSize = 12
  $readout.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 150, 185, 245))
  $readout.HorizontalAlignment = 'Right'
  $readout.VerticalAlignment = 'Center'
  [System.Windows.Controls.Grid]::SetColumn($readout, 1)
  $row.Children.Add($readout) | Out-Null

  $sliderRow = New-GridFromXaml -XamlText '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="0,0,0,7"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/></Grid.ColumnDefinitions></Grid>'

  $slider = New-Object System.Windows.Controls.Slider
  $slider.Minimum = $Min
  $slider.Maximum = $Max
  $slider.TickFrequency = $Step
  $slider.IsSnapToTickEnabled = $true
  $slider.Value = $Value
  $slider.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 111, 168, 255))
  $slider.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(90, 255, 255, 255))
  $slider.VerticalAlignment = 'Center'
  [System.Windows.Controls.Grid]::SetColumn($slider, 0)
  $sliderRow.Children.Add($slider) | Out-Null

  return @{ row = $row; control = $sliderRow; slider = $slider; readout = $readout }
}

function New-CheckRow {
  param([string]$LabelText, [bool]$Checked)

  $row = New-GridFromXaml -XamlText '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="0,5,0,5"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/></Grid.ColumnDefinitions></Grid>'

  $check = New-Object System.Windows.Controls.CheckBox
  $check.IsChecked = $Checked
  $check.Content = $LabelText
  $check.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 226, 236, 252))
  $check.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
  $check.FontSize = 13
  $check.VerticalAlignment = 'Center'
  $row.Children.Add($check) | Out-Null
  return @{ row = $row; control = $null; slider = $null; check = $check }
}

$script:settingsSchema = @(
  @{ key = 'displayScale';        label = 'petSize';        kind = 'range'; min = 0.35; max = 1.0;  step = 0.05; format = '{0:0.00}' }
  @{ key = 'autoSwitchMin';       label = 'switchMin';      kind = 'range'; min = 5;    max = 120;  step = 1;    format = '{0:0} s' }
  @{ key = 'autoSwitchMax';       label = 'switchMax';      kind = 'range'; min = 8;    max = 300;  step = 1;    format = '{0:0} s' }
  @{ key = 'fixedAfterManual';    label = 'manualHold';     kind = 'range'; min = 15;   max = 900;  step = 15;   format = '{0:0} s' }
  @{ key = 'sleepAfterIdle';      label = 'sleepAfter';     kind = 'range'; min = 30;   max = 1200; step = 30;   format = '{0:0} s' }
  @{ key = 'balanceRefresh';      label = 'refreshEvery';   kind = 'range'; min = 2;    max = 300;  step = 1;    format = '{0:0} s' }
  @{ key = 'lowBalance';          label = 'lowBalance';     kind = 'range'; min = 0;    max = 100;  step = 1;    format = '{0:0.00}' }
  @{ key = 'autoEnabled';         label = 'autoRotate';     kind = 'check' }
  @{ key = 'rememberPosition';    label = 'rememberPos';    kind = 'check' }
)

function Get-DefaultSettings {
  return @{
    displayScale = $attrDisplayScale
    autoSwitchMin = $attrAutoMin
    autoSwitchMax = $attrAutoMax
    fixedAfterManual = $attrFixedAfterManual
    sleepAfterIdle = $attrSleepAfterIdle
    balanceRefresh = $attrBalanceRefresh
    lowBalance = $attrLowBalance
    autoEnabled = $true
    rememberPosition = $true
    windowLeft = $null
    windowTop = $null
  }
}

function Read-PetSettings {
  $settings = Get-DefaultSettings
  if (-not (Test-Path -LiteralPath $settingsPath)) { return $settings }
  try {
    $raw = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $loaded = ConvertTo-HashtableDeep $raw
    foreach ($key in @($settings.Keys)) {
      if ($loaded.ContainsKey($key) -and $null -ne $loaded[$key]) { $settings[$key] = $loaded[$key] }
    }
    # A hand-edited file could contain nonsense; keep the values physically meaningful.
    if ([double]$settings.displayScale -lt 0.3 -or [double]$settings.displayScale -gt 1.2) { $settings.displayScale = 0.58 }
    if ([double]$settings.autoSwitchMin -lt 2) { $settings.autoSwitchMin = 5 }
    if ([double]$settings.autoSwitchMax -lt [double]$settings.autoSwitchMin + 1) { $settings.autoSwitchMax = [double]$settings.autoSwitchMin + 5 }
    Write-Log ("settings loaded from {0}" -f $settingsPath)
  } catch {
    Write-Log ("settings unreadable ({0}); using defaults" -f $_.Exception.Message) 'WARN'
  }
  return $settings
}

function Save-PetSettings {
  try {
    $payload = @{}
    foreach ($key in @($script:settings.Keys)) {
      if ($key -in @('windowLeft', 'windowTop')) { continue }
      $payload[$key] = $script:settings[$key]
    }
    if ($script:settings.rememberPosition) {
      $payload.windowLeft = [int]$window.Left
      $payload.windowTop = [int]$window.Top
    } else {
      $payload.windowLeft = $null
      $payload.windowTop = $null
    }
    $payload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
  } catch {
    Write-Log ("settings save failed: {0}" -f $_.Exception.Message) 'WARN'
  }
}

function Get-SettingsText {
  # Two positional arguments: the label key and the value used when config has no such key.
  # The strings live under config.ui.settings, alongside the rest of the interface text.
  param([string]$Key, [string]$Default = '')
  return [string](Get-Opt (Get-Opt $ui 'settings' @{}) $Key $Default)
}

# ---------------------------------------------------------------- settings window

function New-SettingsWindow {
  param([hashtable]$Text)

  # Explicit height with a filling ScrollViewer: SizeToContent together with a ScrollViewer
  # reports a height that clips the footer, so the panel owns its size instead.
  $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DshDesktopPetSettings"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="True" ResizeMode="NoResize" Topmost="True"
        Width="392" Height="700" WindowStartupLocation="Manual">
  <Border x:Name="Shell" CornerRadius="16" Background="#F2141C2B" BorderBrush="#66FFFFFF" BorderThickness="1"
          Padding="18,14,18,16">
    <Border.Effect>
      <DropShadowEffect BlurRadius="18" ShadowDepth="3" Opacity="0.55" Color="#FF000000"/>
    </Border.Effect>
    <DockPanel LastChildFill="True">
      <DockPanel x:Name="HeaderHost" DockPanel.Dock="Top" LastChildFill="False" Margin="0,0,0,10">
        <TextBlock x:Name="TitleText" DockPanel.Dock="Left" FontFamily="Microsoft YaHei UI" FontSize="16"
                   FontWeight="SemiBold" Foreground="#FFF3F7FF" VerticalAlignment="Center"/>
        <Button x:Name="CloseButton" DockPanel.Dock="Right" FontFamily="Microsoft YaHei UI" FontSize="15"
                Foreground="#FFCFE0FF" Background="Transparent" BorderThickness="0" Padding="10,0,4,0"
                Cursor="Hand" VerticalAlignment="Center"/>
      </DockPanel>
      <Border DockPanel.Dock="Top" Height="1" Background="#33FFFFFF" Margin="0,0,0,10"/>
      <StackPanel x:Name="FooterHost" DockPanel.Dock="Bottom" Margin="0,10,0,0"/>
      <Border DockPanel.Dock="Bottom" Height="1" Background="#33FFFFFF" Margin="0,10,0,0"/>
      <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="RowHost"/>
      </ScrollViewer>
    </DockPanel>
  </Border>
</Window>
'@

  $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
  $win = [Windows.Markup.XamlReader]::Load($reader)
  $win.Title = $Text.windowTitle

  $rowHost = $win.FindName('RowHost')
  $footerHost = $win.FindName('FooterHost')
  $shell = $win.FindName('Shell')
  $win.FindName('TitleText').Text = $Text.windowTitle
  $win.FindName('CloseButton').Content = $Text.close

  $script:settingsControls = @{}

  foreach ($field in $script:settingsSchema) {
    $key = [string]$field.key
    $labelText = Get-SettingsText $field.label $key
    if ($field.kind -eq 'range') {
      $row = New-RangeRow -LabelText $labelText -Key $key -Value ([double]$script:settings[$key]) `
        -Min ([double]$field.min) -Max ([double]$field.max) -Step ([double]$field.step) -Format ([string]$field.format)
      $slider = $row.slider
      $readout = $row.readout
      $script:settingsControls[$key] = $slider
      $rowHost.Children.Add($row.row) | Out-Null
      $rowHost.Children.Add($row.control) | Out-Null
      # The row's identity travels on the control itself: a PowerShell closure would have to rebuild
      # its captured scope on every event, which is both slow and unreliable here.
      Add-Member -InputObject $slider -MemberType NoteProperty -Name PetKey -Value $key -Force
      Add-Member -InputObject $slider -MemberType NoteProperty -Name PetFormat -Value ([string]$field.format) -Force
      Add-Member -InputObject $slider -MemberType NoteProperty -Name PetReadout -Value $readout -Force
      $slider.Add_ValueChanged({
        param($sender, $e)
        try {
          $name = $sender.PetKey
          $value = [double]$sender.Value
          $script:settings[$name] = $value
          $sender.PetReadout.Text = ($sender.PetFormat -f $value)
          Apply-Setting -Key $name -Value $value
          Request-SettingsSave
        } catch {
          Write-Log ("setting change failed: {0}" -f $_.Exception.Message) 'WARN'
          Write-Log ("setting change stack: {0}" -f $_.ScriptStackTrace) 'WARN'
        }
      })
    } else {
      $row = New-CheckRow -LabelText $labelText -Checked ([bool]$script:settings[$key])
      $check = $row.check
      $script:settingsControls[$key] = $check
      $rowHost.Children.Add($row.row) | Out-Null
      Add-Member -InputObject $check -MemberType NoteProperty -Name PetKey -Value $key -Force
      $toggle = {
        param($sender, $e)
        try {
          $name = $sender.PetKey
          $value = [bool]$sender.IsChecked
          $script:settings[$name] = $value
          Apply-Setting -Key $name -Value $value
          Request-SettingsSave
        } catch {
          Write-Log ("setting toggle failed: {0}" -f $_.Exception.Message) 'WARN'
        }
      }
      $check.Add_Checked($toggle)
      $check.Add_Unchecked($toggle)
    }
  }

  function New-FooterButton {
    param([string]$Caption, [bool]$Primary = $false)
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Caption
    $b.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
    $b.FontSize = 12.5
    $b.Padding = New-Object System.Windows.Thickness(12, 7, 12, 7)
    $b.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
    $b.Cursor = [System.Windows.Input.Cursors]::Hand
    $b.BorderThickness = New-Object System.Windows.Thickness(0)
    if ($Primary) {
      $b.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 70, 116, 200))
      $b.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 245, 249, 255))
    } else {
      $b.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(46, 255, 255, 255))
      $b.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255, 214, 228, 250))
    }
    return $b
  }

  $buttonRow = New-Object System.Windows.Controls.WrapPanel
  $buttonRow.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)

  $refreshButton = New-FooterButton -Caption $Text.refreshBalance -Primary $true
  $refreshButton.Add_Click({
    $script:lastBalanceAttempt = [DateTime]::MinValue
    $script:balance.fetchedAt = $null
    $script:balance.status = 'loading'
    Update-BalanceDisplay
    Start-BalanceFetch
  })
  $buttonRow.Children.Add($refreshButton) | Out-Null

  $resetButton = New-FooterButton -Caption $Text.reset
  $resetButton.Add_Click({
    $defaults = Get-DefaultSettings
    foreach ($field in $script:settingsSchema) {
      $key = [string]$field.key
      $script:settings[$key] = $defaults[$key]
      $control = $script:settingsControls[$key]
      if ($field.kind -eq 'range') { $control.Value = [double]$defaults[$key] }
      else { $control.IsChecked = [bool]$defaults[$key] }
      Apply-Setting -Key $key -Value $script:settings[$key]
    }
    Save-PetSettings
    Write-Log 'settings reset to defaults'
  })
  $homeButton = New-FooterButton -Caption $Text.moveHome
  $homeButton.Add_Click({
    $wa = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $wa.Right - $window.Width - 24
    $window.Top = $wa.Bottom - $window.Height - 8
    $script:positionDirty = $true
    Save-PetSettings
    Write-Log 'window moved back to the bottom-right corner'
  })
  $buttonRow.Children.Add($homeButton) | Out-Null

  $buttonRow.Children.Add($resetButton) | Out-Null

  $footerHost.Children.Add($buttonRow) | Out-Null

  $hint = New-Object System.Windows.Controls.TextBlock
  $hint.Text = $Text.hint
  $hint.FontFamily = New-Object System.Windows.Media.FontFamily('Microsoft YaHei UI')
  $hint.FontSize = 11
  $hint.TextWrapping = 'Wrap'
  $hint.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(200, 160, 188, 234))
  $footerHost.Children.Add($hint) | Out-Null

  # Every handler below reaches its window through $sender or the visual tree. Referencing the local
  # $win would break: the variable is gone by the time a handler runs, and StrictMode turns that into
  # an exception that takes the whole pet down.
  $win.FindName('CloseButton').Add_Click({
    param($sender, $e)
    $panel = [System.Windows.Window]::GetWindow($sender)
    if ($null -ne $panel) { $panel.Hide() }
  })

  # Drag the panel by its surface with screen coordinates, the same way the pet window is dragged.
  $script:settingsDrag = @{ active = $false; cursorX = 0.0; cursorY = 0.0; originX = 0.0; originY = 0.0; unit = 1.0 }
  $shell.Add_MouseLeftButtonDown({
    param($sender, $e)
    if ($e.OriginalSource -is [System.Windows.Controls.Primitives.ButtonBase]) { return }
    if ($e.OriginalSource -is [System.Windows.Controls.Slider]) { return }
    $panel = [System.Windows.Window]::GetWindow($sender)
    if ($null -eq $panel) { return }
    $cursor = Get-CursorScreen
    if ($null -eq $cursor) { return }
    $unit = Get-DpiScale
    if ($unit -le 0) { $unit = 1.0 }
    $origin = Get-WindowOrigin
    $script:settingsDrag.active = $true
    $script:settingsDrag.cursorX = $cursor.X
    $script:settingsDrag.cursorY = $cursor.Y
    $script:settingsDrag.originX = [double]$origin.X
    $script:settingsDrag.originY = [double]$origin.Y
    $script:settingsDrag.unit = $unit
    # $sender is the raise surface; $shell would be a local that is long gone by the time this runs.
    [void]$sender.CaptureMouse()
  })
  $shell.Add_MouseMove({
    param($sender, $e)
    if (-not $script:settingsDrag.active) { return }
    $panel = [System.Windows.Window]::GetWindow($sender)
    if ($null -eq $panel) { return }
    $cursor = Get-CursorScreen
    if ($null -eq $cursor) { return }
    # Keep the panel's screen origin consistent with its placement units before translating.
    $origin = Get-WindowOrigin
    $shiftX = [double]$origin.X - ($panel.Left * $script:settingsDrag.unit)
    $shiftY = [double]$origin.Y - ($panel.Top * $script:settingsDrag.unit)
    $panel.Left = $panel.Left + (($cursor.X - $script:settingsDrag.cursorX - $shiftX) / $script:settingsDrag.unit)
    $panel.Top = $panel.Top + (($cursor.Y - $script:settingsDrag.cursorY - $shiftY) / $script:settingsDrag.unit)
    $script:settingsDrag.cursorX = $cursor.X
    $script:settingsDrag.cursorY = $cursor.Y
  })
  $shell.Add_MouseLeftButtonUp({
    param($sender, $e)
    $script:settingsDrag.active = $false
    [void]$sender.ReleaseMouseCapture()
  })
  $win.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) {
      $panel = [System.Windows.Window]::GetWindow($sender)
      if ($null -ne $panel) { $panel.Hide() }
    }
  })

  $win.Add_Closing({
    param($sender, $e)
    # Closing hides instead, so the window can be reopened cheaply.
    $e.Cancel = $true
    $panel = [System.Windows.Window]::GetWindow($sender)
    if ($null -ne $panel) { $panel.Hide() }
  })
  $win.Add_Closed({
    Write-Log 'settings: window actually closed' 'WARN'
  })

  return $win
}

function Show-SettingsWindow {
  if ($null -eq $script:settingsWindow) {
    $text = @{
      windowTitle = Get-SettingsText 'windowTitle' 'Settings'
      close = Get-SettingsText 'close' 'Close'
      refreshBalance = Get-SettingsText 'refreshBalance' 'Refresh balance'
      reset = Get-SettingsText 'reset' 'Reset'
      moveHome = Get-SettingsText 'moveHome' 'Move home'
      hint = Get-SettingsText 'hint' ''
      petSize = Get-SettingsText 'petSize' 'Size'
      switchMin = Get-SettingsText 'switchMin' 'Idle switch min'
      switchMax = Get-SettingsText 'switchMax' 'Idle switch max'
      manualHold = Get-SettingsText 'manualHold' 'Hold after manual pick'
      sleepAfter = Get-SettingsText 'sleepAfter' 'Sleep after idle'
      refreshEvery = Get-SettingsText 'refreshEvery' 'Balance refresh'
      lowBalance = Get-SettingsText 'lowBalance' 'Low balance warning'
      autoRotate = Get-SettingsText 'autoRotate' 'Rotate automatically'
      rememberPos = Get-SettingsText 'rememberPos' 'Remember window position'
    }
    $script:settingsWindow = New-SettingsWindow -Text $text
  }
  $win = $script:settingsWindow
  if (-not $win.IsVisible) {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.UpdateLayout()
    # Force a full render pass so every child has been drawn before the panel is screenshotted or seen.
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})
    $w = if ($win.ActualWidth -gt 10) { $win.ActualWidth } else { 392 }
    $h = if ($win.ActualHeight -gt 10) { $win.ActualHeight } else { 700 }
    $win.Height = [Math]::Min($h, $wa.Height - 24)
    $left = $window.Left - $w - 16
    if ($left -lt $wa.Left + 8) { $left = $window.Left + $window.Width + 16 }
    if ($left + $w -gt $wa.Right - 8) { $left = [Math]::Max($wa.Left + 8, $wa.Right - $w - 8) }
    $top = [Math]::Min([Math]::Max($wa.Top + 8, $window.Top), $wa.Bottom - 120)
    $win.Left = $left
    $win.Top = $top
    $win.Show()
    $win.UpdateLayout()
    # Force a full render pass so every child has been drawn before the panel is screenshotted or seen.
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [Action]{})
  } else {
    # Already open: bring it back to the front rather than doing nothing, so the gear always responds.
    $win.Topmost = $false
    $win.Topmost = $true
    $win.Activate()
    Write-Log 'settings window re-activated'
  }
}
