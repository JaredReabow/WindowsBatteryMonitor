param(
  [int]$RefreshMs = 3000,
  [switch]$TopMost,
  [switch]$UseWmi,
  [double]$Scale = 0.9
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# Relaunch in STA if needed (WPF requires STA)
try {
  $apt = [System.Threading.Thread]::CurrentThread.ApartmentState
} catch { $apt = 'Unknown' }
if ($apt -ne 'STA') {
  $scriptPath = $MyInvocation.MyCommand.Path
  $argsList = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$scriptPath`"")
  if ($TopMost) { $argsList += '-TopMost' }
  if ($UseWmi) { $argsList += '-UseWmi' }
  $argsList += @('-RefreshMs', $RefreshMs)
  try {
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argsList -WorkingDirectory (Split-Path -Parent $scriptPath) | Out-Null
    return
  } catch {
    # Silently continue if relaunch fails
    return
  }
}

# ---------- Battery telemetry (self-contained, mirrors battery_monitor.ps1) ----------
function Get-BatteryWmi {
    param([Parameter(Mandatory)][string]$Class)
    try {
        if (-not $UseWmi -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
            return Get-CimInstance -Namespace root\wmi -ClassName $Class -ErrorAction Stop | Select-Object -First 1
        } else {
            return Get-WmiObject -Namespace root\wmi -Class $Class -ErrorAction Stop | Select-Object -First 1
        }
    } catch { return $null }
}

function Get-BatteryInfo {
    $status = Get-BatteryWmi -Class 'BatteryStatus'
    if (-not $status) { return $null }
    $full   = Get-BatteryWmi -Class 'BatteryFullChargedCapacity'
    $static = Get-BatteryWmi -Class 'BatteryStaticData'
    $cycle  = Get-BatteryWmi -Class 'BatteryCycleCount'

    $fcap = $null; $design = $null
    if ($full -and $full.PSObject.Properties.Name -contains 'FullChargedCapacity') { $fcap = [double]$full.FullChargedCapacity }
    if ($static -and $static.PSObject.Properties.Name -contains 'DesignedCapacity') { $design = [double]$static.DesignedCapacity }

    $rcap = $null
    if ($status.PSObject.Properties.Name -contains 'RemainingCapacity') { $rcap = [double]$status.RemainingCapacity }

  $pct  = if ($fcap -and $fcap -gt 0 -and $null -ne $rcap) { [math]::Round(($rcap/$fcap)*100,1) } else { $null }

    $voltageV = $null
  if ($status.PSObject.Properties.Name -contains 'Voltage' -and $null -ne $status.Voltage) {
        $voltageV = [math]::Round(([double]$status.Voltage)/1000.0, 3)
    }

    $chargeRate_mW = $null
    if ($status.PSObject.Properties.Name -contains 'ChargeRate') { $chargeRate_mW = [double]$status.ChargeRate }
    $dischargeRate_mW = $null
    if ($status.PSObject.Properties.Name -contains 'DischargeRate') { $dischargeRate_mW = [double]$status.DischargeRate }

    $onAC = $false; $charging=$false; $discharging=$false; $present=$true
    if ($status.PSObject.Properties.Name -contains 'PowerOnline') { $onAC = [bool]$status.PowerOnline }
    if ($status.PSObject.Properties.Name -contains 'Charging') { $charging = [bool]$status.Charging }
    if ($status.PSObject.Properties.Name -contains 'Discharging') { $discharging = [bool]$status.Discharging }
    if ($status.PSObject.Properties.Name -contains 'Present') { $present = [bool]$status.Present }

    $state = if (-not $present) { 'No battery' } elseif ($charging) { 'Charging' } elseif ($discharging) { 'Discharging' } elseif ($onAC) { 'On AC' } else { 'Idle' }

    $rate_mW = $null
    if ($charging -and $chargeRate_mW -gt 0) { $rate_mW = [math]::Round($chargeRate_mW, 0) }
    elseif ($discharging -and $dischargeRate_mW -gt 0) { $rate_mW = -1 * [math]::Round($dischargeRate_mW, 0) }

  $rate_W = if ($null -ne $rate_mW) { [math]::Round($rate_mW/1000.0, 3) } else { $null }

    $hToFull = $null
  if ($charging -and $chargeRate_mW -gt 0 -and $null -ne $fcap -and $null -ne $rcap) { $hToFull = ($fcap - $rcap)/$chargeRate_mW }
    $hToEmpty = $null
  if ($discharging -and $dischargeRate_mW -gt 0 -and $null -ne $rcap) { $hToEmpty = $rcap/$dischargeRate_mW }

    function Fmt-Hours($h) {
  if ($null -eq $h -or $h -lt 0) { return $null }
        $totalMinutes = [int]([math]::Round($h*60,0))
        $hh = [int]($totalMinutes/60)
        $mm = $totalMinutes % 60
        return ('{0:00}:{1:00}' -f $hh,$mm)
    }

    $wear = $null
  if ($design -and $design -gt 0 -and $null -ne $fcap) { $wear = [math]::Round((1.0 - ($fcap/$design))*100, 1) }

    $cycles = $null
    if ($cycle -and $cycle.PSObject.Properties.Name -contains 'CycleCount') { $cycles = [int]$cycle.CycleCount }

    [pscustomobject]@{
        Time          = (Get-Date)
        Status        = $state
        OnAC          = $onAC
        Percent       = $pct
        VoltageV      = $voltageV
        Rate_mW       = $rate_mW
        Rate_W        = $rate_W
  Remain_mWh    = if ($null -ne $rcap) { [int][math]::Round($rcap,0) } else { $null }
  Full_mWh      = if ($null -ne $fcap) { [int][math]::Round($fcap,0) } else { $null }
  Design_mWh    = if ($null -ne $design) { [int][math]::Round($design,0) } else { $null }
        Wear_pct      = $wear
        EstToFull     = Fmt-Hours $hToFull
        EstToEmpty    = Fmt-Hours $hToEmpty
        Cycles        = $cycles
    }
}

function Get-BatteryInfoFallback {
    try {
        $b = if (-not $UseWmi -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
            Get-CimInstance -Namespace root\cimv2 -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1
        } else {
            Get-WmiObject -Namespace root\cimv2 -Class Win32_Battery -ErrorAction Stop | Select-Object -First 1
        }
    } catch { $null }
    if (-not $b) { return $null }

    $pct = $null
    if ($b.PSObject.Properties.Name -contains 'EstimatedChargeRemaining') { $pct = [int]$b.EstimatedChargeRemaining }
    $runtimeMin = $null
    if ($b.PSObject.Properties.Name -contains 'EstimatedRunTime') { $runtimeMin = [int]$b.EstimatedRunTime }

    function Fmt-Min($m) {
  if ($null -eq $m -or $m -lt 0) { return $null }
        $hh = [int]([math]::Floor($m/60))
        $mm = $m % 60
        '{0:00}:{1:00}' -f $hh,$mm
    }

    [pscustomobject]@{
        Time          = (Get-Date)
        Status        = 'Unknown'
        OnAC          = $null
        Percent       = $pct
        VoltageV      = $null
        Rate_mW       = $null
        Rate_W        = $null
        Remain_mWh    = $null
        Full_mWh      = $null
        Design_mWh    = $null
        Wear_pct      = $null
        EstToFull     = $null
        EstToEmpty    = if ($runtimeMin -and $runtimeMin -lt 65535) { Fmt-Min $runtimeMin } else { $null }
        Cycles        = $null
    }
}

function Read-BatterySafe {
    $i = Get-BatteryInfo
    if (-not $i) { $i = Get-BatteryInfoFallback }
    return $i
}

# ---------- UI (WPF) ----------
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase | Out-Null

$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Battery Widget"
  MinWidth="160" MinHeight="100" SizeToContent="WidthAndHeight" MaxWidth="900" MaxHeight="700"
        Background="#FF1E1E1E" Foreground="#FFF3F3F3"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip">
  <Grid Margin="4,8,4,8">
  <Border x:Name="RootCard" CornerRadius="10" Background="#FF252526" BorderBrush="#FF3C3C3C" BorderThickness="1" Padding="4,8">
  <Grid Margin="2">
          <Grid.RowDefinitions>
            <RowDefinition Height="2.2*"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <!-- Big percent -->
          <TextBlock x:Name="PercentText" Grid.Row="0" Text="--%" FontSize="56" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,6"/>

          <!-- Status and rate -->
          <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,0">
            <TextBlock x:Name="StatusText" Text="Status" FontSize="26" Margin="0,0,10,0" TextTrimming="CharacterEllipsis"/>
            <Border Background="#22FFFFFF" CornerRadius="6" Padding="6,2" Margin="0,0,0,0">
              <TextBlock x:Name="RateText" Text="Rate" FontSize="26"/>
            </Border>
          </StackPanel>

          <!-- Voltage and ETA -->
          <Grid Grid.Row="2" Margin="0,6,0,0" HorizontalAlignment="Center">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="VoltLabel" Grid.Column="0" Text="V" FontSize="22" Margin="0,0,6,0"/>
            <TextBlock x:Name="VoltText" Grid.Column="1" Text="-" FontSize="22" Margin="0,0,12,0" HorizontalAlignment="Left"/>
            <TextBlock x:Name="ToFullLabel" Grid.Column="2" Text="Full" FontSize="22" Margin="0,0,6,0"/>
            <TextBlock x:Name="ToFullText" Grid.Column="3" Text="--:--" FontSize="22" Margin="0,0,12,0" HorizontalAlignment="Left"/>
            <TextBlock x:Name="ToEmptyLabel" Grid.Column="4" Text="Empty" FontSize="22" Margin="0,0,6,0"/>
            <TextBlock x:Name="ToEmptyText" Grid.Column="5" Text="--:--" FontSize="22" HorizontalAlignment="Left"/>
          </Grid>
  </Grid>
    </Border>

    <!-- Top-right buttons -->
    <DockPanel VerticalAlignment="Top" HorizontalAlignment="Right" LastChildFill="False">
      <CheckBox x:Name="PinCheck" Content="Pin" Margin="0,0,6,0" VerticalAlignment="Top"/>
      <Button x:Name="DetailsBtn" Content="Details" Padding="8,2"/>
    </DockPanel>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Find controls
$PercentText = $window.FindName('PercentText')
$StatusText  = $window.FindName('StatusText')
$RateText    = $window.FindName('RateText')
$VoltText    = $window.FindName('VoltText')
$ToFullText  = $window.FindName('ToFullText')
$ToEmptyText = $window.FindName('ToEmptyText')
$PinCheck    = $window.FindName('PinCheck')
$DetailsBtn  = $window.FindName('DetailsBtn')
${RootCard}  = $window.FindName('RootCard')

# Optional Details window
$script:detailsWindow = $null
function Ensure-DetailsWindow {
  if ($null -ne $script:detailsWindow) { return }
    $dxaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="Battery Details" Width="460" Height="260"
            Background="#FF1E1E1E" Foreground="#FFF3F3F3">
      <Grid Margin="10">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Battery Details" FontSize="18" FontWeight="Bold" Margin="0,0,0,8"/>
        <DataGrid x:Name="Grid" Grid.Row="1" AutoGenerateColumns="False" HeadersVisibility="Column"
                  Background="#FF252526" BorderBrush="#FF3C3C3C" BorderThickness="1">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Field" Binding="{Binding Name}" Width="2*"/>
            <DataGridTextColumn Header="Value" Binding="{Binding Value}" Width="3*"/>
          </DataGrid.Columns>
        </DataGrid>
      </Grid>
    </Window>
"@
  $rd = New-Object System.Xml.XmlNodeReader ([xml]$dxaml)
  $script:detailsWindow = [Windows.Markup.XamlReader]::Load($rd)
}

# Update UI from battery read
function Update-UI {
    $i = Read-BatterySafe
    if (-not $i) {
        $PercentText.Text = '--%'
        $StatusText.Text  = 'Unavailable'
        $RateText.Text    = 'n/a'
        $VoltText.Text    = '-'
        $ToFullText.Text  = '--:--'
        $ToEmptyText.Text = '--:--'
  $window.Title     = 'Battery Widget'
  if ($RootCard) { $RootCard.Background = (New-Object Windows.Media.BrushConverter).ConvertFromString('#FF252526') }
        return
    }

  $pTxt = if ($null -ne $i.Percent) { '{0:n1}%' -f $i.Percent } else { '--%' }
  $rTxt = if ($null -ne $i.Rate_W) { '{0:n3} W' -f $i.Rate_W } else { 'n/a' }
  $vTxt = if ($null -ne $i.VoltageV) { '{0:n3}' -f $i.VoltageV } else { '-' }
    $sTxt = $i.Status

    $PercentText.Text = $pTxt
    $StatusText.Text  = $sTxt
    $RateText.Text    = $rTxt
    $VoltText.Text    = $vTxt
    $ToFullText.Text  = if ($i.EstToFull) { $i.EstToFull } else { '--:--' }
    $ToEmptyText.Text = if ($i.EstToEmpty) { $i.EstToEmpty } else { '--:--' }
  $window.Title     = "Battery $pTxt - $sTxt"

    # Color accent on rate: green when charging, red when discharging
  $brush = if ($null -ne $i.Rate_W) {
        if ($i.Rate_W -gt 0) { '#334CAF50' } elseif ($i.Rate_W -lt 0) { '#33F44336' } else { '#22888888' }
    } else { '#22888888' }
    $RateText.Parent.Background = [Windows.Media.Brushes]::Transparent
    $RateText.Parent.Background = (New-Object Windows.Media.BrushConverter).ConvertFromString($brush)

    # Background based on state
  if ($RootCard) {
    $bg = switch ($sTxt) {
      'Charging' { '#6632CD32' }    # brighter green (ForestGreen, semi-opaque)
      'Discharging' { '#66B22222' } # stronger red tint
      default { '#FF252526' }
    }
    $RootCard.Background = (New-Object Windows.Media.BrushConverter).ConvertFromString($bg)
  }

    # If details window is open, refresh it
  if ($null -ne $script:detailsWindow) {
        $grid = $script:detailsWindow.FindName('Grid')
        $rows = @(
            @{ Name='Time'; Value=$i.Time.ToString('HH:mm:ss') },
            @{ Name='Status'; Value=$i.Status },
            @{ Name='On AC'; Value=if ($i.OnAC -ne $null) { $i.OnAC } else { '' } },
            @{ Name='Percent'; Value=if ($i.Percent -ne $null) { '{0:n1}%' -f $i.Percent } else { '' } },
            @{ Name='Voltage (V)'; Value=if ($i.VoltageV -ne $null) { '{0:n3}' -f $i.VoltageV } else { '' } },
            @{ Name='Rate (W)'; Value=if ($i.Rate_W -ne $null) { '{0:n3}' -f $i.Rate_W } else { '' } },
            @{ Name='Rate (mW)'; Value=if ($i.Rate_mW -ne $null) { $i.Rate_mW } else { '' } },
            @{ Name='Remain (mWh)'; Value=$i.Remain_mWh },
            @{ Name='Full (mWh)'; Value=$i.Full_mWh },
            @{ Name='Design (mWh)'; Value=$i.Design_mWh },
            @{ Name='Wear (%)'; Value=if ($i.Wear_pct -ne $null) { '{0:n1}' -f $i.Wear_pct } else { '' } },
            @{ Name='Est to Full'; Value=$i.EstToFull },
            @{ Name='Est to Empty'; Value=$i.EstToEmpty },
            @{ Name='Cycles'; Value=$i.Cycles }
        ) | ForEach-Object { New-Object psobject -Property $_ }
        $grid.ItemsSource = $rows
    }
}

# Wire up events
$PinCheck.IsChecked = $TopMost
$window.Topmost = $TopMost
$PinCheck.Add_Checked({ $window.Topmost = $true }) | Out-Null
$PinCheck.Add_Unchecked({ $window.Topmost = $false }) | Out-Null
$DetailsBtn.Add_Click({ Ensure-DetailsWindow; if ($script:detailsWindow -is [System.Windows.Window]) { $script:detailsWindow.Owner = $window }; Update-UI; $script:detailsWindow.Show() | Out-Null }) | Out-Null
$window.Add_Closed({ if ($null -ne $script:detailsWindow) { $script:detailsWindow.Close() } }) | Out-Null

# Timer to refresh
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(500, $RefreshMs))
$timer.Add_Tick({ Update-UI }) | Out-Null
$timer.Start()

# First read and show
# Apply initial scale
try {
  if ($Scale -and $Scale -ne 1) {
    # Clamp to a reasonable range to avoid accidental huge windows
    $Scale = [math]::Max(0.6, [math]::Min($Scale, 3.0))
  $scaleTransform = New-Object Windows.Media.ScaleTransform($Scale, $Scale)
  if ($RootCard) { $RootCard.LayoutTransform = $scaleTransform }
  }
} catch {}

Update-UI

# Show window
$null = $window.ShowDialog()
