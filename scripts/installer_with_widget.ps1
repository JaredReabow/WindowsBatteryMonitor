# Battery Widget Installer with Embedded Executable
# This installer contains the BatteryWidget.exe embedded as base64

param(
    [switch]$Uninstall
)

# Ensure STA apartment state for WPF
if ([threading.Thread]::CurrentThread.GetApartmentState() -ne "STA") {
    Write-Host "Relaunching in STA mode..."
    $arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.ScriptName)`""
    if ($Uninstall) {
        $arguments += " -Uninstall"
    }
    Start-Process PowerShell -ArgumentList $arguments
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Embedded BatteryWidget.exe as base64 (placeholder - will be replaced by build script)
$EmbeddedWidgetBase64 = "EMBEDDED_WIDGET_BASE64_PLACEHOLDER"

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    if (-not (Test-Administrator)) {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.ScriptName)`""
        if ($Uninstall) {
            $arguments += " -Uninstall"
        }
        Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
        exit
    }
}

function Show-InstallDialog {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Battery Widget Setup" Height="400" Width="500"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="Battery Widget Setup" FontSize="18" FontWeight="Bold" 
                   HorizontalAlignment="Center" Margin="0,0,0,20"/>
        
        <TextBlock Grid.Row="1" TextWrapping="Wrap" Margin="0,0,0,15">
            This will install Battery Widget, a system tray utility for monitoring battery status.
        </TextBlock>
        
        <GroupBox Grid.Row="2" Header="Installation Location" Margin="0,0,0,15">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox x:Name="InstallPath" Grid.Column="0" Margin="5" VerticalAlignment="Center"/>
                <Button x:Name="BrowseButton" Grid.Column="1" Content="Browse..." Margin="5" Padding="10,5"/>
            </Grid>
        </GroupBox>
        
        <CheckBox x:Name="StartupCheckbox" Grid.Row="3" Content="Start with Windows" 
                  IsChecked="True" Margin="0,0,0,15"/>
        
        <CheckBox x:Name="DesktopShortcut" Grid.Row="4" Content="Create desktop shortcut" 
                  IsChecked="True" Margin="0,0,0,15"/>
        
        <StackPanel Grid.Row="6" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="InstallButton" Content="Install" Margin="5" Padding="20,8" IsDefault="True"/>
            <Button x:Name="CancelButton" Content="Cancel" Margin="5" Padding="20,8" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    
    $installPath = $window.FindName("InstallPath")
    $browseButton = $window.FindName("BrowseButton")
    $startupCheckbox = $window.FindName("StartupCheckbox")
    $desktopShortcut = $window.FindName("DesktopShortcut")
    $installButton = $window.FindName("InstallButton")
    $cancelButton = $window.FindName("CancelButton")
    
    # Set default install path
    $installPath.Text = "$env:ProgramFiles\BatteryWidget"
    
    $browseButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select installation folder"
        $dialog.SelectedPath = $installPath.Text
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $installPath.Text = Join-Path $dialog.SelectedPath "BatteryWidget"
        }
    })
    
    $installButton.Add_Click({
        $window.DialogResult = $true
        $window.Close()
    })
    
    $cancelButton.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })
    
    $result = $window.ShowDialog()
    
    if ($result -eq $true) {
        return @{
            InstallPath = $installPath.Text
            StartWithWindows = $startupCheckbox.IsChecked
            CreateDesktopShortcut = $desktopShortcut.IsChecked
        }
    } else {
        return $null
    }
}

function Show-ProgressDialog {
    param([string]$Title, [scriptblock]$Action)
    
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" Height="200" Width="400"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock x:Name="StatusText" Grid.Row="0" Text="Please wait..." FontSize="14" 
                   HorizontalAlignment="Center" Margin="0,0,0,20"/>
        
        <ProgressBar x:Name="ProgressBar" Grid.Row="1" Height="20" IsIndeterminate="True" Margin="0,0,0,20"/>
        
        <TextBox x:Name="LogText" Grid.Row="2" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="10" Background="#F0F0F0"/>
        
        <Button x:Name="CloseButton" Grid.Row="3" Content="Close" HorizontalAlignment="Right" 
                Margin="0,10,0,0" Padding="20,8" IsEnabled="False"/>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
    
    $statusText = $window.FindName("StatusText")
    $progressBar = $window.FindName("ProgressBar")
    $logText = $window.FindName("LogText")
    $closeButton = $window.FindName("CloseButton")
    
    $closeButton.Add_Click({
        $window.Close()
    })
    
    # Show window
    $window.Show()
    $window.Activate()
    
    # Update UI function
    $script:UpdateUI = {
        param([string]$Status, [string]$Log)
        $statusText.Text = $Status
        if ($Log) {
            $logText.AppendText("$Log`r`n")
            $logText.ScrollToEnd()
        }
        $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
    }
    
    # Run action in background
    $job = Start-Job -ScriptBlock $Action -ArgumentList $script:UpdateUI
    
    # Monitor job
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)
    $timer.Add_Tick({
        if ($job.State -eq "Completed") {
            $timer.Stop()
            $progressBar.IsIndeterminate = $false
            $progressBar.Value = 100
            $statusText.Text = "Installation completed successfully!"
            $closeButton.IsEnabled = $true
            
            # Auto-close after 3 seconds
            $autoCloseTimer = New-Object System.Windows.Threading.DispatcherTimer
            $autoCloseTimer.Interval = [TimeSpan]::FromSeconds(3)
            $autoCloseTimer.Add_Tick({
                $autoCloseTimer.Stop()
                $window.Close()
            })
            $autoCloseTimer.Start()
        } elseif ($job.State -eq "Failed") {
            $timer.Stop()
            $progressBar.IsIndeterminate = $false
            $statusText.Text = "Installation failed!"
            $closeButton.IsEnabled = $true
            $jobError = Receive-Job $job 2>&1
            & $script:UpdateUI "Installation failed!" "ERROR: $jobError"
        }
    })
    $timer.Start()
    
    $window.ShowDialog()
    Remove-Job $job -Force
}

function Install-App {
    param($Config)
    
    $installPath = $Config.InstallPath
    
    # Create installation directory
    & $script:UpdateUI "Creating installation directory..." "Creating: $installPath"
    if (!(Test-Path $installPath)) {
        New-Item -Path $installPath -ItemType Directory -Force | Out-Null
    }
    
    # Extract and save the embedded executable
    & $script:UpdateUI "Extracting application files..." "Extracting BatteryWidget.exe"
    if ($EmbeddedWidgetBase64 -eq "EMBEDDED_WIDGET_BASE64_PLACEHOLDER") {
        throw "Installer was not properly built - embedded executable is missing"
    }
    
    $widgetBytes = [Convert]::FromBase64String($EmbeddedWidgetBase64)
    $widgetPath = Join-Path $installPath "BatteryWidget.exe"
    [System.IO.File]::WriteAllBytes($widgetPath, $widgetBytes)
    
    # Registry entries for Programs and Features
    & $script:UpdateUI "Registering application..." "Adding to Programs and Features"
    $uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\BatteryWidget"
    New-Item -Path $uninstallKey -Force | Out-Null
    Set-ItemProperty -Path $uninstallKey -Name "DisplayName" -Value "Battery Widget"
    Set-ItemProperty -Path $uninstallKey -Name "DisplayVersion" -Value "1.0"
    Set-ItemProperty -Path $uninstallKey -Name "Publisher" -Value "Battery Widget"
    Set-ItemProperty -Path $uninstallKey -Name "InstallLocation" -Value $installPath
    Set-ItemProperty -Path $uninstallKey -Name "UninstallString" -Value "`"$($MyInvocation.ScriptName)`" -Uninstall"
    Set-ItemProperty -Path $uninstallKey -Name "NoModify" -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallKey -Name "NoRepair" -Value 1 -Type DWord
    
    # Start menu shortcut
    & $script:UpdateUI "Creating shortcuts..." "Creating Start Menu shortcut"
    $startMenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    $shortcutPath = Join-Path $startMenuPath "Battery Widget.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $widgetPath
    $shortcut.WorkingDirectory = $installPath
    $shortcut.Description = "Battery monitoring widget"
    $shortcut.Save()
    
    # Desktop shortcut
    if ($Config.CreateDesktopShortcut) {
        & $script:UpdateUI "Creating shortcuts..." "Creating Desktop shortcut"
        $desktopPath = [Environment]::GetFolderPath("CommonDesktopDirectory")
        $desktopShortcut = Join-Path $desktopPath "Battery Widget.lnk"
        $shortcut = $shell.CreateShortcut($desktopShortcut)
        $shortcut.TargetPath = $widgetPath
        $shortcut.WorkingDirectory = $installPath
        $shortcut.Description = "Battery monitoring widget"
        $shortcut.Save()
    }
    
    # Startup entry
    if ($Config.StartWithWindows) {
        & $script:UpdateUI "Configuring startup..." "Adding to Windows startup"
        $startupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $startupKey -Name "BatteryWidget" -Value "`"$widgetPath`" -TopMost"
    }
    
    & $script:UpdateUI "Installation complete!" "Battery Widget has been installed successfully"
}

function Uninstall-App {
    $uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\BatteryWidget"
    
    if (Test-Path $uninstallKey) {
        $installPath = Get-ItemProperty -Path $uninstallKey -Name "InstallLocation" -ErrorAction SilentlyContinue
        
        if ($installPath) {
            # Stop any running instances
            Get-Process -Name "BatteryWidget" -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Seconds 2
            
            # Remove startup entry
            $startupKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            Remove-ItemProperty -Path $startupKey -Name "BatteryWidget" -ErrorAction SilentlyContinue
            
            # Remove shortcuts
            $startMenuShortcut = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Battery Widget.lnk"
            $desktopShortcut = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Battery Widget.lnk"
            Remove-Item $startMenuShortcut -ErrorAction SilentlyContinue
            Remove-Item $desktopShortcut -ErrorAction SilentlyContinue
            
            # Remove installation directory
            Remove-Item $installPath.InstallLocation -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Remove registry entry
        Remove-Item $uninstallKey -Recurse -Force
        
        [System.Windows.MessageBox]::Show("Battery Widget has been uninstalled successfully.", "Uninstall Complete", "OK", "Information")
    } else {
        [System.Windows.MessageBox]::Show("Battery Widget is not installed.", "Uninstall", "OK", "Warning")
    }
}

# Main execution
if ($Uninstall) {
    Request-Elevation
    Uninstall-App
    exit
}

# Show install dialog
$config = Show-InstallDialog
if ($null -eq $config) {
    exit # User cancelled
}

# Request elevation if needed
Request-Elevation

# Show progress dialog and install
Show-ProgressDialog -Title "Installing Battery Widget" -Action {
    param($UpdateUI)
    $script:UpdateUI = $UpdateUI
    Install-App $config
}
