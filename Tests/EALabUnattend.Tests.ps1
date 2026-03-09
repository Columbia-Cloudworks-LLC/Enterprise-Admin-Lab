#Requires -Version 5.1
Set-StrictMode -Version Latest

$modulesRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\Modules') -ErrorAction Stop
$env:PSModulePath = "$modulesRoot;$env:PSModulePath"
$modulePath = Join-Path $modulesRoot 'EALabUnattend\EALabUnattend.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'EALabUnattend artifacts' {
    InModuleScope EALabUnattend {
        It 'creates per-VM Autounattend.xml with computer name' {
            $tempRoot = Join-Path $env:TEMP ("ealab-unattend-tests-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            try {
                $context = [PSCustomObject]@{
                    LabRoot = $tempRoot
                    Config = [PSCustomObject]@{
                        guestDefaults = [PSCustomObject]@{
                            locale = 'en-US'
                            timeZone = 'UTC'
                        }
                    }
                }
                $vm = [PSCustomObject]@{
                    generation = 2
                    guestConfiguration = [PSCustomObject]@{
                        computerName = 'DC01'
                    }
                }
                $cred = [PSCredential]::new('Administrator', (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force))

                $path = New-EALabVmUnattendXml -Context $context -VmDefinition $vm -VmName 'DC01' -LocalAdminCredential $cred
                Test-Path -LiteralPath $path | Should Be $true
                $content = Get-Content -LiteralPath $path -Raw
                $content | Should Match '<ComputerName>DC01</ComputerName>'
                $content | Should Match '<Key>/IMAGE/INDEX</Key>'
                $content | Should Match '<Value>1</Value>'
                $content | Should Match '<Username>Administrator</Username>'
                $content | Should Match '<Value>P@ssw0rd!</Value>'
                $content | Should Match '<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'uses configured install image name when specified' {
            $tempRoot = Join-Path $env:TEMP ("ealab-unattend-tests-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            try {
                $context = [PSCustomObject]@{
                    LabRoot = $tempRoot
                    Config  = [PSCustomObject]@{
                        guestDefaults = [PSCustomObject]@{
                            locale = 'en-US'
                            timeZone = 'UTC'
                            installImageName = 'Windows Server 2022 SERVERSTANDARD'
                        }
                    }
                }
                $vm = [PSCustomObject]@{
                    generation = 2
                    guestConfiguration = [PSCustomObject]@{
                        computerName = 'DC01'
                    }
                }
                $cred = [PSCredential]::new('Administrator', (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force))

                $path = New-EALabVmUnattendXml -Context $context -VmDefinition $vm -VmName 'DC01' -LocalAdminCredential $cred
                $content = Get-Content -LiteralPath $path -Raw
                $content | Should Match '<Key>/IMAGE/NAME</Key>'
                $content | Should Match '<Value>Windows Server 2022 SERVERSTANDARD</Value>'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'throws when local admin credential is missing' {
            $tempRoot = Join-Path $env:TEMP ("ealab-unattend-tests-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            try {
                $context = [PSCustomObject]@{
                    LabRoot = $tempRoot
                    Config  = [PSCustomObject]@{
                        guestDefaults = [PSCustomObject]@{
                            locale = 'en-US'
                            timeZone = 'UTC'
                        }
                    }
                }
                $vm = [PSCustomObject]@{
                    generation = 2
                    guestConfiguration = [PSCustomObject]@{
                        computerName = 'DC01'
                    }
                }

                $threw = $false
                try {
                    [void](New-EALabVmUnattendXml -Context $context -VmDefinition $vm -VmName 'DC01' -LocalAdminCredential $null)
                }
                catch {
                    $threw = $true
                }
                $threw | Should Be $true
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'pins OS media to the first DVD slot when enumeration is unsorted' {
            $script:dvdState = @(
                [PSCustomObject]@{
                    ControllerNumber   = 0
                    ControllerLocation = 2
                    Path               = 'E:\ISOs\old-secondary.iso'
                },
                [PSCustomObject]@{
                    ControllerNumber   = 0
                    ControllerLocation = 1
                    Path               = 'E:\ISOs\old-primary.iso'
                }
            )

            Mock -CommandName Get-VMDvdDrive -MockWith {
                return $script:dvdState
            }

            Mock -CommandName Set-VMDvdDrive -MockWith {
                param(
                    [string]$VMName,
                    [int]$ControllerNumber,
                    [int]$ControllerLocation,
                    [string]$Path
                )

                $targetDrive = @($script:dvdState | Where-Object {
                        $_.ControllerNumber -eq $ControllerNumber -and $_.ControllerLocation -eq $ControllerLocation
                    } | Select-Object -First 1)

                if ($targetDrive.Count -gt 0) {
                    $targetDrive[0].Path = $Path
                }
            }

            Mock -CommandName Add-VMDvdDrive -MockWith {
                param(
                    [string]$VMName,
                    [string]$Path
                )

                $highestLocation = @($script:dvdState | Sort-Object ControllerLocation | Select-Object -Last 1)[0].ControllerLocation
                $newDrive = [PSCustomObject]@{
                    ControllerNumber   = 0
                    ControllerLocation = [int]$highestLocation + 1
                    Path               = $Path
                }
                $script:dvdState += $newDrive
                return $newDrive
            }

            $result = Set-EALabVmInstallMedia -VmName 'DC01' -OsIsoPath 'E:\ISOs\ws2022.iso' -UnattendIsoPath 'E:\ISOs\dc01-autounattend.iso'

            $result.OsDvdDrive.ControllerLocation | Should Be 1
            $result.UnattendDvdDrive.ControllerLocation | Should Be 2
            $result.OsIsoPath | Should Be 'E:\ISOs\ws2022.iso'
            $result.UnattendIsoPath | Should Be 'E:\ISOs\dc01-autounattend.iso'
        }
    }
}
