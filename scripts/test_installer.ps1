# Simple Test Installer - No Admin Required
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

function Show-TestDialog {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Test Installer" Height="300" Width="400"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="Test Battery Widget Installer" FontSize="16" FontWeight="Bold" 
                   HorizontalAlignment="Center" Margin="0,0,0,20"/>
        
        <TextBlock Grid.Row="1" TextWrapping="Wrap" VerticalAlignment="Center" HorizontalAlignment="Center">
            If you can see this window, the GUI is working correctly.
            This is a test version without admin requirements.
        </TextBlock>
        
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="OkButton" Content="OK" Margin="5" Padding="20,8" IsDefault="True"/>
        </StackPanel>
    </Grid>
</Window>
"@

    try {
        $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
        $window = [Windows.Markup.XamlReader]::Load($reader)
        
        $okButton = $window.FindName("OkButton")
        $okButton.Add_Click({
            $window.DialogResult = $true
            $window.Close()
        })
        
        $result = $window.ShowDialog()
        [System.Windows.MessageBox]::Show("Test completed successfully!", "Test Result", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", "Test Failed", "OK", "Error")
    }
}

# Set STA apartment state
if ([threading.Thread]::CurrentThread.GetApartmentState() -ne "STA") {
    Write-Host "Relaunching in STA mode..."
    powershell -STA -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit
}

Show-TestDialog
