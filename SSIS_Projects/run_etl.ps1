param(
    [string]$Server = ".",
    [switch]$RestoreLabFiles
)

$ErrorActionPreference = "Stop"
$lab = Join-Path $PSScriptRoot "LabFiles"
if ($RestoreLabFiles) {
    foreach ($dir in "Archive", "Rejected") {
        Get-ChildItem (Join-Path $lab $dir) -Filter *.csv -ErrorAction SilentlyContinue | Move-Item -Destination (Join-Path $lab "Inbox") -Force
    }
}
Write-Host ("Lab files in Inbox: {0}" -f (Get-ChildItem (Join-Path $lab "Inbox") -Filter *.csv).Count)

$dtexec = "C:\Program Files\Microsoft SQL Server\160\DTS\Binn\DTExec.exe"
$master = Join-Path $PSScriptRoot "PolyclinicETL\00_Master.dtsx"
$t = Get-Date
& $dtexec /F $master /Set "\Package.Variables[User::ServerName].Value;$Server" /Rep E
$code = $LASTEXITCODE
Write-Host ("DTExec exit code {0}, {1:N0} s" -f $code, ((Get-Date) - $t).TotalSeconds)

$q = "SET NOCOUNT ON; SELECT PackageName, Status, RowsRead, RowsInserted, RowsUpdated, RowsRejected, DurationSec, Errors " +
     "FROM etl.vw_PackageRuns WHERE RunID = (SELECT MAX(RunID) FROM etl.ETLRun) ORDER BY StartedAt;"
& sqlcmd -S $Server -E -d PolyclinicDW -W -s " | " -Q $q
exit $code
