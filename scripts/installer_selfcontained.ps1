param(
    [switch]$Uninstall
)

# Requires Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "This installer requires Administrator privileges. Restarting as Administrator..." -ForegroundColor Yellow
    Start-Process PowerShell -Verb RunAs "-File `"$($MyInvocation.MyCommand.Path)`" $($MyInvocation.UnboundArguments)"
    exit
}

$AppName = "BatteryWidget"
$Publisher = "Battery Monitor"
$Version = "1.0.0"
$ExeName = "BatteryWidget.exe"

# Paths
$InstallDir = Join-Path $env:ProgramFiles $AppName
$InstallExe = Join-Path $InstallDir $ExeName
$StartMenuDir = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
$ShortcutPath = Join-Path $StartMenuDir "$AppName.lnk"
$StartupRegKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"

# Embedded executable as base64 string (will be replaced during build)
$EmbeddedExeBase64 = "EMBEDDED_EXE_PLACEHOLDER"

function Install-App {
    Write-Host "Installing $AppName..." -ForegroundColor Green
    
    if ($EmbeddedExeBase64 -eq "EMBEDDED_EXE_PLACEHOLDER") {
        Write-Error "This installer was not built properly. The embedded executable is missing."
        exit 1
    }
    
    # Create install directory
    Write-Host "Creating installation directory: $InstallDir"
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    
    # Extract and save embedded executable
    Write-Host "Extracting executable..."
    try {
        $ExeBytes = [System.Convert]::FromBase64String($EmbeddedExeBase64)
        [System.IO.File]::WriteAllBytes($InstallExe, $ExeBytes)
        Write-Host "Executable extracted successfully."
    }
    catch {
        Write-Error "Failed to extract executable: $_"
        exit 1
    }
    
    # Create Start Menu shortcut
    Write-Host "Creating Start Menu shortcut..."
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $InstallExe
    $Shortcut.Arguments = "-TopMost"
    $Shortcut.Description = "Battery monitoring widget"
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.Save()
    
    # Add to startup (run on boot)
    Write-Host "Adding to Windows startup..."
    Set-ItemProperty -Path $StartupRegKey -Name $AppName -Value "`"$InstallExe`" -TopMost" -Type String
    
    # Add to Programs and Features (for easy uninstall)
    Write-Host "Registering with Windows..."
    $UninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"
    New-Item -Path $UninstallKey -Force | Out-Null
    Set-ItemProperty -Path $UninstallKey -Name "DisplayName" -Value $AppName
    Set-ItemProperty -Path $UninstallKey -Name "Publisher" -Value $Publisher
    Set-ItemProperty -Path $UninstallKey -Name "DisplayVersion" -Value $Version
    Set-ItemProperty -Path $UninstallKey -Name "InstallLocation" -Value $InstallDir
    Set-ItemProperty -Path $UninstallKey -Name "UninstallString" -Value "PowerShell.exe -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Uninstall"
    Set-ItemProperty -Path $UninstallKey -Name "NoModify" -Value 1 -Type DWord
    Set-ItemProperty -Path $UninstallKey -Name "NoRepair" -Value 1 -Type DWord
    
    Write-Host "`n$AppName has been installed successfully!" -ForegroundColor Green
    Write-Host "- Installed to: $InstallDir"
    Write-Host "- Start Menu shortcut created"
    Write-Host "- Will start automatically with Windows"
    Write-Host "- You can uninstall from Programs and Features"
    Write-Host "`nStarting $AppName now..." -ForegroundColor Yellow
    
    # Start the app
    Start-Process $InstallExe -ArgumentList "-TopMost"
}

function Uninstall-App {
    Write-Host "Uninstalling $AppName..." -ForegroundColor Yellow
    
    # Stop any running instances
    Get-Process -Name ($ExeName -replace '\.exe$','') -ErrorAction SilentlyContinue | Stop-Process -Force
    
    # Remove from startup
    Write-Host "Removing from Windows startup..."
    Remove-ItemProperty -Path $StartupRegKey -Name $AppName -ErrorAction SilentlyContinue
    
    # Remove Start Menu shortcut
    Write-Host "Removing Start Menu shortcut..."
    Remove-Item $ShortcutPath -Force -ErrorAction SilentlyContinue
    
    # Remove from Programs and Features
    Write-Host "Removing from Programs and Features..."
    $UninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$AppName"
    Remove-Item $UninstallKey -Force -ErrorAction SilentlyContinue
    
    # Remove installation directory
    Write-Host "Removing installation files..."
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    
    Write-Host "`n$AppName has been uninstalled successfully!" -ForegroundColor Green
}

# Main execution
if ($Uninstall) {
    Uninstall-App
} else {
    Install-App
}

Write-Host "`nPress any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
