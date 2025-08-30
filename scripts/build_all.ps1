# Build script for Battery Widget and Installer
param(
    [switch]$Clean,
    [switch]$WidgetOnly,
    [switch]$InstallerOnly
)

$ErrorActionPreference = "Stop"

# Paths
$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectDir = Split-Path -Parent $ScriptDir
$DistDir = Join-Path $ProjectDir "dist"
$WidgetScript = Join-Path $ScriptDir "battery_widget.ps1"
$InstallerTemplate = Join-Path $ScriptDir "installer_selfcontained.ps1"
$WidgetExe = Join-Path $DistDir "BatteryWidget.exe"
$InstallerScript = Join-Path $DistDir "BatteryWidgetInstaller.ps1"
$InstallerExe = Join-Path $DistDir "BatteryWidgetInstaller.exe"

Write-Host "Battery Widget Build System" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan

# Ensure PS2EXE is available
function Ensure-PS2EXE {
    if (-not (Get-Module -ListAvailable -Name PS2EXE)) {
        Write-Host "Installing PS2EXE module..." -ForegroundColor Yellow
        Install-Module -Name PS2EXE -Force -Scope CurrentUser
    }
    Import-Module PS2EXE -Force
}

# Clean previous builds
function Clean-Build {
    Write-Host "Cleaning previous builds..." -ForegroundColor Yellow
    if (Test-Path $DistDir) {
        # Stop any running instances
        Get-Process -Name "BatteryWidget*" -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 1
        Remove-Item $DistDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

# Build widget executable
function Build-Widget {
    Write-Host "`nBuilding Battery Widget executable..." -ForegroundColor Green
    
    if (-not (Test-Path $WidgetScript)) {
        Write-Error "Widget script not found: $WidgetScript"
        return $false
    }
    
    try {
        $ps2exeParams = @{
            inputFile = $WidgetScript
            outputFile = $WidgetExe
            noConsole = $true
            STA = $true
            iconFile = $null
            title = "Battery Widget"
            description = "Battery monitoring widget for Windows"
            company = "Battery Monitor"
            product = "Battery Widget"
            copyright = "© 2025"
            version = "1.0.0.0"
            noError = $true
            noOutput = $true
        }
        
        Invoke-PS2EXE @ps2exeParams
        
        if (Test-Path $WidgetExe) {
            $size = [math]::Round((Get-Item $WidgetExe).Length / 1MB, 2)
            Write-Host "[OK] Widget executable created: $WidgetExe ($size MB)" -ForegroundColor Green
            return $true
        } else {
            Write-Error "Failed to create widget executable"
            return $false
        }
    }
    catch {
        Write-Error "Error building widget: $_"
        return $false
    }
}

# Build installer executable
function Build-Installer {
    Write-Host "`nBuilding self-contained installer..." -ForegroundColor Green
    
    if (-not (Test-Path $WidgetExe)) {
        Write-Error "Widget executable not found. Build the widget first."
        return $false
    }
    
    if (-not (Test-Path $InstallerTemplate)) {
        Write-Error "Installer template not found: $InstallerTemplate"
        return $false
    }
    
    try {
        # Read the widget executable as base64
        Write-Host "Encoding widget executable..."
        $WidgetBytes = [System.IO.File]::ReadAllBytes($WidgetExe)
        $WidgetBase64 = [System.Convert]::ToBase64String($WidgetBytes)
        
        # Read installer template
        $InstallerContent = Get-Content $InstallerTemplate -Raw
        
        # Replace placeholder with embedded executable
        $InstallerContent = $InstallerContent -replace 'EMBEDDED_EXE_PLACEHOLDER', $WidgetBase64
        
        # Save the installer script
        Set-Content -Path $InstallerScript -Value $InstallerContent -Encoding UTF8
        
        Write-Host "Creating installer executable..."
        $ps2exeParams = @{
            inputFile = $InstallerScript
            outputFile = $InstallerExe
            noConsole = $true
            requireAdmin = $true
            iconFile = $null
            title = "Battery Widget Installer"
            description = "Installer for Battery Widget"
            company = "Battery Monitor"
            product = "Battery Widget Installer"
            copyright = "© 2025"
            version = "1.0.0.0"
            noError = $true
            noOutput = $true
        }
        
        Invoke-PS2EXE @ps2exeParams
        
        if (Test-Path $InstallerExe) {
            $size = [math]::Round((Get-Item $InstallerExe).Length / 1MB, 2)
            Write-Host "[OK] Installer executable created: $InstallerExe ($size MB)" -ForegroundColor Green
            
            # Clean up temporary installer script
            Remove-Item $InstallerScript -Force
            return $true
        } else {
            Write-Error "Failed to create installer executable"
            return $false
        }
    }
    catch {
        Write-Error "Error building installer: $_"
        return $false
    }
}

# Main build process
try {
    Ensure-PS2EXE
    
    if ($Clean -or (-not $WidgetOnly -and -not $InstallerOnly)) {
        Clean-Build
    }
    
    $success = $true
    
    if (-not $InstallerOnly) {
        $success = Build-Widget
    }
    
    if ($success -and -not $WidgetOnly) {
        $success = Build-Installer
    }
    
    if ($success) {
        Write-Host "`n" + "="*50 -ForegroundColor Cyan
        Write-Host "BUILD COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host "="*50 -ForegroundColor Cyan
        
        if (Test-Path $WidgetExe) {
            $widgetSize = [math]::Round((Get-Item $WidgetExe).Length / 1MB, 2)
            Write-Host "Widget: $WidgetExe ($widgetSize MB)" -ForegroundColor White
        }
        
        if (Test-Path $InstallerExe) {
            $installerSize = [math]::Round((Get-Item $InstallerExe).Length / 1MB, 2)
            Write-Host "Installer: $InstallerExe ($installerSize MB)" -ForegroundColor White
        }
        
        Write-Host "`nUsage:" -ForegroundColor Yellow
        Write-Host "- Run the installer as Administrator to install system-wide" -ForegroundColor White
        Write-Host "- Or run the widget directly for portable use" -ForegroundColor White
        Write-Host "- Installer includes auto-startup and uninstall capabilities" -ForegroundColor White
        
        # Offer to run the widget
        Write-Host "`nWould you like to test the widget now? (y/n): " -ForegroundColor Yellow -NoNewline
        $response = Read-Host
        if ($response -eq 'y' -or $response -eq 'Y') {
            Start-Process $WidgetExe -ArgumentList "-TopMost"
        }
    }
}
catch {
    Write-Error "Build failed: $_"
    exit 1
}

Write-Host "`nBuild complete. Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
