param(
    [string]$OutputDir = "dist",
    [switch]$BuildCli
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-PS2EXE {
    if (Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue) { return }
    try {
        # Try import if installed but not loaded
        $m = Get-Module -ListAvailable -Name ps2exe | Select-Object -First 1
        if ($m) {
            Import-Module ps2exe -ErrorAction Stop
            return
        }
    } catch {}

    Write-Host 'Installing PS2EXE module (CurrentUser)...'
    try {
        if (-not (Get-Module -ListAvailable -Name PowerShellGet)) {
            Install-Module PowerShellGet -Scope CurrentUser -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Install-Module ps2exe -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module ps2exe -ErrorAction Stop
    } catch {
        Write-Error 'Failed to install or import PS2EXE. Please install manually: Install-Module ps2exe -Scope CurrentUser'
        throw
    }
}

$root = Split-Path -Parent $PSCommandPath
$repo = Split-Path -Parent $root
$out = Join-Path $repo $OutputDir
New-Item -ItemType Directory -Path $out -Force | Out-Null

Ensure-PS2EXE

$widgetIn = Join-Path $repo 'scripts/battery_widget.ps1'
$widgetOut = Join-Path $out 'BatteryWidget.exe'

Write-Host "Building GUI widget: $widgetOut"
Invoke-PS2EXE -InputFile $widgetIn -OutputFile $widgetOut -NoConsole -STA -Title 'Battery Widget' -Product 'Battery Widget' -Company 'Battery Monitor' -Description 'Battery monitor widget' -Version '1.0.0.0'

if ($BuildCli) {
    $cliIn = Join-Path $repo 'scripts/battery_monitor.ps1'
    $cliOut = Join-Path $out 'BatteryMonitor.exe'
    Write-Host "Building CLI monitor: $cliOut"
    Invoke-PS2EXE -InputFile $cliIn -OutputFile $cliOut -Title 'Battery Monitor' -Product 'Battery Monitor' -Company 'Battery Monitor' -Description 'Battery monitor CLI' -Version '1.0.0.0'
}

Write-Host "Done. Output in: $out"
