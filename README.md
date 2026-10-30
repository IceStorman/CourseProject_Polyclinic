# Курсова робота NVBD — Варіант 6 «Поліклініка»

**Тема:** Проектування та аналіз надвеликої бази даних з використанням платформи
Microsoft SQL Server (SSIS, SSAS, SSRS)

**Студент:** _ПІБ_ · **Група:** _група_ · **Варіант:** 6

## Предметна область
Поліклініка: пацієнти, лікарі, хвороби (МКХ-10), історії хвороб, діагнози, візити,
лікарства, призначення та протипоказання. Обсяг даних — понад 50 000 пацієнтів і
500 000 історій хвороб за 10 років (2016–2025).

## Структура репозиторію
```
├── README.md
├── Documentation/
│   └── 01_Проектування_БД.md      — аналіз предметної області, ER-діаграми, нормалізація
└── Database/
    ├── CREATE_DATABASE.sql        — створення БД PolyclinicDB
    ├── CREATE_TABLES.sql          — 16 таблиць
    ├── CREATE_CONSTRAINTS.sql     — FOREIGN KEY, UNIQUE, CHECK, DEFAULT
    ├── CREATE_INDEXES.sql         — індекси (у т.ч. фільтровані та покриваючі)
    ├── CREATE_TRIGGERS.sql        — 6 тригерів (бізнес-правила, аудит)
    ├── CREATE_PROCEDURES.sql      — функції, операційні процедури, процедури звітів
    ├── TEST_CONSTRAINTS.sql       — 22 автоматичні тести обмежень цілісності
    └── deploy.ps1                 — розгортання БД одним скриптом
```

## Вимоги
- Microsoft SQL Server 2022 (Developer), SQL Server Management Studio

## Розгортання бази даних
```powershell
powershell -ExecutionPolicy Bypass -File Database\deploy.ps1 -Server .
```
Скрипт виконує `CREATE_*.sql` по черзі через `sqlcmd` (параметри `-I` — QUOTED_IDENTIFIER ON,
`-f 65001` — UTF-8). Перевірка обмежень цілісності:
```powershell
sqlcmd -S . -E -I -f 65001 -i Database\TEST_CONSTRAINTS.sql
```

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
