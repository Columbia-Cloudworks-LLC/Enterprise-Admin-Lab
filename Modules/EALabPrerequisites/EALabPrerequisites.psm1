<#
.SYNOPSIS
    Prerequisite checking and remediation module for Enterprise Admin Lab.

.DESCRIPTION
    Provides functions to verify system prerequisites for running Hyper-V based
    Active Directory lab environments. Checks include Windows features, PowerShell
    modules, system resources, and administrative privileges.

    Each check returns a structured result object with an optional Remediation
    scriptblock that the UI or CLI can invoke to fix the issue.

.NOTES
    Author: viralarchitect
    Module: EALabPrerequisites
#>

Set-StrictMode -Version Latest

# Import config module
Import-Module (Join-Path $PSScriptRoot '..\EALabConfig\EALabConfig.psd1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EALabCredentials\EALabCredentials.psd1') -Force

# --------------------------------------------------------------------------
# Private helper: create a prerequisite result object
# --------------------------------------------------------------------------
function New-PrereqResult {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet('System', 'Hyper-V', 'Modules', 'Storage', 'Network', 'Provisioning')]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Passed', 'Failed', 'Warning')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [scriptblock]$Remediation = $null
    )

    return [PSCustomObject]@{
        Name        = $Name
        Category    = $Category
        Status      = $Status
        Message     = $Message
        Remediation = $Remediation
    }
}

# Build all known oscdimg.exe locations from environment + registry.
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

# --------------------------------------------------------------------------
# Private check functions
# --------------------------------------------------------------------------

function Test-AdminElevation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        return (New-PrereqResult -Name 'Administrator Elevation' -Category 'System' -Status 'Passed' `
            -Message 'Running with administrator privileges.')
    }
    else {
        return (New-PrereqResult -Name 'Administrator Elevation' -Category 'System' -Status 'Failed' `
            -Message 'Not running as administrator. Restart PowerShell with "Run as Administrator".' `
            -Remediation {
                Write-Warning "Please close this session and relaunch PowerShell as Administrator."
                Write-Warning "Right-click PowerShell -> Run as Administrator"
            })
    }
}

function Test-PowerShellVersion {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $currentVersion = $PSVersionTable.PSVersion

    if ($currentVersion -ge [System.Version]'5.1') {
        return (New-PrereqResult -Name 'PowerShell Version' -Category 'System' -Status 'Passed' `
            -Message "PowerShell $($currentVersion.ToString()) detected (>= 5.1 required).")
    }
    else {
        return (New-PrereqResult -Name 'PowerShell Version' -Category 'System' -Status 'Failed' `
            -Message "PowerShell $($currentVersion.ToString()) detected. Version 5.1 or later is required.")
    }
}

function Test-WindowsEdition {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $edition = $osInfo.Caption

        # Check for Pro, Enterprise, Education (editions that support Hyper-V)
        $supportedEditions = @('Pro', 'Enterprise', 'Education', 'Server')
        $isSupported = $false
        foreach ($ed in $supportedEditions) {
            if ($edition -like "*$ed*") {
                $isSupported = $true
                break
            }
        }

        if ($isSupported) {
            return (New-PrereqResult -Name 'Windows Edition' -Category 'System' -Status 'Passed' `
                -Message "Windows edition '$edition' supports Hyper-V.")
        }
        else {
            return (New-PrereqResult -Name 'Windows Edition' -Category 'System' -Status 'Failed' `
                -Message "Windows edition '$edition' may not support Hyper-V. Pro, Enterprise, or Education is required.")
        }
    }
    catch {
        return (New-PrereqResult -Name 'Windows Edition' -Category 'System' -Status 'Warning' `
            -Message "Could not determine Windows edition: $($_.Exception.Message)")
    }
}

function Test-HyperVFeature {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V' -ErrorAction Stop

        if ($null -ne $feature -and $feature.State -eq 'Enabled') {
            return (New-PrereqResult -Name 'Hyper-V Feature' -Category 'Hyper-V' -Status 'Passed' `
                -Message 'Hyper-V Windows feature is enabled.')
        }
        else {
            $state = if ($null -ne $feature) { $feature.State } else { 'Not Found' }
            return (New-PrereqResult -Name 'Hyper-V Feature' -Category 'Hyper-V' -Status 'Failed' `
                -Message "Hyper-V feature state: $state. Must be enabled." `
                -Remediation {
                    Write-Host '[INFO] Enabling Hyper-V feature (requires restart)...'
                    try {
                        Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -All -NoRestart -ErrorAction Stop
                        Write-Host '[OK] Hyper-V feature enabled. A system restart is required to complete installation.'
                        Write-Warning 'Please restart your computer and run this check again.'
                    }
                    catch {
                        Write-Error "Failed to enable Hyper-V: $($_.Exception.Message)"
                    }
                })
        }
    }
    catch {
        return (New-PrereqResult -Name 'Hyper-V Feature' -Category 'Hyper-V' -Status 'Failed' `
            -Message "Could not check Hyper-V feature: $($_.Exception.Message). Are you running as Administrator?" `
            -Remediation {
                Write-Host '[INFO] Attempting to enable Hyper-V feature...'
                try {
                    Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -All -NoRestart -ErrorAction Stop
                    Write-Host '[OK] Hyper-V feature enabled. A system restart is required.'
                }
                catch {
                    Write-Error "Failed to enable Hyper-V: $($_.Exception.Message)"
                }
            })
    }
}

function Test-HyperVManagementTools {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $toolsFeature = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-Tools-All' -ErrorAction Stop

        if ($null -ne $toolsFeature -and $toolsFeature.State -eq 'Enabled') {
            return (New-PrereqResult -Name 'Hyper-V Management Tools' -Category 'Hyper-V' -Status 'Passed' `
                -Message 'Hyper-V management tools are enabled.')
        }
        else {
            $state = if ($null -ne $toolsFeature) { $toolsFeature.State } else { 'Not Found' }
            return (New-PrereqResult -Name 'Hyper-V Management Tools' -Category 'Hyper-V' -Status 'Failed' `
                -Message "Hyper-V management tools state: $state." `
                -Remediation {
                    Write-Host '[INFO] Enabling Hyper-V management tools...'
                    try {
                        Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-Tools-All' -All -NoRestart -ErrorAction Stop
                        Write-Host '[OK] Hyper-V management tools enabled.'
                    }
                    catch {
                        Write-Error "Failed to enable Hyper-V tools: $($_.Exception.Message)"
                    }
                })
        }
    }
    catch {
        return (New-PrereqResult -Name 'Hyper-V Management Tools' -Category 'Hyper-V' -Status 'Warning' `
            -Message "Could not check Hyper-V management tools: $($_.Exception.Message)")
    }
}

function Test-HyperVPowerShellModule {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $module = Get-Module -ListAvailable -Name 'Hyper-V' -ErrorAction SilentlyContinue

    if ($null -ne $module) {
        $version = ($module | Select-Object -First 1).Version
        return (New-PrereqResult -Name 'Hyper-V PowerShell Module' -Category 'Hyper-V' -Status 'Passed' `
            -Message "Hyper-V PowerShell module v$version is available.")
    }
    else {
        return (New-PrereqResult -Name 'Hyper-V PowerShell Module' -Category 'Hyper-V' -Status 'Failed' `
            -Message 'Hyper-V PowerShell module is not available. Enable the Hyper-V feature first.' `
            -Remediation {
                Write-Host '[INFO] The Hyper-V PowerShell module is installed as part of the Hyper-V feature.'
                Write-Host '[INFO] Enabling Microsoft-Hyper-V-Management-PowerShell...'
                try {
                    Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-Management-PowerShell' -All -NoRestart -ErrorAction Stop
                    Write-Host '[OK] Hyper-V PowerShell module enabled.'
                }
                catch {
                    Write-Error "Failed to enable Hyper-V PowerShell module: $($_.Exception.Message)"
                }
            })
    }
}

function Test-ImportExcelModule {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $module = Get-Module -ListAvailable -Name 'ImportExcel' -ErrorAction SilentlyContinue

    if ($null -ne $module) {
        $version = ($module | Select-Object -First 1).Version
        return (New-PrereqResult -Name 'ImportExcel Module' -Category 'Modules' -Status 'Passed' `
            -Message "ImportExcel module v$version is available.")
    }
    else {
        return (New-PrereqResult -Name 'ImportExcel Module' -Category 'Modules' -Status 'Failed' `
            -Message 'ImportExcel module is not installed. Required for lab report exports.' `
            -Remediation {
                Write-Host '[INFO] Installing ImportExcel module from PSGallery...'
                try {
                    Install-Module -Name ImportExcel -Force -Scope CurrentUser -ErrorAction Stop
                    Write-Host '[OK] ImportExcel module installed successfully.'
                }
                catch {
                    Write-Error "Failed to install ImportExcel: $($_.Exception.Message)"
                }
            })
    }
}

function Test-DiskSpace {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $config = Get-EALabDefaultConfig
        $minimumGB = 50
        if ($null -ne $config -and $null -ne $config.minimumDiskSpaceGB) {
            $minimumGB = $config.minimumDiskSpaceGB
        }

        $systemDrive = $env:SystemDrive
        if (-not $systemDrive) { $systemDrive = 'C:' }

        $driveInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction Stop
        $freeGB = [math]::Round($driveInfo.FreeSpace / 1GB, 1)

        if ($freeGB -ge $minimumGB) {
            return (New-PrereqResult -Name 'Disk Space' -Category 'Storage' -Status 'Passed' `
                -Message "$($freeGB) GB free on $systemDrive (minimum: $($minimumGB) GB).")
        }
        else {
            return (New-PrereqResult -Name 'Disk Space' -Category 'Storage' -Status 'Warning' `
                -Message "$($freeGB) GB free on $systemDrive. Recommended minimum is $($minimumGB) GB for lab VMs.")
        }
    }
    catch {
        return (New-PrereqResult -Name 'Disk Space' -Category 'Storage' -Status 'Warning' `
            -Message "Could not check disk space: $($_.Exception.Message)")
    }
}

function Test-DefaultVSwitch {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        # Only check if Hyper-V module is available
        $hvModule = Get-Module -ListAvailable -Name 'Hyper-V' -ErrorAction SilentlyContinue
        if ($null -eq $hvModule) {
            return (New-PrereqResult -Name 'Default vSwitch' -Category 'Network' -Status 'Warning' `
                -Message 'Cannot check vSwitches - Hyper-V module not available. Install Hyper-V first.')
        }

        $switches = Get-VMSwitch -ErrorAction Stop
        if ($null -ne $switches -and @($switches).Count -gt 0) {
            $switchNames = ($switches | ForEach-Object { $_.Name }) -join ', '
            return (New-PrereqResult -Name 'Default vSwitch' -Category 'Network' -Status 'Passed' `
                -Message "Found $(@($switches).Count) vSwitch(es): $switchNames")
        }
        else {
            return (New-PrereqResult -Name 'Default vSwitch' -Category 'Network' -Status 'Warning' `
                -Message 'No virtual switches found. A vSwitch will be created during lab setup.')
        }
    }
    catch {
        return (New-PrereqResult -Name 'Default vSwitch' -Category 'Network' -Status 'Warning' `
            -Message "Could not enumerate vSwitches: $($_.Exception.Message)")
    }
}

function Test-TerraformCLI {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $tfOutput = & terraform --version 2>&1
        if ($LASTEXITCODE -ne 0 -or $null -eq $tfOutput) {
            throw 'terraform exited with non-zero code'
        }
        $versionLine = ($tfOutput | Select-String 'Terraform v(\d+\.\d+)').Matches
        if ($null -ne $versionLine -and $versionLine.Count -gt 0) {
            $verString = $versionLine[0].Groups[1].Value
            $version = [System.Version]$verString
            if ($version -ge [System.Version]'1.0') {
                return (New-PrereqResult -Name 'Terraform CLI' -Category 'Provisioning' -Status 'Passed' `
                    -Message "Terraform v$verString detected (>= 1.0 required).")
            }
            else {
                return (New-PrereqResult -Name 'Terraform CLI' -Category 'Provisioning' -Status 'Warning' `
                    -Message "Terraform v$verString detected but >= 1.0 is required. Please upgrade.")
            }
        }
        return (New-PrereqResult -Name 'Terraform CLI' -Category 'Provisioning' -Status 'Passed' `
            -Message 'Terraform CLI detected.')
    }
    catch {
        return (New-PrereqResult -Name 'Terraform CLI' -Category 'Provisioning' -Status 'Warning' `
            -Message 'Terraform CLI not found. Install from https://developer.hashicorp.com/terraform/downloads or via winget install Hashicorp.Terraform. (Not required for Phase 2.)' `
            -Remediation {
                Write-Host '[INFO] Installing Terraform via winget...'
                try {
                    & winget install --id Hashicorp.Terraform --exact --accept-source-agreements --accept-package-agreements
                    if ($LASTEXITCODE -ne 0) {
                        throw "winget exited with code $LASTEXITCODE"
                    }
                    Write-Host '[OK] Terraform installation completed.'
                }
                catch {
                    throw "Failed to install Terraform: $($_.Exception.Message)"
                }
            })
    }
}

function Test-DockerDesktop {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Check if Docker Desktop is installed
    $dockerInstalled = $false
    $dockerInstallPaths = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe')
    )
    foreach ($path in $dockerInstallPaths) {
        if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) {
            $dockerInstalled = $true
            break
        }
    }

    if (-not $dockerInstalled) {
        return (New-PrereqResult -Name 'Docker Desktop' -Category 'Provisioning' -Status 'Warning' `
            -Message 'Docker Desktop is not installed. Install from https://www.docker.com/products/docker-desktop or via winget install Docker.DockerDesktop. (Not required for Phase 2.)' `
            -Remediation {
                Write-Host '[INFO] Installing Docker Desktop via winget...'
                try {
                    & winget install --id Docker.DockerDesktop --exact --accept-source-agreements --accept-package-agreements
                    if ($LASTEXITCODE -ne 0) {
                        throw "winget exited with code $LASTEXITCODE"
                    }
                    Write-Host '[OK] Docker Desktop installation completed.'
                }
                catch {
                    throw "Failed to install Docker Desktop: $($_.Exception.Message)"
                }
            })
    }

    # Check if Docker service is running
    try {
        $dockerVersion = & docker --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            return (New-PrereqResult -Name 'Docker Desktop' -Category 'Provisioning' -Status 'Passed' `
                -Message "Docker Desktop installed and CLI available. $dockerVersion")
        }
        else {
            return (New-PrereqResult -Name 'Docker Desktop' -Category 'Provisioning' -Status 'Warning' `
                -Message 'Docker Desktop is installed but the Docker daemon is not running. Start Docker Desktop. (Not required for Phase 2.)')
        }
    }
    catch {
        return (New-PrereqResult -Name 'Docker Desktop' -Category 'Provisioning' -Status 'Warning' `
            -Message 'Docker Desktop is installed but could not contact the Docker daemon. Ensure Docker Desktop is running. (Not required for Phase 2.)')
    }
}

function Test-OscdimgTool {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $oscdimgPath = Get-EALabOscdimgPath
        if (-not [string]::IsNullOrWhiteSpace([string]$oscdimgPath)) {
            return (New-PrereqResult -Name 'Oscdimg Tool' -Category 'Provisioning' -Status 'Passed' `
                -Message "oscdimg.exe detected at '$oscdimgPath'.")
        }

        return (New-PrereqResult -Name 'Oscdimg Tool' -Category 'Provisioning' -Status 'Warning' `
            -Message 'oscdimg.exe not found. Install Windows ADK with Deployment Tools. Required for unattended media generation during VM provisioning.' `
            -Remediation {
                $foundExe = Get-EALabOscdimgPath
                if ([string]::IsNullOrWhiteSpace([string]$foundExe)) {
                    throw 'Windows ADK Deployment Tools are not installed. Install ADK: https://learn.microsoft.com/windows-hardware/get-started/adk-install'
                }

                $foundPath = Split-Path -Path $foundExe -Parent
                Write-Host "[INFO] Found oscdimg.exe at '$foundExe'."
                $machinePath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::Machine)
                if ([string]::IsNullOrWhiteSpace([string]$machinePath)) {
                    $machinePath = ''
                }

                if ($machinePath -notlike "*$foundPath*") {
                    $newMachinePath = if ([string]::IsNullOrWhiteSpace($machinePath)) { $foundPath } else { "$machinePath;$foundPath" }
                    [Environment]::SetEnvironmentVariable('Path', $newMachinePath, [EnvironmentVariableTarget]::Machine)
                    Write-Host '[OK] Added Oscdimg directory to machine PATH.'
                }
                else {
                    Write-Host '[INFO] Oscdimg directory already present in machine PATH.'
                }

                if ($env:Path -notlike "*$foundPath*") {
                    $env:Path = "$env:Path;$foundPath"
                }

                Write-Host '[OK] Oscdimg remediation completed.'
            })
    }
    catch {
        return (New-PrereqResult -Name 'Oscdimg Tool' -Category 'Provisioning' -Status 'Warning' `
            -Message "Could not validate oscdimg.exe availability: $($_.Exception.Message)")
    }
}

function Test-EALabProvisioningReadiness {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory = $false)]
        [bool]$SkipOrchestration = $false
    )

    $results = [System.Collections.ArrayList]::new()
    Write-Debug "Starting Test-EALabProvisioningReadiness for lab '$LabName' (SkipOrchestration=$SkipOrchestration)."

    if ($null -eq $Config) {
        Write-Debug "No config object provided. Loading config for lab '$LabName'."
        $Config = Get-EALabConfig -LabName $LabName
    }

    if ($null -eq $Config) {
        Write-Debug "Lab configuration for '$LabName' could not be loaded."
        [void]$results.Add((New-PrereqResult -Name 'Lab Configuration' -Category 'Provisioning' -Status 'Failed' `
            -Message "Lab '$LabName' configuration could not be loaded."))
        return $results.ToArray()
    }

    $orchestrationEnabled = $false
    if (-not $SkipOrchestration) {
        $configOrchestration = if ($Config.PSObject.Properties.Name -contains 'orchestration' -and $null -ne $Config.orchestration) {
            $Config.orchestration
        } else {
            [PSCustomObject]@{}
        }

        $engine = if (-not [string]::IsNullOrWhiteSpace([string]$configOrchestration.engine)) {
            [string]$configOrchestration.engine
        } else {
            'hybrid'
        }
        $postProvisionEnabled = if ($null -ne $configOrchestration.postProvisionEnabled) {
            [bool]$configOrchestration.postProvisionEnabled
        } else {
            $false
        }
        $configSkip = if ($null -ne $configOrchestration.skipOrchestration) {
            [bool]$configOrchestration.skipOrchestration
        } else {
            $false
        }
        $orchestrationEnabled = ($engine -eq 'hybrid') -and $postProvisionEnabled -and (-not $configSkip)
        Write-Debug "Resolved orchestration gating: Engine='$engine', PostProvisionEnabled=$postProvisionEnabled, ConfigSkip=$configSkip, EffectiveEnabled=$orchestrationEnabled."
    }

    # 1) ISO path checks for each OS that is actually used by VMs
    $usedOs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($vm in @($Config.vmDefinitions)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$vm.os)) {
            [void]$usedOs.Add([string]$vm.os)
        }
    }
    $hasWindowsGuests = ($usedOs | Where-Object { [string]$_ -like 'windows*' } | Measure-Object).Count -gt 0

    foreach ($osKey in $usedOs) {
        Write-Debug "Checking ISO path for OS key '$osKey'."
        $isoPath = $null
        if ($null -ne $Config.baseImages -and $Config.baseImages.PSObject.Properties.Name -contains $osKey) {
            $isoPath = [string]$Config.baseImages.$osKey.isoPath
        }

        if ([string]::IsNullOrWhiteSpace($isoPath)) {
            Write-Debug "ISO path for '$osKey' is missing from baseImages."
            [void]$results.Add((New-PrereqResult -Name "ISO Path ($osKey)" -Category 'Provisioning' -Status 'Failed' `
                -Message "No ISO path configured for OS '$osKey' in baseImages."))
            continue
        }

        if (Test-Path -LiteralPath $isoPath -PathType Leaf) {
            Write-Debug "ISO path exists for '$osKey': $isoPath"
            [void]$results.Add((New-PrereqResult -Name "ISO Path ($osKey)" -Category 'Provisioning' -Status 'Passed' `
                -Message "ISO found: $isoPath"))
        }
        else {
            Write-Debug "ISO path missing on disk for '$osKey': $isoPath"
            [void]$results.Add((New-PrereqResult -Name "ISO Path ($osKey)" -Category 'Provisioning' -Status 'Failed' `
                -Message "ISO not found: $isoPath"))
        }
    }

    $oscdimgCheck = Test-OscdimgTool
    if ($null -ne $oscdimgCheck) {
        if ($hasWindowsGuests -and [string]$oscdimgCheck.Status -eq 'Warning') {
            [void]$results.Add((New-PrereqResult -Name $oscdimgCheck.Name -Category $oscdimgCheck.Category -Status 'Failed' `
                -Message "Windows VM definitions require unattended media generation. $([string]$oscdimgCheck.Message)"))
        }
        else {
            [void]$results.Add($oscdimgCheck)
        }
    }

    # 2) Storage path writable + free space check
    $defaults = Get-EALabDefaultConfig
    $vmRootPath = if ($null -ne $Config.storage -and -not [string]::IsNullOrWhiteSpace([string]$Config.storage.vmRootPath)) {
        [string]$Config.storage.vmRootPath
    } elseif ($null -ne $defaults -and -not [string]::IsNullOrWhiteSpace([string]$defaults.vmRootPath)) {
        [string]$defaults.vmRootPath
    } else {
        'E:\EALabs'
    }

    try {
        if (-not (Test-Path -LiteralPath $vmRootPath)) {
            Write-Debug "Storage root path does not exist. Creating '$vmRootPath'."
            [void](New-Item -ItemType Directory -Path $vmRootPath -Force -ErrorAction Stop)
        }

        $probeFile = Join-Path $vmRootPath ".__ealab_write_test_$([guid]::NewGuid().ToString('N')).tmp"
        Set-Content -LiteralPath $probeFile -Value 'ok' -Encoding UTF8 -ErrorAction Stop
        Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue

        [void]$results.Add((New-PrereqResult -Name 'Storage Path Write Access' -Category 'Provisioning' -Status 'Passed' `
            -Message "Storage path is writable: $vmRootPath"))
    }
    catch {
        Write-Debug "Storage path write probe failed for '$vmRootPath': $($_.Exception.Message)"
        [void]$results.Add((New-PrereqResult -Name 'Storage Path Write Access' -Category 'Provisioning' -Status 'Failed' `
            -Message "Storage path is not writable: $vmRootPath. $($_.Exception.Message)"))
    }

    try {
        $root = [System.IO.Path]::GetPathRoot($vmRootPath).TrimEnd('\')
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$root'" -ErrorAction Stop
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $minimumGB = 50
        if ($null -ne $defaults -and $null -ne $defaults.minimumDiskSpaceGB) {
            $minimumGB = [double]$defaults.minimumDiskSpaceGB
        }

        if ($freeGB -ge $minimumGB) {
            [void]$results.Add((New-PrereqResult -Name 'Storage Free Space' -Category 'Provisioning' -Status 'Passed' `
                -Message "$freeGB GB free on $root (minimum: $minimumGB GB)."))
        }
        else {
            [void]$results.Add((New-PrereqResult -Name 'Storage Free Space' -Category 'Provisioning' -Status 'Warning' `
                -Message "$freeGB GB free on $root. Recommended minimum is $minimumGB GB."))
        }
    }
    catch {
        Write-Debug "Failed to query free space for '$vmRootPath': $($_.Exception.Message)"
        [void]$results.Add((New-PrereqResult -Name 'Storage Free Space' -Category 'Provisioning' -Status 'Warning' `
            -Message "Could not evaluate free space for '$vmRootPath': $($_.Exception.Message)"))
    }

    # 3) Hyper-V cmdlet availability sanity (including media and firmware)
    $requiredCmdlets = @(
        'Get-VM', 'New-VM', 'Remove-VM', 'Get-VMSwitch', 'New-VMSwitch',
        'Add-VMDvdDrive', 'Set-VMDvdDrive', 'Get-VMDvdDrive', 'Get-VMHardDiskDrive',
        'Set-VMFirmware', 'Get-VMFirmware'
    )
    foreach ($cmd in $requiredCmdlets) {
        if (Get-Command -Name $cmd -ErrorAction SilentlyContinue) {
            Write-Debug "Hyper-V cmdlet check passed: $cmd"
            [void]$results.Add((New-PrereqResult -Name "Hyper-V Cmdlet $cmd" -Category 'Provisioning' -Status 'Passed' `
                -Message "$cmd is available."))
        }
        else {
            Write-Debug "Hyper-V cmdlet check failed: $cmd"
            [void]$results.Add((New-PrereqResult -Name "Hyper-V Cmdlet $cmd" -Category 'Provisioning' -Status 'Failed' `
                -Message "$cmd is not available. Hyper-V module may be missing."))
        }
    }

    # 3b) Optional UEFI boot file check for Windows ISOs (Gen2 lab VMs require UEFI-bootable media)
    $gen2WindowsOs = @($Config.vmDefinitions) | Where-Object {
        [int]$_.generation -eq 2 -and [string]$_.os -like 'windows*'
    }
    if ($gen2WindowsOs.Count -gt 0) {
        foreach ($osKey in $usedOs) {
            if ([string]$osKey -notlike 'windows*') { continue }
            $isoPath = $null
            if ($null -ne $Config.baseImages -and $Config.baseImages.PSObject.Properties.Name -contains $osKey) {
                $isoPath = [string]$Config.baseImages.$osKey.isoPath
            }
            if ([string]::IsNullOrWhiteSpace($isoPath) -or -not (Test-Path -LiteralPath $isoPath -PathType Leaf)) {
                continue
            }
            try {
                $img = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
                $vol = $img | Get-Volume
                $efiBootPath = Join-Path ($vol.DriveLetter + ':\') 'EFI\BOOT\bootx64.efi'
                $hasUefi = Test-Path -LiteralPath $efiBootPath -PathType Leaf
                Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue | Out-Null
                if ($hasUefi) {
                    [void]$results.Add((New-PrereqResult -Name "ISO UEFI Boot ($osKey)" -Category 'Provisioning' -Status 'Passed' `
                        -Message "ISO contains UEFI boot file (bootx64.efi)."))
                }
                else {
                    [void]$results.Add((New-PrereqResult -Name "ISO UEFI Boot ($osKey)" -Category 'Provisioning' -Status 'Warning' `
                        -Message "ISO may not support UEFI boot. Gen2 VMs require EFI\BOOT\bootx64.efi. Verify Windows eval/retail ISO."))
                }
            }
            catch {
                Write-Debug "ISO UEFI check failed for '$osKey': $($_.Exception.Message)"
                [void]$results.Add((New-PrereqResult -Name "ISO UEFI Boot ($osKey)" -Category 'Provisioning' -Status 'Warning' `
                    -Message "Could not verify UEFI boot files. Ensure Windows ISO supports UEFI for Gen2 VMs: $($_.Exception.Message)"))
            }
        }
    }

    try {
        $credentialSupport = Test-EALabCredentialManagerSupport
        $supportStatus = if ([bool]$credentialSupport.Supported) { 'Passed' } else { 'Warning' }
        [void]$results.Add((New-PrereqResult -Name 'Credential Manager Support' -Category 'Provisioning' -Status $supportStatus `
            -Message ([string]$credentialSupport.Message)))
    }
    catch {
        Write-Debug "Credential manager support probe failed: $($_.Exception.Message)"
        [void]$results.Add((New-PrereqResult -Name 'Credential Manager Support' -Category 'Provisioning' -Status 'Warning' `
            -Message "Credential manager check failed: $($_.Exception.Message)"))
    }

    if ($orchestrationEnabled) {
        Write-Debug "Ansible orchestration prerequisite checks are enabled."
        # 4) Ansible availability checks
        if (Get-Command -Name 'ansible-playbook' -ErrorAction SilentlyContinue) {
            [void]$results.Add((New-PrereqResult -Name 'Ansible CLI' -Category 'Provisioning' -Status 'Passed' `
                -Message 'ansible-playbook is available.'))
        }
        else {
            [void]$results.Add((New-PrereqResult -Name 'Ansible CLI' -Category 'Provisioning' -Status 'Failed' `
                -Message 'ansible-playbook is not available in PATH. Install Ansible on the shared controller host.'))
        }

        try {
            $collectionOutput = & ansible-galaxy collection list 2>$null
            $hasAnsibleWindows = ($collectionOutput -match 'ansible\.windows')
            $hasMicrosoftAd = ($collectionOutput -match 'microsoft\.ad')

            if ($hasAnsibleWindows) {
                [void]$results.Add((New-PrereqResult -Name 'Collection ansible.windows' -Category 'Provisioning' -Status 'Passed' `
                    -Message 'ansible.windows collection detected.'))
            }
            else {
                [void]$results.Add((New-PrereqResult -Name 'Collection ansible.windows' -Category 'Provisioning' -Status 'Failed' `
                    -Message 'ansible.windows collection is missing. Install with: ansible-galaxy collection install ansible.windows'))
            }

            if ($hasMicrosoftAd) {
                [void]$results.Add((New-PrereqResult -Name 'Collection microsoft.ad' -Category 'Provisioning' -Status 'Passed' `
                    -Message 'microsoft.ad collection detected.'))
            }
            else {
                [void]$results.Add((New-PrereqResult -Name 'Collection microsoft.ad' -Category 'Provisioning' -Status 'Failed' `
                    -Message 'microsoft.ad collection is missing. Install with: ansible-galaxy collection install microsoft.ad'))
            }
        }
        catch {
            Write-Debug "Ansible collection lookup failed: $($_.Exception.Message)"
            [void]$results.Add((New-PrereqResult -Name 'Ansible collections lookup' -Category 'Provisioning' -Status 'Warning' `
                -Message "Could not query installed Ansible collections: $($_.Exception.Message)"))
        }

        # 5) Workspace writeability for generated per-lab inventory
        try {
            $defaults = Get-EALabDefaultConfig
            $vmRootPath = if ($null -ne $Config.storage -and -not [string]::IsNullOrWhiteSpace([string]$Config.storage.vmRootPath)) {
                [string]$Config.storage.vmRootPath
            } elseif ($null -ne $defaults -and -not [string]::IsNullOrWhiteSpace([string]$defaults.vmRootPath)) {
                [string]$defaults.vmRootPath
            } else {
                'E:\EALabs'
            }

            $labRootPath = Join-Path $vmRootPath $LabName
            $ansiblePath = Join-Path $labRootPath 'Ansible'
            if (-not (Test-Path -LiteralPath $ansiblePath)) {
                [void](New-Item -ItemType Directory -Path $ansiblePath -Force -ErrorAction Stop)
            }
            $probeFile = Join-Path $ansiblePath ".__ealab_ansible_write_test_$([guid]::NewGuid().ToString('N')).tmp"
            Set-Content -LiteralPath $probeFile -Value 'ok' -Encoding UTF8 -ErrorAction Stop
            Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
            [void]$results.Add((New-PrereqResult -Name 'Ansible Workspace Write Access' -Category 'Provisioning' -Status 'Passed' `
                -Message "Ansible workspace path is writable: $ansiblePath"))
        }
        catch {
            Write-Debug "Ansible workspace write probe failed: $($_.Exception.Message)"
            [void]$results.Add((New-PrereqResult -Name 'Ansible Workspace Write Access' -Category 'Provisioning' -Status 'Failed' `
                -Message "Failed to write Ansible workspace artifacts: $($_.Exception.Message)"))
        }
    }
    else {
        Write-Debug 'Ansible orchestration checks skipped for this readiness run.'
    }

    Write-Debug "Completed Test-EALabProvisioningReadiness with $($results.Count) result(s)."
    return $results.ToArray()
}

# --------------------------------------------------------------------------
# Public functions
# --------------------------------------------------------------------------

<#
.SYNOPSIS
    Runs all prerequisite checks for the Enterprise Admin Lab environment.

.DESCRIPTION
    Checks system requirements, Hyper-V features, required PowerShell modules,
    disk space, and network configuration. Returns an array of structured result
    objects, each containing Name, Category, Status, Message, and an optional
    Remediation scriptblock.

.OUTPUTS
    PSCustomObject[] - Array of prerequisite check results.

.EXAMPLE
    $results = Test-EALabPrerequisites
    $results | Format-Table Name, Status, Message -AutoSize

.EXAMPLE
    # Check and display only failures
    Test-EALabPrerequisites | Where-Object { $_.Status -eq 'Failed' }
#>
function Test-EALabPrerequisites {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $results = [System.Collections.ArrayList]::new()

    # Define checks in execution order
    $checks = @(
        { Test-AdminElevation }
        { Test-PowerShellVersion }
        { Test-WindowsEdition }
        { Test-HyperVFeature }
        { Test-HyperVManagementTools }
        { Test-HyperVPowerShellModule }
        { Test-ImportExcelModule }
        { Test-DiskSpace }
        { Test-DefaultVSwitch }
        { Test-TerraformCLI }
        { Test-DockerDesktop }
        { Test-OscdimgTool }
    )

    $totalChecks = $checks.Count
    $currentCheck = 0
    Write-Debug "Starting Test-EALabPrerequisites with $totalChecks checks."

    foreach ($check in $checks) {
        $currentCheck++
        Write-Progress -Id 100 -Activity 'Checking prerequisites' `
            -Status "Check $currentCheck of $totalChecks" `
            -PercentComplete (($currentCheck / $totalChecks) * 100)

        try {
            $result = & $check
            if ($null -ne $result) {
                [void]$results.Add($result)
                Write-Debug ("Prerequisite check {0}/{1}: {2} -> {3}" -f $currentCheck, $totalChecks, $result.Name, $result.Status)
            }
        }
        catch {
            Write-Debug "Prerequisite check $currentCheck raised an exception: $($_.Exception.Message)"
            [void]$results.Add((New-PrereqResult -Name 'Unknown Check' -Category 'System' -Status 'Warning' `
                -Message "Check failed unexpectedly: $($_.Exception.Message)"))
        }
    }

    Write-Progress -Id 100 -Activity 'Checking prerequisites' -Completed

    Write-Debug "Completed Test-EALabPrerequisites with $($results.Count) result(s)."
    return $results.ToArray()
}

<#
.SYNOPSIS
    Executes the remediation action for a failed prerequisite.

.DESCRIPTION
    Takes a prerequisite result object (from Test-EALabPrerequisites) and
    invokes its Remediation scriptblock if one is available.

.PARAMETER PrerequisiteResult
    A PSCustomObject from Test-EALabPrerequisites containing a Remediation scriptblock.

.OUTPUTS
    System.Boolean - $true if remediation was attempted, $false if no remediation available.

.EXAMPLE
    $results = Test-EALabPrerequisites
    $failed = $results | Where-Object { $_.Status -eq 'Failed' -and $null -ne $_.Remediation }
    foreach ($item in $failed) {
        Install-EALabPrerequisite -PrerequisiteResult $item
    }
#>
function Install-EALabPrerequisite {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$PrerequisiteResult
    )

    if ($null -eq $PrerequisiteResult.Remediation) {
        Write-Debug "No remediation script is available for prerequisite '$($PrerequisiteResult.Name)'."
        Write-Warning "No remediation available for '$($PrerequisiteResult.Name)'."
        return $false
    }

    Write-Host "[INFO] Remediating: $($PrerequisiteResult.Name)..." -ForegroundColor Cyan
    Write-Debug "Invoking remediation for prerequisite '$($PrerequisiteResult.Name)'."

    try {
        & $PrerequisiteResult.Remediation
        Write-Host "[OK] Remediation completed for '$($PrerequisiteResult.Name)'." -ForegroundColor Green
        Write-Debug "Remediation completed for '$($PrerequisiteResult.Name)'."
        return $true
    }
    catch {
        Write-Debug "Remediation failed for '$($PrerequisiteResult.Name)': $($_.Exception.Message)"
        Write-Error "Remediation failed for '$($PrerequisiteResult.Name)': $($_.Exception.Message)"
        return $false
    }
}

<#
.SYNOPSIS
    Generates a summary string from prerequisite check results.

.DESCRIPTION
    Counts passed, failed, and warning results and returns a formatted summary string.

.PARAMETER Results
    Array of PSCustomObject results from Test-EALabPrerequisites.

.OUTPUTS
    System.String - Formatted summary showing counts of each status.

.EXAMPLE
    $results = Test-EALabPrerequisites
    $summary = Get-EALabPrerequisiteSummary -Results $results
    Write-Host $summary
#>
function Get-EALabPrerequisiteSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Results
    )

    $passed  = @($Results | Where-Object { $_.Status -eq 'Passed' }).Count
    $failed  = @($Results | Where-Object { $_.Status -eq 'Failed' }).Count
    $warning = @($Results | Where-Object { $_.Status -eq 'Warning' }).Count
    $total   = $Results.Count

    return "$total checks complete: $passed passed, $failed failed, $warning warnings"
}

# Export module members
Export-ModuleMember -Function Test-EALabPrerequisites, Install-EALabPrerequisite, Get-EALabPrerequisiteSummary, Test-EALabProvisioningReadiness
