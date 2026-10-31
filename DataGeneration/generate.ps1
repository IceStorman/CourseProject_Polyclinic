param(
    [string]$Server = "."
)

$ErrorActionPreference = "Stop"
$log = Join-Path $PSScriptRoot "generation_log.txt"
$start = Get-Date

& (Join-Path $PSScriptRoot "..\Database\deploy.ps1") -Server $Server

$scripts = @(
    "01_REFERENCE_DATA.sql",
    "02_DOCTORS_PATIENTS.sql",
    "03_MEDICAL_DATA.sql",
    "04_VALIDATE_AND_STATS.sql"
)

"Generation started $start" | Out-File $log -Encoding utf8
foreach ($script in $scripts) {
    $t = Get-Date
    Write-Host "==> $script"
    $out = Join-Path $env:TEMP "gen_$script.txt"
    & sqlcmd -S $Server -E -b -I -f 65001 -W -s "|" -i (Join-Path $PSScriptRoot $script) -o $out
    $code = $LASTEXITCODE
    "`n===== $script =====" | Out-File $log -Append -Encoding utf8
    Get-Content $out -Encoding UTF8 |
        Where-Object { $_ -notmatch '^Updating \[|has been updated|update is not necessary|index\(es\)/statistic|^Statistics for all|^\s*$' } |
        Out-File $log -Append -Encoding utf8
    if ($code -ne 0) { Get-Content $out -Encoding UTF8 | Select-Object -Last 20; throw "Error in $script" }
    Write-Host ("    {0:N0} s" -f ((Get-Date) - $t).TotalSeconds)
}

Write-Host ("Done in {0:N1} min. Log: {1}" -f ((Get-Date) - $start).TotalMinutes, $log)
