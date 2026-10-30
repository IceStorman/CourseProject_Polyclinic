# Перевірка звітів на сервері: параметри (діапазон дат, каскадні списки, булеві, drillthrough)
# та експорт у PDF / Excel / Word. Результати — у SSRS_Projects\Exports.
# Usage:  powershell -ExecutionPolicy Bypass -File SSRS_Projects\Builder\test_reports.ps1
param(
    [string]$ReportServer = "http://localhost/ReportServer",
    [string]$Folder = "/Поліклініка"
)

$ErrorActionPreference = "Stop"
$out = Join-Path $PSScriptRoot "..\Exports"
New-Item -ItemType Directory -Force $out | Out-Null

function Render([string]$report, [string]$params, [string]$format, [string]$file) {
    $url = "$ReportServer`?" + [Uri]::EscapeDataString("$Folder/$report") + "&rs:Format=$format" + $params
    $path = Join-Path $out $file
    $t = Get-Date
    try {
        Invoke-WebRequest $url -UseDefaultCredentials -UseBasicParsing -TimeoutSec 600 -OutFile $path
        "{0,-58} OK   {1,8:N0} KB {2,5:N1} s" -f $file, ((Get-Item $path).Length / 1KB), ((Get-Date) - $t).TotalSeconds
    } catch {
        "{0,-58} FAIL {1}" -f $file, $_.Exception.Message
    }
}
function P([string]$name, [string]$value) { "&" + [Uri]::EscapeDataString($name) + "=" + [Uri]::EscapeDataString($value) }

# 1. Експорт у три формати
Render "01_Лікарі_та_пацієнти" "" "PDF" "01_Лікарі_та_пацієнти.pdf"
Render "01_Лікарі_та_пацієнти" "" "EXCELOPENXML" "01_Лікарі_та_пацієнти.xlsx"
Render "02_Історія_хвороби_пацієнта" "" "WORDOPENXML" "02_Історія_хвороби_пацієнта.docx"
Render "03_Завантаженість_лікарів" "" "EXCELOPENXML" "03_Завантаженість_лікарів.xlsx"
Render "04_Ефективність_лікування" "" "PDF" "04_Ефективність_лікування.pdf"
Render "05_Статистика_захворювань" "" "PDF" "05_Статистика_захворювань.pdf"
Render "06_Дашборд" "" "PDF" "06_Дашборд.pdf"

# 2. Діапазон дат: початок пізніше кінця -> повідомлення про помилку замість таблиці
Render "01_Лікарі_та_пацієнти" ((P "DateFrom" "2025-12-31") + (P "DateTo" "2025-12-01")) "IMAGE&rc:OutputFormat=PNG&rc:EndPage=1" "test_01_невірні_дати.png"

# 3. Каскадні параметри: одне відділення -> спеціальності й лікарі лише цього відділення (за замовчуванням)
Render "01_Лікарі_та_пацієнти" ((P "Department" "Кардіологічне відділення") + (P "OnlyChronic" "true")) "IMAGE&rc:OutputFormat=PNG&rc:EndPage=1" "test_01_каскад_кардіологія_хронічні.png"

# 4. Каскадний пошук пацієнта: інше прізвище
Render "02_Історія_хвороби_пацієнта" (P "LastName" "Коваль") "IMAGE&rc:OutputFormat=PNG&rc:EndPage=1" "test_02_прізвище_Коваль.png"

# 5. Булевий параметр і мультивибір: з профілактичними оглядами, два роки
Render "04_Ефективність_лікування" ((P "IncludePreventive" "true") + (P "Years" "[Дата].[Рік].&[2024]") + (P "Years" "[Дата].[Рік].&[2025]")) "IMAGE&rc:OutputFormat=PNG&rc:EndPage=1" "test_04_з_профілактикою_2024_2025.png"

# 6. Drillthrough-ціль з параметрами (як із звіту 05): хвороба + кілька років
$key = (& sqlcmd -S . -E -d PolyclinicDW -h -1 -W -Q "SET NOCOUNT ON; SELECT DiseaseKey FROM dim.DimDisease WHERE ICDCode = 'E11.9'").Trim()
Render "07_Пацієнти_з_діагнозом" ((P "DiseaseKey" $key) + (P "Years" "2024") + (P "Years" "2025")) "IMAGE&rc:OutputFormat=PNG&rc:EndPage=1" "test_07_діабет_2024_2025.png"
