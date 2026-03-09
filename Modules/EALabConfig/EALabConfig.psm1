<#
.SYNOPSIS
    Configuration management module for Enterprise Admin Lab.

.DESCRIPTION
    Provides functions to read, validate, and manage lab configuration files.
    Global defaults are stored in Config\defaults.json. Per-lab configs are
    stored in Labs\<name>.json (script-relative). vmRootPath in defaults.json
    is the Hyper-V host storage root used in Phase 3 provisioning.

.NOTES
    Author: viralarchitect
    Module: EALabConfig
#>

Set-StrictMode -Version Latest

# Module-level paths
$script:configDir = Join-Path $PSScriptRoot '..\..\Config'
$script:labsDir   = Join-Path $PSScriptRoot '..\..\Labs'

<#
.SYNOPSIS
    Gets the path to the default configuration file.

.DESCRIPTION
    Returns the full path to Config\defaults.json relative to the project root.

.OUTPUTS
    System.String - Full path to defaults.json.

.EXAMPLE
    $configPath = Get-EALabConfigPath
#>
function Get-EALabConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $configPath = Join-Path $script:configDir 'defaults.json'
    return (Resolve-Path -LiteralPath $configPath -ErrorAction SilentlyContinue).Path
}

<#
.SYNOPSIS
    Reads and returns the default lab configuration.

.DESCRIPTION
    Parses Config\defaults.json and returns the configuration as a PSCustomObject.
    Optionally accepts a custom path to load a different configuration file.

.PARAMETER ConfigPath
    Optional path to a custom JSON configuration file. Defaults to Config\defaults.json.

.OUTPUTS
    PSCustomObject - Parsed configuration object.

.EXAMPLE
    $config = Get-EALabDefaultConfig

.EXAMPLE
    $config = Get-EALabDefaultConfig -ConfigPath 'C:\Labs\mylab.json'
#>
function Get-EALabDefaultConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigPath
    )

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $script:configDir 'defaults.json'
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Error "Configuration file not found: $ConfigPath"
        return $null
    }

    try {
        $rawContent = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
        $config = $rawContent | ConvertFrom-Json

        # Migration guard: warn if legacy Phase 1 baseImages.windowsServer key is present
        if ($null -ne $config.baseImages -and
            $config.baseImages.PSObject.Properties.Name -contains 'windowsServer') {
            Write-Warning ("defaults.json contains the legacy 'baseImages.windowsServer' key from Phase 1. " +
                "This key has been replaced by 'windowsServer2019' and 'windowsServer2022'. " +
                "Please update your defaults.json. Continuing with legacy config.")
        }

        return $config
    }
    catch {
        Write-Error "Failed to read configuration file '$ConfigPath': $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Validates the global defaults configuration object (private).

.DESCRIPTION
    Checks that defaults.json contains all required keys and that values meet
    basic constraints. Returns an array of validation findings.
    This is the Phase 1 validator, retained internally for dashboard use.

.PARAMETER Config
    The defaults configuration object (PSCustomObject from ConvertFrom-Json).

.OUTPUTS
    PSCustomObject[] - Array with Name, Status, Message properties.
#>
function Test-EALabDefaultConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    $results = [System.Collections.ArrayList]::new()

    # Required top-level keys
    $requiredKeys = @('version', 'labsPath', 'logsPath', 'minimumDiskSpaceGB', 'defaultHardware')

    foreach ($key in $requiredKeys) {
        if ($null -eq $Config.$key) {
            [void]$results.Add([PSCustomObject]@{
                Name    = "Config.$key"
                Status  = 'Failed'
                Message = "Required configuration key '$key' is missing."
            })
        }
        else {
            [void]$results.Add([PSCustomObject]@{
                Name    = "Config.$key"
                Status  = 'Passed'
                Message = "Key '$key' is present."
            })
        }
    }

    # Validate defaultHardware sub-keys if present
    if ($null -ne $Config.defaultHardware) {
        $hardwareKeys = @('cpuCount', 'memoryMB', 'diskSizeGB')
        foreach ($hKey in $hardwareKeys) {
            if ($null -eq $Config.defaultHardware.$hKey) {
                [void]$results.Add([PSCustomObject]@{
                    Name    = "Config.defaultHardware.$hKey"
                    Status  = 'Failed'
                    Message = "Required hardware key '$hKey' is missing."
                })
            }
            else {
                [void]$results.Add([PSCustomObject]@{
                    Name    = "Config.defaultHardware.$hKey"
                    Status  = 'Passed'
                    Message = "Hardware key '$hKey' = $($Config.defaultHardware.$hKey)"
                })
            }
        }
    }

    # Validate minimumDiskSpaceGB is a positive number
    if ($null -ne $Config.minimumDiskSpaceGB) {
        if ($Config.minimumDiskSpaceGB -le 0) {
            [void]$results.Add([PSCustomObject]@{
                Name    = 'Config.minimumDiskSpaceGB.Range'
                Status  = 'Warning'
                Message = "minimumDiskSpaceGB is $($Config.minimumDiskSpaceGB) - should be a positive value."
            })
        }
    }

    return $results.ToArray()
}

# ============================================================================
# Per-lab config validation (Phase 2)
# ============================================================================

function Resolve-EALabVmRoles {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmDefinition
    )

    $resolvedRoles = [System.Collections.Generic.List[string]]::new()
    if ($VmDefinition.PSObject.Properties.Name -contains 'roles' -and $null -ne $VmDefinition.roles) {
        foreach ($roleEntry in @($VmDefinition.roles)) {
            $roleText = [string]$roleEntry
            if (-not [string]::IsNullOrWhiteSpace($roleText)) {
                $resolvedRoles.Add($roleText)
            }
        }
    }

    if ($resolvedRoles.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$VmDefinition.role)) {
        $resolvedRoles.Add([string]$VmDefinition.role)
    }

    return @($resolvedRoles.ToArray())
}

function Test-EALabGuestConfiguration {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    $errors = [System.Collections.ArrayList]::new()
    $ipPattern = '^\d{1,3}(\.\d{1,3}){3}$'
    $allowedRoles = @('DomainController', 'MemberServer', 'Client', 'Linux', 'DNS')
    $hasNewForestDc = $false

    for ($vmIdx = 0; $vmIdx -lt @($Config.vmDefinitions).Count; $vmIdx++) {
        $vm = $Config.vmDefinitions[$vmIdx]
        $field = "vmDefinitions[$vmIdx]"
        $vmRoles = @(Resolve-EALabVmRoles -VmDefinition $vm)
        $isDomainController = $vmRoles -contains 'DomainController'

        foreach ($roleText in $vmRoles) {
            if ($roleText -notin $allowedRoles) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.roles"
                    Message = "role '$roleText' is not supported. Allowed values: $($allowedRoles -join ', ')."
                })
            }
        }

        if ($isDomainController) {
            $deploymentType = ''
            if ($vm.PSObject.Properties.Name -contains 'domainController' -and
                $null -ne $vm.domainController -and
                $vm.domainController.PSObject.Properties.Name -contains 'deploymentType' -and
                -not [string]::IsNullOrWhiteSpace([string]$vm.domainController.deploymentType)) {
                $deploymentType = [string]$vm.domainController.deploymentType
                if ($deploymentType -notin @('newForest', 'additional')) {
                    [void]$errors.Add([PSCustomObject]@{
                        Field = "$field.domainController.deploymentType"
                        Message = "deploymentType must be 'newForest' or 'additional'."
                    })
                }
            }

            if ($deploymentType -eq 'additional' -and
                ($null -eq $vm.domainController -or
                $vm.domainController.PSObject.Properties.Name -notcontains 'sourceDcName' -or
                [string]::IsNullOrWhiteSpace([string]$vm.domainController.sourceDcName))) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.domainController.sourceDcName"
                    Message = 'sourceDcName is required when deploymentType is additional.'
                })
            }

            if ([string]::IsNullOrWhiteSpace($deploymentType) -or $deploymentType -eq 'newForest') {
                $hasNewForestDc = $true
            }
        }

        if ($vm.PSObject.Properties.Name -notcontains 'guestConfiguration' -or $null -eq $vm.guestConfiguration) {
            continue
        }

        if ($vm.guestConfiguration.PSObject.Properties.Name -contains 'computerName' -and
            -not [string]::IsNullOrWhiteSpace([string]$vm.guestConfiguration.computerName)) {
            $computerName = [string]$vm.guestConfiguration.computerName
            if ($computerName.Length -gt 15) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.guestConfiguration.computerName"
                    Message = 'computerName must be 15 characters or less.'
                })
            }
        }

        $networkCfg = if ($vm.guestConfiguration.PSObject.Properties.Name -contains 'network') { $vm.guestConfiguration.network } else { $null }
        if ($null -ne $networkCfg) {
            if ($networkCfg.PSObject.Properties.Name -contains 'ipAddress' -and
                -not [string]::IsNullOrWhiteSpace([string]$networkCfg.ipAddress) -and [string]$networkCfg.ipAddress -notmatch $ipPattern) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.guestConfiguration.network.ipAddress"
                    Message = "ipAddress '$($networkCfg.ipAddress)' is not valid."
                })
            }
            if ($networkCfg.PSObject.Properties.Name -contains 'subnetMask' -and
                -not [string]::IsNullOrWhiteSpace([string]$networkCfg.subnetMask) -and [string]$networkCfg.subnetMask -notmatch $ipPattern) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.guestConfiguration.network.subnetMask"
                    Message = "subnetMask '$($networkCfg.subnetMask)' is not valid."
                })
            }
            if ($networkCfg.PSObject.Properties.Name -contains 'gateway' -and
                -not [string]::IsNullOrWhiteSpace([string]$networkCfg.gateway) -and [string]$networkCfg.gateway -notmatch $ipPattern) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.guestConfiguration.network.gateway"
                    Message = "gateway '$($networkCfg.gateway)' is not valid."
                })
            }

            if ($networkCfg.PSObject.Properties.Name -contains 'dnsServers' -and $null -ne $networkCfg.dnsServers) {
                $dnsIdx = 0
                foreach ($dns in @($networkCfg.dnsServers)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$dns) -and [string]$dns -notmatch $ipPattern) {
                        [void]$errors.Add([PSCustomObject]@{
                            Field = "$field.guestConfiguration.network.dnsServers[$dnsIdx]"
                            Message = "DNS server '$dns' is not valid."
                        })
                    }
                    $dnsIdx++
                }
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$vm.staticIP) -and
                $networkCfg.PSObject.Properties.Name -contains 'ipAddress' -and
                -not [string]::IsNullOrWhiteSpace([string]$networkCfg.ipAddress) -and
                [string]$vm.staticIP -ne [string]$networkCfg.ipAddress) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.guestConfiguration.network.ipAddress"
                    Message = 'guestConfiguration.network.ipAddress must match staticIP when both are specified.'
                })
            }
        }

        if ($vm.guestConfiguration.PSObject.Properties.Name -contains 'domainJoin' -and $null -ne $vm.guestConfiguration.domainJoin) {
            $domainJoin = $vm.guestConfiguration.domainJoin
            $hasInlineDomainAdmin = ($Config.PSObject.Properties.Name -contains 'credentials' -and
                $null -ne $Config.credentials -and
                $Config.credentials.PSObject.Properties.Name -contains 'domainAdminUser' -and
                $Config.credentials.PSObject.Properties.Name -contains 'domainAdminPassword' -and
                -not [string]::IsNullOrWhiteSpace([string]$Config.credentials.domainAdminUser) -and
                -not [string]::IsNullOrWhiteSpace([string]$Config.credentials.domainAdminPassword))
            if ($domainJoin.PSObject.Properties.Name -contains 'enabled' -and
                $domainJoin.enabled -eq $true -and
                ($domainJoin.PSObject.Properties.Name -notcontains 'credentialRef' -or [string]::IsNullOrWhiteSpace([string]$domainJoin.credentialRef)) -and
                -not $hasInlineDomainAdmin) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.guestConfiguration.domainJoin.credentialRef"
                    Message = 'credentialRef is required when domainJoin.enabled is true unless credentials.domainAdminUser/domainAdminPassword are set.'
                })
            }

            if ($domainJoin.PSObject.Properties.Name -contains 'enabled' -and $domainJoin.enabled -eq $true -and $isDomainController) {
                [void]$errors.Add([PSCustomObject]@{
                    Field = "$field.guestConfiguration.domainJoin.enabled"
                    Message = 'DomainController VMs should not set domainJoin.enabled to true.'
                })
            }
        }
    }

    if (-not $hasNewForestDc) {
        [void]$errors.Add([PSCustomObject]@{
            Field = 'vmDefinitions'
            Message = 'At least one DomainController VM must deploy as newForest.'
        })
    }

    return $errors.ToArray()
}

<#
.SYNOPSIS
    Validates a per-lab configuration object.

.DESCRIPTION
    Full schema validation for per-lab JSON configs stored in Labs\<name>.json.
    Returns a structured result indicating validity and a list of errors.

.PARAMETER Config
    A PSCustomObject representing the lab configuration (from ConvertFrom-Json).

.OUTPUTS
    PSCustomObject - { IsValid: bool; Errors: @({ Field: string; Message: string }) }

.EXAMPLE
    $labConfig = Get-EALabConfig -LabName 'my-lab'
    $result = Test-EALabConfig -Config $labConfig
    if (-not $result.IsValid) { $result.Errors | Format-Table }
#>
function Test-EALabConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    $errors = [System.Collections.ArrayList]::new()

    function Add-Error {
        param([string]$Field, [string]$Message)
        [void]$errors.Add([PSCustomObject]@{ Field = $Field; Message = $Message })
    }

    # --- metadata ---
    if ($null -eq $Config.metadata) {
        Add-Error 'metadata' 'metadata section is required.'
    } else {
        $slug = $Config.metadata.name
        if ([string]::IsNullOrWhiteSpace($slug)) {
            Add-Error 'metadata.name' 'Lab name (slug) is required.'
        } elseif ($slug -notmatch '^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$') {
            Add-Error 'metadata.name' "Lab name '$slug' is invalid. Must match ^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$."
        }
        if ([string]::IsNullOrWhiteSpace($Config.metadata.displayName)) {
            Add-Error 'metadata.displayName' 'displayName is required.'
        }
    }

    # --- domain ---
    if ($null -eq $Config.domain) {
        Add-Error 'domain' 'domain section is required.'
    } else {
        if ([string]::IsNullOrWhiteSpace($Config.domain.fqdn)) {
            Add-Error 'domain.fqdn' 'domain.fqdn is required.'
        }
        if ([string]::IsNullOrWhiteSpace($Config.domain.netbiosName)) {
            Add-Error 'domain.netbiosName' 'domain.netbiosName is required.'
        }
        $validLevels = @('Win2012R2', 'Win2016', 'Win2019')
        if ($null -eq $Config.domain.functionalLevel -or $Config.domain.functionalLevel -notin $validLevels) {
            Add-Error 'domain.functionalLevel' "domain.functionalLevel must be one of: $($validLevels -join ', ')."
        }
    }

    # --- networks ---
    if ($null -eq $Config.networks -or @($Config.networks).Count -eq 0) {
        Add-Error 'networks' 'At least one network definition is required.'
    } else {
        $networkNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $validSwitchTypes = @('Internal', 'Private', 'External')
        $cidrPattern = '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$'

        $netIdx = 0
        foreach ($net in $Config.networks) {
            $field = "networks[$netIdx]"
            if ([string]::IsNullOrWhiteSpace($net.name)) {
                Add-Error "$field.name" 'Network name is required.'
            } elseif (-not $networkNames.Add($net.name)) {
                Add-Error "$field.name" "Duplicate network name '$($net.name)'."
            }
            if ($null -eq $net.switchType -or $net.switchType -notin $validSwitchTypes) {
                Add-Error "$field.switchType" "switchType must be one of: $($validSwitchTypes -join ', ')."
            }
            if ([string]::IsNullOrWhiteSpace($net.subnet)) {
                Add-Error "$field.subnet" 'subnet (CIDR) is required.'
            } elseif ($net.subnet -notmatch $cidrPattern) {
                Add-Error "$field.subnet" "subnet '$($net.subnet)' is not valid CIDR notation (e.g. 192.168.10.0/24)."
            }
            if (-not [string]::IsNullOrWhiteSpace($net.gateway)) {
                if ($net.gateway -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
                    Add-Error "$field.gateway" "gateway '$($net.gateway)' is not a valid IP address."
                }
            }
            if ($null -ne $net.dnsServers) {
                $dnsIdx = 0
                foreach ($dns in $net.dnsServers) {
                    if ($dns -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
                        Add-Error "$field.dnsServers[$dnsIdx]" "DNS server '$dns' is not a valid IP address."
                    }
                    $dnsIdx++
                }
            }
            $netIdx++
        }
    }

    # --- vmDefinitions ---
    if ($null -eq $Config.vmDefinitions -or @($Config.vmDefinitions).Count -eq 0) {
        Add-Error 'vmDefinitions' 'At least one VM definition is required.'
    } else {
        $vmNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $validRoles = @('DomainController', 'MemberServer', 'Client', 'Linux')
        $validOS    = @('windowsServer2019', 'windowsServer2022', 'windowsServer2025', 'windowsClient', 'linux')
        $validGens  = @(1, 2)
        $validPhaseTags = @('dc-primary', 'dc-additional', 'member', 'client', 'linux')
        $validBootstraps = @('winrm', 'ssh', 'none')
        $definedNetworks = if ($null -ne $Config.networks) { @($Config.networks | ForEach-Object { $_.name }) } else { @() }
        $hasDC = $false

        $vmIdx = 0
        foreach ($vm in $Config.vmDefinitions) {
            $field = "vmDefinitions[$vmIdx]"

            if ([string]::IsNullOrWhiteSpace($vm.name)) {
                Add-Error "$field.name" 'VM name is required.'
            } elseif (-not $vmNames.Add($vm.name)) {
                Add-Error "$field.name" "Duplicate VM name '$($vm.name)'."
            }

            if ($null -eq $vm.role -or $vm.role -notin $validRoles) {
                Add-Error "$field.role" "role must be one of: $($validRoles -join ', ')."
            } elseif ($vm.role -eq 'DomainController') {
                $hasDC = $true
            }

            if ($null -eq $vm.os -or $vm.os -notin $validOS) {
                Add-Error "$field.os" "os must be one of: $($validOS -join ', ')."
            }
            else {
                $isWindowsVm = [string]$vm.os -like 'windows*'
                if ($isWindowsVm) {
                    $baseImages = if ($null -ne $Config.baseImages) { $Config.baseImages } else { $null }
                    $baseImageEntry = if ($null -ne $baseImages) { $baseImages.PSObject.Properties[[string]$vm.os] } else { $null }
                    $isoPath = if ($null -ne $baseImageEntry -and $null -ne $baseImageEntry.Value) {
                        [string]$baseImageEntry.Value.isoPath
                    } else {
                        ''
                    }

                    if ([string]::IsNullOrWhiteSpace($isoPath)) {
                        Add-Error "$field.os" "Windows VM '$($vm.name)' requires baseImages.$($vm.os).isoPath to be configured."
                    }
                    elseif (-not (Test-Path -LiteralPath $isoPath -PathType Leaf)) {
                        Add-Error "$field.os" "Windows VM '$($vm.name)' references ISO path '$isoPath', but the file was not found."
                    }
                }
            }

            $gen = $vm.generation
            if ($null -eq $gen -or $gen -notin $validGens) {
                Add-Error "$field.generation" 'generation must be 1 or 2.'
            } else {
                # secureBoot only on Gen 2
                if ($vm.secureBoot -eq $true -and $gen -ne 2) {
                    Add-Error "$field.secureBoot" 'secureBoot can only be enabled on Generation 2 VMs.'
                }
                # tpmEnabled only on Gen 2 + windowsClient
                if ($vm.tpmEnabled -eq $true) {
                    if ($gen -ne 2 -or $vm.os -ne 'windowsClient') {
                        Add-Error "$field.tpmEnabled" 'tpmEnabled is only supported on Generation 2 windowsClient VMs.'
                    }
                }
            }

            # Hardware range checks
            if ($null -ne $vm.hardware) {
                if ($null -ne $vm.hardware.cpuCount -and ($vm.hardware.cpuCount -lt 1 -or $vm.hardware.cpuCount -gt 16)) {
                    Add-Error "$field.hardware.cpuCount" "cpuCount $($vm.hardware.cpuCount) is out of range (1-16)."
                }
                if ($null -ne $vm.hardware.memoryMB -and ($vm.hardware.memoryMB -lt 512 -or $vm.hardware.memoryMB -gt 65536)) {
                    Add-Error "$field.hardware.memoryMB" "memoryMB $($vm.hardware.memoryMB) is out of range (512-65536)."
                }
                if ($null -ne $vm.hardware.diskSizeGB -and ($vm.hardware.diskSizeGB -lt 20 -or $vm.hardware.diskSizeGB -gt 2000)) {
                    Add-Error "$field.hardware.diskSizeGB" "diskSizeGB $($vm.hardware.diskSizeGB) is out of range (20-2000)."
                }
            }

            # Network reference must exist
            if ([string]::IsNullOrWhiteSpace($vm.network)) {
                Add-Error "$field.network" 'network reference is required.'
            } elseif ($vm.network -notin $definedNetworks) {
                Add-Error "$field.network" "network '$($vm.network)' is not defined in the networks array."
            }

            # Static IP format if provided
            if (-not [string]::IsNullOrWhiteSpace($vm.staticIP)) {
                if ($vm.staticIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
                    Add-Error "$field.staticIP" "staticIP '$($vm.staticIP)' is not a valid IP address."
                }
            }

            if ($null -ne $vm.orchestration) {
                if (-not [string]::IsNullOrWhiteSpace([string]$vm.orchestration.phaseTag) -and
                    [string]$vm.orchestration.phaseTag -notin $validPhaseTags) {
                    Add-Error "$field.orchestration.phaseTag" "phaseTag must be one of: $($validPhaseTags -join ', ')."
                }

                if (-not [string]::IsNullOrWhiteSpace([string]$vm.orchestration.bootstrap) -and
                    [string]$vm.orchestration.bootstrap -notin $validBootstraps) {
                    Add-Error "$field.orchestration.bootstrap" "bootstrap must be one of: $($validBootstraps -join ', ')."
                }
            }

            $vmIdx++
        }

        if (-not $hasDC) {
            Add-Error 'vmDefinitions' 'At least one VM with role DomainController is required.'
        }
    }

    # --- globalHardwareDefaults ---
    if ($null -ne $Config.globalHardwareDefaults) {
        $ghd = $Config.globalHardwareDefaults
        if ($null -ne $ghd.cpuCount -and ($ghd.cpuCount -lt 1 -or $ghd.cpuCount -gt 16)) {
            Add-Error 'globalHardwareDefaults.cpuCount' "cpuCount $($ghd.cpuCount) is out of range (1-16)."
        }
        if ($null -ne $ghd.memoryMB -and ($ghd.memoryMB -lt 512 -or $ghd.memoryMB -gt 65536)) {
            Add-Error 'globalHardwareDefaults.memoryMB' "memoryMB $($ghd.memoryMB) is out of range (512-65536)."
        }
        if ($null -ne $ghd.diskSizeGB -and ($ghd.diskSizeGB -lt 20 -or $ghd.diskSizeGB -gt 2000)) {
            Add-Error 'globalHardwareDefaults.diskSizeGB' "diskSizeGB $($ghd.diskSizeGB) is out of range (20-2000)."
        }
    }

    # --- orchestration ---
    if ($null -ne $Config.orchestration) {
        $validEngines = @('hybrid', 'hyperv-only')
        $validControllers = @('shared')
        $validStrategies = @('per-lab')

        if (-not [string]::IsNullOrWhiteSpace([string]$Config.orchestration.engine) -and
            [string]$Config.orchestration.engine -notin $validEngines) {
            Add-Error 'orchestration.engine' "orchestration.engine must be one of: $($validEngines -join ', ')."
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$Config.orchestration.controller) -and
            [string]$Config.orchestration.controller -notin $validControllers) {
            Add-Error 'orchestration.controller' "orchestration.controller must be one of: $($validControllers -join ', ')."
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$Config.orchestration.inventoryStrategy) -and
            [string]$Config.orchestration.inventoryStrategy -notin $validStrategies) {
            Add-Error 'orchestration.inventoryStrategy' "orchestration.inventoryStrategy must be one of: $($validStrategies -join ', ')."
        }
    }

    if ($Config.PSObject.Properties.Name -contains 'credentials' -and $null -ne $Config.credentials) {
        foreach ($credentialField in @('localAdminRef', 'domainAdminRef', 'dsrmRef')) {
            if ($Config.credentials.PSObject.Properties.Name -contains $credentialField) {
                $value = [string]$Config.credentials.$credentialField
                if (-not [string]::IsNullOrWhiteSpace($value) -and $value.Length -lt 3) {
                    Add-Error "credentials.$credentialField" "$credentialField must be at least 3 characters when provided."
                }
            }
        }

        foreach ($userPasswordPair in @(
                @{ UserField = 'localAdminUser'; PasswordField = 'localAdminPassword' },
                @{ UserField = 'domainAdminUser'; PasswordField = 'domainAdminPassword' }
            )) {
            $userField = [string]$userPasswordPair.UserField
            $passwordField = [string]$userPasswordPair.PasswordField
            $hasUser = ($Config.credentials.PSObject.Properties.Name -contains $userField -and -not [string]::IsNullOrWhiteSpace([string]$Config.credentials.$userField))
            $hasPassword = ($Config.credentials.PSObject.Properties.Name -contains $passwordField -and -not [string]::IsNullOrWhiteSpace([string]$Config.credentials.$passwordField))

            if ($hasUser -xor $hasPassword) {
                Add-Error "credentials.$userField" "$userField and $passwordField must be provided together when using inline credentials."
            }
        }
    }

    if ($Config.PSObject.Properties.Name -contains 'guestDefaults' -and $null -ne $Config.guestDefaults) {
        if ($Config.guestDefaults.PSObject.Properties.Name -contains 'installTimeoutMinutes' -and $null -ne $Config.guestDefaults.installTimeoutMinutes) {
            $installTimeout = [int]$Config.guestDefaults.installTimeoutMinutes
            if ($installTimeout -lt 5 -or $installTimeout -gt 480) {
                Add-Error 'guestDefaults.installTimeoutMinutes' 'installTimeoutMinutes must be between 5 and 480.'
            }
        }

        if ($Config.guestDefaults.PSObject.Properties.Name -contains 'postInstallTimeoutMinutes' -and $null -ne $Config.guestDefaults.postInstallTimeoutMinutes) {
            $postInstallTimeout = [int]$Config.guestDefaults.postInstallTimeoutMinutes
            if ($postInstallTimeout -lt 5 -or $postInstallTimeout -gt 480) {
                Add-Error 'guestDefaults.postInstallTimeoutMinutes' 'postInstallTimeoutMinutes must be between 5 and 480.'
            }
        }
    }

    foreach ($guestError in @(Test-EALabGuestConfiguration -Config $Config)) {
        Add-Error $guestError.Field $guestError.Message
    }

    return [PSCustomObject]@{
        IsValid = ($errors.Count -eq 0)
        Errors  = $errors.ToArray()
    }
}

# ============================================================================
# Per-lab CRUD operations (Phase 2)
# ============================================================================

<#
.SYNOPSIS
    Reads and parses a per-lab configuration file.

.PARAMETER LabName
    The slug name of the lab (maps to Labs\<name>.json).

.OUTPUTS
    PSCustomObject - Parsed lab configuration.

.EXAMPLE
    $lab = Get-EALabConfig -LabName 'basic-ad-lab'
#>
function Get-EALabConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName
    )

    $labFile = Join-Path $script:labsDir "$LabName.json"
    if (-not (Test-Path -LiteralPath $labFile)) {
        Write-Error "Lab configuration not found: $labFile"
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $labFile -Raw -ErrorAction Stop
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-Error "Failed to read lab config '$labFile': $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
    Lists all saved per-lab configurations.

.DESCRIPTION
    Scans the Labs\ directory (excluding the templates\ subdirectory) and returns
    summary metadata for each lab config found.

.OUTPUTS
    PSCustomObject[] - Array of { Name; DisplayName; VMCount; LastModified } objects.

.EXAMPLE
    Get-EALabConfigs | Format-Table -AutoSize
#>
function Get-EALabConfigs {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    if (-not (Test-Path -LiteralPath $script:labsDir)) {
        return @()
    }

    $results = [System.Collections.ArrayList]::new()

    Get-ChildItem -LiteralPath $script:labsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -notlike '*\templates' -and $_.DirectoryName -notlike '*/templates' } |
        ForEach-Object {
            $file = $_
            try {
                $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
                $cfg = $raw | ConvertFrom-Json
                [void]$results.Add([PSCustomObject]@{
                    Name         = $file.BaseName
                    DisplayName  = if ($null -ne $cfg.metadata -and -not [string]::IsNullOrWhiteSpace($cfg.metadata.displayName)) { $cfg.metadata.displayName } else { $file.BaseName }
                    VMCount      = if ($null -ne $cfg.vmDefinitions) { @($cfg.vmDefinitions).Count } else { 0 }
                    LastModified = $file.LastWriteTime
                })
            }
            catch {
                Write-Warning "Could not read lab config '$($file.FullName)': $($_.Exception.Message)"
            }
        }

    return $results.ToArray()
}

<#
.SYNOPSIS
    Saves a per-lab configuration object to disk after validation.

.PARAMETER LabName
    The slug name of the lab.

.PARAMETER Config
    The PSCustomObject to save.

.OUTPUTS
    System.Boolean - $true if saved successfully, $false on validation failure.

.EXAMPLE
    Set-EALabConfig -LabName 'my-lab' -Config $labObj
#>
function Set-EALabConfig {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    $validation = Test-EALabConfig -Config $Config
    if (-not $validation.IsValid) {
        Write-Error "Lab config validation failed for '$LabName':"
        foreach ($err in $validation.Errors) {
            Write-Error "  [$($err.Field)] $($err.Message)"
        }
        return $false
    }

    # Stamp modified timestamp
    if ($null -ne $Config.metadata) {
        $Config.metadata | Add-Member -MemberType NoteProperty -Name 'modified' -Value (Get-Date -Format 'o') -Force
    }

    $labFile = Join-Path $script:labsDir "$LabName.json"

    if (-not (Test-Path -LiteralPath $script:labsDir)) {
        [void](New-Item -ItemType Directory -Path $script:labsDir -Force -ErrorAction Stop)
    }

    if ($PSCmdlet.ShouldProcess($labFile, 'Write lab configuration')) {
        try {
            $Config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $labFile -Encoding UTF8 -Force
            return $true
        }
        catch {
            Write-Error "Failed to write lab config '$labFile': $($_.Exception.Message)"
            return $false
        }
    }
    return $false
}

<#
.SYNOPSIS
    Creates a new per-lab configuration from a template or blank scaffold.

.PARAMETER LabName
    Slug name for the new lab.

.PARAMETER TemplateName
    Optional template name from Labs\templates\. Defaults to 'basic-ad-lab'.

.OUTPUTS
    PSCustomObject - The newly created lab config.

.EXAMPLE
    New-EALabConfig -LabName 'test-lab-01'
    New-EALabConfig -LabName 'test-lab-02' -TemplateName 'basic-ad-lab'
#>
function New-EALabConfig {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName,

        [Parameter(Mandatory = $false)]
        [string]$TemplateName = 'basic-ad-lab'
    )

    $labFile = Join-Path $script:labsDir "$LabName.json"
    if (Test-Path -LiteralPath $labFile) {
        Write-Error "Lab '$LabName' already exists at '$labFile'. Use Set-EALabConfig to update it."
        return $null
    }

    $templatesDir = Join-Path $script:labsDir 'templates'
    $templateFile = Join-Path $templatesDir "$TemplateName.json"

    if (-not (Test-Path -LiteralPath $templateFile)) {
        Write-Warning "Template '$TemplateName' not found at '$templateFile'. Creating blank scaffold."
        $newConfig = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                name        = $LabName
                displayName = $LabName
                description = ''
                author      = ''
                created     = (Get-Date -Format 'o')
                modified    = (Get-Date -Format 'o')
                tags        = @()
            }
            domain = [PSCustomObject]@{
                fqdn              = 'lab.local'
                netbiosName       = 'LAB'
                functionalLevel   = 'Win2019'
                safeModePassword  = ''
            }
            networks = @()
            baseImages = [PSCustomObject]@{
                windowsServer2019 = [PSCustomObject]@{ isoPath = ''; productKey = '' }
                windowsServer2022 = [PSCustomObject]@{ isoPath = ''; productKey = '' }
                windowsServer2025 = [PSCustomObject]@{ isoPath = ''; productKey = '' }
                windowsClient     = [PSCustomObject]@{ isoPath = ''; productKey = '' }
                linux             = [PSCustomObject]@{ isoPath = ''; distro = '' }
            }
            vmDefinitions         = @()
            globalHardwareDefaults = [PSCustomObject]@{ cpuCount = 2; memoryMB = 2048; diskSizeGB = 60 }
            storage = [PSCustomObject]@{ vmRootPath = 'E:\EALabs'; logsPath = 'E:\EALabs\Logs' }
            orchestration = [PSCustomObject]@{
                engine               = 'hybrid'
                controller           = 'shared'
                postProvisionEnabled = $true
                playbookProfile      = 'default-ad'
                inventoryStrategy    = 'per-lab'
                skipOrchestration    = $false
            }
        }
    }
    else {
        $raw = Get-Content -LiteralPath $templateFile -Raw -ErrorAction Stop
        $newConfig = $raw | ConvertFrom-Json
        # Stamp with new name/timestamps
        if ($null -ne $newConfig.metadata) {
            $newConfig.metadata | Add-Member -MemberType NoteProperty -Name 'name'    -Value $LabName           -Force
            $newConfig.metadata | Add-Member -MemberType NoteProperty -Name 'created' -Value (Get-Date -Format 'o') -Force
            $newConfig.metadata | Add-Member -MemberType NoteProperty -Name 'modified' -Value (Get-Date -Format 'o') -Force
        }
        if ($null -eq $newConfig.orchestration) {
            $newConfig | Add-Member -MemberType NoteProperty -Name 'orchestration' -Value ([PSCustomObject]@{
                engine               = 'hybrid'
                controller           = 'shared'
                postProvisionEnabled = $true
                playbookProfile      = 'default-ad'
                inventoryStrategy    = 'per-lab'
                skipOrchestration    = $false
            }) -Force
        }
    }

    if (-not (Test-Path -LiteralPath $script:labsDir)) {
        [void](New-Item -ItemType Directory -Path $script:labsDir -Force)
    }

    if ($PSCmdlet.ShouldProcess($labFile, 'Create lab configuration')) {
        $newConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $labFile -Encoding UTF8 -Force
    }

    return $newConfig
}

<#
.SYNOPSIS
    Removes a per-lab configuration file.

.PARAMETER LabName
    The slug name of the lab to remove.

.PARAMETER Force
    Suppress the ShouldProcess confirmation prompt.

.EXAMPLE
    Remove-EALabConfig -LabName 'my-old-lab'
    Remove-EALabConfig -LabName 'my-old-lab' -Force
#>
function Remove-EALabConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $labFile = Join-Path $script:labsDir "$LabName.json"
    if (-not (Test-Path -LiteralPath $labFile)) {
        Write-Error "Lab '$LabName' not found at '$labFile'."
        return
    }

    $confirmAction = if ($Force) { $true } else { $PSCmdlet.ShouldProcess($labFile, 'Delete lab configuration') }

    if ($confirmAction) {
        try {
            Remove-Item -LiteralPath $labFile -Force -ErrorAction Stop
            Write-Verbose "Removed lab configuration: $labFile"
        }
        catch {
            Write-Error "Failed to remove lab config '$labFile': $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
    Duplicates an existing lab configuration under a new name.

.PARAMETER SourceLabName
    Name of the lab to copy.

.PARAMETER NewLabName
    Name for the new lab.

.OUTPUTS
    PSCustomObject - The duplicated lab config.

.EXAMPLE
    Copy-EALabConfig -SourceLabName 'basic-ad-lab' -NewLabName 'test-ad-lab'
#>
function Copy-EALabConfig {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SourceLabName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NewLabName
    )

    $sourceFile = Join-Path $script:labsDir "$SourceLabName.json"
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        Write-Error "Source lab '$SourceLabName' not found at '$sourceFile'."
        return $null
    }

    $destFile = Join-Path $script:labsDir "$NewLabName.json"
    if (Test-Path -LiteralPath $destFile) {
        Write-Error "Destination lab '$NewLabName' already exists. Choose a different name."
        return $null
    }

    $raw = Get-Content -LiteralPath $sourceFile -Raw -ErrorAction Stop
    $newConfig = $raw | ConvertFrom-Json

    if ($null -ne $newConfig.metadata) {
        $newConfig.metadata | Add-Member -MemberType NoteProperty -Name 'name'     -Value $NewLabName         -Force
        $newConfig.metadata | Add-Member -MemberType NoteProperty -Name 'created'  -Value (Get-Date -Format 'o') -Force
        $newConfig.metadata | Add-Member -MemberType NoteProperty -Name 'modified' -Value (Get-Date -Format 'o') -Force
    }

    if ($PSCmdlet.ShouldProcess($destFile, 'Create copied lab configuration')) {
        $newConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $destFile -Encoding UTF8 -Force
    }

    return $newConfig
}

# Export module members
Export-ModuleMember -Function @(
    'Get-EALabConfigPath',
    'Get-EALabDefaultConfig',
    'Test-EALabConfig',
    'Get-EALabConfig',
    'Get-EALabConfigs',
    'Set-EALabConfig',
    'New-EALabConfig',
    'Remove-EALabConfig',
    'Copy-EALabConfig'
)
