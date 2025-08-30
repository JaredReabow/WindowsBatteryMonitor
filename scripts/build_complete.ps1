# Complete Build Script - Battery Widget with GUI Installer
# Creates both BatteryWidget.exe and BatteryWidgetSetup.exe

param(
    [switch]$SkipWidget,
    [switch]$SkipInstaller
)

Write-Host "=== Battery Widget Complete Build System ===" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$buildDir = Join-Path $projectRoot "build"

# Ensure build directory exists
if (!(Test-Path $buildDir)) {
    New-Item -Path $buildDir -ItemType Directory -Force | Out-Null
}

function Ensure-PS2EXE {
    Write-Host "Checking PS2EXE module..." -ForegroundColor Yellow
    if (!(Get-Module -ListAvailable -Name PS2EXE)) {
        Write-Host "Installing PS2EXE module..." -ForegroundColor Yellow
        Install-Module -Name PS2EXE -Force -Scope CurrentUser
    }
    Import-Module PS2EXE -Force
    Write-Host "* PS2EXE module ready" -ForegroundColor Green
}

function Build-Widget {
    Write-Host ""
    Write-Host "=== Building Battery Widget Executable ===" -ForegroundColor Cyan
    
    $widgetScript = Join-Path $scriptDir "battery_widget.ps1"
    $widgetExe = Join-Path $buildDir "BatteryWidget.exe"
    
    if (!(Test-Path $widgetScript)) {
        throw "Widget script not found: $widgetScript"
    }
    
    # Kill any running instances
    Get-Process -Name "BatteryWidget" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    
    # Remove old executable
    if (Test-Path $widgetExe) {
        Remove-Item $widgetExe -Force
    }
    
    Write-Host "Compiling battery_widget.ps1 -> BatteryWidget.exe..." -ForegroundColor Yellow
    
    try {
        $result = ps2exe -inputFile $widgetScript -outputFile $widgetExe -iconFile $null -noConsole -STA -noError -noOutput 2>&1
        
        if (Test-Path $widgetExe) {
            $size = [math]::Round((Get-Item $widgetExe).Length / 1MB, 2)
            Write-Host "* BatteryWidget.exe created successfully ($size MB)" -ForegroundColor Green
            return $widgetExe
        } else {
            throw "Executable was not created"
        }
    } catch {
        Write-Error "Failed to build widget: $_"
        return $null
    }
}

function Build-Installer {
    param([string]$WidgetExePath)
    
    Write-Host ""
    Write-Host "=== Building GUI Installer Executable ===" -ForegroundColor Cyan
    
    $installerTemplate = Join-Path $scriptDir "installer_with_widget.ps1"
    $installerScript = Join-Path $buildDir "installer_final.ps1"
    $installerExe = Join-Path $buildDir "BatteryWidgetSetup.exe"
    
    if (!(Test-Path $installerTemplate)) {
        throw "Installer template not found: $installerTemplate"
    }
    
    if (!(Test-Path $WidgetExePath)) {
        throw "Widget executable not found: $WidgetExePath"
    }
    
    # Read widget executable as base64
    Write-Host "Embedding BatteryWidget.exe into installer..." -ForegroundColor Yellow
    $widgetBytes = [System.IO.File]::ReadAllBytes($WidgetExePath)
    $widgetBase64 = [Convert]::ToBase64String($widgetBytes)
    Write-Host "Embedded widget size: $([math]::Round($widgetBytes.Length / 1MB, 2)) MB" -ForegroundColor Gray
    
    # Read installer template
    $installerContent = Get-Content $installerTemplate -Raw
    
    # Replace placeholder with embedded executable
    $installerContent = $installerContent -replace "EMBEDDED_WIDGET_BASE64_PLACEHOLDER", $widgetBase64
    
    # Write final installer script
    $installerContent | Set-Content $installerScript -Encoding UTF8
    
    # Remove old installer executable
    if (Test-Path $installerExe) {
        Remove-Item $installerExe -Force
    }
    
    Write-Host "Compiling installer -> BatteryWidgetSetup.exe..." -ForegroundColor Yellow
    
    try {
        $result = ps2exe -inputFile $installerScript -outputFile $installerExe -iconFile $null -STA -noError -noOutput 2>&1
        
        if (Test-Path $installerExe) {
            $size = [math]::Round((Get-Item $installerExe).Length / 1MB, 2)
            Write-Host "* BatteryWidgetSetup.exe created successfully ($size MB)" -ForegroundColor Green
            
            # Clean up temporary installer script
            Remove-Item $installerScript -Force
            
            return $installerExe
        } else {
            throw "Installer executable was not created"
        }
    } catch {
        Write-Error "Failed to build installer: $_"
        return $null
    }
}

# Main build process
try {
    Ensure-PS2EXE
    
    $widgetExe = $null
    $installerExe = $null
    
    # Build widget executable
    if (!$SkipWidget) {
        $widgetExe = Build-Widget
        if (!$widgetExe) {
            throw "Widget build failed"
        }
    } else {
        $widgetExe = Join-Path $buildDir "BatteryWidget.exe"
        if (!(Test-Path $widgetExe)) {
            throw "Widget executable not found, cannot skip widget build"
        }
    }
    
    # Build installer executable
    if (!$SkipInstaller) {
        $installerExe = Build-Installer -WidgetExePath $widgetExe
        if (!$installerExe) {
            throw "Installer build failed"
        }
    }
    
    Write-Host ""
    Write-Host "=== Build Complete ===" -ForegroundColor Green
    Write-Host ""
    
    if ($widgetExe -and (Test-Path $widgetExe)) {
        Write-Host "Widget Executable: $widgetExe" -ForegroundColor Cyan
    }
    
    if ($installerExe -and (Test-Path $installerExe)) {
        Write-Host "Installer Executable: $installerExe" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "* Ready for distribution!" -ForegroundColor Green
        Write-Host "  - Run BatteryWidgetSetup.exe to install with GUI" -ForegroundColor Gray
        Write-Host "  - Or run BatteryWidget.exe directly (portable mode)" -ForegroundColor Gray
    }
    
} catch {
    Write-Error "Build failed: $_"
    exit 1
}
