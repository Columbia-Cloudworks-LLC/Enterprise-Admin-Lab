<#
.SYNOPSIS
    Unattended installation artifact generation for Enterprise Admin Lab.
#>

Set-StrictMode -Version Latest

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
    if ($null -ne $LocalAdminCredential) {
        $adminUser = [string]$LocalAdminCredential.UserName
        $adminPasswordPlain = [string]$LocalAdminCredential.GetNetworkCredential().Password
    }

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
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>2</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
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

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        [void](New-Item -ItemType Directory -Path $OutputPath -Force -ErrorAction Stop)
    }

    $stagingPath = Join-Path $OutputPath 'Autounattend'
    if (-not (Test-Path -LiteralPath $stagingPath)) {
        [void](New-Item -ItemType Directory -Path $stagingPath -Force -ErrorAction Stop)
    }

    Copy-Item -LiteralPath $UnattendXmlPath -Destination (Join-Path $stagingPath 'Autounattend.xml') -Force -ErrorAction Stop
    $isoPath = Join-Path $OutputPath "$VmName-autounattend.iso"

    $oscdimg = Get-Command -Name 'oscdimg.exe' -ErrorAction SilentlyContinue
    if ($null -eq $oscdimg) {
        throw "oscdimg.exe was not found in PATH. Install Windows ADK or disable unattended media generation."
    }

    $arguments = @(
        '-n',
        '-m',
        $stagingPath,
        $isoPath
    )

    $process = Start-Process -FilePath $oscdimg.Source -ArgumentList $arguments -PassThru -NoNewWindow -Wait
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

    $dvdDrives = @(Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue)
    if (-not [string]::IsNullOrWhiteSpace([string]$OsIsoPath)) {
        if ($dvdDrives.Count -eq 0) {
            Add-VMDvdDrive -VMName $VmName -Path $OsIsoPath -ErrorAction Stop | Out-Null
            $dvdDrives = @(Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue)
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
}

Export-ModuleMember -Function @(
    'New-EALabVmUnattendXml',
    'New-EALabUnattendMedia',
    'Set-EALabVmInstallMedia'
)
