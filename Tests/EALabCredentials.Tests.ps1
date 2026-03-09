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
            Mock -CommandName Get-EALabCredentialFromCredentialManager -MockWith {
                $securePassword = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
                return [PSCredential]::new('lab\administrator', $securePassword)
            }
            Mock -CommandName Get-EALabCredentialFromCmdKey -MockWith { return $null }
            Mock -CommandName Get-EALabCredentialFromWinCredNative -MockWith { return $null }
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
            Assert-MockCalled -CommandName Get-Credential -Times 0 -Exactly -Scope It
        }

        It 'prefers CredentialManager resolution before cmdkey fallback' {
            $securePassword = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $credential = [PSCredential]::new('lab\administrator', $securePassword)
            Mock -CommandName Get-EALabCredentialFromCredentialManager -MockWith { return $credential }
            Mock -CommandName Get-EALabCredentialFromCmdKey -MockWith { throw 'cmdkey provider should not be called when primary succeeds.' }

            $resolved = Resolve-EALabCredentialRef -CredentialRef 'ealab-local-admin'
            $resolved.UserName | Should Be 'lab\administrator'
            Assert-MockCalled -CommandName Get-EALabCredentialFromCredentialManager -Times 1 -Exactly -Scope It
            Assert-MockCalled -CommandName Get-EALabCredentialFromCmdKey -Times 0 -Exactly -Scope It
        }

        It 'falls back to cmdkey provider when CredentialManager returns null' {
            $securePassword = ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force
            $credential = [PSCredential]::new('lab\administrator', $securePassword)
            Mock -CommandName Get-EALabCredentialFromCredentialManager -MockWith { return $null }
            Mock -CommandName Get-EALabCredentialFromCmdKey -MockWith { return $credential }

            $resolved = Resolve-EALabCredentialRef -CredentialRef 'ealab-local-admin'
            $resolved.UserName | Should Be 'lab\administrator'
            Assert-MockCalled -CommandName Get-EALabCredentialFromCredentialManager -Times 1 -Exactly -Scope It
            Assert-MockCalled -CommandName Get-EALabCredentialFromCmdKey -Times 1 -Exactly -Scope It
        }

        It 'returns missing status when credential ref does not resolve' {
            Mock -CommandName Resolve-EALabCredentialRef -MockWith { return $null }

            $status = Test-EALabCredentialRef -CredentialRef 'ealab-missing'
            $status.Exists | Should Be $false
            $status.Ref | Should Be 'ealab-missing'
            $status.PasswordPresent | Should Be $false
        }

        It 'builds credentials from inline config when refs are empty' {
            $config = [PSCustomObject]@{
                credentials = [PSCustomObject]@{
                    localAdminRef = ''
                    domainAdminRef = ''
                    dsrmRef = ''
                    localAdminUser = 'Administrator'
                    localAdminPassword = 'LabPassw0rd!'
                    domainAdminUser = 'LAB\Administrator'
                    domainAdminPassword = 'LabPassw0rd!'
                    dsrmUser = 'DSRM'
                    dsrmPassword = 'LabPassw0rd!'
                }
            }

            $set = Get-EALabCredentialSet -Config $config -AllowPrompt:$false
            $set.LocalAdmin.UserName | Should Be 'Administrator'
            $set.DomainAdmin.UserName | Should Be 'LAB\Administrator'
            $set.Dsrm.UserName | Should Be 'DSRM'
        }
    }
}
