<#
.SYNOPSIS
    EALabUI is retired.

.DESCRIPTION
    This module is no longer used. The Node.js web application (Web/) has replaced
    this Windows Forms dashboard. All functionality including prerequisites checks,
    labs management, and configuration has been migrated to the React web app.

.NOTES
    Author: viralarchitect
    Module: EALabUI (RETIRED)
#>

Set-StrictMode -Version Latest

Write-Warning 'EALabUI is retired. Use the Node.js web app (Web/). Run Invoke-EALab.ps1 with no arguments.'

# Stub exports satisfy dependency resolution but are deprecated.
function New-EALabDashboardForm {
    Write-Warning 'EALabUI.New-EALabDashboardForm is retired. Use the Node.js web app instead.'
}

function Show-EALabDashboard {
    Write-Warning 'EALabUI.Show-EALabDashboard is retired. Use the Node.js web app instead.'
}

Export-ModuleMember -Function @()
