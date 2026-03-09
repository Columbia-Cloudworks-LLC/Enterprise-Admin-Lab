<#
.SYNOPSIS
    Hyper-V provisioning and lifecycle module for Enterprise Admin Lab.

.DESCRIPTION
    Provisions and removes lab VMs from per-lab JSON configuration files.
    Persists lifecycle state and operation logs under each lab logs path.
#>

Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..\EALabConfig\EALabConfig.psd1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EALabPrerequisites\EALabPrerequisites.psd1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EALabCredentials\EALabCredentials.psd1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EALabUnattend\EALabUnattend.psd1') -Force
Import-Module (Join-Path $PSScriptRoot '..\EALabGuestOrchestration\EALabGuestOrchestration.psd1') -Force

function Get-EALabVmInstanceNames {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmDefinition
    )

    $baseName = [string]$VmDefinition.name
    $count = if ($null -ne $VmDefinition.count -and $VmDefinition.count -gt 0) { [int]$VmDefinition.count } else { 1 }

    if ($count -le 1) {
        return @($baseName)
    }

    $names = [System.Collections.Generic.List[string]]::new()
    for ($i = 1; $i -le $count; $i++) {
        $names.Add(('{0}-{1:d2}' -f $baseName, $i))
    }
    return $names
}

function Get-EALabContext {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName
    )

    $config = Get-EALabConfig -LabName $LabName
    if ($null -eq $config) {
        throw "Lab configuration '$LabName' could not be loaded."
    }

    $defaults = Get-EALabDefaultConfig
    $vmRootPath = if ($null -ne $config.storage -and -not [string]::IsNullOrWhiteSpace($config.storage.vmRootPath)) {
        [string]$config.storage.vmRootPath
    } elseif ($null -ne $defaults -and -not [string]::IsNullOrWhiteSpace($defaults.vmRootPath)) {
        [string]$defaults.vmRootPath
    } else {
        'E:\EALabs'
    }

    $logsPath = if ($null -ne $config.storage -and -not [string]::IsNullOrWhiteSpace($config.storage.logsPath)) {
        [string]$config.storage.logsPath
    } elseif ($null -ne $defaults -and -not [string]::IsNullOrWhiteSpace($defaults.logsPath)) {
        [string]$defaults.logsPath
    } else {
        (Join-Path $vmRootPath 'Logs')
    }

    Write-Debug ("Resolved lab context for '{0}': VmRootPath='{1}', LogsPath='{2}'." -f $LabName, $vmRootPath, $logsPath)

    return [PSCustomObject]@{
        LabName    = $LabName
        Config     = $config
        VmRootPath = $vmRootPath
        LogsPath   = $logsPath
        StateFile  = (Join-Path $logsPath "$LabName.state.json")
        LogFile    = (Join-Path $logsPath "$LabName-$(Get-Date -Format 'yyyyMMdd').log")
        LabRoot    = (Join-Path $vmRootPath $LabName)
    }
}

function Initialize-EALabDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop)
    }
}

function Write-EALabLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Initialize-EALabDirectory -Path $Context.LogsPath
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'o'), $Level, $Message
    Add-Content -LiteralPath $Context.LogFile -Value $line -Encoding UTF8

    $consoleMessage = "[EALab][$($Context.LabName)][$Level] $Message"
    switch ($Level) {
        'INFO' {
            Write-Verbose $consoleMessage
            Write-Debug $consoleMessage
        }
        'WARN' {
            Write-Warning $consoleMessage
            Write-Debug $consoleMessage
        }
        'ERROR' {
            Write-Debug $consoleMessage
        }
    }
}

function Set-EALabLifecycleState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [ValidateSet('NotCreated', 'Creating', 'Running', 'Error', 'Destroying', 'Destroyed')]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$Message = '',

        [Parameter(Mandatory = $false)]
        [string]$Step = '',

        [Parameter(Mandatory = $false)]
        [string]$VmName = '',

        [Parameter(Mandatory = $false)]
        [hashtable]$Details = @{}
    )

    Initialize-EALabDirectory -Path $Context.LogsPath

    $current = $null
    if (Test-Path -LiteralPath $Context.StateFile) {
        try {
            $current = Get-Content -LiteralPath $Context.StateFile -Raw -ErrorAction Stop | ConvertFrom-Json
        }
        catch {
            Write-Debug "State file '$($Context.StateFile)' could not be parsed. Continuing with a fresh state object."
            $current = $null
        }
    }

    $state = [PSCustomObject]@{
        labName      = $Context.LabName
        status       = $Status
        message      = $Message
        step         = $Step
        vmName       = $VmName
        updated      = (Get-Date -Format 'o')
        created      = if ($null -ne $current -and $current.created) { [string]$current.created } else { (Get-Date -Format 'o') }
        operationLog = [string]$Context.LogFile
        details      = $Details
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Context.StateFile -Encoding UTF8
}

function Get-EALabVmNamesFromConfig {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )

    $vmNames = [System.Collections.Generic.List[string]]::new()
    foreach ($vmDef in @($Config.vmDefinitions)) {
        foreach ($name in (Get-EALabVmInstanceNames -VmDefinition $vmDef)) {
            $vmNames.Add($name)
        }
    }
    return @($vmNames.ToArray())
}

function Get-IsoPathForVm {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmDefinition
    )

    if ($null -eq $Config.baseImages) {
        return ''
    }

    $osKey = [string]$VmDefinition.os
    if ([string]::IsNullOrWhiteSpace($osKey)) {
        return ''
    }

    $entry = $Config.baseImages.PSObject.Properties[$osKey]
    if ($null -eq $entry -or $null -eq $entry.Value) {
        return ''
    }

    return [string]$entry.Value.isoPath
}

function Get-EALabOrchestrationSettings {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,

        [Parameter(Mandatory = $false)]
        [bool]$SkipOrchestration = $false
    )

    $defaults = Get-EALabDefaultConfig
    $defaultOrchestration = if ($null -ne $defaults -and $null -ne $defaults.defaultOrchestration) {
        $defaults.defaultOrchestration
    } else {
        [PSCustomObject]@{
            engine               = 'hybrid'
            controller           = 'shared'
            postProvisionEnabled = $false
            playbookProfile      = 'default-ad'
            inventoryStrategy    = 'per-lab'
            skipOrchestration    = $false
        }
    }

    $configOrchestration = if ($Config.PSObject.Properties.Name -contains 'orchestration' -and $null -ne $Config.orchestration) {
        $Config.orchestration
    } else {
        [PSCustomObject]@{}
    }

    $engine = if (-not [string]::IsNullOrWhiteSpace([string]$configOrchestration.engine)) {
        [string]$configOrchestration.engine
    } else {
        [string]$defaultOrchestration.engine
    }

    $controller = if (-not [string]::IsNullOrWhiteSpace([string]$configOrchestration.controller)) {
        [string]$configOrchestration.controller
    } else {
        [string]$defaultOrchestration.controller
    }

    $playbookProfile = if (-not [string]::IsNullOrWhiteSpace([string]$configOrchestration.playbookProfile)) {
        [string]$configOrchestration.playbookProfile
    } else {
        [string]$defaultOrchestration.playbookProfile
    }

    $inventoryStrategy = if (-not [string]::IsNullOrWhiteSpace([string]$configOrchestration.inventoryStrategy)) {
        [string]$configOrchestration.inventoryStrategy
    } else {
        [string]$defaultOrchestration.inventoryStrategy
    }

    $postProvisionEnabled = if ($null -ne $configOrchestration.postProvisionEnabled) {
        [bool]$configOrchestration.postProvisionEnabled
    } elseif ($null -ne $defaultOrchestration.postProvisionEnabled) {
        [bool]$defaultOrchestration.postProvisionEnabled
    } else {
        $false
    }

    $configSkip = if ($null -ne $configOrchestration.skipOrchestration) { [bool]$configOrchestration.skipOrchestration } else { $false }
    $effectiveSkip = $SkipOrchestration -or $configSkip

    if ($effectiveSkip -or $engine -eq 'hyperv-only') {
        $postProvisionEnabled = $false
    }

    return [PSCustomObject]@{
        Engine               = $engine
        Controller           = $controller
        PostProvisionEnabled = $postProvisionEnabled
        PlaybookProfile      = $playbookProfile
        InventoryStrategy    = $inventoryStrategy
        SkipOrchestration    = $effectiveSkip
    }
}

function Get-EALabVmAnsibleGroup {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmDefinition
    )

    switch ([string]$VmDefinition.role) {
        'DomainController' { return 'domain_controllers' }
        'MemberServer' { return 'member_servers' }
        'Client' { return 'clients' }
        'Linux' { return 'linux_hosts' }
        default { return 'ungrouped' }
    }
}

function Get-EALabVmPhaseTag {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmDefinition
    )

    if ($VmDefinition.PSObject.Properties.Name -contains 'orchestration' -and
        $null -ne $VmDefinition.orchestration -and
        -not [string]::IsNullOrWhiteSpace([string]$VmDefinition.orchestration.phaseTag)) {
        return [string]$VmDefinition.orchestration.phaseTag
    }

    switch ([string]$VmDefinition.role) {
        'DomainController' { return 'dc-primary' }
        'MemberServer' { return 'member' }
        'Client' { return 'client' }
        'Linux' { return 'linux' }
        default { return 'member' }
    }
}

function Get-EALabVmBootstrapMode {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmDefinition
    )

    if ($VmDefinition.PSObject.Properties.Name -contains 'orchestration' -and
        $null -ne $VmDefinition.orchestration -and
        -not [string]::IsNullOrWhiteSpace([string]$VmDefinition.orchestration.bootstrap)) {
        return [string]$VmDefinition.orchestration.bootstrap
    }

    if ([string]$VmDefinition.os -eq 'linux') {
        return 'ssh'
    }
    return 'winrm'
}

function Initialize-EALabSwitch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Network
    )

    $existing = Get-VMSwitch -Name $Network.name -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        return
    }

    switch ([string]$Network.switchType) {
        'Internal' {
            New-VMSwitch -Name $Network.name -SwitchType Internal -ErrorAction Stop | Out-Null
        }
        'Private' {
            New-VMSwitch -Name $Network.name -SwitchType Private -ErrorAction Stop | Out-Null
        }
        'External' {
            if ([string]::IsNullOrWhiteSpace([string]$Network.netAdapterName)) {
                throw "Network '$($Network.name)' is External but netAdapterName is missing in config."
            }
            New-VMSwitch -Name $Network.name -NetAdapterName ([string]$Network.netAdapterName) -AllowManagementOS $true -ErrorAction Stop | Out-Null
        }
        default {
            throw "Unsupported switchType '$($Network.switchType)' for network '$($Network.name)'."
        }
    }
}

function Resolve-EALabPlaybookPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName
    )

    $projectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..') -ErrorAction Stop
    $profilePath = Join-Path $projectRoot "Ansible\profiles\$ProfileName\site.yml"
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        throw "Ansible playbook profile '$ProfileName' was not found at '$profilePath'."
    }
    return [string]$profilePath
}

function New-EALabAnsibleContext {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Orchestration
    )

    $ansibleRoot = Join-Path $Context.LabRoot 'Ansible'
    $inventoryDir = Join-Path $ansibleRoot 'inventory'
    $groupVarsDir = Join-Path $inventoryDir 'group_vars'
    $hostVarsDir = Join-Path $inventoryDir 'host_vars'

    Initialize-EALabDirectory -Path $ansibleRoot
    Initialize-EALabDirectory -Path $inventoryDir
    Initialize-EALabDirectory -Path $groupVarsDir
    Initialize-EALabDirectory -Path $hostVarsDir

    $inventoryPath = Join-Path $inventoryDir 'hosts.ini'
    $extraVarsPath = Join-Path $ansibleRoot 'extra-vars.json'
    $ansibleLogPath = Join-Path $Context.LogsPath "$($Context.LabName)-ansible.log"
    $playbookPath = Resolve-EALabPlaybookPath -ProfileName ([string]$Orchestration.PlaybookProfile)

    $groups = @{
        domain_controllers = [System.Collections.Generic.List[string]]::new()
        member_servers     = [System.Collections.Generic.List[string]]::new()
        clients            = [System.Collections.Generic.List[string]]::new()
        linux_hosts        = [System.Collections.Generic.List[string]]::new()
    }

    $allGroupLines = [System.Collections.Generic.List[string]]::new()
    $allGroupLines.Add('[all]')

    foreach ($vmDef in @($Context.Config.vmDefinitions)) {
        $groupName = Get-EALabVmAnsibleGroup -VmDefinition $vmDef
        $phaseTag = Get-EALabVmPhaseTag -VmDefinition $vmDef
        $bootstrapMode = Get-EALabVmBootstrapMode -VmDefinition $vmDef
        foreach ($instanceName in (Get-EALabVmInstanceNames -VmDefinition $vmDef)) {
            $hostAddress = if (-not [string]::IsNullOrWhiteSpace([string]$vmDef.staticIP)) {
                [string]$vmDef.staticIP
            } else {
                $instanceName
            }

            if ($groups.ContainsKey($groupName)) {
                $groups[$groupName].Add($instanceName)
            }

            $allGroupLines.Add("$instanceName ansible_host=$hostAddress")

            $hostVar = [System.Collections.Generic.List[string]]::new()
            $hostVar.Add("lab_vm_name: $instanceName")
            $hostVar.Add("lab_role: $($vmDef.role)")
            $hostVar.Add("lab_phase_tag: $phaseTag")
            $hostVar.Add("lab_bootstrap_mode: $bootstrapMode")
            $hostVar.Add("lab_network: $($vmDef.network)")
            if (-not [string]::IsNullOrWhiteSpace([string]$vmDef.staticIP)) {
                $hostVar.Add("lab_static_ip: $($vmDef.staticIP)")
            }
            Set-Content -LiteralPath (Join-Path $hostVarsDir "$instanceName.yml") -Value ($hostVar -join [Environment]::NewLine) -Encoding UTF8
        }
    }

    $inventoryLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $allGroupLines) { $inventoryLines.Add($line) }
    foreach ($key in @('domain_controllers', 'member_servers', 'clients', 'linux_hosts')) {
        if ($groups[$key].Count -eq 0) {
            continue
        }
        $inventoryLines.Add('')
        $inventoryLines.Add("[$key]")
        foreach ($inventoryHost in $groups[$key]) {
            $inventoryLines.Add($inventoryHost)
        }
    }
    Set-Content -LiteralPath $inventoryPath -Value ($inventoryLines -join [Environment]::NewLine) -Encoding UTF8

    $allVars = [System.Collections.Generic.List[string]]::new()
    $allVars.Add("lab_name: $($Context.LabName)")
    $allVars.Add("lab_domain_fqdn: $($Context.Config.domain.fqdn)")
    $allVars.Add("lab_domain_netbios: $($Context.Config.domain.netbiosName)")
    $allVars.Add("lab_domain_functional_level: $($Context.Config.domain.functionalLevel)")
    $allVars.Add("lab_playbook_profile: $($Orchestration.PlaybookProfile)")
    Set-Content -LiteralPath (Join-Path $groupVarsDir 'all.yml') -Value ($allVars -join [Environment]::NewLine) -Encoding UTF8

    $extraVarsObject = [PSCustomObject]@{
        labName              = $Context.LabName
        domainFqdn           = [string]$Context.Config.domain.fqdn
        domainNetbiosName    = [string]$Context.Config.domain.netbiosName
        domainFunctionalLevel = [string]$Context.Config.domain.functionalLevel
        domainSafeModePassword = [string]$Context.Config.domain.safeModePassword
        domainAdminUser      = ''
        domainAdminPassword  = ''
        domainJoinOuPath     = ''
        lab_enable_ad_promotion = $false
        lab_enable_domain_join = $false
    }
    $extraVarsObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $extraVarsPath -Encoding UTF8

    return [PSCustomObject]@{
        RootPath      = $ansibleRoot
        InventoryPath = $inventoryPath
        ExtraVarsPath = $extraVarsPath
        PlaybookPath  = $playbookPath
        LogPath       = $ansibleLogPath
    }
}

function Wait-EALabGuestBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300
    )

    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($vmDef in @($Context.Config.vmDefinitions)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$vmDef.staticIP)) {
            foreach ($instanceName in (Get-EALabVmInstanceNames -VmDefinition $vmDef)) {
                [void]$instanceName
                $targets.Add([string]$vmDef.staticIP)
            }
        }
    }

    if ($targets.Count -eq 0) {
        Write-Debug "Wait-EALabGuestBootstrap found no static IP targets for lab '$($Context.LabName)'."
        return
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    Write-Debug "Waiting for guest bootstrap targets: $($targets -join ', '). TimeoutSeconds=$TimeoutSeconds."
    foreach ($target in $targets) {
        $ready = $false
        $attempt = 0
        while ((Get-Date) -lt $deadline) {
            $attempt++
            try {
                if (Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                    Write-Debug "Guest bootstrap target '$target' is reachable on attempt $attempt."
                    $ready = $true
                    break
                }
                Write-Debug "Guest bootstrap target '$target' not reachable on attempt $attempt yet."
            }
            catch {
                Write-Debug "Guest bootstrap probe error for '$target' on attempt ${attempt}: $($_.Exception.Message)"
                Start-Sleep -Seconds 3
            }
            Start-Sleep -Seconds 3
        }

        if (-not $ready) {
            Write-Debug "Guest bootstrap timed out for '$target' after $attempt attempts."
            throw "Guest bootstrap readiness timed out waiting for host '$target'."
        }
    }
}

function Invoke-EALabProvisionStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Stage,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Set-EALabLifecycleState -Context $Context -Status Creating -Message $Message -Step $Stage
    Write-EALabLog -Context $Context -Level INFO -Message $Message
    & $Action
}

function Update-EALabVmProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [string]$Phase,

        [Parameter(Mandatory = $false)]
        [string]$Message = '',

        [Parameter(Mandatory = $false)]
        [string]$Status = 'InProgress'
    )

    $details = @{}
    if (Test-Path -LiteralPath $Context.StateFile) {
        try {
            $state = Get-Content -LiteralPath $Context.StateFile -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($null -ne $state -and $null -ne $state.details) {
                foreach ($prop in $state.details.PSObject.Properties) {
                    $details[$prop.Name] = $prop.Value
                }
            }
        }
        catch {
            Write-Debug "Unable to read VM progress from '$($Context.StateFile)'. Resetting vmProgress details."
            $details = @{}
        }
    }

    if (-not $details.ContainsKey('vmProgress') -or $null -eq $details.vmProgress) {
        $details.vmProgress = @{}
    }

    $details.vmProgress[$VmName] = [PSCustomObject]@{
        phase   = $Phase
        status  = $Status
        message = $Message
        updated = (Get-Date -Format 'o')
    }

    Set-EALabLifecycleState -Context $Context -Status Creating -Message $Message -Step $Phase -VmName $VmName -Details $details
}

function Get-EALabVmExecutionPlan {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context
    )

    $plan = [System.Collections.Generic.List[object]]::new()
    foreach ($vmDef in @($Context.Config.vmDefinitions)) {
        foreach ($instanceName in (Get-EALabVmInstanceNames -VmDefinition $vmDef)) {
            $roles = if ($vmDef.PSObject.Properties.Name -contains 'roles' -and $null -ne $vmDef.roles -and @($vmDef.roles).Count -gt 0) { @($vmDef.roles) } else { @([string]$vmDef.role) }
            $isDc = $roles -contains 'DomainController'
            $deploymentType = if ($vmDef.PSObject.Properties.Name -contains 'domainController' -and
                $null -ne $vmDef.domainController -and
                $vmDef.domainController.PSObject.Properties.Name -contains 'deploymentType' -and
                -not [string]::IsNullOrWhiteSpace([string]$vmDef.domainController.deploymentType)) {
                [string]$vmDef.domainController.deploymentType
            } elseif ($isDc) {
                'newForest'
            } else {
                ''
            }

            $domainJoinEnabled = $false
            $domainJoinCredentialRef = ''
            if ($vmDef.PSObject.Properties.Name -contains 'guestConfiguration' -and
                $null -ne $vmDef.guestConfiguration -and
                $vmDef.guestConfiguration.PSObject.Properties.Name -contains 'domainJoin' -and
                $null -ne $vmDef.guestConfiguration.domainJoin -and
                $vmDef.guestConfiguration.domainJoin.enabled -eq $true) {
                $domainJoinEnabled = $true
                if ($vmDef.guestConfiguration.domainJoin.PSObject.Properties.Name -contains 'credentialRef') {
                    $domainJoinCredentialRef = [string]$vmDef.guestConfiguration.domainJoin.credentialRef
                }
            }

            $plan.Add([PSCustomObject]@{
                Name              = $instanceName
                VmDefinition      = $vmDef
                Roles             = $roles
                IsDomainController = $isDc
                DeploymentType    = $deploymentType
                DomainJoinEnabled = $domainJoinEnabled
                DomainJoinCredentialRef = $domainJoinCredentialRef
                IsWindows         = ([string]$vmDef.os -like 'windows*')
            })
        }
    }
    return @($plan.ToArray())
}

function Get-EALabRequiredCredentialRefs {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$VmExecutionPlan
    )

    $refs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $credentialConfig = if ($null -ne $Context.Config.credentials) { $Context.Config.credentials } else { [PSCustomObject]@{} }
    $inlineLocalAdminUser = if ($credentialConfig.PSObject.Properties.Name -contains 'localAdminUser') { [string]$credentialConfig.localAdminUser } else { '' }
    $inlineLocalAdminPassword = if ($credentialConfig.PSObject.Properties.Name -contains 'localAdminPassword') { [string]$credentialConfig.localAdminPassword } else { '' }
    $inlineDomainAdminUser = if ($credentialConfig.PSObject.Properties.Name -contains 'domainAdminUser') { [string]$credentialConfig.domainAdminUser } else { '' }
    $inlineDomainAdminPassword = if ($credentialConfig.PSObject.Properties.Name -contains 'domainAdminPassword') { [string]$credentialConfig.domainAdminPassword } else { '' }
    $inlineDsrmPassword = if ($credentialConfig.PSObject.Properties.Name -contains 'dsrmPassword') { [string]$credentialConfig.dsrmPassword } else { '' }
    $hasInlineLocalAdmin = (-not [string]::IsNullOrWhiteSpace($inlineLocalAdminUser) -and -not [string]::IsNullOrWhiteSpace($inlineLocalAdminPassword))
    $hasInlineDomainAdmin = (-not [string]::IsNullOrWhiteSpace($inlineDomainAdminUser) -and -not [string]::IsNullOrWhiteSpace($inlineDomainAdminPassword))
    $hasInlineDsrm = (-not [string]::IsNullOrWhiteSpace($inlineDsrmPassword))

    $globalRefSpecs = @(
        @{ RefField = 'localAdminRef'; HasInline = $hasInlineLocalAdmin },
        @{ RefField = 'domainAdminRef'; HasInline = $hasInlineDomainAdmin },
        @{ RefField = 'dsrmRef'; HasInline = $hasInlineDsrm }
    )
    foreach ($spec in $globalRefSpecs) {
        if ($spec.HasInline) {
            continue
        }

        $field = [string]$spec.RefField
        if ($credentialConfig.PSObject.Properties.Name -contains $field) {
            $value = [string]$credentialConfig.$field
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                [void]$refs.Add($value)
            }
        }
    }

    foreach ($vmRuntime in @($VmExecutionPlan | Where-Object { $_.DomainJoinEnabled })) {
        if ($hasInlineDomainAdmin) {
            continue
        }

        $ref = [string]$vmRuntime.DomainJoinCredentialRef
        if (-not [string]::IsNullOrWhiteSpace($ref)) {
            [void]$refs.Add($ref)
        }
    }

    $collectedRefs = @()
    foreach ($item in $refs) {
        $collectedRefs += [string]$item
    }
    return @($collectedRefs | Sort-Object)
}

function Resolve-EALabCredentialRefs {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'CredentialRefs are lookup keys, not secret values.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CredentialRefs
    )

    $resolvedByRef = @{}
    $missing = [System.Collections.Generic.List[object]]::new()

    foreach ($ref in @($CredentialRefs)) {
        if ([string]::IsNullOrWhiteSpace($ref)) {
            continue
        }

        $health = Test-EALabCredentialRef -CredentialRef $ref
        if (-not [bool]$health.Exists) {
            [void]$missing.Add([PSCustomObject]@{
                Ref      = $ref
                Provider = ''
                Message  = 'Credential reference was not found in supported providers.'
            })
            continue
        }

        $credential = Resolve-EALabCredentialRef -CredentialRef $ref
        if ($null -eq $credential) {
            [void]$missing.Add([PSCustomObject]@{
                Ref      = $ref
                Provider = [string]$health.Provider
                Message  = 'Credential exists but is not readable with username/password.'
            })
            continue
        }

        $resolvedByRef[$ref] = $credential
    }

    return [PSCustomObject]@{
        ResolvedByRef = $resolvedByRef
        Missing       = @($missing.ToArray())
    }
}

function Invoke-EALabAnsiblePlaybook {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AnsibleContext,

        [Parameter(Mandatory = $false)]
        [int]$Retries = 1,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 1800
    )

    $attempt = 0
    do {
        $attempt++
        $arguments = @(
            '-i', $AnsibleContext.InventoryPath,
            $AnsibleContext.PlaybookPath,
            '--extra-vars', "@$($AnsibleContext.ExtraVarsPath)"
        )
        Write-Debug "Starting ansible-playbook attempt $attempt with inventory '$($AnsibleContext.InventoryPath)' and playbook '$($AnsibleContext.PlaybookPath)'."

        $stdoutPath = "$($AnsibleContext.LogPath).stdout"
        $stderrPath = "$($AnsibleContext.LogPath).stderr"
        if (Test-Path -LiteralPath $stdoutPath) { Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }

        Add-Content -LiteralPath $AnsibleContext.LogPath -Value ("{0} [INFO] Running ansible-playbook attempt {1}." -f (Get-Date -Format o), $attempt) -Encoding UTF8
        $process = Start-Process -FilePath 'ansible-playbook' -ArgumentList $arguments -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        Write-Debug "ansible-playbook PID=$($process.Id), TimeoutSeconds=$TimeoutSeconds."
        try {
            Wait-Process -Id $process.Id -Timeout $TimeoutSeconds -ErrorAction Stop
        }
        catch {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Write-Debug "ansible-playbook attempt $attempt timed out after $TimeoutSeconds seconds."
            throw "Ansible execution timed out after $TimeoutSeconds seconds."
        }

        if (Test-Path -LiteralPath $stdoutPath) {
            Add-Content -LiteralPath $AnsibleContext.LogPath -Value (Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue) -Encoding UTF8
        }
        if (Test-Path -LiteralPath $stderrPath) {
            Add-Content -LiteralPath $AnsibleContext.LogPath -Value (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue) -Encoding UTF8
        }
        Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        Write-Debug "ansible-playbook attempt $attempt completed with exit code $($process.ExitCode)."

        if ($process.ExitCode -eq 0) {
            return [PSCustomObject]@{
                Success  = $true
                Attempts = $attempt
                LogPath  = $AnsibleContext.LogPath
            }
        }

        if ($attempt -lt $Retries) {
            Write-Debug "Ansible attempt $attempt failed. Retrying after backoff."
            Start-Sleep -Seconds 5
        }
    } while ($attempt -lt $Retries)

    throw "Ansible playbook failed after $Retries attempt(s). See '$($AnsibleContext.LogPath)'."
}

function New-EALabEnvironment {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [bool]$StartVMs = $true,

        [Parameter(Mandatory = $false)]
        [switch]$SkipOrchestration
    )

    $context = Get-EALabContext -LabName $LabName
    Write-Debug "New-EALabEnvironment start. LabName='$LabName', Force=$Force, StartVMs=$StartVMs, SkipOrchestration=$SkipOrchestration."
    Initialize-EALabDirectory -Path $context.LogsPath
    Initialize-EALabDirectory -Path $context.LabRoot
    Initialize-EALabDirectory -Path (Join-Path $context.LabRoot 'VMs')
    Initialize-EALabDirectory -Path (Join-Path $context.LabRoot 'Disks')

    Write-EALabLog -Context $context -Level INFO -Message "Starting provisioning for lab '$LabName'."
    Set-EALabLifecycleState -Context $context -Status Creating -Message 'Starting provisioning.' -Step 'Initialize'

    try {
        $validation = Test-EALabConfig -Config $context.Config
        if (-not $validation.IsValid) {
            $firstError = if ($validation.Errors.Count -gt 0) { "[{0}] {1}" -f $validation.Errors[0].Field, $validation.Errors[0].Message } else { 'Unknown validation error.' }
            throw "Lab configuration validation failed. $firstError"
        }

        $orchestration = Get-EALabOrchestrationSettings -Config $context.Config -SkipOrchestration ([bool]$SkipOrchestration)
        Write-Debug ("Orchestration settings: Engine='{0}', Controller='{1}', PostProvisionEnabled={2}, SkipOrchestration={3}, PlaybookProfile='{4}'." -f `
                $orchestration.Engine, $orchestration.Controller, $orchestration.PostProvisionEnabled, $orchestration.SkipOrchestration, $orchestration.PlaybookProfile)
        $readiness = Test-EALabProvisioningReadiness -LabName $LabName -Config $context.Config -SkipOrchestration ([bool]$orchestration.SkipOrchestration)
        $failedChecks = @($readiness | Where-Object { $_.Status -eq 'Failed' })
        Write-Debug "Provisioning readiness checks: Total=$(@($readiness).Count), Failed=$($failedChecks.Count)."
        if ($failedChecks.Count -gt 0) {
            $failedSummary = ($failedChecks | ForEach-Object { "$($_.Name): $($_.Message)" }) -join '; '
            throw "Provisioning prerequisites failed. $failedSummary"
        }
        $vmExecutionPlan = @(Get-EALabVmExecutionPlan -Context $context)
        $requiredCredentialRefs = @(Get-EALabRequiredCredentialRefs -Context $context -VmExecutionPlan $vmExecutionPlan)
        $resolvedCredentialRefs = @{}
        if ($requiredCredentialRefs.Count -gt 0) {
            $credentialResolution = Resolve-EALabCredentialRefs -CredentialRefs $requiredCredentialRefs
            $resolvedCredentialRefs = $credentialResolution.ResolvedByRef
            $missingRefs = @($credentialResolution.Missing)
            if ($missingRefs.Count -gt 0) {
                $missingList = ($missingRefs | ForEach-Object { [string]$_.Ref } | Sort-Object -Unique) -join ', '
                throw "Provisioning credential preflight failed. Missing or unreadable credential refs: $missingList. Configure these refs in Windows Credential Manager, or provide inline credentials.*User/*Password in the lab config before launching non-interactive provisioning."
            }
        }

        $credentialSet = Get-EALabCredentialSet -Config $context.Config -AllowPrompt
        Write-Debug ("Credential availability: LocalAdmin={0}, DomainAdmin={1}, Dsrm={2}; RequiredRefs={3}." -f `
                ($null -ne $credentialSet.LocalAdmin), ($null -ne $credentialSet.DomainAdmin), ($null -ne $credentialSet.Dsrm), $requiredCredentialRefs.Count)

        Invoke-EALabProvisionStage -Context $context -Stage 'Networks' -Message 'Ensuring networks.' -Action {
            foreach ($network in @($context.Config.networks)) {
                Write-EALabLog -Context $context -Level INFO -Message "Ensuring vSwitch '$($network.name)' ($($network.switchType))."
                Initialize-EALabSwitch -Network $network
            }
        }

        $createdVmNames = [System.Collections.Generic.List[string]]::new()

        foreach ($vmDef in @($context.Config.vmDefinitions)) {
            $instanceNames = Get-EALabVmInstanceNames -VmDefinition $vmDef
            $cpuCount = if ($null -ne $vmDef.hardware -and $null -ne $vmDef.hardware.cpuCount) { [int]$vmDef.hardware.cpuCount } else { [int]$context.Config.globalHardwareDefaults.cpuCount }
            $memoryMB = if ($null -ne $vmDef.hardware -and $null -ne $vmDef.hardware.memoryMB) { [int]$vmDef.hardware.memoryMB } else { [int]$context.Config.globalHardwareDefaults.memoryMB }
            $diskSizeGB = if ($null -ne $vmDef.hardware -and $null -ne $vmDef.hardware.diskSizeGB) { [int]$vmDef.hardware.diskSizeGB } else { [int]$context.Config.globalHardwareDefaults.diskSizeGB }
            $isoPath = Get-IsoPathForVm -Config $context.Config -VmDefinition $vmDef

            foreach ($vmName in $instanceNames) {
                Set-EALabLifecycleState -Context $context -Status Creating -Message "Provisioning VM '$vmName'." -Step 'ProvisionVM' -VmName $vmName
                Update-EALabVmProgress -Context $context -VmName $vmName -Phase 'Provisioning' -Message "Creating resources for $vmName."
                $unattendIsoPath = ''

                $existing = Get-VM -Name $vmName -ErrorAction SilentlyContinue
                if ($null -ne $existing) {
                    if (-not $Force) {
                        Write-EALabLog -Context $context -Level WARN -Message "VM '$vmName' already exists. Skipping because -Force was not provided."
                        continue
                    }

                    Write-EALabLog -Context $context -Level WARN -Message "VM '$vmName' already exists. Removing because -Force was provided."
                    Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
                    Remove-VM -Name $vmName -Force -ErrorAction Stop
                }
                else {
                    Write-Debug "VM '$vmName' does not already exist. Continuing with creation."
                }

                $vmPath = Join-Path (Join-Path $context.LabRoot 'VMs') $vmName
                $vhdPath = Join-Path (Join-Path $context.LabRoot 'Disks') "$vmName.vhdx"
                Initialize-EALabDirectory -Path $vmPath
                if (Test-Path -LiteralPath $vhdPath) {
                    if ($Force) {
                        Write-EALabLog -Context $context -Level WARN -Message "Disk '$vhdPath' already exists. Removing because -Force was provided."
                        Remove-Item -LiteralPath $vhdPath -Force -ErrorAction Stop
                    }
                    else {
                        throw "Disk '$vhdPath' already exists. Re-run create with -Force, or run destroy/cleanup first."
                    }
                }

                $createMessage = "Create VM '$vmName'"
                if ($PSCmdlet.ShouldProcess($vmName, $createMessage)) {
                    Write-EALabLog -Context $context -Level INFO -Message "Creating VM '$vmName' (Gen $($vmDef.generation), CPU $cpuCount, RAM ${memoryMB}MB, Disk ${diskSizeGB}GB)."
                    $memoryBytes = [int64]$memoryMB * 1MB
                    $diskSizeBytes = [int64]$diskSizeGB * 1GB

                    New-VM -Name $vmName `
                        -Generation ([int]$vmDef.generation) `
                        -Path $vmPath `
                        -MemoryStartupBytes $memoryBytes `
                        -NewVHDPath $vhdPath `
                        -NewVHDSizeBytes $diskSizeBytes `
                        -SwitchName ([string]$vmDef.network) `
                        -ErrorAction Stop | Out-Null

                    Set-VMProcessor -VMName $vmName -Count $cpuCount -ErrorAction Stop | Out-Null

                    if ([int]$vmDef.generation -eq 2) {
                        $secureBootState = if ($vmDef.secureBoot -eq $false) { 'Off' } else { 'On' }
                        Set-VMFirmware -VMName $vmName -EnableSecureBoot $secureBootState -ErrorAction Stop | Out-Null
                    }

                    if ([string]$vmDef.os -like 'windows*' -and -not [string]::IsNullOrWhiteSpace($isoPath)) {
                        $unattendXmlPath = New-EALabVmUnattendXml -Context $context -VmDefinition $vmDef -VmName $vmName -LocalAdminCredential $credentialSet.LocalAdmin
                        $unattendIsoPath = New-EALabUnattendMedia -VmName $vmName -UnattendXmlPath $unattendXmlPath -OutputPath (Split-Path -Path $unattendXmlPath -Parent)
                    }
                    Set-EALabVmInstallMedia -VmName $vmName -OsIsoPath $isoPath -UnattendIsoPath $unattendIsoPath

                    if ($StartVMs) {
                        Start-VM -Name $vmName -ErrorAction Stop | Out-Null
                        Write-EALabLog -Context $context -Level INFO -Message "Started VM '$vmName'."
                    }
                }
                else {
                    Write-Debug "ShouldProcess declined VM creation for '$vmName'."
                }

                $createdVmNames.Add($vmName)
                Update-EALabVmProgress -Context $context -VmName $vmName -Phase 'Provisioned' -Message "Provisioning complete for $vmName." -Status 'Succeeded'
            }
        }

        $ansibleContext = $null
        if ($StartVMs) {
            $localAdminCredential = $credentialSet.LocalAdmin
            if ($null -eq $localAdminCredential) {
                throw "A local admin credential is required to perform guest orchestration. Configure credentials.localAdminRef or provide it interactively."
            }

            $domainAdminCredential = if ($null -ne $credentialSet.DomainAdmin) { $credentialSet.DomainAdmin } else { $localAdminCredential }
            $dsrmCredential = if ($null -ne $credentialSet.Dsrm) { $credentialSet.Dsrm } else { $localAdminCredential }
            $installTimeoutSeconds = 5400
            if ($context.Config.PSObject.Properties.Name -contains 'guestDefaults' -and
                $null -ne $context.Config.guestDefaults -and
                $context.Config.guestDefaults.PSObject.Properties.Name -contains 'installTimeoutMinutes' -and
                $null -ne $context.Config.guestDefaults.installTimeoutMinutes) {
                $installTimeoutSeconds = [int]$context.Config.guestDefaults.installTimeoutMinutes * 60
            }
            $postInstallTimeoutSeconds = 1800
            if ($context.Config.PSObject.Properties.Name -contains 'guestDefaults' -and
                $null -ne $context.Config.guestDefaults -and
                $context.Config.guestDefaults.PSObject.Properties.Name -contains 'postInstallTimeoutMinutes' -and
                $null -ne $context.Config.guestDefaults.postInstallTimeoutMinutes) {
                $postInstallTimeoutSeconds = [int]$context.Config.guestDefaults.postInstallTimeoutMinutes * 60
            }

            Invoke-EALabProvisionStage -Context $context -Stage 'GuestInstall' -Message 'Waiting for guest install readiness.' -Action {
                foreach ($vmRuntime in @($vmExecutionPlan | Where-Object { $_.IsWindows })) {
                    Update-EALabVmProgress -Context $context -VmName $vmRuntime.Name -Phase 'Installing' -Message "Waiting for $($vmRuntime.Name) to finish setup."
                    Wait-EALabVmInstallReady -VmName $vmRuntime.Name -LocalAdminCredential $localAdminCredential -TimeoutSeconds $installTimeoutSeconds
                    Update-EALabVmProgress -Context $context -VmName $vmRuntime.Name -Phase 'Installed' -Message "Windows setup completed on $($vmRuntime.Name)." -Status 'Succeeded'
                }
            }

            Invoke-EALabProvisionStage -Context $context -Stage 'GuestBaseline' -Message 'Applying first-boot guest baseline.' -Action {
                foreach ($vmRuntime in @($vmExecutionPlan | Where-Object { $_.IsWindows })) {
                    Update-EALabVmProgress -Context $context -VmName $vmRuntime.Name -Phase 'GuestBaseline' -Message "Applying baseline on $($vmRuntime.Name)."
                    Initialize-EALabGuestBaseline -Context $context -VmRuntime $vmRuntime -LocalAdminCredential $localAdminCredential
                    Update-EALabVmProgress -Context $context -VmName $vmRuntime.Name -Phase 'BaselineConfigured' -Message "Baseline completed on $($vmRuntime.Name)." -Status 'Succeeded'
                }
            }

            $primaryDcs = @($vmExecutionPlan | Where-Object { $_.IsDomainController -and $_.DeploymentType -eq 'newForest' })
            $additionalDcs = @($vmExecutionPlan | Where-Object { $_.IsDomainController -and $_.DeploymentType -eq 'additional' })
            $joinTargets = @($vmExecutionPlan | Where-Object { -not $_.IsDomainController -and $_.DomainJoinEnabled })

            if ($primaryDcs.Count -gt 0) {
                Invoke-EALabProvisionStage -Context $context -Stage 'PromoteDC' -Message 'Promoting primary domain controller(s).' -Action {
                    foreach ($dcVm in $primaryDcs) {
                        Update-EALabVmProgress -Context $context -VmName $dcVm.Name -Phase 'PromoteDC' -Message "Promoting $($dcVm.Name) as primary DC."
                        Invoke-EALabDomainControllerPromotion -Context $context -VmRuntime $dcVm -DomainAdminCredential $localAdminCredential -DsrmCredential $dsrmCredential
                        Update-EALabVmProgress -Context $context -VmName $dcVm.Name -Phase 'Promoted' -Message "$($dcVm.Name) promoted to DC." -Status 'Succeeded'
                    }
                }

                Invoke-EALabProvisionStage -Context $context -Stage 'DomainReadiness' -Message 'Waiting for domain readiness.' -Action {
                    Wait-EALabDomainReadiness -Context $context -PrimaryDcName $primaryDcs[0].Name -TimeoutSeconds $postInstallTimeoutSeconds
                }
            }

            if ($additionalDcs.Count -gt 0) {
                Invoke-EALabProvisionStage -Context $context -Stage 'PromoteAdditionalDC' -Message 'Promoting additional domain controllers.' -Action {
                    foreach ($dcVm in $additionalDcs) {
                        Update-EALabVmProgress -Context $context -VmName $dcVm.Name -Phase 'PromoteDC' -Message "Promoting additional DC $($dcVm.Name)."
                        Invoke-EALabDomainControllerPromotion -Context $context -VmRuntime $dcVm -DomainAdminCredential $domainAdminCredential -DsrmCredential $dsrmCredential
                        Update-EALabVmProgress -Context $context -VmName $dcVm.Name -Phase 'Promoted' -Message "$($dcVm.Name) promoted as additional DC." -Status 'Succeeded'
                    }
                }
            }

            if ($joinTargets.Count -gt 0) {
                Invoke-EALabProvisionStage -Context $context -Stage 'DomainJoin' -Message 'Joining member servers and clients to domain.' -Action {
                    foreach ($joinVm in $joinTargets) {
                        $joinCredential = $null
                        $joinCredentialRef = [string]$joinVm.DomainJoinCredentialRef
                        if (-not [string]::IsNullOrWhiteSpace($joinCredentialRef) -and $resolvedCredentialRefs.ContainsKey($joinCredentialRef)) {
                            $joinCredential = $resolvedCredentialRefs[$joinCredentialRef]
                        }

                        if ($null -eq $joinCredential) {
                            $joinCredential = if ($null -ne $domainAdminCredential) { $domainAdminCredential } else { $localAdminCredential }
                        }

                        Update-EALabVmProgress -Context $context -VmName $joinVm.Name -Phase 'DomainJoin' -Message "Joining $($joinVm.Name) to domain."
                        Join-EALabMachineToDomain -Context $context -VmRuntime $joinVm -DomainAdminCredential $joinCredential -LocalAdminCredential $localAdminCredential
                        Update-EALabVmProgress -Context $context -VmName $joinVm.Name -Phase 'DomainJoined' -Message "$($joinVm.Name) joined to domain." -Status 'Succeeded'
                    }
                }
            }

            if ($orchestration.PostProvisionEnabled) {
                Set-EALabLifecycleState -Context $context -Status Creating -Message 'Waiting for guest bootstrap.' -Step 'GuestBootstrap'
                Write-EALabLog -Context $context -Level INFO -Message 'Waiting for guest network bootstrap readiness.'
                Wait-EALabGuestBootstrap -Context $context

                Set-EALabLifecycleState -Context $context -Status Creating -Message 'Preparing Ansible inventory.' -Step 'AnsiblePrep'
                $ansibleContext = New-EALabAnsibleContext -Context $context -Orchestration $orchestration
                Write-EALabLog -Context $context -Level INFO -Message "Ansible context prepared at '$($ansibleContext.RootPath)'."

                Set-EALabLifecycleState -Context $context -Status Creating -Message 'Running Ansible playbook.' -Step 'PostProvision' -Details @{
                    inventoryPath = $ansibleContext.InventoryPath
                    playbookPath  = $ansibleContext.PlaybookPath
                    ansibleLog    = $ansibleContext.LogPath
                }
                [void](Invoke-EALabAnsiblePlaybook -Context $context -AnsibleContext $ansibleContext)
                Write-EALabLog -Context $context -Level INFO -Message "Ansible orchestration completed. Log: $($ansibleContext.LogPath)"
            }
            else {
                Write-Debug 'Post-provision orchestration is disabled for this run.'
            }
        }

        $statusMessage = if ($StartVMs) { 'Provisioning complete. VMs launched.' } else { 'Provisioning complete.' }
        $finalDetails = @{}
        if (Test-Path -LiteralPath $context.StateFile) {
            try {
                $state = Get-Content -LiteralPath $context.StateFile -Raw -ErrorAction Stop | ConvertFrom-Json
                if ($null -ne $state -and $null -ne $state.details) {
                    foreach ($prop in $state.details.PSObject.Properties) {
                        $finalDetails[$prop.Name] = $prop.Value
                    }
                }
            }
            catch {
                Write-Debug "Could not read final state details from '$($context.StateFile)'. Returning minimal details."
                $finalDetails = @{}
            }
        }
        $finalDetails.ansibleLog = if ($null -ne $ansibleContext) { $ansibleContext.LogPath } else { '' }
        Set-EALabLifecycleState -Context $context -Status Running -Message $statusMessage -Step 'Complete' -Details @{
            ansibleLog = $finalDetails.ansibleLog
            vmProgress = $finalDetails.vmProgress
        }
        Write-EALabLog -Context $context -Level INFO -Message $statusMessage

        return [PSCustomObject]@{
            Success = $true
            LabName = $LabName
            Status  = 'Running'
            Message = $statusMessage
            VMs     = $createdVmNames.ToArray()
            LogFile = $context.LogFile
            AnsibleLog = if ($null -ne $ansibleContext) { $ansibleContext.LogPath } else { '' }
        }
    }
    catch {
        $msg = $_.Exception.Message
        Write-Debug "New-EALabEnvironment failure for '$LabName': $msg"
        Set-EALabLifecycleState -Context $context -Status Error -Message $msg -Step 'Failed'
        Write-EALabLog -Context $context -Level ERROR -Message $msg
        throw
    }
}

function Remove-EALabEnvironment {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName,

        [Parameter(Mandatory = $false)]
        [switch]$DeleteLabData
    )

    $context = Get-EALabContext -LabName $LabName
    Write-Debug "Remove-EALabEnvironment start. LabName='$LabName', DeleteLabData=$DeleteLabData."
    Initialize-EALabDirectory -Path $context.LogsPath

    Write-EALabLog -Context $context -Level INFO -Message "Starting teardown for lab '$LabName'."
    Set-EALabLifecycleState -Context $context -Status Destroying -Message 'Destroying lab resources.' -Step 'Initialize'

    try {
        $vmNames = @(Get-EALabVmNamesFromConfig -Config $context.Config)
        $removed = [System.Collections.Generic.List[string]]::new()

        foreach ($vmName in $vmNames) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-Debug "VM '$vmName' was not found during teardown."
                continue
            }

            Set-EALabLifecycleState -Context $context -Status Destroying -Message "Removing VM '$vmName'." -Step 'RemoveVM' -VmName $vmName
            if ($PSCmdlet.ShouldProcess($vmName, "Remove VM '$vmName'")) {
                Write-EALabLog -Context $context -Level INFO -Message "Stopping and removing VM '$vmName'."
                Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
                Remove-VM -Name $vmName -Force -ErrorAction Stop
                $removed.Add($vmName)
            }
            else {
                Write-Debug "ShouldProcess declined VM removal for '$vmName'."
            }
        }

        foreach ($network in @($context.Config.networks)) {
            $switch = Get-VMSwitch -Name $network.name -ErrorAction SilentlyContinue
            if ($null -eq $switch) {
                Write-Debug "Switch '$($network.name)' not found during teardown."
                continue
            }

            $attachedAdapters = @(Get-VMNetworkAdapter -All -ErrorAction SilentlyContinue | Where-Object { $_.SwitchName -eq $network.name })
            if ($attachedAdapters.Count -eq 0) {
                if ($PSCmdlet.ShouldProcess($network.name, "Remove vSwitch '$($network.name)'")) {
                    Write-EALabLog -Context $context -Level INFO -Message "Removing unused switch '$($network.name)'."
                    Remove-VMSwitch -Name $network.name -Force -ErrorAction SilentlyContinue
                }
                else {
                    Write-Debug "ShouldProcess declined switch removal for '$($network.name)'."
                }
            }
            else {
                Write-Debug "Switch '$($network.name)' still has attached adapters and will be kept."
            }
        }

        if ($DeleteLabData -and (Test-Path -LiteralPath $context.LabRoot)) {
            if ($PSCmdlet.ShouldProcess($context.LabRoot, "Delete lab data directory")) {
                Write-EALabLog -Context $context -Level WARN -Message "Deleting lab data path '$($context.LabRoot)'."
                Remove-Item -LiteralPath $context.LabRoot -Recurse -Force -ErrorAction Stop
            }
            else {
                Write-Debug "ShouldProcess declined lab data deletion for '$($context.LabRoot)'."
            }
        }

        Set-EALabLifecycleState -Context $context -Status Destroyed -Message 'Lab resources removed.' -Step 'Complete'
        Write-EALabLog -Context $context -Level INFO -Message 'Lab resources removed.'

        return [PSCustomObject]@{
            Success = $true
            LabName = $LabName
            Status  = 'Destroyed'
            Removed = $removed.ToArray()
            LogFile = $context.LogFile
        }
    }
    catch {
        $msg = $_.Exception.Message
        Write-Debug "Remove-EALabEnvironment failure for '$LabName': $msg"
        Set-EALabLifecycleState -Context $context -Status Error -Message $msg -Step 'Failed'
        Write-EALabLog -Context $context -Level ERROR -Message $msg
        throw
    }
}

function Get-EALabEnvironmentStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$LabName
    )

    $context = Get-EALabContext -LabName $LabName
    $state = $null

    if (Test-Path -LiteralPath $context.StateFile) {
        try {
            $state = Get-Content -LiteralPath $context.StateFile -Raw -ErrorAction Stop | ConvertFrom-Json
        }
        catch {
            Write-Debug "Failed to parse state file '$($context.StateFile)'. Falling back to live VM state."
            $state = $null
        }
    }

    $vmNames = @(Get-EALabVmNamesFromConfig -Config $context.Config)
    $existingVms = [System.Collections.Generic.List[object]]::new()
    $runningCount = 0
    $canQueryVm = $null -ne (Get-Command -Name 'Get-VM' -ErrorAction SilentlyContinue)

    if ($canQueryVm) {
        foreach ($vmName in $vmNames) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -ne $vm) {
                $existingVms.Add([PSCustomObject]@{
                    Name  = $vm.Name
                    State = [string]$vm.State
                })
                if ([string]$vm.State -eq 'Running') {
                    $runningCount++
                }
            }
            else {
                Write-Debug "VM '$vmName' not found while gathering environment status."
            }
        }
    }

    $status = if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.status)) {
        [string]$state.status
    } elseif ($existingVms.Count -eq 0) {
        'NotCreated'
    } elseif ($runningCount -gt 0) {
        'Running'
    } else {
        'NotCreated'
    }

    return [PSCustomObject]@{
        LabName      = $LabName
        Status       = $status
        Message      = if ($null -ne $state) { [string]$state.message } else { '' }
        Step         = if ($null -ne $state) { [string]$state.step } else { '' }
        Updated      = if ($null -ne $state) { [string]$state.updated } else { '' }
        Details      = if ($null -ne $state -and $null -ne $state.details) { $state.details } else { @{} }
        ExistingVMs  = $existingVms.ToArray()
        ExpectedVMs  = @($vmNames).Count
        RunningVMs   = $runningCount
        StateFile    = $context.StateFile
        OperationLog = if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace([string]$state.operationLog)) { [string]$state.operationLog } else { $context.LogFile }
    }
}

Export-ModuleMember -Function @(
    'New-EALabEnvironment',
    'Remove-EALabEnvironment',
    'Get-EALabEnvironmentStatus'
)
