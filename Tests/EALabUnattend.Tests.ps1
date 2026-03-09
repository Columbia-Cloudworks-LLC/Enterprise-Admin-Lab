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
                    guestConfiguration = [PSCustomObject]@{
                        computerName = 'DC01'
                    }
                }
                $cred = [PSCredential]::new('Administrator', (ConvertTo-SecureString 'P@ssw0rd!' -AsPlainText -Force))

                $path = New-EALabVmUnattendXml -Context $context -VmDefinition $vm -VmName 'DC01' -LocalAdminCredential $cred
                Test-Path -LiteralPath $path | Should Be $true
                (Get-Content -LiteralPath $path -Raw) | Should Match '<ComputerName>DC01</ComputerName>'
            }
            finally {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
