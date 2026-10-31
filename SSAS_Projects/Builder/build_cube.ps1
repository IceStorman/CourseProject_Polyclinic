param(
    [string]$SqlServer = "localhost",
    [string]$OlapServer = "localhost",
    [double]$AggregationPercent = 35,
    [switch]$NoBackup,
    [switch]$ExportOnly
)

$ErrorActionPreference = "Stop"
$v = "Version=15.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
$refs = @(
    [System.Reflection.Assembly]::Load("Microsoft.AnalysisServices, $v").Location,
    [System.Reflection.Assembly]::Load("Microsoft.AnalysisServices.Core, $v").Location,
    "System.Data.dll", "System.Xml.dll", "System.Core.dll", "System.Xml.Linq.dll"
)
Add-Type -Path (Get-ChildItem $PSScriptRoot -Filter *.cs | ForEach-Object { $_.FullName }) -ReferencedAssemblies $refs

$projectDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path + "\PolyclinicOLAP"
if ($ExportOnly) { [PolyclinicOlap.ProjectExporter]::Export($OlapServer, "PolyclinicOLAP", $projectDir); return }

& sqlcmd -S $SqlServer -E -b -I -i (Join-Path $PSScriptRoot "GRANT_SSAS_ACCESS.sql") | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Cannot grant SSAS access to PolyclinicDW" }

$b = New-Object PolyclinicOlap.CubeBuilder
$b.SqlServer = $SqlServer
$b.OlapServer = $OlapServer
try {
    $b.Build($true) | Out-Null
    Write-Host "Designing aggregations ($AggregationPercent%)..."
    $b.DesignAggregations($AggregationPercent)
    if (-not $NoBackup) { $b.Backup("PolyclinicOLAP.abf") }
}
finally {
    $b.Disconnect()
}
[PolyclinicOlap.ProjectExporter]::Export($OlapServer, "PolyclinicOLAP", $projectDir)
Write-Host "PolyclinicOLAP is deployed and processed."
