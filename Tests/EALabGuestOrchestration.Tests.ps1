#Requires -Version 5.1
Set-StrictMode -Version Latest

$modulesRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\Modules') -ErrorAction Stop
$env:PSModulePath = "$modulesRoot;$env:PSModulePath"
$modulePath = Join-Path $modulesRoot 'EALabGuestOrchestration\EALabGuestOrchestration.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'EALabGuestOrchestration readiness helpers' {
    InModuleScope EALabGuestOrchestration {
        It 'returns quickly when domain controller is reachable' {
            Mock Test-Connection { return $true }
            $context = [PSCustomObject]@{ }
            { Wait-EALabDomainReadiness -Context $context -PrimaryDcName 'DC01' -TimeoutSeconds 2 } | Should Not Throw
        }

        It 'throws on domain readiness timeout and emits debug traces' {
            Mock Test-Connection { return $false }
            Mock Start-Sleep {}
            Mock Write-Debug {}
            $context = [PSCustomObject]@{ }

            { Wait-EALabDomainReadiness -Context $context -PrimaryDcName 'DC01' -TimeoutSeconds 1 } | Should Throw
            Assert-MockCalled Write-Debug -Times 1
        }
    }
}
