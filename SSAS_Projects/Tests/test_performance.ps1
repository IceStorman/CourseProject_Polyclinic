param(
    [string]$SqlServer = "localhost",
    [string]$OlapServer = "localhost"
)

$ErrorActionPreference = "Stop"
$v = "Version=15.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
[System.Reflection.Assembly]::Load("Microsoft.AnalysisServices.AdomdClient, $v") | Out-Null
[System.Reflection.Assembly]::Load("Microsoft.AnalysisServices, $v") | Out-Null
[System.Reflection.Assembly]::Load("Microsoft.AnalysisServices.Core, $v") | Out-Null

function Sql-Time([string]$db, [string]$query, [bool]$cold) {
    $c = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$db;Integrated Security=SSPI")
    $c.Open()
    try {
        if ($cold) { $x = $c.CreateCommand(); $x.CommandText = "CHECKPOINT; DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS; DBCC FREEPROCCACHE WITH NO_INFOMSGS;"; $x.ExecuteNonQuery() | Out-Null }
        $cmd = $c.CreateCommand(); $cmd.CommandText = $query; $cmd.CommandTimeout = 600
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = $cmd.ExecuteReader(); $rows = 0; while ($r.Read()) { $rows++ }; $r.Close()
        $sw.Stop()
        return @{ Ms = $sw.ElapsedMilliseconds; Rows = $rows }
    } finally { $c.Close() }
}

function Mdx-Time([string]$query, [bool]$cold) {
    $c = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=$OlapServer;Catalog=PolyclinicOLAP")
    $c.Open()
    try {
        if ($cold) {
            $x = $c.CreateCommand()
            $x.CommandText = '<ClearCache xmlns="http://schemas.microsoft.com/analysisservices/2003/engine"><Object><DatabaseID>PolyclinicOLAP</DatabaseID></Object></ClearCache>'
            $x.ExecuteNonQuery() | Out-Null
        }
        $cmd = $c.CreateCommand(); $cmd.CommandText = $query
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $r = $cmd.ExecuteReader(); $rows = 0; while ($r.Read()) { $rows++ }; $r.Close()
        $sw.Stop()
        return @{ Ms = $sw.ElapsedMilliseconds; Rows = $rows }
    } finally { $c.Close() }
}

function Measure-Query($name, [scriptblock]$run) {
    $cold = & $run $true
    $warm = 0; 1..3 | ForEach-Object { $warm += (& $run $false).Ms }
    [pscustomobject]@{ Query = $name; ColdMs = $cold.Ms; WarmMs = [math]::Round($warm / 3); Rows = $cold.Rows }
}

$q1Oltp = @"
SELECT YEAR(v.VisitDateTime) AS Yr, s.Name AS Specialty, COUNT(*) AS Visits, SUM(v.Cost) AS Revenue, COUNT(DISTINCT r.PatientID) AS Patients
FROM dbo.Visits v JOIN dbo.Doctors d ON d.DoctorID = v.DoctorID JOIN dbo.Specialties s ON s.SpecialtyID = d.SpecialtyID
JOIN dbo.MedicalRecords r ON r.RecordID = v.RecordID
GROUP BY YEAR(v.VisitDateTime), s.Name
"@
$q1Dw = @"
SELECT d.YearNo, doc.Specialty, COUNT(*) AS Visits, SUM(f.Cost) AS Revenue, COUNT(DISTINCT f.PatientKey) AS Patients
FROM fact.FactVisit f JOIN dim.DimDate d ON d.DateKey = f.DateKey JOIN dim.DimDoctor doc ON doc.DoctorKey = f.DoctorKey
GROUP BY d.YearNo, doc.Specialty
"@
$q1Mdx = @"
SELECT { [Measures].[Кількість візитів], [Measures].[Виручка], [Measures].[Унікальні пацієнти] } ON 0,
NON EMPTY [Дата].[Рік].[Рік].MEMBERS * [Лікар].[Спеціальність].[Спеціальність].MEMBERS ON 1 FROM [Поліклініка]
"@

$q2Oltp = @"
SELECT dc.Name AS Chapter, YEAR(r.CloseDate) AS Yr, dbo.fn_AgeGroup(p.BirthDate, r.OpenDate) AS AgeGroup,
       COUNT(*) AS Cases, AVG(1.0 * DATEDIFF(DAY, r.OpenDate, r.CloseDate)) AS AvgDays,
       SUM(CASE WHEN r.Outcome IN (N'Одужання', N'Покращення') THEN 1 ELSE 0 END) AS Positive
FROM dbo.MedicalRecords r
JOIN dbo.Diagnoses dg ON dg.RecordID = r.RecordID AND dg.DiagnosisType = N'Основний'
JOIN dbo.Diseases ds ON ds.DiseaseID = dg.DiseaseID JOIN dbo.DiseaseCategories dc ON dc.CategoryID = ds.CategoryID
JOIN dbo.Patients p ON p.PatientID = r.PatientID
WHERE r.Status = N'Закрита'
GROUP BY dc.Name, YEAR(r.CloseDate), dbo.fn_AgeGroup(p.BirthDate, r.OpenDate)
"@
$q2Dw = @"
SELECT dis.CategoryName, d.YearNo, ag.AgeGroup, COUNT(*) AS Cases, AVG(1.0 * f.TreatmentDays) AS AvgDays, SUM(f.IsPositive) AS Positive
FROM fact.FactTreatment f JOIN dim.DimDisease dis ON dis.DiseaseKey = f.DiseaseKey JOIN dim.DimDate d ON d.DateKey = f.CloseDateKey
JOIN dim.DimAgeGroup ag ON ag.AgeGroupKey = f.AgeGroupKey
GROUP BY dis.CategoryName, d.YearNo, ag.AgeGroup
"@
$q2Mdx = @"
SELECT { [Measures].[Випадки лікування], [Measures].[Середня тривалість лікування], [Measures].[Позитивні результати] } ON 0,
NON EMPTY [Хвороба].[Клас МКХ-10].[Клас МКХ-10].MEMBERS * [Дата].[Рік].[Рік].MEMBERS * [Вікова група].[Вікова група].[Вікова група].MEMBERS ON 1
FROM [Поліклініка]
"@

$results = @()
$results += Measure-Query "Q1 OLTP (PolyclinicDB)"     { param($c) Sql-Time "PolyclinicDB" $q1Oltp $c }
$results += Measure-Query "Q1 DW (PolyclinicDW)"       { param($c) Sql-Time "PolyclinicDW" $q1Dw $c }
$results += Measure-Query "Q1 OLAP (з агрегаціями)"     { param($c) Mdx-Time $q1Mdx $c }
$results += Measure-Query "Q2 OLTP (PolyclinicDB)"     { param($c) Sql-Time "PolyclinicDB" $q2Oltp $c }
$results += Measure-Query "Q2 DW (PolyclinicDW)"       { param($c) Sql-Time "PolyclinicDW" $q2Dw $c }
$results += Measure-Query "Q2 OLAP (з агрегаціями)"     { param($c) Mdx-Time $q2Mdx $c }

function Xmla-Process([string]$type) {
    $c = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=$OlapServer")
    $c.Open()
    try {
        $x = $c.CreateCommand()
        $x.CommandText = '<Process xmlns="http://schemas.microsoft.com/analysisservices/2003/engine"><Type>' + $type +
            '</Type><Object><DatabaseID>PolyclinicOLAP</DatabaseID><CubeID>Polyclinic</CubeID></Object></Process>'
        $x.ExecuteNonQuery() | Out-Null
    } finally { $c.Close() }
}
Xmla-Process "ProcessClearIndexes"
$results += Measure-Query "Q1 OLAP (без агрегацій)"    { param($c) Mdx-Time $q1Mdx $c }
$results += Measure-Query "Q2 OLAP (без агрегацій)"    { param($c) Mdx-Time $q2Mdx $c }
Xmla-Process "ProcessIndexes"

$out = Join-Path $PSScriptRoot "performance_results.txt"
$results | Format-Table -AutoSize | Out-String -Width 200 | Tee-Object -FilePath $out
Write-Host "Saved: $out"
