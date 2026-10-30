/* =====================================================================
   Курсова робота NVBD, варіант 6 «Поліклініка»
   Етап 3. Сховище даних PolyclinicDW (схема «сузір'я» — 4 таблиці фактів
   зі спільними вимірами, кожна окремо — «зірка»).
     dim.*   — виміри (9)        fact.* — факти (4)
     stg.*   — проміжні таблиці  etl.*  — журнали та службові таблиці ETL
   УВАГА: існуюча БД PolyclinicDW буде видалена.
   ===================================================================== */
USE master;
GO
IF DB_ID(N'PolyclinicDW') IS NOT NULL
BEGIN
    ALTER DATABASE PolyclinicDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PolyclinicDW;
END
GO
CREATE DATABASE PolyclinicDW COLLATE Ukrainian_CI_AS;
GO
ALTER DATABASE PolyclinicDW MODIFY FILE (NAME = N'PolyclinicDW',     SIZE = 1024MB, FILEGROWTH = 256MB);
ALTER DATABASE PolyclinicDW MODIFY FILE (NAME = N'PolyclinicDW_log', SIZE = 512MB,  FILEGROWTH = 256MB);
ALTER DATABASE PolyclinicDW SET RECOVERY SIMPLE;
GO
USE PolyclinicDW;
GO
EXEC('CREATE SCHEMA dim');
EXEC('CREATE SCHEMA fact');
EXEC('CREATE SCHEMA stg');
EXEC('CREATE SCHEMA etl');
GO

/* =====================================================================
   ВИМІРИ
   ===================================================================== */

-- Календар (генерується процедурою etl.usp_Load_DimDate)
CREATE TABLE dim.DimDate (
    DateKey        INT          NOT NULL CONSTRAINT PK_DimDate PRIMARY KEY,   -- yyyymmdd
    FullDate       DATE         NOT NULL,
    DayOfMonth     TINYINT      NOT NULL,
    DayOfWeek      TINYINT      NOT NULL,   -- 1 = понеділок
    DayName        NVARCHAR(15) NOT NULL,
    WeekOfYear     TINYINT      NOT NULL,   -- ISO
    MonthNo        TINYINT      NOT NULL,
    MonthName      NVARCHAR(15) NOT NULL,
    MonthYear      CHAR(7)      NOT NULL,   -- 2025-01
    MonthYearName  NVARCHAR(25) NOT NULL,   -- Січень 2025
    QuarterNo      TINYINT      NOT NULL,
    QuarterName    NVARCHAR(10) NOT NULL,   -- I кв.
    YearNo         SMALLINT     NOT NULL,
    Season         NVARCHAR(10) NOT NULL,
    IsWeekend      BIT          NOT NULL,
    IsHoliday      BIT          NOT NULL,
    HolidayName    NVARCHAR(50) NULL,
    IsWorkingDay   BIT          NOT NULL
);

-- Пацієнт: SCD Type 2 за містом/регіоном та наявністю страховки, SCD Type 1 — решта
CREATE TABLE dim.DimPatient (
    PatientKey     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimPatient PRIMARY KEY,
    PatientID      INT           NOT NULL,      -- бізнес-ключ (OLTP)
    LastName       NVARCHAR(50)  NOT NULL,
    FirstName      NVARCHAR(50)  NOT NULL,
    MiddleName     NVARCHAR(50)  NULL,
    FullName       NVARCHAR(160) NOT NULL,
    Gender         NCHAR(1)      NOT NULL,
    GenderName     NVARCHAR(10)  NOT NULL,
    BirthDate      DATE          NOT NULL,
    BirthYear      SMALLINT      NOT NULL,
    BloodType      NVARCHAR(10)  NOT NULL,
    City           NVARCHAR(100) NOT NULL,      -- SCD2
    Region         NVARCHAR(100) NOT NULL,      -- SCD2
    CityGroup      NVARCHAR(30)  NOT NULL,      -- SCD2: Львів / Львівська область / Інші регіони
    HasInsurance   NVARCHAR(10)  NOT NULL,      -- SCD2: Так / Ні
    ValidFrom      DATE          NOT NULL,
    ValidTo        DATE          NOT NULL,
    IsCurrent      BIT           NOT NULL,
    ETLRunID       INT           NULL
);
CREATE UNIQUE INDEX UX_DimPatient_Current ON dim.DimPatient (PatientID) WHERE IsCurrent = 1;
CREATE INDEX IX_DimPatient_BK ON dim.DimPatient (PatientID, ValidFrom);

-- Лікар: SCD Type 2 за спеціальністю, відділенням, категорією
CREATE TABLE dim.DimDoctor (
    DoctorKey        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimDoctor PRIMARY KEY,
    DoctorID         INT           NOT NULL,
    FullName         NVARCHAR(160) NOT NULL,
    ShortName        NVARCHAR(80)  NOT NULL,    -- Шевченко О. І.
    Gender           NCHAR(1)      NOT NULL,
    Specialty        NVARCHAR(100) NOT NULL,    -- SCD2
    Department       NVARCHAR(100) NOT NULL,    -- SCD2
    Category         NVARCHAR(20)  NOT NULL,    -- SCD2
    HireDate         DATE          NOT NULL,
    DismissalDate    DATE          NULL,
    EmploymentStatus NVARCHAR(20)  NOT NULL,    -- Працює / Звільнений
    ValidFrom        DATE          NOT NULL,
    ValidTo          DATE          NOT NULL,
    IsCurrent        BIT           NOT NULL,
    ETLRunID         INT           NULL
);
CREATE UNIQUE INDEX UX_DimDoctor_Current ON dim.DimDoctor (DoctorID) WHERE IsCurrent = 1;

-- Хвороба (SCD Type 1), ієрархія Клас МКХ-10 → Хвороба
CREATE TABLE dim.DimDisease (
    DiseaseKey       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimDisease PRIMARY KEY,
    DiseaseID        INT           NOT NULL CONSTRAINT UQ_DimDisease_BK UNIQUE,
    ICDCode          NVARCHAR(10)  NOT NULL,
    DiseaseName      NVARCHAR(200) NOT NULL,
    DiseaseFullName  NVARCHAR(220) NOT NULL,    -- J06.9 Гостра інфекція...
    ICDChapter       NVARCHAR(10)  NOT NULL,
    CategoryName     NVARCHAR(150) NOT NULL,
    IsChronic        BIT           NOT NULL,
    CourseType       NVARCHAR(15)  NOT NULL,    -- Хронічна / Гостра
    IsInfectious     BIT           NOT NULL,
    Severity         TINYINT       NOT NULL,
    SeverityName     NVARCHAR(20)  NOT NULL,
    AvgTreatmentDays SMALLINT      NOT NULL,
    Seasonality      NVARCHAR(20)  NOT NULL,
    ETLRunID         INT           NULL
);

-- Лікарський засіб (SCD Type 1), ієрархія Фармгрупа → Препарат
CREATE TABLE dim.DimMedication (
    MedicationKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimMedication PRIMARY KEY,
    MedicationID       INT           NOT NULL CONSTRAINT UQ_DimMedication_BK UNIQUE,
    MedicationName     NVARCHAR(150) NOT NULL,
    ActiveSubstance    NVARCHAR(150) NOT NULL,
    GroupName          NVARCHAR(100) NOT NULL,
    DosageForm         NVARCHAR(50)  NOT NULL,
    Manufacturer       NVARCHAR(100) NOT NULL,
    PrescriptionStatus NVARCHAR(20)  NOT NULL,  -- За рецептом / Без рецепта
    CurrentPrice       DECIMAL(10,2) NOT NULL,
    PriceCategory      NVARCHAR(20)  NOT NULL,  -- до 100 грн / 100–500 грн / понад 500 грн
    ETLRunID           INT           NULL
);

-- Вікова група пацієнта на дату події (статичний вимір)
CREATE TABLE dim.DimAgeGroup (
    AgeGroupKey  INT          NOT NULL CONSTRAINT PK_DimAgeGroup PRIMARY KEY,
    AgeGroup     NVARCHAR(15) NOT NULL,
    AgeCategory  NVARCHAR(20) NOT NULL,   -- Діти / Дорослі / Літні
    MinAge       TINYINT      NOT NULL,
    MaxAge       TINYINT      NOT NULL
);

-- Тип і статус візиту (junk-вимір, статичний)
CREATE TABLE dim.DimVisitType (
    VisitTypeKey INT          NOT NULL CONSTRAINT PK_DimVisitType PRIMARY KEY,
    VisitType    NVARCHAR(20) NOT NULL,
    VisitStatus  NVARCHAR(15) NOT NULL,
    IsCompleted  BIT          NOT NULL
);

-- Результат лікування (статичний)
CREATE TABLE dim.DimOutcome (
    OutcomeKey   INT          NOT NULL CONSTRAINT PK_DimOutcome PRIMARY KEY,
    Outcome      NVARCHAR(30) NOT NULL,
    OutcomeGroup NVARCHAR(15) NOT NULL,   -- Позитивний / Нейтральний / Негативний
    IsPositive   BIT          NOT NULL,
    SortOrder    TINYINT      NOT NULL
);

-- Лабораторний аналіз (статичний) + словник варіантів назв для очищення даних
CREATE TABLE dim.DimLabTest (
    LabTestKey   INT           NOT NULL CONSTRAINT PK_DimLabTest PRIMARY KEY,
    TestCode     NVARCHAR(10)  NOT NULL CONSTRAINT UQ_DimLabTest_Code UNIQUE,
    TestName     NVARCHAR(100) NOT NULL,
    TestGroup    NVARCHAR(50)  NOT NULL,
    Unit         NVARCHAR(20)  NOT NULL,
    RefMin       DECIMAL(10,3) NOT NULL,
    RefMax       DECIMAL(10,3) NOT NULL,
    PlausibleMax DECIMAL(10,3) NOT NULL   -- більші значення — помилка введення
);

CREATE TABLE dim.LabTestAlias (
    Alias      NVARCHAR(50) NOT NULL CONSTRAINT PK_LabTestAlias PRIMARY KEY,   -- нормалізована назва (UPPER, без пробілів)
    LabTestKey INT          NOT NULL CONSTRAINT FK_LabTestAlias_Test REFERENCES dim.DimLabTest (LabTestKey)
);
GO

/* =====================================================================
   ФАКТИ
   ===================================================================== */

-- Візит (зерно: один візит)
CREATE TABLE fact.FactVisit (
    VisitID           BIGINT        NOT NULL CONSTRAINT PK_FactVisit PRIMARY KEY NONCLUSTERED,
    RecordID          INT           NOT NULL,   -- вироджений вимір (історія хвороби)
    DateKey           INT           NOT NULL CONSTRAINT FK_FactVisit_Date      REFERENCES dim.DimDate (DateKey),
    PatientKey        INT           NOT NULL CONSTRAINT FK_FactVisit_Patient   REFERENCES dim.DimPatient (PatientKey),
    DoctorKey         INT           NOT NULL CONSTRAINT FK_FactVisit_Doctor    REFERENCES dim.DimDoctor (DoctorKey),
    DiseaseKey        INT           NOT NULL CONSTRAINT FK_FactVisit_Disease   REFERENCES dim.DimDisease (DiseaseKey),
    VisitTypeKey      INT           NOT NULL CONSTRAINT FK_FactVisit_VisitType REFERENCES dim.DimVisitType (VisitTypeKey),
    AgeGroupKey       INT           NOT NULL CONSTRAINT FK_FactVisit_AgeGroup  REFERENCES dim.DimAgeGroup (AgeGroupKey),
    VisitHour         TINYINT       NOT NULL,
    DurationMin       SMALLINT      NOT NULL,
    Cost              DECIMAL(12,2) NOT NULL,
    IsCompleted       INT           NOT NULL,   -- 0/1 (для SUM у кубі)
    IsNoShow          INT           NOT NULL,
    PrescriptionCount INT           NOT NULL,
    MedicationCost    DECIMAL(12,2) NOT NULL,
    ETLRunID          INT           NULL
);
CREATE CLUSTERED INDEX CIX_FactVisit_Date ON fact.FactVisit (DateKey);

-- Призначення ліків (зерно: одне призначення)
CREATE TABLE fact.FactPrescription (
    PrescriptionID BIGINT        NOT NULL CONSTRAINT PK_FactPrescription PRIMARY KEY NONCLUSTERED,
    VisitID        BIGINT        NOT NULL,
    DateKey        INT           NOT NULL CONSTRAINT FK_FactPrescr_Date       REFERENCES dim.DimDate (DateKey),
    PatientKey     INT           NOT NULL CONSTRAINT FK_FactPrescr_Patient    REFERENCES dim.DimPatient (PatientKey),
    DoctorKey      INT           NOT NULL CONSTRAINT FK_FactPrescr_Doctor     REFERENCES dim.DimDoctor (DoctorKey),
    DiseaseKey     INT           NOT NULL CONSTRAINT FK_FactPrescr_Disease    REFERENCES dim.DimDisease (DiseaseKey),
    MedicationKey  INT           NOT NULL CONSTRAINT FK_FactPrescr_Medication REFERENCES dim.DimMedication (MedicationKey),
    AgeGroupKey    INT           NOT NULL CONSTRAINT FK_FactPrescr_AgeGroup   REFERENCES dim.DimAgeGroup (AgeGroupKey),
    Quantity       SMALLINT      NOT NULL,
    UnitPrice      DECIMAL(10,2) NOT NULL,
    TotalCost      DECIMAL(12,2) NOT NULL,
    DurationDays   SMALLINT      NOT NULL,
    TimesPerDay    TINYINT       NOT NULL,
    ETLRunID       INT           NULL
);
CREATE CLUSTERED INDEX CIX_FactPrescription_Date ON fact.FactPrescription (DateKey);

-- Випадок лікування (зерно: закрита історія хвороби) — для аналізу ефективності лікування
CREATE TABLE fact.FactTreatment (
    RecordID            INT           NOT NULL CONSTRAINT PK_FactTreatment PRIMARY KEY NONCLUSTERED,
    OpenDateKey         INT           NOT NULL CONSTRAINT FK_FactTreat_OpenDate  REFERENCES dim.DimDate (DateKey),
    CloseDateKey        INT           NOT NULL CONSTRAINT FK_FactTreat_CloseDate REFERENCES dim.DimDate (DateKey),
    PatientKey          INT           NOT NULL CONSTRAINT FK_FactTreat_Patient   REFERENCES dim.DimPatient (PatientKey),
    DoctorKey           INT           NOT NULL CONSTRAINT FK_FactTreat_Doctor    REFERENCES dim.DimDoctor (DoctorKey),
    DiseaseKey          INT           NOT NULL CONSTRAINT FK_FactTreat_Disease   REFERENCES dim.DimDisease (DiseaseKey),
    OutcomeKey          INT           NOT NULL CONSTRAINT FK_FactTreat_Outcome   REFERENCES dim.DimOutcome (OutcomeKey),
    AgeGroupKey         INT           NOT NULL CONSTRAINT FK_FactTreat_AgeGroup  REFERENCES dim.DimAgeGroup (AgeGroupKey),
    Severity            TINYINT       NOT NULL,
    TreatmentDays       INT           NOT NULL,
    NormTreatmentDays   INT           NOT NULL,
    DaysOverNorm        INT           NOT NULL,
    VisitCount          INT           NOT NULL,
    CompletedVisitCount INT           NOT NULL,
    TotalVisitCost      DECIMAL(12,2) NOT NULL,
    ComorbidityCount    INT           NOT NULL,
    ComplicationCount   INT           NOT NULL,
    IsRecovered         INT           NOT NULL,   -- 0/1
    IsPositive          INT           NOT NULL,   -- одужання або покращення
    IsWithinNorm        INT           NOT NULL,   -- тривалість у межах нормативу
    ETLRunID            INT           NULL
);
CREATE CLUSTERED INDEX CIX_FactTreatment_Close ON fact.FactTreatment (CloseDateKey);

-- Результат лабораторного аналізу (джерело — CSV-файли партнерської лабораторії)
CREATE TABLE fact.FactLabResult (
    LabResultID  BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactLabResult PRIMARY KEY NONCLUSTERED,
    LabOrderNo   NVARCHAR(20)  NOT NULL,
    DateKey      INT           NOT NULL CONSTRAINT FK_FactLab_Date     REFERENCES dim.DimDate (DateKey),
    PatientKey   INT           NOT NULL CONSTRAINT FK_FactLab_Patient  REFERENCES dim.DimPatient (PatientKey),
    LabTestKey   INT           NOT NULL CONSTRAINT FK_FactLab_Test     REFERENCES dim.DimLabTest (LabTestKey),
    AgeGroupKey  INT           NOT NULL CONSTRAINT FK_FactLab_AgeGroup REFERENCES dim.DimAgeGroup (AgeGroupKey),
    ResultValue  DECIMAL(10,3) NOT NULL,
    IsAbnormal   INT           NOT NULL,
    IsHigh       INT           NOT NULL,
    IsLow        INT           NOT NULL,
    SourceFile   NVARCHAR(260) NOT NULL,
    ETLRunID     INT           NULL,
    CONSTRAINT UQ_FactLabResult_Order UNIQUE (LabOrderNo, LabTestKey)
);
CREATE CLUSTERED INDEX CIX_FactLabResult_Date ON fact.FactLabResult (DateKey);
GO

/* =====================================================================
   ПРОМІЖНІ ТАБЛИЦІ (STAGING)
   ===================================================================== */
CREATE TABLE stg.Patient (
    PatientID    INT           NOT NULL PRIMARY KEY,
    LastName     NVARCHAR(50)  NOT NULL,
    FirstName    NVARCHAR(50)  NOT NULL,
    MiddleName   NVARCHAR(50)  NULL,
    FullName     NVARCHAR(160) NOT NULL,
    Gender       NCHAR(1)      NOT NULL,
    GenderName   NVARCHAR(10)  NOT NULL,
    BirthDate    DATE          NOT NULL,
    BirthYear    SMALLINT      NOT NULL,
    BloodType    NVARCHAR(10)  NOT NULL,
    City         NVARCHAR(100) NOT NULL,
    Region       NVARCHAR(100) NOT NULL,
    CityGroup    NVARCHAR(30)  NOT NULL,
    HasInsurance NVARCHAR(10)  NOT NULL,
    ModifiedAt   DATETIME2(0)  NOT NULL
);

CREATE TABLE stg.Doctor (
    DoctorID         INT           NOT NULL PRIMARY KEY,
    FullName         NVARCHAR(160) NOT NULL,
    ShortName        NVARCHAR(80)  NOT NULL,
    Gender           NCHAR(1)      NOT NULL,
    Specialty        NVARCHAR(100) NOT NULL,
    Department       NVARCHAR(100) NOT NULL,
    Category         NVARCHAR(20)  NOT NULL,
    HireDate         DATE          NOT NULL,
    DismissalDate    DATE          NULL,
    EmploymentStatus NVARCHAR(20)  NOT NULL,
    ModifiedAt       DATETIME2(0)  NOT NULL
);

-- Змінені рядки SCD Type 1 (виявляє SSIS: Lookup + Conditional Split)
CREATE TABLE stg.DiseaseUpdate (
    DiseaseKey       INT           NOT NULL PRIMARY KEY,
    ICDCode          NVARCHAR(10)  NOT NULL,
    DiseaseName      NVARCHAR(200) NOT NULL,
    DiseaseFullName  NVARCHAR(220) NOT NULL,
    ICDChapter       NVARCHAR(10)  NOT NULL,
    CategoryName     NVARCHAR(150) NOT NULL,
    IsChronic        BIT           NOT NULL,
    CourseType       NVARCHAR(15)  NOT NULL,
    IsInfectious     BIT           NOT NULL,
    Severity         TINYINT       NOT NULL,
    SeverityName     NVARCHAR(20)  NOT NULL,
    AvgTreatmentDays SMALLINT      NOT NULL,
    Seasonality      NVARCHAR(20)  NOT NULL
);

CREATE TABLE stg.MedicationUpdate (
    MedicationKey      INT           NOT NULL PRIMARY KEY,
    MedicationName     NVARCHAR(150) NOT NULL,
    ActiveSubstance    NVARCHAR(150) NOT NULL,
    GroupName          NVARCHAR(100) NOT NULL,
    DosageForm         NVARCHAR(50)  NOT NULL,
    Manufacturer       NVARCHAR(100) NOT NULL,
    PrescriptionStatus NVARCHAR(20)  NOT NULL,
    CurrentPrice       DECIMAL(10,2) NOT NULL,
    PriceCategory      NVARCHAR(20)  NOT NULL
);
GO

/* =====================================================================
   СЛУЖБОВІ ТАБЛИЦІ ETL (аудит і контроль якості)
   ===================================================================== */
CREATE TABLE etl.ETLRun (
    RunID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ETLRun PRIMARY KEY,
    StartedAt  DATETIME2(0)  NOT NULL CONSTRAINT DF_ETLRun_Start DEFAULT (SYSDATETIME()),
    FinishedAt DATETIME2(0)  NULL,
    Status     NVARCHAR(15)  NOT NULL CONSTRAINT DF_ETLRun_Status DEFAULT (N'Running'),  -- Running / Succeeded / Failed
    StartedBy  SYSNAME       NOT NULL CONSTRAINT DF_ETLRun_User DEFAULT (SUSER_SNAME())
);

CREATE TABLE etl.PackageLog (
    LogID        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PackageLog PRIMARY KEY,
    RunID        INT           NOT NULL CONSTRAINT FK_PackageLog_Run REFERENCES etl.ETLRun (RunID),
    PackageName  NVARCHAR(100) NOT NULL,
    StartedAt    DATETIME2(0)  NOT NULL CONSTRAINT DF_PackageLog_Start DEFAULT (SYSDATETIME()),
    FinishedAt   DATETIME2(0)  NULL,
    DurationSec  AS DATEDIFF(SECOND, StartedAt, FinishedAt),
    Status       NVARCHAR(15)  NOT NULL CONSTRAINT DF_PackageLog_Status DEFAULT (N'Running'),
    RowsRead     INT           NULL,
    RowsInserted INT           NULL,
    RowsUpdated  INT           NULL,
    RowsRejected INT           NULL
);

CREATE TABLE etl.ErrorLog (
    ErrorID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ErrorLog PRIMARY KEY,
    LogID        INT            NULL,
    PackageName  NVARCHAR(100)  NULL,
    SourceName   NVARCHAR(200)  NULL,
    ErrorCode    INT            NULL,
    ErrorMessage NVARCHAR(4000) NULL,
    LoggedAt     DATETIME2(0)   NOT NULL CONSTRAINT DF_ErrorLog_At DEFAULT (SYSDATETIME())
);

-- Відхилені рядки даних (не пройшли перевірку або не знайдено ключ виміру)
CREATE TABLE etl.RejectedRows (
    RejectID     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RejectedRows PRIMARY KEY,
    RunID        INT            NULL,
    PackageName  NVARCHAR(100)  NOT NULL,
    SourceKey    NVARCHAR(100)  NULL,
    RejectReason NVARCHAR(200)  NOT NULL,
    RowData      NVARCHAR(1000) NULL,
    SourceFile   NVARCHAR(260)  NULL,
    LoggedAt     DATETIME2(0)   NOT NULL CONSTRAINT DF_Rejected_At DEFAULT (SYSDATETIME())
);

-- Межі інкрементального завантаження
CREATE TABLE etl.Watermark (
    TableName   NVARCHAR(100) NOT NULL CONSTRAINT PK_Watermark PRIMARY KEY,
    LastID      BIGINT        NOT NULL,
    LastDate    DATETIME2(0)  NOT NULL,
    UpdatedAt   DATETIME2(0)  NOT NULL CONSTRAINT DF_Watermark_At DEFAULT (SYSDATETIME())
);

-- Оброблені файли лабораторії
CREATE TABLE etl.FileLog (
    FileLogID    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FileLog PRIMARY KEY,
    RunID        INT           NULL,
    LogID        INT           NULL,
    FileName     NVARCHAR(260) NOT NULL,
    FileSizeKB   INT           NULL,
    LineCount    INT           NULL,
    RowsRead     INT           NULL,
    RowsLoaded   INT           NULL,
    RowsRejected INT           NULL,
    RowsDuplicate INT          NULL,
    Status       NVARCHAR(15)  NOT NULL,   -- Loaded / Rejected
    Message      NVARCHAR(500) NULL,
    ProcessedAt  DATETIME2(0)  NOT NULL CONSTRAINT DF_FileLog_At DEFAULT (SYSDATETIME())
);
GO
