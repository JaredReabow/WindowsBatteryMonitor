param(
    [switch]$Once,
    [int]$IntervalSeconds = 5,
    [switch]$UseWmi,
    [switch]$NoClear,
    [switch]$Details
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BatteryWmi {
    param(
        [Parameter(Mandatory)] [string]$Class
    )
    try {
        if (-not $UseWmi -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
            return Get-CimInstance -Namespace root\wmi -ClassName $Class -ErrorAction Stop | Select-Object -First 1
        } else {
            return Get-WmiObject -Namespace root\wmi -Class $Class -ErrorAction Stop | Select-Object -First 1
        }
    } catch {
        return $null
    }
}

function Get-BatteryInfo {
    $status = Get-BatteryWmi -Class 'BatteryStatus'
    if (-not $status) {
    return $null
    }

    $full = Get-BatteryWmi -Class 'BatteryFullChargedCapacity'
    $static = Get-BatteryWmi -Class 'BatteryStaticData'
    $cycle  = Get-BatteryWmi -Class 'BatteryCycleCount'

    $fcap = $null; $design = $null
    if ($full -and $full.PSObject.Properties.Name -contains 'FullChargedCapacity') { $fcap = [double]$full.FullChargedCapacity } 
    if ($static -and $static.PSObject.Properties.Name -contains 'DesignedCapacity') { $design = [double]$static.DesignedCapacity }

    $rcap = $null
    if ($status.PSObject.Properties.Name -contains 'RemainingCapacity') { $rcap = [double]$status.RemainingCapacity }

    $pct  = if ($fcap -and $fcap -gt 0 -and $rcap -ne $null) { [math]::Round(($rcap/$fcap)*100,1) } else { $null }

    $voltageV = $null
    if ($status.PSObject.Properties.Name -contains 'Voltage' -and $status.Voltage -ne $null) {
        # Voltage is reported in millivolts by most ACPI implementations
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

    # Unified signed rate in mW and W (negative when discharging)
    $rate_mW = $null
    if ($charging -and $chargeRate_mW -gt 0) { $rate_mW = [math]::Round($chargeRate_mW, 0) }
    elseif ($discharging -and $dischargeRate_mW -gt 0) { $rate_mW = -1 * [math]::Round($dischargeRate_mW, 0) }

    $rate_W = if ($rate_mW -ne $null) { [math]::Round($rate_mW/1000.0, 3) } else { $null }

    # Time estimates (hours) based on energy (mWh) / power (mW)
    $hToFull = $null
    if ($charging -and $chargeRate_mW -gt 0 -and $fcap -ne $null -and $rcap -ne $null) {
        $hToFull = ($fcap - $rcap)/$chargeRate_mW
    }
    $hToEmpty = $null
    if ($discharging -and $dischargeRate_mW -gt 0 -and $rcap -ne $null) {
        $hToEmpty = $rcap/$dischargeRate_mW
    }

    function Fmt-Hours($h) {
        if ($h -eq $null -or $h -lt 0) { return $null }
        $totalMinutes = [int]([math]::Round($h*60,0))
        $hh = [int]($totalMinutes/60)
        $mm = $totalMinutes % 60
        return ('{0:00}:{1:00}' -f $hh,$mm)
    }

    $wear = $null
    if ($design -and $design -gt 0 -and $fcap -ne $null) {
        $wear = [math]::Round((1.0 - ($fcap/$design))*100, 1)
    }

    # Optional extra data
    $manufacturer = $null; $chemistry=$null; $serial=$null; $devname=$null
    if ($static) {
        foreach ($n in 'Manufacturer','Chemistry','SerialNumber','DeviceName') {
            if ($static.PSObject.Properties.Name -contains $n) {
                switch ($n) {
                    'Manufacturer' { $manufacturer = [string]$static.Manufacturer }
                    'Chemistry'    { $chemistry    = [string]$static.Chemistry }
                    'SerialNumber' { $serial       = [string]$static.SerialNumber }
                    'DeviceName'   { $devname      = [string]$static.DeviceName }
                }
            }
        }
    }

    $cycles = $null
    if ($cycle -and $cycle.PSObject.Properties.Name -contains 'CycleCount') { $cycles = [int]$cycle.CycleCount }

    [pscustomobject]@{
        Time          = (Get-Date).ToString('HH:mm:ss')
        Status        = $state
        OnAC          = $onAC
        Percent       = if ($pct -ne $null) { '{0:n1} %' -f $pct } else { $null }
        VoltageV      = $voltageV
        Rate_mW       = $rate_mW
        Rate_W        = $rate_W
        Remain_mWh    = if ($rcap -ne $null) { [int][math]::Round($rcap,0) } else { $null }
        Full_mWh      = if ($fcap -ne $null) { [int][math]::Round($fcap,0) } else { $null }
        Design_mWh    = if ($design -ne $null) { [int][math]::Round($design,0) } else { $null }
        Wear_pct      = if ($wear -ne $null) { '{0:n1}' -f $wear } else { $null }
        EstToFull     = Fmt-Hours $hToFull
        EstToEmpty    = Fmt-Hours $hToEmpty
        Cycles        = $cycles
        Manufacturer  = $manufacturer
        Chemistry     = $chemistry
        Serial        = $serial
        Device        = $devname
    }
}

# Minimal fallback using Win32_Battery (root\cimv2) when detailed WMI battery classes are unavailable
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

    $statusText = switch ($b.BatteryStatus) {
        1 { 'Discharging' }
        2 { 'AC (not charging)' }
        3 { 'Fully Charged' }
        4 { 'Low' }
        5 { 'Critical' }
        6 { 'Charging' }
        7 { 'Charging and High' }
        8 { 'Charging and Low' }
        9 { 'Charging and Critical' }
        10 { 'Undefined' }
        11 { 'Partially Charged' }
        Default { 'Unknown' }
    }

    function Fmt-Min($m) {
        if ($m -eq $null -or $m -lt 0) { return $null }
        $hh = [int]([math]::Floor($m/60))
        $mm = $m % 60
        '{0:00}:{1:00}' -f $hh,$mm
    }

    [pscustomobject]@{
        Time          = (Get-Date).ToString('HH:mm:ss')
        Status        = $statusText
        OnAC          = $null
        Percent       = if ($pct -ne $null) { '{0:n0} %' -f $pct } else { $null }
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
        Manufacturer  = $b.Manufacturer
        Chemistry     = $null
        Serial        = $b.SerialNumber
        Device        = $b.Name
    }
}

function Show-BatteryOnce {
    $info = Get-BatteryInfo
    if (-not $info) { $info = Get-BatteryInfoFallback }
    if (-not $info) {
        Write-Warning 'Battery information not available. This device may not expose battery telemetry over WMI/CIM, or no battery is present.'
        return
    }

    if ($Details) {
        $info | Format-Table Time, Status, OnAC, Percent, VoltageV, Rate_W, Rate_mW, Remain_mWh, Full_mWh, Design_mWh, Wear_pct, EstToFull, EstToEmpty -AutoSize
        $details = @()
        foreach ($k in 'Manufacturer','Chemistry','Serial','Device','Cycles') {
            $v = $info.$k
            if ($v) { $details += ('{0}: {1}' -f $k,$v) }
        }
        if ($details.Count -gt 0) { Write-Host "`n" ($details -join '  |  ') }
    } else {
        $pct = if ($info.Percent) { $info.Percent } else { 'n/a' }
        $rateW = if ($info.Rate_W -ne $null) { '{0:n3} W' -f $info.Rate_W } else { 'n/a' }
        $volt = if ($info.VoltageV -ne $null) { '{0:n3} V' -f $info.VoltageV } else { 'n/a' }
        $toF = if ($info.EstToFull) { $info.EstToFull } else { '--:--' }
        $toE = if ($info.EstToEmpty) { $info.EstToEmpty } else { '--:--' }
        Write-Host ("{0}  {1,-12}  {2,6}  Rate {3,10}  V {4,8}  ToFull {5,5}  ToEmpty {6,5}" -f $info.Time, $info.Status, $pct, $rateW, $volt, $toF, $toE)
    }
}

if (-not $Once) {
    while ($true) {
        if (-not $NoClear) { Clear-Host }
        Show-BatteryOnce
        Start-Sleep -Seconds $IntervalSeconds
    }
} else {
    Show-BatteryOnce
}
