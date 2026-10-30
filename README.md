# Курсова робота NVBD — Варіант 6 «Поліклініка»

**Тема:** Проектування та аналіз надвеликої бази даних з використанням платформи
Microsoft SQL Server (SSIS, SSAS, SSRS)

**Студент:** _ПІБ_ · **Група:** _група_ · **Варіант:** 6

## Предметна область
Поліклініка: пацієнти, лікарі, хвороби (МКХ-10), історії хвороб, діагнози, візити,
лікарства, призначення та протипоказання. Обсяг даних — понад 50 000 пацієнтів і
500 000 історій хвороб за 10 років (2016–2025).

## Стан виконання

| Етап | Зміст | Стан |
|---|---|---|
| 1. Проектування БД | ER-моделі, нормалізація, SQL-скрипти, тести обмежень | ✅ |
| 2. Генерація даних | 3,57 млн записів (538 тис. історій хвороб), валідація | ✅ |
| 3. ETL (SSIS) | Сховище PolyclinicDW (4 факти, 9 вимірів), 7 пакетів SSIS, SCD2, інкрементальне завантаження | ✅ |
| 4. OLAP-куб (SSAS) | Куб «Поліклініка»: 9 вимірів, 5 груп мір, 24 MDX-обчислення, 4 KPI, партиції, агрегації, перспективи | ✅ |
| 5. Звіти (SSRS) | 8 звітів: таблиця, матриця, діаграми, дашборд, drill-down; 5 типів параметрів | ✅ |

## Структура репозиторію
```
├── README.md
├── Documentation/
│   ├── 01_Проектування_БД.md      — аналіз предметної області, ER-діаграми, нормалізація
│   ├── 02_Генерація_даних.md      — генератор, моделі реалістичності, валідація, статистика
│   ├── 03_ETL_SSIS.md             — сховище даних, пакети SSIS, трансформації, контроль якості
│   ├── 04_OLAP_SSAS.md            — OLAP-куб: виміри, міри, MDX, KPI, оптимізація, тестування
│   └── 05_Звіти_SSRS.md           — звіти SSRS: типи, параметри, інтерактивність, тестування
├── Database/
│   ├── CREATE_DATABASE.sql        — створення БД PolyclinicDB
│   ├── CREATE_TABLES.sql          — 16 таблиць
│   ├── CREATE_CONSTRAINTS.sql     — FOREIGN KEY, UNIQUE, CHECK, DEFAULT
│   ├── CREATE_INDEXES.sql         — індекси (у т.ч. фільтровані та покриваючі)
│   ├── CREATE_TRIGGERS.sql        — 6 тригерів (бізнес-правила, аудит)
│   ├── CREATE_PROCEDURES.sql      — функції, операційні процедури, процедури звітів
│   ├── TEST_CONSTRAINTS.sql       — 22 автоматичні тести обмежень цілісності
│   └── deploy.ps1                 — розгортання БД одним скриптом
├── DataGeneration/
│   ├── 01_REFERENCE_DATA.sql      — довідники (МКХ-10, ліки, протипоказання, географія)
│   ├── 02_DOCTORS_PATIENTS.sql    — лікарі та 55 000 пацієнтів
│   ├── 03_MEDICAL_DATA.sql        — історії хвороб, діагнози, візити, призначення (2016–2025)
│   ├── 04_VALIDATE_AND_STATS.sql  — перевірка бізнес-правил і статистика
│   ├── 05_LAB_FILES.ps1           — CSV-файли лабораторії з навмисними проблемами якості даних
│   ├── generate.ps1               — повна генерація одним запуском (~2,5 хв)
│   └── generation_log.txt         — журнал останньої генерації
├── SSIS_Projects/
│   ├── PolyclinicETL.sln          — рішення Visual Studio
│   ├── PolyclinicETL/             — 7 пакетів .dtsx (00_Master … 06_Load_LabResults), .dtproj
│   ├── DataWarehouse/             — створення PolyclinicDW, процедури ETL, тест інкрементальних змін
│   ├── LabFiles/                  — Inbox → Archive / Rejected (CSV лабораторії)
│   ├── Builder/                   — генератор пакетів SSIS (C#, об'єктна модель SSIS)
│   └── run_etl.ps1                — повний запуск ETL
├── SSAS_Projects/
│   ├── PolyclinicOLAP.sln         — рішення Visual Studio
│   ├── PolyclinicOLAP/            — проєкт SSAS Multidimensional (.dsv, .dim, .cube, .partitions)
│   ├── Builder/                   — створення та обробка куба (C#, AMO), MDX-скрипт, KPI
│   └── Tests/                     — MDX-запити, порівняння продуктивності OLTP / DW / OLAP
└── SSRS_Projects/
    ├── PolyclinicReports.sln      — рішення Visual Studio
    ├── PolyclinicReports/         — 8 звітів .rdl, спільні джерела даних .rds
    ├── Builder/                   — генерація, перевірка, розгортання і тестування звітів
    └── Exports/                   — звіти у PDF / Excel / Word і знімки сторінок
```

## Вимоги
- Microsoft SQL Server 2022 (Developer), SQL Server Management Studio
- Visual Studio 2026 (або 2022) з розширеннями SSIS / SSAS / SSRS (етапи 3–5)
- Integration Services 2022 (компонент SQL Server — для запуску пакетів поза Visual Studio)
- SQL Server Analysis Services 2022 у режимі Multidimensional, SQL Server 2022 Reporting Services

## Розгортання бази даних
```powershell
powershell -ExecutionPolicy Bypass -File Database\deploy.ps1 -Server .
```
Скрипт виконує `CREATE_*.sql` по черзі через `sqlcmd` (параметри `-I` — QUOTED_IDENTIFIER ON,
`-f 65001` — UTF-8). Перевірка обмежень цілісності:
```powershell
sqlcmd -S . -E -I -f 65001 -i Database\TEST_CONSTRAINTS.sql
```

## Генерація даних
```powershell
powershell -ExecutionPolicy Bypass -File DataGeneration\generate.ps1 -Server .
```
Перестворює БД і заповнює її даними за ~2,5 хв.

| Таблиця | Записів |
|---|---:|
| Visits | 1 086 025 |
| Prescriptions | 1 011 646 |
| Diagnoses | 877 443 |
| MedicalRecords | 538 258 |
| Patients | 55 000 |
| **Разом (усі таблиці)** | **3 568 805** |

## ETL та сховище даних
```powershell
powershell -ExecutionPolicy Bypass -File DataGeneration\05_LAB_FILES.ps1                 # CSV-файли лабораторії
powershell -ExecutionPolicy Bypass -File SSIS_Projects\DataWarehouse\deploy_dw.ps1       # створення PolyclinicDW
powershell -ExecutionPolicy Bypass -File SSIS_Projects\run_etl.ps1                       # повний ETL (~45 с)
```
Або у Visual Studio: `SSIS_Projects/PolyclinicETL.sln` → `00_Master.dtsx` → Start.

| Факт | Записів |
|---|---:|
| FactVisit | 1 086 026 |
| FactPrescription | 1 011 647 |
| FactTreatment | 534 961 |
| FactLabResult | 101 558 |

Використані трансформації: Data Cleansing, Data Conversion, Derived Column, Lookup, Aggregate,
Conditional Split, Union All (+ Multicast, Sort, Row Count). Задачі та контейнери: Execute SQL,
Script Task, For Each Loop, Sequence, Execute Package, File System, обробники OnError.

## OLAP-куб
```powershell
powershell -ExecutionPolicy Bypass -File SSAS_Projects\Builder\build_cube.ps1            # розгортання, обробка, агрегації, backup
powershell -ExecutionPolicy Bypass -File SSAS_Projects\Tests\run_all_mdx.ps1             # демонстраційні MDX-запити
powershell -ExecutionPolicy Bypass -File SSAS_Projects\Tests\test_performance.ps1        # OLTP vs DW vs OLAP
```
Або у Visual Studio: `SSAS_Projects/PolyclinicOLAP.sln` → Deploy. Сервер — SSAS 2022 у режимі Multidimensional.

| Показник | Значення |
|---|---|
| Виміри | Дата (рольовий), Пацієнт (SCD2), Лікар (SCD2), Хвороба, Препарат, Вікова група, Тип візиту, Результат лікування, Аналіз |
| Групи мір | Візити, Унікальні пацієнти (Distinct Count), Призначення, Лікування, Аналізи |
| Міри | 33 фізичні (Sum, Count, Min, Max, Distinct Count, AverageOfChildren) + 24 обчислювані |
| MDX | YTD, PY, YoY, MoM, ковзні середні, Топ-10, RANK, бізнес-показники; 4 KPI |
| Оптимізація | MOLAP/HOLAP, партиції за роками, агрегації ~30%, 3 перспективи |
| Швидкодія | статистика захворювань: OLTP 6,4 с → куб 36 мс |

## Звіти
```powershell
python SSRS_Projects\Builder\reports.py                                                   # генерація .rdl
powershell -ExecutionPolicy Bypass -File SSRS_Projects\Builder\deploy_reports.ps1 -Render  # публікація + PDF
powershell -ExecutionPolicy Bypass -File SSRS_Projects\Builder\test_reports.ps1            # параметри та експорт
```
Портал: `http://localhost/Reports` → папка «Поліклініка».

| Звіт | Тип | Джерело |
|---|---|---|
| 01 Список лікарів та їх пацієнтів | Таблиця з групуванням і підсумками | Сховище |
| 02 Історія хвороби пацієнта | Деталізація + вкладений звіт призначень | OLTP |
| 03 Завантаженість лікарів по місяцях | Матриця, теплова карта | OLAP-куб |
| 04 Аналіз ефективності лікування | 4 діаграми (Column, Line, Pie, Bar) | OLAP-куб |
| 05 Статистика захворювань | Drill-down + drillthrough | OLAP-куб |
| 06 Дашборд | KPI, датчики, спарклайни | OLAP-куб |
| 07 Пацієнти з діагнозом | Ціль drillthrough | Сховище |

## Модель даних (коротко)
- **Довідники:** Regions, Cities, Specialties, Departments, DiseaseCategories, Diseases,
  MedicationGroups, Medications
- **Основні:** Patients, Doctors, MedicalRecords (історії хвороб), Diagnoses, Visits,
  Prescriptions, Contraindications
- **Службові:** AuditLog (журнал змін у JSON)

Ключові бізнес-правила, реалізовані в БД:
- один основний діагноз на історію хвороби (фільтрований унікальний індекс);
- візити — лише в межах періоду історії та лише до працюючого лікаря (тригер);
- заборона призначення ліків з абсолютним протипоказанням до поточної, активної або
  хронічної хвороби пацієнта (тригер); попередження про відносні протипоказання (процедура);
- вартість візиту залежить від спеціальності та категорії лікаря (функція `fn_VisitPrice`);
- аудит змін пацієнтів і лікарів (тригери → AuditLog).
