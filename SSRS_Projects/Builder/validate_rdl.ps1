# Validates every .rdl in a folder against the RDL schema shipped with the SSRS designer (2010 schema; the 2016
# namespace is mapped to it in memory - the 2016 format only adds elements these reports do not use).
# Usage:  powershell -ExecutionPolicy Bypass -File SSRS_Projects\Builder\validate_rdl.ps1 -Folder SSRS_Projects\PolyclinicReports
param([string]$Folder)
$xsdDir = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\SSRS"
$set = New-Object System.Xml.Schema.XmlSchemaSet
Get-ChildItem $xsdDir -Filter "ReportDefinition2010.xsd" | ForEach-Object { $set.Add("http://schemas.microsoft.com/sqlserver/reporting/2010/01/reportdefinition", $_.FullName) | Out-Null }
$set.Compile()
foreach ($f in Get-ChildItem $Folder -Filter *.rdl) {
    $errors = New-Object System.Collections.Generic.List[string]
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.ValidationType = [System.Xml.ValidationType]::Schema
    $settings.Schemas = $set
    $settings.ValidationFlags = [System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings
    $handler = [System.Xml.Schema.ValidationEventHandler]{ param($s, $e) if ($e.Severity -eq [System.Xml.Schema.XmlSeverityType]::Error -and $e.Message -notmatch "reportdesigner|defaultfontfamily") { $errors.Add("pos $($e.Exception.LinePosition): $($e.Message)") } }
    $settings.add_ValidationEventHandler($handler)
    $text = [IO.File]::ReadAllText($f.FullName)
    $text = $text.Replace("reporting/2016/01/reportdefinition""", "reporting/2010/01/reportdefinition""")
    $text = [regex]::Replace($text, '<df:DefaultFontFamily>[^<]*</df:DefaultFontFamily>', '')
    $text = $text.Replace(' MustUnderstand="df"', '')
    $r = [System.Xml.XmlReader]::Create((New-Object IO.StringReader $text), $settings)
    try { while ($r.Read()) {} } catch { $errors.Add("XML: " + $_.Exception.Message) } finally { $r.Close() }
    "{0}: {1} issue(s)" -f $f.Name, $errors.Count
    $errors | Select-Object -Unique -First 8 | ForEach-Object { "   $_" }
}
