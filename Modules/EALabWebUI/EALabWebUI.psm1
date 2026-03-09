<#
.SYNOPSIS
    EALabWebUI is retired.

.DESCRIPTION
    This module is no longer used. The Node.js web application (Web/) has replaced
    the PowerShell HttpListener and WinForms dashboard. All functionality has been
    migrated to Express + React.

.NOTES
    Author: viralarchitect
    Module: EALabWebUI (RETIRED)
#>

Set-StrictMode -Version Latest

Write-Warning 'EALabWebUI is retired. Use the Node.js web app (Web/). Run Invoke-EALab.ps1 with no arguments.'

# Stub exports satisfy dependency resolution but are deprecated.
function Show-EALabConfigForm {
    Write-Warning 'EALabWebUI.Show-EALabConfigForm is retired. Use the Node.js web app instead.'
}

function Stop-EALabConfigForm {
    Write-Warning 'EALabWebUI.Stop-EALabConfigForm is retired.'
}

Export-ModuleMember -Function @()
