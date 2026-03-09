<#
.SYNOPSIS
    Guest OS orchestration helpers for Enterprise Admin Lab.
#>

Set-StrictMode -Version Latest

function Invoke-EALabGuestCommand {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @()
    )

    Write-Debug "Invoke-EALabGuestCommand executing against VM '$VmName' with argument count $(@($ArgumentList).Count)."
    return Invoke-Command -VMName $VmName -Credential $Credential -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
}

function Wait-EALabVmInstallReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [PSCredential]$LocalAdminCredential,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 5400
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    $lastObserved = 'No VM telemetry collected yet.'
    Write-Debug "Waiting for VM '$VmName' to become reachable through PowerShell Direct. TimeoutSeconds=$TimeoutSeconds."
    while ((Get-Date) -lt $deadline) {
        $attempt++
        $vmState = 'Unknown'
        $heartbeatStatus = 'Unknown'
        try {
            $vm = Get-VM -Name $VmName -ErrorAction Stop
            $vmState = [string]$vm.State
            $heartbeatService = Get-VMIntegrationService -VMName $VmName -Name 'Heartbeat' -ErrorAction SilentlyContinue
            if ($null -ne $heartbeatService) {
                $heartbeatStatus = [string]$heartbeatService.PrimaryStatusDescription
            }
            $lastObserved = "VM State='$vmState', Heartbeat='$heartbeatStatus'"
        }
        catch {
            $lastObserved = "VM telemetry unavailable: $($_.Exception.Message)"
        }

        if ($vmState -ne 'Running') {
            Write-Debug "VM '$VmName' is not running on attempt $attempt. $lastObserved"
            Start-Sleep -Seconds 10
            continue
        }

        try {
            [void](Invoke-EALabGuestCommand -VmName $VmName -Credential $LocalAdminCredential -ScriptBlock { 'ready' })
            Write-Debug "VM '$VmName' is reachable after $attempt attempt(s)."
            return [PSCustomObject]@{
                VmName     = $VmName
                Attempts   = $attempt
                VmState    = $vmState
                Heartbeat  = $heartbeatStatus
                ReadyVia   = 'PowerShellDirect'
                LastStatus = $lastObserved
            }
        }
        catch {
            $lastObserved = "$lastObserved; PowerShellDirect='$($_.Exception.Message)'"
            Write-Debug "VM '$VmName' not reachable on attempt ${attempt}: $lastObserved"
            Start-Sleep -Seconds 15
        }
    }

    Write-Debug "VM '$VmName' did not become reachable before timeout after $attempt attempt(s)."
    throw "VM '$VmName' did not become reachable through PowerShell Direct within $TimeoutSeconds seconds. Last observed: $lastObserved"
}

function Get-EALabVmGuestNetworkConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmRuntime
    )

    $vmDef = $VmRuntime.VmDefinition
    $networkFromGuest = if ($null -ne $vmDef.guestConfiguration -and $null -ne $vmDef.guestConfiguration.network) {
        $vmDef.guestConfiguration.network
    } else {
        [PSCustomObject]@{}
    }

    $networkModel = $null
    foreach ($network in @($Context.Config.networks)) {
        if ([string]$network.name -eq [string]$vmDef.network) {
            $networkModel = $network
            break
        }
    }

    $ipAddress = if (-not [string]::IsNullOrWhiteSpace([string]$networkFromGuest.ipAddress)) {
        [string]$networkFromGuest.ipAddress
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$vmDef.staticIP)) {
        [string]$vmDef.staticIP
    } else {
        ''
    }

    $gateway = if (-not [string]::IsNullOrWhiteSpace([string]$networkFromGuest.gateway)) {
        [string]$networkFromGuest.gateway
    } elseif ($null -ne $networkModel -and -not [string]::IsNullOrWhiteSpace([string]$networkModel.gateway)) {
        [string]$networkModel.gateway
    } else {
        ''
    }

    $dnsServers = @()
    if ($null -ne $networkFromGuest.dnsServers -and @($networkFromGuest.dnsServers).Count -gt 0) {
        $dnsServers = @($networkFromGuest.dnsServers)
    } elseif ($null -ne $networkModel -and $null -ne $networkModel.dnsServers -and @($networkModel.dnsServers).Count -gt 0) {
        $dnsServers = @($networkModel.dnsServers)
    }

    $prefixLength = 24
    if (-not [string]::IsNullOrWhiteSpace([string]$networkModel.subnet) -and [string]$networkModel.subnet -match '/(\d{1,2})$') {
        $prefixLength = [int]$matches[1]
    }

    return [PSCustomObject]@{
        IpAddress    = $ipAddress
        PrefixLength = $prefixLength
        Gateway      = $gateway
        DnsServers   = @($dnsServers | ForEach-Object { [string]$_ })
    }
}

function Enable-EALabGuestRemoting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential
    )

    Write-Debug "Enabling PS remoting on VM '$VmName'."
    Invoke-EALabGuestCommand -VmName $VmName -Credential $Credential -ScriptBlock {
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
        Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -Force
        netsh advfirewall firewall set rule group="Windows Remote Management" new enable=Yes | Out-Null
    } | Out-Null
}

function Install-EALabGuestTools {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [string[]]$Tools = @()
    )

    if (@($Tools).Count -eq 0) {
        Write-Debug "No guest tools requested for VM '$VmName'."
        return
    }

    Write-Debug "Installing guest tools on VM '$VmName': $($Tools -join ', ')."
    Invoke-EALabGuestCommand -VmName $VmName -Credential $Credential -ScriptBlock {
        param($SelectedTools)

        foreach ($toolName in @($SelectedTools)) {
            if ([string]::IsNullOrWhiteSpace([string]$toolName)) {
                continue
            }
            if (Get-Command -Name Install-WindowsFeature -ErrorAction SilentlyContinue) {
                Install-WindowsFeature -Name $toolName -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
            }
        }
    } -ArgumentList @($Tools) | Out-Null
}

function Initialize-EALabGuestBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmRuntime,

        [Parameter(Mandatory = $true)]
        [PSCredential]$LocalAdminCredential
    )

    $vmName = [string]$VmRuntime.Name
    $vmDef = $VmRuntime.VmDefinition
    $guestDefaults = if ($null -ne $Context.Config.guestDefaults) { $Context.Config.guestDefaults } else { [PSCustomObject]@{} }
    $guestConfig = if ($null -ne $vmDef.guestConfiguration) { $vmDef.guestConfiguration } else { [PSCustomObject]@{} }
    $networkConfig = Get-EALabVmGuestNetworkConfig -Context $Context -VmRuntime $VmRuntime
    $locale = if (-not [string]::IsNullOrWhiteSpace([string]$guestConfig.locale)) { [string]$guestConfig.locale } else { [string]$guestDefaults.locale }
    $timeZone = if (-not [string]::IsNullOrWhiteSpace([string]$guestConfig.timeZone)) { [string]$guestConfig.timeZone } else { [string]$guestDefaults.timeZone }
    $computerName = if (-not [string]::IsNullOrWhiteSpace([string]$guestConfig.computerName)) { [string]$guestConfig.computerName } else { $vmName }
    $tools = if ($null -ne $guestConfig.tools -and @($guestConfig.tools).Count -gt 0) { @($guestConfig.tools) } else { @($guestDefaults.defaultTools) }
    Write-Debug ("Initializing guest baseline for VM '{0}'. ComputerName='{1}', IpAddress='{2}', PrefixLength='{3}', DnsServers='{4}', TimeZone='{5}', Locale='{6}'." -f `
            $vmName, $computerName, $networkConfig.IpAddress, $networkConfig.PrefixLength, ($networkConfig.DnsServers -join ','), $timeZone, $locale)

    Invoke-EALabGuestCommand -VmName $vmName -Credential $LocalAdminCredential -ScriptBlock {
        param($networkArgs, $newComputerName, $targetLocale, $targetTimeZone)

        if (-not [string]::IsNullOrWhiteSpace([string]$networkArgs.IpAddress)) {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
            if ($null -ne $adapter) {
                $existing = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                foreach ($entry in @($existing)) {
                    Remove-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $entry.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
                }

                New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $networkArgs.IpAddress -PrefixLength $networkArgs.PrefixLength -DefaultGateway $networkArgs.Gateway -ErrorAction SilentlyContinue | Out-Null
                if ($null -ne $networkArgs.DnsServers -and @($networkArgs.DnsServers).Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $networkArgs.DnsServers -ErrorAction SilentlyContinue
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$targetTimeZone) -and (Get-Command -Name Set-TimeZone -ErrorAction SilentlyContinue)) {
            Set-TimeZone -Id $targetTimeZone -ErrorAction SilentlyContinue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$targetLocale)) {
            if (Get-Command -Name Set-WinSystemLocale -ErrorAction SilentlyContinue) {
                Set-WinSystemLocale -SystemLocale $targetLocale -ErrorAction SilentlyContinue
            }
            if (Get-Command -Name Set-WinUserLanguageList -ErrorAction SilentlyContinue) {
                Set-WinUserLanguageList -LanguageList $targetLocale -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$newComputerName) -and $env:COMPUTERNAME -ne $newComputerName) {
            Rename-Computer -NewName $newComputerName -Force -ErrorAction SilentlyContinue
        }
    } -ArgumentList @($networkConfig, $computerName, $locale, $timeZone) | Out-Null
    Write-Debug "Guest baseline network and locale configuration applied for VM '$vmName'."

    Enable-EALabGuestRemoting -VmName $vmName -Credential $LocalAdminCredential
    Install-EALabGuestTools -VmName $vmName -Credential $LocalAdminCredential -Tools $tools

    if (-not [string]::IsNullOrWhiteSpace([string]$guestConfig.firstBootScript)) {
        $scriptPath = [string]$guestConfig.firstBootScript
        Write-Debug "VM '$vmName' has firstBootScript configured at '$scriptPath'."
        if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
            $scriptContent = Get-Content -LiteralPath $scriptPath -Raw -ErrorAction Stop
            Invoke-EALabGuestCommand -VmName $vmName -Credential $LocalAdminCredential -ScriptBlock {
                param($inlineScript)
                Invoke-Expression $inlineScript
            } -ArgumentList @($scriptContent) | Out-Null
            Write-Debug "Executed firstBootScript for VM '$vmName'."
        }
        else {
            Write-Debug "firstBootScript path not found for VM '$vmName': '$scriptPath'."
        }
    }
}

function Invoke-EALabDomainControllerPromotion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmRuntime,

        [Parameter(Mandatory = $true)]
        [PSCredential]$DomainAdminCredential,

        [Parameter(Mandatory = $true)]
        [PSCredential]$DsrmCredential
    )

    $vmName = [string]$VmRuntime.Name
    $vmDef = $VmRuntime.VmDefinition
    $deploymentType = if ($null -ne $vmDef.domainController -and -not [string]::IsNullOrWhiteSpace([string]$vmDef.domainController.deploymentType)) {
        [string]$vmDef.domainController.deploymentType
    } else {
        'newForest'
    }
    Write-Debug "Promoting VM '$vmName' to domain controller. DeploymentType='$deploymentType'."

    $promotionResult = Invoke-EALabGuestCommand -VmName $vmName -Credential $DomainAdminCredential -ScriptBlock {
        param($domainFqdn, $netbiosName, $safeMode, $mode)

        $domainRole = [int](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).DomainRole
        if ($domainRole -ge 4) {
            return [PSCustomObject]@{
                AlreadyDomainController = $true
                ActionTaken             = 'Skipped'
                Reason                  = 'Host is already promoted as a domain controller.'
            }
        }

        $featureState = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction Stop
        if (-not [bool]$featureState.Installed) {
            Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools -ErrorAction Stop | Out-Null
        }

        if ($mode -eq 'additional') {
            Install-ADDSDomainController -DomainName $domainFqdn -InstallDns -SafeModeAdministratorPassword $safeMode -Force:$true -NoRebootOnCompletion:$false
        } else {
            Install-ADDSForest -DomainName $domainFqdn -DomainNetbiosName $netbiosName -InstallDns -SafeModeAdministratorPassword $safeMode -Force:$true -NoRebootOnCompletion:$false
        }
        return [PSCustomObject]@{
            AlreadyDomainController = $false
            ActionTaken             = 'Promote'
            Reason                  = "Promotion initiated in mode '$mode'."
        }
    } -ArgumentList @(
        [string]$Context.Config.domain.fqdn,
        [string]$Context.Config.domain.netbiosName,
        $DsrmCredential.Password,
        $deploymentType
    )

    $normalizedResult = @($promotionResult | Select-Object -First 1)
    if ($normalizedResult.Count -eq 0) {
        return [PSCustomObject]@{
            AlreadyDomainController = $false
            ActionTaken             = 'Unknown'
            Reason                  = 'Promotion result did not return telemetry.'
        }
    }
    return $normalizedResult[0]
}

function Wait-EALabDomainReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [string]$PrimaryDcName,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 1800
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $attempt = 0
    $lastStatus = 'No readiness checks executed yet.'
    Write-Debug "Waiting for domain readiness on primary DC '$PrimaryDcName'. TimeoutSeconds=$TimeoutSeconds."
    while ((Get-Date) -lt $deadline) {
        $attempt++
        try {
            $status = Invoke-EALabGuestCommand -VmName $PrimaryDcName -Credential $Credential -ScriptBlock {
                param($domainFqdn)

                $netlogonRunning = $false
                $adwsRunning = $false
                $dnsSrvReady = $false
                $adModuleReady = $false

                $netlogon = Get-Service -Name Netlogon -ErrorAction SilentlyContinue
                if ($null -ne $netlogon -and [string]$netlogon.Status -eq 'Running') {
                    $netlogonRunning = $true
                }

                $adws = Get-Service -Name ADWS -ErrorAction SilentlyContinue
                if ($null -ne $adws -and [string]$adws.Status -eq 'Running') {
                    $adwsRunning = $true
                }

                $srvRecord = "_ldap._tcp.dc._msdcs.$domainFqdn"
                try {
                    if (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue) {
                        $dnsEntry = Resolve-DnsName -Name $srvRecord -Type SRV -ErrorAction Stop | Select-Object -First 1
                        if ($null -ne $dnsEntry) {
                            $dnsSrvReady = $true
                        }
                    }
                }
                catch {
                    $dnsSrvReady = $false
                }

                try {
                    Import-Module ActiveDirectory -ErrorAction Stop
                    $domain = Get-ADDomain -Identity $domainFqdn -ErrorAction Stop
                    if ($null -ne $domain) {
                        $adModuleReady = $true
                    }
                }
                catch {
                    $adModuleReady = $false
                }

                $ready = ($netlogonRunning -and $adwsRunning -and $dnsSrvReady -and $adModuleReady)
                return [PSCustomObject]@{
                    Ready           = $ready
                    NetLogonRunning = $netlogonRunning
                    ADWSRunning     = $adwsRunning
                    DnsSrvReady     = $dnsSrvReady
                    ADModuleReady   = $adModuleReady
                }
            } -ArgumentList @([string]$Context.Config.domain.fqdn)
            $status = @($status | Select-Object -First 1)[0]

            $lastStatus = "NetLogon=$([bool]$status.NetLogonRunning); ADWS=$([bool]$status.ADWSRunning); DnsSrv=$([bool]$status.DnsSrvReady); ADModule=$([bool]$status.ADModuleReady)"
            if ([bool]$status.Ready) {
                Write-Debug "Domain controller '$PrimaryDcName' is AD-ready after $attempt attempt(s). $lastStatus"
                return [PSCustomObject]@{
                    VmName      = $PrimaryDcName
                    Attempts    = $attempt
                    LastStatus  = $lastStatus
                    Ready       = $true
                    ReadyChecks = $status
                }
            }
            Write-Debug "Domain controller '$PrimaryDcName' not AD-ready on attempt $attempt. $lastStatus"
        }
        catch {
            $lastStatus = "Readiness probe error: $($_.Exception.Message)"
            Write-Debug "Domain readiness probe error on attempt $attempt for '$PrimaryDcName': $lastStatus"
            Start-Sleep -Seconds 15
        }

        Start-Sleep -Seconds 15
    }

    Write-Debug "Domain readiness timeout waiting for '$PrimaryDcName' after $attempt attempt(s)."
    throw "Domain readiness timed out waiting for domain controller '$PrimaryDcName'. Last status: $lastStatus"
}

function Join-EALabMachineToDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Context,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$VmRuntime,

        [Parameter(Mandatory = $true)]
        [PSCredential]$DomainAdminCredential,

        [Parameter(Mandatory = $true)]
        [PSCredential]$LocalAdminCredential
    )

    $vmName = [string]$VmRuntime.Name
    $vmDef = $VmRuntime.VmDefinition
    $domainJoin = if ($null -ne $vmDef.guestConfiguration -and $null -ne $vmDef.guestConfiguration.domainJoin) {
        $vmDef.guestConfiguration.domainJoin
    } else {
        [PSCustomObject]@{}
    }
    $ouPath = if (-not [string]::IsNullOrWhiteSpace([string]$domainJoin.ouPath)) {
        [string]$domainJoin.ouPath
    } elseif ($null -ne $Context.Config.guestDefaults -and -not [string]::IsNullOrWhiteSpace([string]$Context.Config.guestDefaults.domainJoinOuPath)) {
        [string]$Context.Config.guestDefaults.domainJoinOuPath
    } else {
        ''
    }
    Write-Debug "Joining VM '$vmName' to domain '$([string]$Context.Config.domain.fqdn)' with OUPath '$ouPath'."

    Invoke-EALabGuestCommand -VmName $vmName -Credential $LocalAdminCredential -ScriptBlock {
        param([string]$targetDomain, [PSCredential]$joinCredential, [string]$targetOuPath)

        if (-not [string]::IsNullOrWhiteSpace([string]$targetOuPath)) {
            Add-Computer -DomainName $targetDomain -Credential $joinCredential -OUPath $targetOuPath -Force -ErrorAction Stop
        } else {
            Add-Computer -DomainName $targetDomain -Credential $joinCredential -Force -ErrorAction Stop
        }
    } -ArgumentList @([string]$Context.Config.domain.fqdn, $DomainAdminCredential, $ouPath) | Out-Null
}

Export-ModuleMember -Function @(
    'Wait-EALabVmInstallReady',
    'Invoke-EALabGuestCommand',
    'Initialize-EALabGuestBaseline',
    'Enable-EALabGuestRemoting',
    'Install-EALabGuestTools',
    'Invoke-EALabDomainControllerPromotion',
    'Wait-EALabDomainReadiness',
    'Join-EALabMachineToDomain'
)
