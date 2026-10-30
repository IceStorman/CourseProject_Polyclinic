# Builds the SSIS packages of PolyclinicETL from the C# definitions (SSIS object model v16)
# and optionally runs them with DTExec.
# Usage:
#   powershell -ExecutionPolicy Bypass -File SSIS_Projects\Builder\build.ps1            # build all
#   powershell -ExecutionPolicy Bypass -File SSIS_Projects\Builder\build.ps1 -Only 01,02 -Run
param(
    [string]$Server = ".",
    [string]$Only = "",
    [switch]$Run
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$v = "Version=16.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
$refs = @(
    "Microsoft.SqlServer.ManagedDTS, $v",
    "Microsoft.SqlServer.DTSPipelineWrap, $v",
    "Microsoft.SqlServer.DTSRuntimeWrap, $v",
    "Microsoft.SqlServer.FileSystemTask, $v",
    "Microsoft.SqlServer.ExecPackageTaskWrap, $v",
    "Microsoft.SqlServer.ScriptTask, $v",
    "Microsoft.SqlServer.VSTAScriptingLib, $v"
) | ForEach-Object { [System.Reflection.Assembly]::Load($_).Location }
$refs += "C:\Program Files\Microsoft SQL Server\160\DTS\Tasks\Microsoft.SqlServer.SQLTask.dll"
$refs += "System.Core.dll", "System.Xml.dll", "System.Xml.Linq.dll", "System.Data.dll"
$refs += [System.Reflection.Assembly]::Load("System.IO.Compression, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089").Location
$refs += [System.Reflection.Assembly]::Load("System.IO.Compression.FileSystem, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089").Location

$sources = Get-ChildItem $PSScriptRoot -Filter *.cs | ForEach-Object { $_.FullName }
Add-Type -Path $sources -ReferencedAssemblies $refs

$saved = [PolyclinicEtl.Builder]::Build($root, $Server, $Only)
$saved | ForEach-Object { Write-Host "Saved: $_" }

if ($Run) {
    $dtexec = "C:\Program Files\Microsoft SQL Server\160\DTS\Binn\DTExec.exe"
    foreach ($p in $saved) {
        if ((Split-Path $p -Leaf) -like "00_*") { continue }
        Write-Host "`n=== Running $(Split-Path $p -Leaf)"
        $t = Get-Date
        $out = & $dtexec /F $p /Rep EW
        $code = $LASTEXITCODE
        $out | Where-Object { $_ -match "^\s+Description:" } | Select-Object -Unique -First 15 | ForEach-Object { $_.Trim() }
        Write-Host ("Exit code {0} in {1:N0} s" -f $code, ((Get-Date) - $t).TotalSeconds)
        if ($code -ne 0) { break }
    }
}
