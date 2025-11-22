# VM Detection Evasion Setup Script
# Run as Administrator on first boot
# This script complements the VM XML configuration for maximum evasion

#Requires -RunAsAdministrator

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "     VM Detection Evasion Setup - Windows Configuration" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# 1. Disable VM-related Services
# ============================================================================

Write-Host "[1/8] Disabling VM-related services..." -ForegroundColor Yellow

$vmServices = @(
    "HvHost",
    "vmickvpexchange",
    "vmicguestinterface",
    "vmicshutdown",
    "vmicheartbeat",
    "vmicvss",
    "vmictimesync",
    "vmicrdv"
)

foreach ($service in $vmServices) {
    try {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host "  Disabled: $service" -ForegroundColor Green
        }
    } catch {
        # Service doesn't exist or already disabled
    }
}

# ============================================================================
# 2. Remove VM-related Software Entries
# ============================================================================

Write-Host ""
Write-Host "[2/8] Removing VM software registry entries..." -ForegroundColor Yellow

$vmRegPaths = @(
    "HKLM:\SOFTWARE\VMware, Inc.",
    "HKLM:\SOFTWARE\Oracle\VirtualBox Guest Additions",
    "HKLM:\SOFTWARE\Microsoft\Virtual Machine",
    "HKLM:\SYSTEM\ControlSet001\Services\VBoxGuest",
    "HKLM:\SYSTEM\ControlSet001\Services\VBoxMouse",
    "HKLM:\SYSTEM\ControlSet001\Services\VBoxService",
    "HKLM:\SYSTEM\ControlSet001\Services\VBoxSF",
    "HKLM:\SYSTEM\ControlSet001\Services\VBoxVideo"
)

foreach ($path in $vmRegPaths) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed: $path" -ForegroundColor Green
    }
}

# ============================================================================
# 3. Hide VirtIO Network Adapter Name
# ============================================================================

Write-Host ""
Write-Host "[3/8] Renaming VirtIO network adapters..." -ForegroundColor Yellow

Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*VirtIO*" -or $_.InterfaceDescription -like "*Red Hat*" } | ForEach-Object {
    $newName = "Intel(R) Ethernet Connection"
    try {
        Rename-NetAdapter -Name $_.Name -NewName $newName -ErrorAction SilentlyContinue
        Write-Host "  Renamed adapter: $($_.Name) -> $newName" -ForegroundColor Green
    } catch {
        Write-Host "  Could not rename: $($_.Name)" -ForegroundColor Gray
    }
}

# Also update registry descriptions
$netAdapters = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}" -ErrorAction SilentlyContinue

foreach ($adapter in $netAdapters) {
    $driverDesc = (Get-ItemProperty -Path $adapter.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc

    if ($driverDesc -like "*VirtIO*" -or $driverDesc -like "*Red Hat*") {
        Set-ItemProperty -Path $adapter.PSPath -Name "DriverDesc" -Value "Intel(R) I211 Gigabit Network Connection"
        Write-Host "  Updated registry: $driverDesc -> Intel I211" -ForegroundColor Green
    }
}

# ============================================================================
# 4. Spoof Disk Model Names
# ============================================================================

Write-Host ""
Write-Host "[4/8] Checking disk models..." -ForegroundColor Yellow

Get-PhysicalDisk | Where-Object { $_.FriendlyName -like "*QEMU*" -or $_.FriendlyName -like "*VirtIO*" } | ForEach-Object {
    Write-Host "  Warning: VM disk detected: $($_.FriendlyName)" -ForegroundColor Yellow
    Write-Host "  (This is handled at hypervisor level, may still be visible)" -ForegroundColor Gray
}

# ============================================================================
# 5. Disable Windows Telemetry and Data Collection
# ============================================================================

Write-Host ""
Write-Host "[5/8] Disabling telemetry (reduces fingerprinting)..." -ForegroundColor Yellow

# Disable telemetry
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Force

# Disable DiagTrack
Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue

Write-Host "  Telemetry disabled" -ForegroundColor Green

# ============================================================================
# 6. Optimize GPU Passthrough Settings
# ============================================================================

Write-Host ""
Write-Host "[6/8] Configuring GPU passthrough optimizations..." -ForegroundColor Yellow

# Disable TDR (Timeout Detection and Recovery)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrLevel" -Value 0 -Force
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrDelay" -Value 60 -Force
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "TdrDdiDelay" -Value 60 -Force

Write-Host "  GPU TDR disabled for better passthrough performance" -ForegroundColor Green

# ============================================================================
# 7. Hide Virtualization CPU Features (Registry)
# ============================================================================

Write-Host ""
Write-Host "[7/8] Checking CPU virtualization features..." -ForegroundColor Yellow

# Check if hypervisor is present
$hvPresent = (Get-WmiObject -Class Win32_ComputerSystem).HypervisorPresent

if ($hvPresent) {
    Write-Host "  Warning: Hypervisor bit is present!" -ForegroundColor Red
    Write-Host "  This should be hidden by your VM XML config (kvm hidden=on)" -ForegroundColor Yellow
} else {
    Write-Host "  Good: No hypervisor detected in WMI" -ForegroundColor Green
}

# Check manufacturer
$manufacturer = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
if ($manufacturer -like "*QEMU*" -or $manufacturer -like "*innotek*" -or $manufacturer -like "*VMware*") {
    Write-Host "  Warning: VM manufacturer detected: $manufacturer" -ForegroundColor Red
    Write-Host "  Fix this in your VM XML SMBIOS settings!" -ForegroundColor Yellow
} else {
    Write-Host "  Good: Manufacturer looks legitimate: $manufacturer" -ForegroundColor Green
}

# ============================================================================
# 8. Performance Optimizations (reduces VM overhead detection)
# ============================================================================

Write-Host ""
Write-Host "[8/8] Applying performance optimizations..." -ForegroundColor Yellow

# Disable unnecessary services
$unnecessaryServices = @(
    "PcaSvc",          # Program Compatibility Assistant
    "WSearch",         # Windows Search (use Everything instead)
    "SysMain",         # Superfetch
    "wisvc",           # Windows Insider Service
    "RetailDemo"       # Retail Demo Service
)

foreach ($service in $unnecessaryServices) {
    try {
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
        Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  Disabled: $service" -ForegroundColor Green
    } catch {
        # Service doesn't exist
    }
}

# Disable Windows Defender (optional - may help with performance)
# Uncomment if you use alternative antivirus
# Set-MpPreference -DisableRealtimeMonitoring $true

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "                    Configuration Complete!" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Reboot the system for all changes to take effect" -ForegroundColor White
Write-Host "  2. Run Pafish or Al-Khaser to test VM detection" -ForegroundColor White
Write-Host "  3. Check Device Manager for any VirtIO/QEMU devices" -ForegroundColor White
Write-Host "  4. Verify BIOS info with: Get-WmiObject -Class Win32_BIOS" -ForegroundColor White
Write-Host ""
Write-Host "Testing Commands:" -ForegroundColor Yellow
Write-Host "  Get-WmiObject -Class Win32_BIOS" -ForegroundColor Gray
Write-Host "  Get-WmiObject -Class Win32_ComputerSystem" -ForegroundColor Gray
Write-Host "  Get-PhysicalDisk | Select Model,FriendlyName" -ForegroundColor Gray
Write-Host "  Get-NetAdapter | Select Name,InterfaceDescription" -ForegroundColor Gray
Write-Host ""

# Prompt for reboot
$reboot = Read-Host "Reboot now to apply changes? (Y/N)"
if ($reboot -eq "Y" -or $reboot -eq "y") {
    Write-Host "Rebooting in 10 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
