# Windows VM Evasion Scripts

Scripts to inject into your custom Windows 11 ISO for improved VM detection evasion.

## Files

1. **`vm-evasion.reg`** - Registry tweaks for VM detection evasion
2. **`vm-evasion-setup.ps1`** - PowerShell script for comprehensive setup
3. **`autounattend.xml`** (example below) - Unattended installation file

## How to Use

### Method 1: Add to Custom ISO (Recommended)

1. **Extract Windows 11 ISO**:
   ```bash
   mkdir win11-custom
   7z x Win11_23H2.iso -owin11-custom/
   ```

2. **Copy scripts to ISO**:
   ```bash
   cp vm-evasion.reg win11-custom/sources/$OEM$/$1/Setup/
   cp vm-evasion-setup.ps1 win11-custom/sources/$OEM$/$1/Setup/
   ```

3. **Create autounattend.xml** (see example below) and place in ISO root:
   ```bash
   cp autounattend.xml win11-custom/
   ```

4. **Recreate ISO**:
   ```bash
   genisoimage -b boot/etfsboot.com -no-emul-boot -boot-load-size 8 \
     -iso-level 4 -udf -joliet -D -N -relaxed-filenames \
     -o Win11_Custom.iso win11-custom/
   ```

### Method 2: Manual Run After Installation

1. Mount the VirtIO drivers ISO in your VM
2. Copy `vm-evasion.reg` and `vm-evasion-setup.ps1` to the VM
3. Right-click `vm-evasion.reg` → Merge
4. Run PowerShell as Administrator:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\vm-evasion-setup.ps1
   ```
5. Reboot

## Autounattend.xml Example

Create this file to automate the script execution during Windows installation:

```xml
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral"
                   versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <FirstLogonCommands>
                <!-- Import registry tweaks -->
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>reg import C:\Windows\Setup\Scripts\vm-evasion.reg</CommandLine>
                    <Description>Import VM evasion registry settings</Description>
                </SynchronousCommand>

                <!-- Run PowerShell setup script -->
                <SynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <CommandLine>powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\vm-evasion-setup.ps1</CommandLine>
                    <Description>Run VM evasion setup script</Description>
                </SynchronousCommand>
            </FirstLogonCommands>

            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
                <SkipUserOOBE>true</SkipUserOOBE>
                <SkipMachineOOBE>true</SkipMachineOOBE>
            </OOBE>

            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Name>User</Name>
                        <Password>
                            <Value></Value>
                            <PlainText>true</PlainText>
                        </Password>
                        <Group>Administrators</Group>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
        </component>
    </settings>

    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral"
                   versionScope="nonSxS">
            <!-- Copy scripts to a permanent location -->
            <CopyProfile>true</CopyProfile>
        </component>
    </settings>
</unattend>
```

## What These Scripts Do

### Registry Tweaks (`vm-evasion.reg`)
- Disables Hyper-V guest services
- Removes VM software registry entries
- Spoofs BIOS/System information (backup to SMBIOS)
- Disables VM-specific Windows features
- Optimizes GPU passthrough settings
- Disables telemetry (reduces fingerprinting)

### PowerShell Script (`vm-evasion-setup.ps1`)
- Disables and stops VM-related services
- Cleans up VMware/VirtualBox registry keys
- Renames VirtIO network adapters to look like Intel NICs
- Updates network adapter descriptions in registry
- Checks for VM disk models
- Disables GPU TDR for better passthrough
- Checks for hypervisor presence
- Applies performance optimizations
- Provides diagnostic output

## Testing VM Detection

After running these scripts and rebooting, test with:

### PowerShell Commands
```powershell
# Should show your REAL motherboard info
Get-WmiObject -Class Win32_BIOS

# Should NOT show "True" for HypervisorPresent
Get-WmiObject -Class Win32_ComputerSystem | Select-Object HypervisorPresent

# Should show real manufacturer (not QEMU/VMware)
Get-WmiObject -Class Win32_ComputerSystem | Select-Object Manufacturer,Model

# Check network adapters (should not mention VirtIO)
Get-NetAdapter | Select-Object Name,InterfaceDescription
```

### Third-Party Tools
- **Pafish**: https://github.com/a0rtega/pafish
- **Al-Khaser**: https://github.com/LordNoteworthy/al-khaser
- **CPU-Z**: https://www.cpuid.com/ (should NOT show "Hypervisor")

## Important Notes

1. **VM XML Configuration First**: These scripts complement but don't replace your VM XML SMBIOS settings. The XML configuration is MORE important.

2. **GPU Passthrough**: These scripts assume you have a dedicated GPU passed through. Some checks may fail without it.

3. **Anti-Cheat Specific**:
   - **EasyAntiCheat/BattlEye**: Should work with these scripts + proper VM XML
   - **Vanguard (Valorant)**: May still detect - requires kernel-level evasion
   - **ESEA/FACEIT**: Usually works

4. **Legal Notice**: Use these scripts for legitimate purposes only (testing, development, running your own software). Circumventing licensing or ToS may violate laws.

5. **Backup**: Always backup before importing registry files.

## Troubleshooting

**Scripts don't run during installation**:
- Verify `autounattend.xml` is in the root of the ISO
- Check script paths match your ISO structure
- Look for errors in `C:\Windows\Panther\setupact.log`

**Still detected as VM**:
- Verify SMBIOS settings in your VM XML (most important!)
- Run `virsh dumpxml win11 | grep -E "hypervisor|vendor_id|smbios"`
- Check if `kvm hidden=on` is set
- Test with detection tools listed above

**Network adapter still shows VirtIO**:
- Run the PowerShell script again as Administrator
- Manually rename in Device Manager
- Check if driver was reinstalled

## Integration with Your Setup

Your VM XML already has excellent detection evasion configured:
- ✅ KVM hidden
- ✅ Custom Hyper-V vendor ID
- ✅ Real SMBIOS (Gigabyte B550 AORUS ELITE V2)
- ✅ Custom MAC address
- ✅ GPU passthrough
- ✅ Host CPU passthrough

These Windows scripts add an additional layer by cleaning up any VM traces that Windows itself might expose.

## Additional Resources

- VM Detection Evasion Guide: `../docs/VM_DETECTION_EVASION.md`
- WENDELL METHOD Documentation: `../docs/WENDELL_METHOD.md`
- r/VFIO Wiki: https://www.reddit.com/r/VFIO/wiki/
- Level1Techs Forum: https://forum.level1techs.com/c/linux/vfio/

