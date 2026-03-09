$paths = @(
    'C:\Users\viral\.cursor\plugins\cache\cursor-public\1password\20f39145eba52e5b82d70d06672cfddf74c85638\scripts\validate-mounted-env-files.sh',
    'C:\Users\viral\.cursor\plugins\cache\cursor-public\1password\9cec23ceb4bea5c1b1fc24b190f51df39ff87f2a\scripts\validate-mounted-env-files.sh'
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        $content = [System.IO.File]::ReadAllText($p)
        $content = $content -replace "`r`n", "`n" -replace "`r", "`n"
        [System.IO.File]::WriteAllText($p, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Fixed: $p"
    } else {
        Write-Host "Not found: $p"
    }
}
