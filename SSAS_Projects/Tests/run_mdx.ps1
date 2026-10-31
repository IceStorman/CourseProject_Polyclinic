param(
    [string]$Query,
    [string]$File,
    [string]$Server = "localhost",
    [string]$Database = "PolyclinicOLAP",
    [int]$MaxRows = 40
)
$ErrorActionPreference = "Stop"
[System.Reflection.Assembly]::Load("Microsoft.AnalysisServices.AdomdClient, Version=15.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91") | Out-Null
if ($File) { $Query = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8) }
$conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=$Server;Catalog=$Database")
$conn.Open()
try {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $reader = $cmd.ExecuteReader()
    $names = @(); for ($c = 0; $c -lt $reader.FieldCount; $c++) {
        $names += ($reader.GetName($c) -replace '\[Measures\]\.', '' -replace '\.\[MEMBER_CAPTION\]', '' -replace '[\[\]]', '') }
    ($names -join " | ")
    $rows = 0
    while ($reader.Read()) {
        $rows++
        if ($rows -gt $MaxRows) { continue }
        $vals = @(); for ($c = 0; $c -lt $reader.FieldCount; $c++) {
            $x = $reader.GetValue($c)
            if ($x -is [double]) { $x = [math]::Round($x, 4) }
            $vals += "$x" }
        ($vals -join " | ")
    }
    $reader.Close()
    $sw.Stop()
    if ($rows -gt $MaxRows) { "... ($rows rows)" }
    "-- $rows rows, $($sw.ElapsedMilliseconds) ms"
}
finally { $conn.Close() }
