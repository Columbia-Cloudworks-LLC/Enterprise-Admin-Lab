<#
.SYNOPSIS
    Unattended installation artifact generation for Enterprise Admin Lab.
#>

Set-StrictMode -Version Latest

function Get-EALabOscdimgCandidatePaths {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $candidates = [System.Collections.Generic.List[string]]::new()
    $baseRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    foreach ($baseRoot in $baseRoots) {
        foreach ($kitsVersion in @('10', '11')) {
            foreach ($arch in @('amd64', 'x86')) {
                [void]$candidates.Add(
                    (Join-Path $baseRoot "Windows Kits\$kitsVersion\Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe")
                )
            }
        }
    }

    foreach ($registryPath in @(
            'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
        )) {
        if (-not (Test-Path -LiteralPath $registryPath)) {
            continue
        }

        $roots = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $roots) {
            continue
        }

        foreach ($prop in $roots.PSObject.Properties) {
            if ($prop.Name -notmatch '^KitsRoot\d+$') {
                continue
            }

            $kitsRoot = [string]$prop.Value
            if ([string]::IsNullOrWhiteSpace($kitsRoot)) {
                continue
            }

            foreach ($arch in @('amd64', 'x86')) {
                [void]$candidates.Add(
                    (Join-Path $kitsRoot "Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe")
                )
            }
        }
    }

    return @($candidates | Select-Object -Unique)
}

function Get-EALabOscdimgPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $oscdimg = Get-Command -Name 'oscdimg.exe' -ErrorAction SilentlyContinue
    if ($null -ne $oscdimg -and -not [string]::IsNullOrWhiteSpace([string]$oscdimg.Source)) {
        return [string]$oscdimg.Source
    }

    $resolved = Get-EALabOscdimgCandidatePaths |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    if (-not [string]::IsNullOrWhiteSpace([string]$resolved)) {
        return [string]$resolved
    }

    return $null
}

function Initialize-EALabArtifactDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$VmName
    )

    $artifactRoot = Join-Path $Context.LabRoot 'Artifacts'
    $vmArtifactPath = Join-Path (Join-Path $artifactRoot 'Unattend') $VmName
    if (-not (Test-Path -LiteralPath $vmArtifactPath)) {
        [void](New-Item -ItemType Directory -Path $vmArtifactPath -Force -ErrorAction Stop)
    }
    return $vmArtifactPath
}

function New-EALabVmUnattendXml {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmDefinition,

        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $false)]
        [PSCredential]$LocalAdminCredential
    )

    $artifactPath = Initialize-EALabArtifactDirectory -Context $Context -VmName $VmName
    $unattendPath = Join-Path $artifactPath 'Autounattend.xml'
    $guestConfig = if ($VmDefinition.PSObject.Properties.Name -contains 'guestConfiguration' -and $null -ne $VmDefinition.guestConfiguration) { $VmDefinition.guestConfiguration } else { [PSCustomObject]@{} }
    $guestDefaults = if ($Context.Config.PSObject.Properties.Name -contains 'guestDefaults' -and $null -ne $Context.Config.guestDefaults) { $Context.Config.guestDefaults } else { [PSCustomObject]@{} }

    $computerName = if ($guestConfig.PSObject.Properties.Name -contains 'computerName' -and -not [string]::IsNullOrWhiteSpace([string]$guestConfig.computerName)) {
        [string]$guestConfig.computerName
    } else {
        $VmName
    }
    $locale = if ($guestConfig.PSObject.Properties.Name -contains 'locale' -and -not [string]::IsNullOrWhiteSpace([string]$guestConfig.locale)) {
        [string]$guestConfig.locale
    } elseif ($guestDefaults.PSObject.Properties.Name -contains 'locale' -and -not [string]::IsNullOrWhiteSpace([string]$guestDefaults.locale)) {
        [string]$guestDefaults.locale
    } else {
        'en-US'
    }
    $timeZone = if ($guestConfig.PSObject.Properties.Name -contains 'timeZone' -and -not [string]::IsNullOrWhiteSpace([string]$guestConfig.timeZone)) {
        [string]$guestConfig.timeZone
    } elseif ($guestDefaults.PSObject.Properties.Name -contains 'timeZone' -and -not [string]::IsNullOrWhiteSpace([string]$guestDefaults.timeZone)) {
        [string]$guestDefaults.timeZone
    } else {
        'UTC'
    }

    $adminUser = ''
    $adminPasswordPlain = ''
    if ($null -eq $LocalAdminCredential) {
        throw "A local admin credential is required to generate unattended setup for VM '$VmName'."
    }

    $adminUser = [string]$LocalAdminCredential.UserName
    $adminPasswordPlain = [string]$LocalAdminCredential.GetNetworkCredential().Password
    if ([string]::IsNullOrWhiteSpace($adminUser) -or [string]::IsNullOrWhiteSpace($adminPasswordPlain)) {
        throw "Local admin credential for VM '$VmName' is missing username or password."
    }

    $installImageName = if ($guestConfig.PSObject.Properties.Name -contains 'installImageName' -and -not [string]::IsNullOrWhiteSpace([string]$guestConfig.installImageName)) {
        [string]$guestConfig.installImageName
    } elseif ($guestDefaults.PSObject.Properties.Name -contains 'installImageName' -and -not [string]::IsNullOrWhiteSpace([string]$guestDefaults.installImageName)) {
        [string]$guestDefaults.installImageName
    } else {
        ''
    }

    $installFromXml = @'
          <InstallFrom>
            <MetaData wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
              <Key>/IMAGE/INDEX</Key>
              <Value>1</Value>
            </MetaData>
          </InstallFrom>
'@
    if (-not [string]::IsNullOrWhiteSpace($installImageName)) {
        $installFromXml = @"
          <InstallFrom>
            <MetaData wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
              <Key>/IMAGE/NAME</Key>
              <Value>$installImageName</Value>
            </MetaData>
          </InstallFrom>
"@
    }

    $gen = if ($VmDefinition.PSObject.Properties.Name -contains 'generation' -and $null -ne $VmDefinition.generation) { [int]$VmDefinition.generation } else { 2 }
    $isUefi = ($gen -eq 2)

    if ($isUefi) {
        $diskConfigXml = @'
      <DiskConfiguration>
        <WillShowUI>OnError</WillShowUI>
        <Disk wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Type>EFI</Type>
              <Size>260</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Type>MSR</Type>
              <Size>128</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Format>FAT32</Format>
              <Label>System</Label>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>3</PartitionID>
              <Format>NTFS</Format>
              <Letter>C</Letter>
              <Label>Windows</Label>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
__INSTALL_FROM__
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
'@
    }
    else {
        $diskConfigXml = @'
      <DiskConfiguration>
        <WillShowUI>OnError</WillShowUI>
        <Disk wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Type>Primary</Type>
              <Size>500</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Format>NTFS</Format>
              <Label>System</Label>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
              <Format>NTFS</Format>
              <Letter>C</Letter>
              <Label>Windows</Label>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
__INSTALL_FROM__
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>2</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
'@
    }

    $diskConfigXml = $diskConfigXml.Replace('__INSTALL_FROM__', $installFromXml)

    $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>$locale</UILanguage>
      </SetupUILanguage>
      <InputLocale>$locale</InputLocale>
      <SystemLocale>$locale</SystemLocale>
      <UILanguage>$locale</UILanguage>
      <UILanguageFallback>$locale</UILanguageFallback>
      <UserLocale>$locale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
$diskConfigXml
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>$computerName</ComputerName>
      <TimeZone>$timeZone</TimeZone>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <InputLocale>$locale</InputLocale>
      <SystemLocale>$locale</SystemLocale>
      <UILanguage>$locale</UILanguage>
      <UserLocale>$locale</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <AutoLogon>
        <Enabled>true</Enabled>
        <Username>$adminUser</Username>
        <Password>
          <Value>$adminPasswordPlain</Value>
          <PlainText>true</PlainText>
        </Password>
        <LogonCount>1</LogonCount>
      </AutoLogon>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <Name>$adminUser</Name>
            <Group>Administrators</Group>
            <Password>
              <Value>$adminPasswordPlain</Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
    </component>
  </settings>
</unattend>
"@

    Set-Content -LiteralPath $unattendPath -Value $xmlContent -Encoding UTF8
    return $unattendPath
}

function New-EALabUnattendMedia {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [string]$UnattendXmlPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $UnattendXmlPath -PathType Leaf)) {
        throw "Unattend XML was not found at '$UnattendXmlPath'."
    }

    $unattendFile = Get-Item -LiteralPath $UnattendXmlPath -ErrorAction Stop
    if ($unattendFile.Length -le 0) {
        throw "Unattend XML at '$UnattendXmlPath' is empty."
    }

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        [void](New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop)
    }

    $stagingPath = Join-Path $OutputPath ("Autounattend-{0}" -f $VmName)
    if (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
    }
    [void](New-Item -ItemType Directory -Path $stagingPath -Force -ErrorAction Stop)

    Copy-Item -LiteralPath $UnattendXmlPath -Destination (Join-Path $stagingPath 'Autounattend.xml') -Force -ErrorAction Stop
    $isoPath = Join-Path $OutputPath "$VmName-autounattend.iso"
    if (Test-Path -LiteralPath $isoPath -PathType Leaf) {
        Remove-Item -LiteralPath $isoPath -Force -ErrorAction Stop
    }

    $oscdimgPath = Get-EALabOscdimgPath

    if ([string]::IsNullOrWhiteSpace([string]$oscdimgPath)) {
        throw "oscdimg.exe was not found. Install Windows ADK Deployment Tools."
    }

    $arguments = @(
        '-n',
        '-m',
        $stagingPath,
        $isoPath
    )

    $process = Start-Process -FilePath $oscdimgPath -ArgumentList $arguments -PassThru -NoNewWindow -Wait
    if ($process.ExitCode -ne 0) {
        throw "Failed to build unattended ISO for '$VmName'. oscdimg exit code: $($process.ExitCode)."
    }

    return $isoPath
}

function Set-EALabVmInstallMedia {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $false)]
        [string]$OsIsoPath,

        [Parameter(Mandatory = $false)]
        [string]$UnattendIsoPath
    )

    $dvdDrives = @(Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue |
            Sort-Object ControllerNumber, ControllerLocation)
    if (-not [string]::IsNullOrWhiteSpace([string]$OsIsoPath)) {
        if ($dvdDrives.Count -eq 0) {
            Add-VMDvdDrive -VMName $VmName -Path $OsIsoPath -ErrorAction Stop | Out-Null
            $dvdDrives = @(Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue |
                    Sort-Object ControllerNumber, ControllerLocation)
        } else {
            Set-VMDvdDrive -VMName $VmName -ControllerNumber $dvdDrives[0].ControllerNumber -ControllerLocation $dvdDrives[0].ControllerLocation -Path $OsIsoPath -ErrorAction Stop | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$UnattendIsoPath)) {
        if ($dvdDrives.Count -lt 2) {
            Add-VMDvdDrive -VMName $VmName -Path $UnattendIsoPath -ErrorAction Stop | Out-Null
        } else {
            Set-VMDvdDrive -VMName $VmName -ControllerNumber $dvdDrives[1].ControllerNumber -ControllerLocation $dvdDrives[1].ControllerLocation -Path $UnattendIsoPath -ErrorAction Stop | Out-Null
        }
    }

    $attachedDrives = @(Get-VMDvdDrive -VMName $VmName -ErrorAction Stop |
            Sort-Object ControllerNumber, ControllerLocation)
    $osDrive = $null
    $unattendDrive = $null

    if (-not [string]::IsNullOrWhiteSpace([string]$OsIsoPath)) {
        $osDrive = @($attachedDrives | Where-Object { [string]$_.Path -eq $OsIsoPath } | Select-Object -First 1)
        if (@($osDrive).Count -eq 0) {
            throw "OS install media was not attached correctly for VM '$VmName'. Expected path '$OsIsoPath'."
        }
        $osDrive = $osDrive[0]
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$UnattendIsoPath)) {
        $unattendDrive = @($attachedDrives | Where-Object { [string]$_.Path -eq $UnattendIsoPath } | Select-Object -First 1)
        if (@($unattendDrive).Count -eq 0) {
            throw "Unattended media was not attached correctly for VM '$VmName'. Expected path '$UnattendIsoPath'."
        }
        $unattendDrive = $unattendDrive[0]
    }

    return [PSCustomObject]@{
        VmName          = $VmName
        OsIsoPath       = if ($null -ne $osDrive) { [string]$osDrive.Path } else { '' }
        UnattendIsoPath = if ($null -ne $unattendDrive) { [string]$unattendDrive.Path } else { '' }
        OsDvdDrive      = $osDrive
        UnattendDvdDrive = $unattendDrive
        DvdDriveCount   = @($attachedDrives).Count
    }
}

Export-ModuleMember -Function @(
    'Get-EALabOscdimgPath',
    'New-EALabVmUnattendXml',
    'New-EALabUnattendMedia',
    'Set-EALabVmInstallMedia'
)
