# Deploys the PolyclinicReports project to SQL Server Reporting Services (SOAP API ReportService2010):
# folders, shared data sources, reports with data source references; optionally renders every report to PDF.
# Usage:  powershell -ExecutionPolicy Bypass -File SSRS_Projects\Builder\deploy_reports.ps1 [-ReportServer http://localhost/ReportServer] [-Render]
param(
    [string]$ReportServer = "http://localhost/ReportServer",
    [string]$Folder = "Поліклініка",
    [switch]$Render
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "..\PolyclinicReports"
$rs = New-WebServiceProxy -Uri "$ReportServer/ReportService2010.asmx?wsdl" -UseDefaultCredential -Namespace "SSRS.RS2010"
$rs.Timeout = 600000
$ns = $rs.GetType().Namespace

function Ensure-Folder([string]$parent, [string]$name, [string]$description) {
    $path = if ($parent -eq "/") { "/$name" } else { "$parent/$name" }
    $exists = $rs.ListChildren($parent, $false) | Where-Object { $_.TypeName -eq "Folder" -and $_.Name -eq $name }
    if (-not $exists) {
        $p = New-Object "$ns.Property"; $p.Name = "Description"; $p.Value = $description
        $rs.CreateFolder($name, $parent, @($p)) | Out-Null
        Write-Host "Folder: $path"
    }
    return $path
}

$root = Ensure-Folder "/" $Folder "Аналітична звітність поліклініки (курсова робота NVBD, варіант 6)"
$dsFolder = Ensure-Folder $root "Джерела даних" "Спільні джерела даних звітів"

# ---- спільні джерела даних (Windows-автентифікація користувача, що переглядає звіт) ----
foreach ($file in Get-ChildItem $project -Filter *.rds) {
    [xml]$x = Get-Content $file.FullName -Encoding UTF8
    $def = New-Object "$ns.DataSourceDefinition"
    $def.Extension = $x.RptDataSource.ConnectionProperties.Extension
    $def.ConnectString = $x.RptDataSource.ConnectionProperties.ConnectString
    $def.CredentialRetrieval = "Integrated"
    $def.Enabled = $true
    $rs.CreateDataSource($file.BaseName, $dsFolder, $true, $def, $null) | Out-Null
    Write-Host "Data source: $dsFolder/$($file.BaseName) ($($def.Extension))"
}

# ---- звіти ----
$failed = 0
foreach ($file in Get-ChildItem $project -Filter *.rdl | Sort-Object Name) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    [xml]$x = Get-Content $file.FullName -Encoding UTF8
    $desc = New-Object "$ns.Property"; $desc.Name = "Description"; $desc.Value = $x.Report.Description
    $warnings = $null
    try {
        $item = $rs.CreateCatalogItem("Report", $file.BaseName, $root, $true, $bytes, @($desc), [ref]$warnings)
    } catch {
        $failed++
        Write-Host "FAILED: $($file.BaseName)`n  $($_.Exception.InnerException.Message)$($_.Exception.Message)" -ForegroundColor Red
        continue
    }
    $refs = @()
    foreach ($src in $x.Report.DataSources.DataSource) {
        $ref = New-Object "$ns.DataSourceReference"; $ref.Reference = "$dsFolder/$($src.DataSourceReference)"
        $d = New-Object "$ns.DataSource"; $d.Name = $src.Name; $d.Item = $ref
        $refs += $d
    }
    $rs.SetItemDataSources($item.Path, $refs)
    $warnings = @($warnings | Where-Object { $_.Message -notmatch "is not published on the report server" })
    $w = @($warnings | Where-Object { $_.Severity -ne "Information" }).Count
    Write-Host ("Report: {0}{1}" -f $item.Path, $(if ($w) { " ($w warning(s): " + (($warnings | ForEach-Object { $_.Message }) -join " | ") + ")" } else { "" }))
}
if ($failed) { throw "$failed report(s) failed to deploy" }

# ---- рендеринг кожного звіту в PDF (перевірка виконання з даними) ----
if ($Render) {
    $out = Join-Path $PSScriptRoot "..\Exports"
    New-Item -ItemType Directory -Force $out | Out-Null
    foreach ($file in Get-ChildItem $project -Filter *.rdl | Sort-Object Name) {
        if ($file.BaseName -like "02a_*") { continue }   # вкладений звіт рендериться в складі звіту 02
        $url = "$ReportServer`?" + [Uri]::EscapeDataString("$root/$($file.BaseName)") + "&rs:Format=PDF"
        $pdf = Join-Path $out "$($file.BaseName).pdf"
        $t = Get-Date
        try {
            Invoke-WebRequest $url -UseDefaultCredentials -UseBasicParsing -TimeoutSec 600 -OutFile $pdf
            Write-Host ("Rendered: {0} ({1:N0} KB, {2:N1} s)" -f $file.BaseName, ((Get-Item $pdf).Length / 1KB), ((Get-Date) - $t).TotalSeconds)
        } catch {
            $msg = $_.Exception.Message
            if ($_.Exception.Response) {
                $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                $html = $sr.ReadToEnd()
                $msg = ([regex]::Matches($html, '<li>(.*?)</li>') | ForEach-Object { $_.Groups[1].Value -replace '<[^>]+>', '' }) -join " | "
            }
            Write-Host "RENDER FAILED: $($file.BaseName)`n  $msg" -ForegroundColor Red
        }
    }
}
