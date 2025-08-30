# Battery Monitor (PowerShell)

A simple PowerShell monitor that expands on `gwmi -Class BatteryStatus -Namespace root\wmi` by computing charge/discharge rate, battery percentage, wear level, time-to-empty/time-to-full, and more.

## Features

- Uses WMI/CIM classes in `root\\wmi` to read:
  - `BatteryStatus` (voltage, remaining capacity, charge/discharge rates, power state)
  - `BatteryFullChargedCapacity`
  - `BatteryStaticData` (manufacturer, chemistry, design capacity)
  - `BatteryCycleCount` (if available)
- Calculates:
  - Percent = Remaining / FullChargedCapacity
  - Signed power rate (mW) and W (positive charging, negative discharging)
  - Time to full / time to empty (HH:MM)
  - Wear level = 1 - (FullChargedCapacity / DesignedCapacity)
- Watch/refresh mode for live updates

## Usage

Run from PowerShell:

```powershell
# Live watch (default)
./scripts/battery_monitor.ps1

# One shot
./scripts/battery_monitor.ps1 -Once

# Refresh every 2 seconds
./scripts/battery_monitor.ps1 -IntervalSeconds 2

# Keep screen from clearing each refresh
./scripts/battery_monitor.ps1 -NoClear

# Force legacy WMI instead of CIM (if CIM is blocked)
./scripts/battery_monitor.ps1 -UseWmi
```

### Widget (resizable UI)

```powershell
# Start the resizable battery widget
./scripts/battery_widget.ps1

# Make it stay on top
./scripts/battery_widget.ps1 -TopMost

# Faster refresh (1s)
./scripts/battery_widget.ps1 -RefreshMs 1000

# Force legacy WMI
./scripts/battery_widget.ps1 -UseWmi
```

## Installation

### Option 1: GUI Installer (Recommended)
1. Build or download `BatteryWidgetSetup.exe`
2. Run the installer - it will show a GUI interface where you can:
   - Choose installation location (defaults to `C:\Program Files\BatteryWidget`)
   - Select whether to start with Windows
   - Choose whether to create desktop shortcut
3. The installer will show progress and confirm when complete
4. The widget will be added to Programs and Features for easy uninstall

### Option 2: Command Line Installer
To install the widget as a system service that starts with Windows:

```powershell
# Run as Administrator
./scripts/install.ps1
```

This will:
- Copy BatteryWidget.exe to Program Files
- Create a Start Menu shortcut
- Add to Windows startup (runs on boot)
- Register with Programs and Features for easy uninstall

To uninstall:
```powershell
# Run as Administrator
./scripts/install.ps1 -Uninstall
# OR uninstall from Windows "Programs and Features"
```

### Option 3: Portable Mode
1. Build or download `BatteryWidget.exe`
2. Run it directly - no installation required
3. Use command line parameters if needed:
   ```
   BatteryWidget.exe -TopMost -Scale 1.4
   ```

## Building Executables

### Build Everything (Widget + GUI Installer)
Create both the portable widget and a GUI installer:

```powershell
# Build both widget and installer executables
./scripts/build_complete.ps1
```

Output: 
- `build/BatteryWidget.exe` (portable widget)
- `build/BatteryWidgetSetup.exe` (GUI installer with embedded widget)

### Build Widget Only
Create a portable .exe file:

```powershell
# Build GUI widget only
./scripts/build_exe.ps1

# Build both GUI widget and CLI tool
./scripts/build_exe.ps1 -BuildCli
```

Output: `dist/BatteryWidget.exe` (and optionally `dist/BatteryMonitor.exe`)

Notes:
- Values depend on what the ACPI/EC exposes. Some laptops report only a subset.
- Voltage typically arrives in millivolts (mV). The script converts to volts.
- Time estimates are approximate: based on instantaneous rate and can be noisy at high loads.

## Relation to your original command

Equivalent raw output for selected fields:

```powershell
gwmi -Class BatteryStatus -Namespace root\wmi | Format-List | Out-String -Stream | Select-String -Pattern "Voltage","Charge","Capacity"
```

This script gathers the same data but also joins other classes and computes derived metrics.
