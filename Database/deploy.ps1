# Creates PolyclinicDB from scratch by running the SQL scripts in order.
# Usage:  powershell -ExecutionPolicy Bypass -File Database\deploy.ps1 [-Server .]
param(
    [string]$Server = "."
)

$ErrorActionPreference = "Stop"
$scripts = @(
    "CREATE_DATABASE.sql",
    "CREATE_TABLES.sql",
    "CREATE_CONSTRAINTS.sql",
    "CREATE_INDEXES.sql",
    "CREATE_TRIGGERS.sql",
    "CREATE_PROCEDURES.sql"
)

foreach ($script in $scripts) {
    $path = Join-Path $PSScriptRoot $script
    Write-Host "==> $script"
    # -b: stop on error, -I: QUOTED_IDENTIFIER ON (needed for filtered/computed indexes),
    # -f 65001: scripts are UTF-8 (Ukrainian text)
    & sqlcmd -S $Server -E -b -I -f 65001 -i $path
    if ($LASTEXITCODE -ne 0) { throw "Error in $script" }
}

Write-Host "PolyclinicDB created successfully."
