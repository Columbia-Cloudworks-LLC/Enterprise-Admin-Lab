#Requires -Version 5.1
Set-StrictMode -Version Latest

$modulesRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\Modules') -ErrorAction Stop
$env:PSModulePath = "$modulesRoot;$env:PSModulePath"
$modulePath = Join-Path $modulesRoot 'EALabProvisioning\EALabProvisioning.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'EALabProvisioning internal orchestration helpers' {
    InModuleScope EALabProvisioning {
        It 'resolves playbook path for default-ad profile' {
            $path = Resolve-EALabPlaybookPath -ProfileName 'default-ad'
            Test-Path -LiteralPath $path | Should Be $true
        }

        It 'generates per-lab ansible inventory and vars artifacts' {
            $tempRoot = Join-Path $env:TEMP ("ealab-tests-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

            $context = [PSCustomObject]@{
                LabName = 'test-hybrid'
                LabRoot = $tempRoot
                LogsPath = $tempRoot
                Config = [PSCustomObject]@{
                    domain = [PSCustomObject]@{
                        fqdn = 'lab.local'
                        netbiosName = 'LAB'
                        functionalLevel = 'Win2019'
                        safeModePassword = ''
                    }
                    vmDefinitions = @(
                        [PSCustomObject]@{
                            name = 'DC01'
                            role = 'DomainController'
                            os = 'windowsServer2022'
                            network = 'LabInternal'
                            staticIP = '192.168.10.10'
                            count = 1
                        },
                        [PSCustomObject]@{
                            name = 'SRV01'
                            role = 'MemberServer'
                            os = 'windowsServer2022'
                            network = 'LabInternal'
                            staticIP = '192.168.10.20'
                            count = 1
                        }
                    )
                }
            }
            $orch = [PSCustomObject]@{
                PlaybookProfile = 'default-ad'
            }

            try {
                $ansible = New-EALabAnsibleContext -Context $context -Orchestration $orch
                Test-Path -LiteralPath $ansible.InventoryPath | Should Be $true
                Test-Path -LiteralPath $ansible.ExtraVarsPath | Should Be $true
                Test-Path -LiteralPath $ansible.PlaybookPath | Should Be $true
                (Get-Content -LiteralPath $ansible.InventoryPath -Raw) | Should Match '\[domain_controllers\]'
                (Get-Content -LiteralPath $ansible.InventoryPath -Raw) | Should Match '\[member_servers\]'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'builds execution plan with DC and domain join flags' {
            $context = [PSCustomObject]@{
                Config = [PSCustomObject]@{
                    vmDefinitions = @(
                        [PSCustomObject]@{
                            name = 'DC01'
                            role = 'DomainController'
                            os = 'windowsServer2022'
                            count = 1
                            domainController = [PSCustomObject]@{
                                deploymentType = 'newForest'
                            }
                        },
                        [PSCustomObject]@{
                            name = 'APP01'
                            role = 'MemberServer'
                            os = 'windowsServer2022'
                            count = 1
                            guestConfiguration = [PSCustomObject]@{
                                domainJoin = [PSCustomObject]@{
                                    enabled = $true
                                }
                            }
                        }
                    )
                }
            }

            $plan = Get-EALabVmExecutionPlan -Context $context
            $plan.Count | Should Be 2
            ($plan | Where-Object { $_.Name -eq 'DC01' }).IsDomainController | Should Be $true
            ($plan | Where-Object { $_.Name -eq 'APP01' }).DomainJoinEnabled | Should Be $true
        }

        It 'mirrors INFO log messages to verbose and debug streams' {
            $tempRoot = Join-Path $env:TEMP ("ealab-tests-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            $context = [PSCustomObject]@{
                LabName = 'debug-lab'
                LogsPath = $tempRoot
                LogFile = (Join-Path $tempRoot 'debug-lab.log')
            }

            try {
                Mock Write-Verbose {}
                Mock Write-Debug {}
                Write-EALabLog -Context $context -Level INFO -Message 'debug message'
                Test-Path -LiteralPath $context.LogFile | Should Be $true
                Assert-MockCalled Write-Verbose -Times 1 -Exactly
                Assert-MockCalled Write-Debug -Times 1 -Exactly
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
