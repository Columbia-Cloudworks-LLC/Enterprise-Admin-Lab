#Requires -Version 5.1
Set-StrictMode -Version Latest

Describe 'Invoke-EALab parameter sets' {
    It 'includes the Status parameter set and LabName binding' {
        $scriptPath = Join-Path $PSScriptRoot '..\Invoke-EALab.ps1'
        $command = Get-Command -Name $scriptPath -ErrorAction Stop

        ($command.ParameterSets.Name -contains 'Status') | Should Be $true
        $statusSet = $command.ParameterSets | Where-Object { $_.Name -eq 'Status' } | Select-Object -First 1
        ($statusSet.Parameters.Name -contains 'LabName') | Should Be $true
    }

    It 'includes debug bootstrap and action routing debug checkpoints' {
        $scriptPath = Join-Path $PSScriptRoot '..\Invoke-EALab.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw -ErrorAction Stop

        ($content -match '\$debugEnabled\s*=\s*\$PSBoundParameters\.ContainsKey\(''Debug''\)') | Should Be $true
        ($content -match '\$VerbosePreference\s*=\s*''Continue''') | Should Be $true
        ($content -match 'Write-Debug\s+"Routing to action parameter set') | Should Be $true
    }
}
