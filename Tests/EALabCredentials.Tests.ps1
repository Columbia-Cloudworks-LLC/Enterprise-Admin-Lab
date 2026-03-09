#Requires -Version 5.1
Set-StrictMode -Version Latest

$modulesRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\Modules') -ErrorAction Stop
$env:PSModulePath = "$modulesRoot;$env:PSModulePath"
$modulePath = Join-Path $modulesRoot 'EALabCredentials\EALabCredentials.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'EALabCredentials resolution' {
    InModuleScope EALabCredentials {
        It 'returns null when prompting is disabled and no reference exists' {
            $credential = Get-EALabCredential -CredentialRef '' -AllowPrompt:$false
            $credential | Should Be $null
        }

        It 'builds a credential set object with expected keys' {
            $config = [PSCustomObject]@{
                credentials = [PSCustomObject]@{
                    localAdminRef = ''
                    domainAdminRef = ''
                    dsrmRef = ''
                }
            }

            $set = Get-EALabCredentialSet -Config $config -AllowPrompt:$false
            ($set.PSObject.Properties.Name -contains 'LocalAdmin') | Should Be $true
            ($set.PSObject.Properties.Name -contains 'DomainAdmin') | Should Be $true
            ($set.PSObject.Properties.Name -contains 'Dsrm') | Should Be $true
        }

        It 'does not prompt for optional credentials when refs are empty' {
            $securePassword = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $localAdminCredential = [PSCredential]::new('lab\administrator', $securePassword)
            Mock -CommandName Get-EALabCredentialFromCredentialManager -MockWith {
                return $localAdminCredential
            }
            Mock -CommandName Get-Credential -MockWith {
                throw 'Get-Credential should not be called for optional blank references.'
            }

            $config = [PSCustomObject]@{
                credentials = [PSCustomObject]@{
                    localAdminRef = 'ealab-local-admin'
                    domainAdminRef = ''
                    dsrmRef = ''
                }
            }

            $set = Get-EALabCredentialSet -Config $config -AllowPrompt
            $set.LocalAdmin.UserName | Should Be 'lab\administrator'
            $set.DomainAdmin | Should Be $null
            $set.Dsrm | Should Be $null
            Assert-MockCalled -CommandName Get-Credential -Times 0 -Exactly
        }
    }
}
