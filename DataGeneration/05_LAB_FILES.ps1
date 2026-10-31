param(
    [string]$Server = ".",
    [string]$OutDir = (Join-Path $PSScriptRoot "..\SSIS_Projects\LabFiles\Inbox"),
    [int]$Seed = 2026
)

$ErrorActionPreference = "Stop"
$rnd = New-Object System.Random($Seed)

$query = @"
SET NOCOUNT ON;
WITH Rules AS (
    SELECT * FROM (VALUES
     ('E11.9','GLU',0.85),('E11.9','HBA1C',0.80),('E11.9','CREA',0.15),('E10.9','GLU',0.85),('E10.9','HBA1C',0.85),
     ('E66.9','GLU',0.35),('E66.9','CHOL',0.60),
     ('I10','CHOL',0.55),('I10','LDL',0.55),('I10','CREA',0.15),('I20.9','CHOL',0.65),('I20.9','LDL',0.70),
     ('I25.1','CHOL',0.65),('I25.1','LDL',0.70),('I48','TSH',0.15),('I50.9','CREA',0.40),('I69.3','LDL',0.50),
     ('E03.9','TSH',0.85),('E04.9','TSH',0.35),
     ('D50.9','HGB',0.90),('D50.9','FERR',0.90),
     ('N18.9','CREA',0.90),('N18.9','URIC',0.50),('M10.9','URIC',0.85),
     ('J18.9','WBC',0.85),('J18.9','CRP',0.90),('J20.9','WBC',0.40),('J20.9','CRP',0.50),('J03.9','WBC',0.60),
     ('J03.9','CRP',0.60),('U07.1','CRP',0.70),('U07.1','WBC',0.30),('J10.1','WBC',0.25),('A09','WBC',0.40),
     ('N39.0','WBC',0.55),('N30.0','WBC',0.45),('M06.9','CRP',0.80),
     ('K29.7','ALT',0.15),('K80.2','ALT',0.50),('K25.9','HGB',0.30),
     ('Z00.0','GLU',0.08),('Z00.0','CHOL',0.20),('Z00.0','HGB',0.08),('Z00.0','WBC',0.05)
    ) r(ICD, Test, Abn)
)
SELECT v.VisitID, CAST(v.VisitDateTime AS DATE) AS SampleDate, r.PatientID, p.LastName, LEFT(p.FirstName,1) AS FI,
       ru.Test, ru.Abn, (v.VisitID * 2654435761) % 1000 AS Pick
FROM dbo.Visits v
JOIN dbo.MedicalRecords r ON r.RecordID = v.RecordID
JOIN dbo.Patients p       ON p.PatientID = r.PatientID
JOIN dbo.Diagnoses dg     ON dg.RecordID = r.RecordID AND dg.DiagnosisType = N'Основний'
JOIN dbo.Diseases ds      ON ds.DiseaseID = dg.DiseaseID
JOIN Rules ru             ON ru.ICD = ds.ICDCode
WHERE v.VisitDateTime >= '2024-01-01' AND v.Status = N'Відбувся'
  AND (v.VisitType = N'Первинний' OR (ds.IsChronic = 1 AND (v.VisitID * 2654435761) % 1000 < 300))
  AND (v.VisitID * 2654435761) % 1000 < 700
ORDER BY v.VisitID, ru.Test;
"@

$tests = @{
    GLU   = @{ Lo = 4.0;  Hi = 6.0;  ALo = 6.5; AHi = 14.0; Dec = 1; Unit = "ммоль/л";  Names = @("GLU","Glucose","глюкоза","Глюкоза крові","GLUCOSE") }
    HBA1C = @{ Lo = 4.2;  Hi = 5.8;  ALo = 6.2; AHi = 11.0; Dec = 1; Unit = "%";        Names = @("HbA1c","HBA1C","A1C","Глікований гемоглобін") }
    CHOL  = @{ Lo = 3.5;  Hi = 5.1;  ALo = 5.3; AHi = 8.0;  Dec = 2; Unit = "ммоль/л";  Names = @("CHOL","Cholesterol","холестерин","Загальний холестерин") }
    LDL   = @{ Lo = 1.5;  Hi = 2.9;  ALo = 3.1; AHi = 5.5;  Dec = 2; Unit = "ммоль/л";  Names = @("LDL","LDL-C","ЛПНЩ") }
    HGB   = @{ Lo = 125;  Hi = 160;  ALo = 85;  AHi = 118;  Dec = 0; Unit = "г/л";      Names = @("HGB","Hb","Hemoglobin","гемоглобін") }
    WBC   = @{ Lo = 4.5;  Hi = 8.8;  ALo = 9.5; AHi = 18.0; Dec = 1; Unit = "x10^9/л";  Names = @("WBC","Leukocytes","лейкоцити","Лейкоцити") }
    CRP   = @{ Lo = 0.5;  Hi = 4.5;  ALo = 8;   AHi = 120;  Dec = 1; Unit = "мг/л";     Names = @("CRP","СРБ","C-reactive protein") }
    CREA  = @{ Lo = 65;   Hi = 110;  ALo = 130; AHi = 450;  Dec = 0; Unit = "мкмоль/л"; Names = @("CREA","Creatinine","креатинін") }
    TSH   = @{ Lo = 0.6;  Hi = 3.8;  ALo = 4.5; AHi = 15.0; Dec = 2; Unit = "мМО/л";    Names = @("TSH","ТТГ","tsh") }
    ALT   = @{ Lo = 10;   Hi = 38;   ALo = 45;  AHi = 160;  Dec = 0; Unit = "Од/л";     Names = @("ALT","АЛТ","ALAT") }
    URIC  = @{ Lo = 180;  Hi = 400;  ALo = 430; AHi = 700;  Dec = 0; Unit = "мкмоль/л"; Names = @("URIC","Uric acid","Сечова кислота") }
    FERR  = @{ Lo = 25;   Hi = 140;  ALo = 5;   AHi = 14;   Dec = 0; Unit = "нг/мл";    Names = @("FERR","Ferritin","феритин") }
}
$unknownTests = @("Вітамін D", "PSA", "Vitamin B12", "Прокальцитонін")
$labs = @("Лабораторія «Діалаб»", "Лабораторія «Сінево»", "ЛабДіагностика")

$conn = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Database=PolyclinicDB;Integrated Security=SSPI;")
$conn.Open()
$cmd = $conn.CreateCommand(); $cmd.CommandText = $query; $cmd.CommandTimeout = 600
$reader = $cmd.ExecuteReader()
$rows = New-Object System.Collections.Generic.List[object]
while ($reader.Read()) {
    $rows.Add([pscustomobject]@{
        VisitID = $reader.GetInt64(0); SampleDate = $reader.GetDateTime(1); PatientID = $reader.GetInt32(2)
        LastName = $reader.GetString(3); FI = $reader.GetString(4); Test = $reader.GetString(5); Abn = [double]$reader.GetDecimal(6)
    })
}
$conn.Close()
Write-Host ("Source rows: {0:N0}" -f $rows.Count)

New-Item -ItemType Directory -Force $OutDir | Out-Null
Get-ChildItem $OutDir -Filter "*.csv" | Remove-Item
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Pad([string]$s) {
    switch ($rnd.Next(10)) { 0 { " $s" } 1 { "$s  " } default { $s } }
}

$stats = @{ Rows = 0; Duplicates = 0; Empty = 0; Implausible = 0; UnknownPatient = 0; UnknownTest = 0 }
$byMonth = $rows | Group-Object { $_.SampleDate.ToString("yyyy_MM") }
foreach ($month in $byMonth | Sort-Object Name) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("LabOrderNo;PatientRef;PatientName;TestName;Result;Unit;SampleDate;Laboratory")
    $lab = $labs[$rnd.Next($labs.Count)]
    foreach ($r in $month.Group) {
        $t = $tests[$r.Test]
        $order = "LAB-{0}-{1:D7}" -f $r.SampleDate.ToString("yyMM"), $r.VisitID
        $abn = $rnd.NextDouble() -lt $r.Abn
        $lo = if ($abn) { $t.ALo } else { $t.Lo }; $hi = if ($abn) { $t.AHi } else { $t.Hi }
        $value = [math]::Round($lo + ($hi - $lo) * $rnd.NextDouble(), $t.Dec)
        $resultText = $value.ToString("F$($t.Dec)", $inv)
        $testName = $t.Names[$rnd.Next($t.Names.Count)]
        $patientRef = if ($rnd.Next(100) -lt 15) { "P-{0:D6}" -f $r.PatientID } else { "$($r.PatientID)" }

        $p = $rnd.Next(1000)
        if     ($p -lt 10) { $resultText = ""; $stats.Empty++ }
        elseif ($p -lt 15) { $resultText = "н/д"; $stats.Empty++ }
        elseif ($p -lt 18) { $resultText = if ($rnd.Next(2) -eq 0) { "-$resultText" } else { ($value * 100).ToString("F0", $inv) }; $stats.Implausible++ }
        elseif ($p -lt 22) { $patientRef = "$(900000 + $rnd.Next(99999))"; $stats.UnknownPatient++ }
        elseif ($p -lt 25) { $testName = $unknownTests[$rnd.Next($unknownTests.Count)]; $stats.UnknownTest++ }
        if ($rnd.Next(2) -eq 0) { $resultText = $resultText.Replace(".", ",") }

        $dateText = switch ($rnd.Next(10)) {
            { $_ -lt 4 } { $r.SampleDate.ToString("yyyy-MM-dd", $inv); break }
            { $_ -lt 8 } { $r.SampleDate.ToString("dd.MM.yyyy", $inv); break }
            default      { $r.SampleDate.ToString("MM/dd/yyyy", $inv) }
        }
        if ($rnd.Next(1000) -lt 5) { $dateText = ""; $stats.Empty++ }

        $line = "{0};{1};{2};{3};{4};{5};{6};{7}" -f $order, (Pad $patientRef), "$($r.LastName) $($r.FI).", (Pad $testName), $resultText, $t.Unit, $dateText, $lab
        $lines.Add($line); $stats.Rows++
        if ($rnd.Next(100) -lt 2) { $lines.Add($line); $stats.Duplicates++; $stats.Rows++ }
    }
    $file = Join-Path $OutDir ("lab_results_{0}.csv" -f $month.Name)
    [System.IO.File]::WriteAllLines($file, $lines, $utf8)
}

$bad = @("Order,Patient,Test,Value,Date", "LAB-2512-0000001,123,GLU,5.4,2025-12-01")
[System.IO.File]::WriteAllLines((Join-Path $OutDir "lab_results_2025_12_partner_export.csv"), $bad, $utf8)

$files = Get-ChildItem $OutDir -Filter "*.csv"
Write-Host ("Files: {0}, data rows: {1:N0}" -f $files.Count, $stats.Rows)
Write-Host ("Dirty rows -> duplicates: {0}, empty/н/д: {1}, implausible: {2}, unknown patient: {3}, unknown test: {4}" -f `
    $stats.Duplicates, $stats.Empty, $stats.Implausible, $stats.UnknownPatient, $stats.UnknownTest)
