# Creates PolyclinicDW from scratch (drops it if it exists).
# Usage:  powershell -ExecutionPolicy Bypass -File SSIS_Projects\DataWarehouse\deploy_dw.ps1 [-Server .]
param(
    [string]$Server = "."
)

$ErrorActionPreference = "Stop"
foreach ($script in "01_CREATE_DW.sql", "02_ETL_OBJECTS.sql") {
    Write-Host "==> $script"
    & sqlcmd -S $Server -E -b -I -f 65001 -i (Join-Path $PSScriptRoot $script)
    if ($LASTEXITCODE -ne 0) { throw "Error in $script" }
}
Write-Host "PolyclinicDW created successfully."
