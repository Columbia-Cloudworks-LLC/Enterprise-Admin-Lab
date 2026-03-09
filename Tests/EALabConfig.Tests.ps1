#Requires -Version 5.1
Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '..\Modules\EALabConfig\EALabConfig.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

function New-ValidLabConfigObject {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        metadata = [PSCustomObject]@{
            name = 'test-lab'
            displayName = 'Test Lab'
        }
        domain = [PSCustomObject]@{
            fqdn = 'lab.local'
            netbiosName = 'LAB'
            functionalLevel = 'Win2019'
            safeModePassword = ''
        }
        networks = @(
            [PSCustomObject]@{
                name = 'LabInternal'
                switchType = 'Internal'
                subnet = '192.168.10.0/24'
                gateway = '192.168.10.1'
                dnsServers = @('192.168.10.10')
            }
        )
        baseImages = [PSCustomObject]@{
            windowsServer2019 = [PSCustomObject]@{ isoPath = 'C:\fake.iso'; productKey = '' }
            windowsServer2022 = [PSCustomObject]@{ isoPath = 'C:\fake.iso'; productKey = '' }
            windowsClient = [PSCustomObject]@{ isoPath = ''; productKey = '' }
            linux = [PSCustomObject]@{ isoPath = ''; distro = '' }
        }
        vmDefinitions = @(
            [PSCustomObject]@{
                name = 'DC01'
                role = 'DomainController'
                os = 'windowsServer2022'
                generation = 2
                secureBoot = $true
                tpmEnabled = $false
                hardware = [PSCustomObject]@{
                    cpuCount = 2
                    memoryMB = 2048
                    diskSizeGB = 60
                }
                network = 'LabInternal'
                staticIP = '192.168.10.10'
                count = 1
                orchestration = [PSCustomObject]@{
                    phaseTag = 'dc-primary'
                    bootstrap = 'winrm'
                }
            }
        )
        globalHardwareDefaults = [PSCustomObject]@{
            cpuCount = 2
            memoryMB = 2048
            diskSizeGB = 60
        }
        storage = [PSCustomObject]@{
            vmRootPath = 'E:\EALabs'
            logsPath = 'E:\EALabs\Logs'
        }
        orchestration = [PSCustomObject]@{
            engine = 'hybrid'
            controller = 'shared'
            postProvisionEnabled = $true
            playbookProfile = 'default-ad'
            inventoryStrategy = 'per-lab'
            skipOrchestration = $false
        }
    }
}

Describe 'Test-EALabConfig orchestration validation' {
    It 'accepts a valid orchestration block' {
        $config = New-ValidLabConfigObject
        $result = Test-EALabConfig -Config $config
        $result.IsValid | Should Be $true
    }

    It 'rejects invalid orchestration.engine values' {
        $config = New-ValidLabConfigObject
        $config.orchestration.engine = 'bad-engine'
        $result = Test-EALabConfig -Config $config
        $result.IsValid | Should Be $false
        ($result.Errors.Field -contains 'orchestration.engine') | Should Be $true
    }

    It 'rejects invalid vmDefinitions orchestration phase tags' {
        $config = New-ValidLabConfigObject
        $config.vmDefinitions[0].orchestration.phaseTag = 'invalid-tag'
        $result = Test-EALabConfig -Config $config
        $result.IsValid | Should Be $false
        ($result.Errors.Field -contains 'vmDefinitions[0].orchestration.phaseTag') | Should Be $true
    }

    It 'rejects domainJoin enabled without credentialRef' {
        $config = New-ValidLabConfigObject
        $config.vmDefinitions[0].role = 'MemberServer'
        $config.vmDefinitions[0] | Add-Member -MemberType NoteProperty -Name guestConfiguration -Value ([PSCustomObject]@{
            domainJoin = [PSCustomObject]@{
                enabled = $true
                credentialRef = ''
            }
        }) -Force
        $result = Test-EALabConfig -Config $config
        $result.IsValid | Should Be $false
        ($result.Errors.Field -contains 'vmDefinitions[0].guestConfiguration.domainJoin.credentialRef') | Should Be $true
    }

    It 'rejects configurations without a newForest domain controller' {
        $config = New-ValidLabConfigObject
        $config.vmDefinitions[0] | Add-Member -MemberType NoteProperty -Name domainController -Value ([PSCustomObject]@{
            deploymentType = 'additional'
            sourceDcName = 'DC01'
        }) -Force
        $result = Test-EALabConfig -Config $config
        $result.IsValid | Should Be $false
        ($result.Errors.Message -match 'newForest') | Should Be $true
    }
}
