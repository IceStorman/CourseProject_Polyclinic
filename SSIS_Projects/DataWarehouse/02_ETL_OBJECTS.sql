/* =====================================================================
   Курсова робота NVBD, варіант 6 «Поліклініка»
   Етап 3. Службові об'єкти сховища:
     - статичні виміри та «невідомі» члени (-1)
     - генерація календаря dim.DimDate
     - процедури аудиту ETL (запуск, пакет, помилки, watermark)
     - процедури SCD Type 2 (пацієнт, лікар) і SCD Type 1 (хвороба, ліки)
     - представлення для звітів про якість ETL
   ===================================================================== */
USE PolyclinicDW;
GO
SET NOCOUNT ON;
GO

/* ===================== СТАТИЧНІ ВИМІРИ ===================== */
INSERT dim.DimAgeGroup (AgeGroupKey, AgeGroup, AgeCategory, MinAge, MaxAge) VALUES
 (-1, N'Невідомо', N'Невідомо', 0, 0),
 ( 1, N'0-17',  N'Діти',    0,  17),
 ( 2, N'18-34', N'Дорослі', 18, 34),
 ( 3, N'35-49', N'Дорослі', 35, 49),
 ( 4, N'50-64', N'Дорослі', 50, 64),
 ( 5, N'65+',   N'Літні',   65, 120);

INSERT dim.DimVisitType (VisitTypeKey, VisitType, VisitStatus, IsCompleted)
SELECT -1, N'Невідомо', N'Невідомо', 0
UNION ALL
SELECT ROW_NUMBER() OVER (ORDER BY t.SortT, s.SortS), t.VisitType, s.VisitStatus, IIF(s.VisitStatus = N'Відбувся', 1, 0)
FROM (VALUES (1, N'Первинний'), (2, N'Повторний'), (3, N'Консультація'), (4, N'Виклик додому')) t(SortT, VisitType)
CROSS JOIN (VALUES (1, N'Відбувся'), (2, N'Скасовано'), (3, N'Неявка')) s(SortS, VisitStatus);

INSERT dim.DimOutcome (OutcomeKey, Outcome, OutcomeGroup, IsPositive, SortOrder) VALUES
 (-1, N'Невідомо',                 N'Невідомо',    0, 99),
 ( 1, N'Одужання',                 N'Позитивний',  1, 1),
 ( 2, N'Покращення',               N'Позитивний',  1, 2),
 ( 3, N'Без змін',                 N'Нейтральний', 0, 3),
 ( 4, N'Перехід у хронічну форму', N'Негативний',  0, 4),
 ( 5, N'Погіршення',               N'Негативний',  0, 5),
 ( 6, N'Госпіталізація',           N'Негативний',  0, 6);

INSERT dim.DimLabTest (LabTestKey, TestCode, TestName, TestGroup, Unit, RefMin, RefMax, PlausibleMax) VALUES
 (-1, N'UNKNOWN', N'Невідомо',                 N'Невідомо',          N'',          0,     0,     0),
 ( 1, N'GLU',     N'Глюкоза крові',            N'Біохімія',          N'ммоль/л',   3.9,   6.1,   40),
 ( 2, N'HBA1C',   N'Глікований гемоглобін',    N'Біохімія',          N'%',         4.0,   6.0,   20),
 ( 3, N'CHOL',    N'Загальний холестерин',     N'Ліпідний профіль',  N'ммоль/л',   3.0,   5.2,   20),
 ( 4, N'LDL',     N'Холестерин ЛПНЩ',          N'Ліпідний профіль',  N'ммоль/л',   0.0,   3.0,   15),
 ( 5, N'HGB',     N'Гемоглобін',               N'Загальний аналіз',  N'г/л',       120,   160,   250),
 ( 6, N'WBC',     N'Лейкоцити',                N'Загальний аналіз',  N'×10⁹/л',    4.0,   9.0,   100),
 ( 7, N'CRP',     N'С-реактивний білок',       N'Запалення',         N'мг/л',      0.0,   5.0,   400),
 ( 8, N'CREA',    N'Креатинін',                N'Біохімія',          N'мкмоль/л',  62,    115,   2000),
 ( 9, N'TSH',     N'Тиреотропний гормон',      N'Гормони',           N'мМО/л',     0.4,   4.0,   100),
 (10, N'ALT',     N'Аланінамінотрансфераза',   N'Біохімія',          N'Од/л',      0,     40,    3000),
 (11, N'URIC',    N'Сечова кислота',           N'Біохімія',          N'мкмоль/л',  150,   420,   1500),
 (12, N'FERR',    N'Феритин',                  N'Біохімія',          N'нг/мл',     15,    150,   3000);

-- Варіанти назв аналізів у файлах лабораторії (після нормалізації: UPPER, без пробілів і дефісів)
INSERT dim.LabTestAlias (Alias, LabTestKey)
SELECT a.Alias, t.LabTestKey
FROM (VALUES
 (N'GLU', N'GLU'), (N'GLUCOSE', N'GLU'), (N'ГЛЮКОЗА', N'GLU'), (N'ГЛЮКОЗАКРОВІ', N'GLU'),
 (N'HBA1C', N'HBA1C'), (N'A1C', N'HBA1C'), (N'ГЛІКОВАНИЙГЕМОГЛОБІН', N'HBA1C'),
 (N'CHOL', N'CHOL'), (N'CHOLESTEROL', N'CHOL'), (N'ХОЛЕСТЕРИН', N'CHOL'), (N'ЗАГАЛЬНИЙХОЛЕСТЕРИН', N'CHOL'),
 (N'LDL', N'LDL'), (N'LDLC', N'LDL'), (N'ЛПНЩ', N'LDL'),
 (N'HGB', N'HGB'), (N'HB', N'HGB'), (N'HEMOGLOBIN', N'HGB'), (N'ГЕМОГЛОБІН', N'HGB'),
 (N'WBC', N'WBC'), (N'LEUKOCYTES', N'WBC'), (N'ЛЕЙКОЦИТИ', N'WBC'),
 (N'CRP', N'CRP'), (N'СРБ', N'CRP'), (N'CREACTIVEPROTEIN', N'CRP'),
 (N'CREA', N'CREA'), (N'CREATININE', N'CREA'), (N'КРЕАТИНІН', N'CREA'),
 (N'TSH', N'TSH'), (N'ТТГ', N'TSH'),
 (N'ALT', N'ALT'), (N'ALAT', N'ALT'), (N'АЛТ', N'ALT'),
 (N'URIC', N'URIC'), (N'URICACID', N'URIC'), (N'СЕЧОВАКИСЛОТА', N'URIC'),
 (N'FERR', N'FERR'), (N'FERRITIN', N'FERR'), (N'ФЕРИТИН', N'FERR')
) a(Alias, Code)
JOIN dim.DimLabTest t ON t.TestCode = a.Code;

-- «Невідомі» члени для вимірів з IDENTITY
SET IDENTITY_INSERT dim.DimPatient ON;
INSERT dim.DimPatient (PatientKey, PatientID, LastName, FirstName, MiddleName, FullName, Gender, GenderName, BirthDate, BirthYear,
                       BloodType, City, Region, CityGroup, HasInsurance, ValidFrom, ValidTo, IsCurrent)
VALUES (-1, -1, N'Невідомо', N'Невідомо', NULL, N'Невідомий пацієнт', 'U', N'Невідомо', '1900-01-01', 1900,
        N'Невідомо', N'Невідомо', N'Невідомо', N'Невідомо', N'Невідомо', '1900-01-01', '9999-12-31', 1);
SET IDENTITY_INSERT dim.DimPatient OFF;

SET IDENTITY_INSERT dim.DimDoctor ON;
INSERT dim.DimDoctor (DoctorKey, DoctorID, FullName, ShortName, Gender, Specialty, Department, Category, HireDate,
                      DismissalDate, EmploymentStatus, ValidFrom, ValidTo, IsCurrent)
VALUES (-1, -1, N'Невідомий лікар', N'Невідомо', 'U', N'Невідомо', N'Невідомо', N'Невідомо', '1900-01-01',
        NULL, N'Невідомо', '1900-01-01', '9999-12-31', 1);
SET IDENTITY_INSERT dim.DimDoctor OFF;

SET IDENTITY_INSERT dim.DimDisease ON;
INSERT dim.DimDisease (DiseaseKey, DiseaseID, ICDCode, DiseaseName, DiseaseFullName, ICDChapter, CategoryName, IsChronic,
                       CourseType, IsInfectious, Severity, SeverityName, AvgTreatmentDays, Seasonality)
VALUES (-1, -1, N'—', N'Невідомо', N'Невідомо', N'—', N'Невідомо', 0, N'Невідомо', 0, 0, N'Невідомо', 0, N'Невідомо');
SET IDENTITY_INSERT dim.DimDisease OFF;

SET IDENTITY_INSERT dim.DimMedication ON;
INSERT dim.DimMedication (MedicationKey, MedicationID, MedicationName, ActiveSubstance, GroupName, DosageForm, Manufacturer,
                          PrescriptionStatus, CurrentPrice, PriceCategory)
VALUES (-1, -1, N'Невідомо', N'Невідомо', N'Невідомо', N'Невідомо', N'Невідомо', N'Невідомо', 0, N'Невідомо');
SET IDENTITY_INSERT dim.DimMedication OFF;

INSERT etl.Watermark (TableName, LastID, LastDate) VALUES
 (N'DimPatient',       0, '1900-01-01'),
 (N'DimDoctor',        0, '1900-01-01'),
 (N'FactVisit',        0, '1900-01-01'),
 (N'FactPrescription', 0, '1900-01-01'),
 (N'FactTreatment',    0, '1900-01-01');
GO

/* ===================== КАЛЕНДАР ===================== */
CREATE OR ALTER PROCEDURE etl.usp_Load_DimDate
    @DateFrom DATE = '2015-01-01',
    @DateTo   DATE = '2026-12-31'
AS
BEGIN
    SET NOCOUNT ON;

    WITH N AS (
        SELECT TOP (DATEDIFF(DAY, @DateFrom, @DateTo) + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS I
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    ), D AS (
        SELECT DATEADD(DAY, I, @DateFrom) AS Dt FROM N
    ), H AS (
        SELECT Dt,
               CASE WHEN MONTH(Dt) = 1  AND DAY(Dt) = 1  THEN N'Новий рік'
                    WHEN MONTH(Dt) = 1  AND DAY(Dt) = 7  AND YEAR(Dt) <= 2023 THEN N'Різдво Христове (за юліанським календарем)'
                    WHEN MONTH(Dt) = 3  AND DAY(Dt) = 8  THEN N'Міжнародний жіночий день'
                    WHEN MONTH(Dt) = 5  AND DAY(Dt) = 1  THEN N'День праці'
                    WHEN MONTH(Dt) = 6  AND DAY(Dt) = 28 THEN N'День Конституції України'
                    WHEN MONTH(Dt) = 8  AND DAY(Dt) = 24 THEN N'День Незалежності України'
                    WHEN MONTH(Dt) = 10 AND DAY(Dt) = 14 AND YEAR(Dt) >= 2015 THEN N'День захисників і захисниць України'
                    WHEN MONTH(Dt) = 12 AND DAY(Dt) = 25 AND YEAR(Dt) >= 2017 THEN N'Різдво Христове'
               END AS HolidayName,
               DATEDIFF(DAY, '19000101', Dt) % 7 + 1 AS Dow
        FROM D
    )
    INSERT dim.DimDate (DateKey, FullDate, DayOfMonth, DayOfWeek, DayName, WeekOfYear, MonthNo, MonthName, MonthYear,
                        MonthYearName, QuarterNo, QuarterName, YearNo, Season, IsWeekend, IsHoliday, HolidayName, IsWorkingDay)
    SELECT YEAR(Dt) * 10000 + MONTH(Dt) * 100 + DAY(Dt),
           Dt, DAY(Dt), Dow,
           CHOOSE(Dow, N'Понеділок', N'Вівторок', N'Середа', N'Четвер', N'П''ятниця', N'Субота', N'Неділя'),
           DATEPART(ISO_WEEK, Dt),
           MONTH(Dt),
           CHOOSE(MONTH(Dt), N'Січень', N'Лютий', N'Березень', N'Квітень', N'Травень', N'Червень',
                             N'Липень', N'Серпень', N'Вересень', N'Жовтень', N'Листопад', N'Грудень'),
           FORMAT(Dt, 'yyyy-MM'),
           CHOOSE(MONTH(Dt), N'Січень', N'Лютий', N'Березень', N'Квітень', N'Травень', N'Червень',
                             N'Липень', N'Серпень', N'Вересень', N'Жовтень', N'Листопад', N'Грудень') + N' ' + CAST(YEAR(Dt) AS NVARCHAR(4)),
           DATEPART(QUARTER, Dt),
           CHOOSE(DATEPART(QUARTER, Dt), N'I кв.', N'II кв.', N'III кв.', N'IV кв.'),
           YEAR(Dt),
           CASE WHEN MONTH(Dt) IN (12, 1, 2) THEN N'Зима' WHEN MONTH(Dt) IN (3, 4, 5) THEN N'Весна'
                WHEN MONTH(Dt) IN (6, 7, 8) THEN N'Літо' ELSE N'Осінь' END,
           IIF(Dow >= 6, 1, 0),
           IIF(HolidayName IS NULL, 0, 1),
           HolidayName,
           IIF(Dow = 7 OR HolidayName IS NOT NULL, 0, 1)   -- поліклініка працює пн–сб
    FROM H
    WHERE NOT EXISTS (SELECT 1 FROM dim.DimDate x WHERE x.FullDate = H.Dt);

    SELECT @@ROWCOUNT AS RowsInserted;
END
GO

/* ===================== АУДИТ ETL ===================== */

-- Початок повного запуску ETL (викликає головний пакет)
CREATE OR ALTER PROCEDURE etl.usp_RunStart
AS
BEGIN
    SET NOCOUNT ON;
    -- незавершені попередні запуски вважаються аварійно зупиненими
    UPDATE etl.ETLRun SET Status = N'Failed', FinishedAt = SYSDATETIME() WHERE Status = N'Running';
    INSERT etl.ETLRun DEFAULT VALUES;
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS RunID;
END
GO

CREATE OR ALTER PROCEDURE etl.usp_RunEnd
    @RunID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE etl.ETLRun
    SET FinishedAt = SYSDATETIME(),
        Status = IIF(EXISTS (SELECT 1 FROM etl.PackageLog WHERE RunID = @RunID AND Status <> N'Succeeded'), N'Failed', N'Succeeded')
    WHERE RunID = @RunID;
END
GO

-- Початок пакета: повертає RunID (поточного запуску або нового, якщо пакет запущено окремо) і LogID
CREATE OR ALTER PROCEDURE etl.usp_PackageStart
    @PackageName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RunID INT = (SELECT MAX(RunID) FROM etl.ETLRun WHERE Status = N'Running');
    IF @RunID IS NULL
    BEGIN
        INSERT etl.ETLRun DEFAULT VALUES;
        SET @RunID = SCOPE_IDENTITY();
    END
    INSERT etl.PackageLog (RunID, PackageName) VALUES (@RunID, @PackageName);
    SELECT @RunID AS RunID, CAST(SCOPE_IDENTITY() AS INT) AS LogID;
END
GO

CREATE OR ALTER PROCEDURE etl.usp_PackageEnd
    @LogID        INT,
    @RowsRead     INT = NULL,
    @RowsInserted INT = NULL,
    @RowsUpdated  INT = NULL,
    @RowsRejected INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE etl.PackageLog
    SET FinishedAt = SYSDATETIME(),
        Status = IIF(Status = N'Failed', N'Failed', N'Succeeded'),
        RowsRead = @RowsRead, RowsInserted = @RowsInserted, RowsUpdated = @RowsUpdated, RowsRejected = @RowsRejected
    WHERE LogID = @LogID;

    -- пакет, запущений окремо (не з головного), сам завершує свій запуск
    DECLARE @RunID INT = (SELECT RunID FROM etl.PackageLog WHERE LogID = @LogID);
    IF NOT EXISTS (SELECT 1 FROM etl.PackageLog WHERE RunID = @RunID AND PackageName LIKE N'00%')
        EXEC etl.usp_RunEnd @RunID;
END
GO

-- Викликається з обробника подій OnError кожного пакета
CREATE OR ALTER PROCEDURE etl.usp_LogError
    @LogID        INT,
    @PackageName  NVARCHAR(100),
    @SourceName   NVARCHAR(200),
    @ErrorCode    INT,
    @ErrorMessage NVARCHAR(4000)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT etl.ErrorLog (LogID, PackageName, SourceName, ErrorCode, ErrorMessage)
    VALUES (NULLIF(@LogID, 0), @PackageName, @SourceName, @ErrorCode, @ErrorMessage);
    UPDATE etl.PackageLog SET Status = N'Failed', FinishedAt = SYSDATETIME() WHERE LogID = @LogID;
END
GO

CREATE OR ALTER PROCEDURE etl.usp_SetWatermark
    @TableName NVARCHAR(100),
    @LastID    BIGINT,
    @LastDate  DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE etl.Watermark
    SET LastID = ISNULL(@LastID, LastID), LastDate = ISNULL(@LastDate, LastDate), UpdatedAt = SYSDATETIME()
    WHERE TableName = @TableName;
END
GO

/* ===================== ФАЙЛИ ЛАБОРАТОРІЇ ===================== */
CREATE OR ALTER PROCEDURE etl.usp_LogFile
    @LogID         INT,
    @FileName      NVARCHAR(260),
    @FileSizeKB    INT,
    @LineCount     INT,
    @RowsRead      INT,
    @RowsLoaded    INT,
    @RowsRejected  INT,
    @RowsDuplicate INT,
    @Status        NVARCHAR(15),
    @Message       NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT etl.FileLog (RunID, LogID, FileName, FileSizeKB, LineCount, RowsRead, RowsLoaded, RowsRejected, RowsDuplicate, Status, Message)
    SELECT RunID, @LogID, @FileName, @FileSizeKB, @LineCount, @RowsRead, @RowsLoaded, @RowsRejected, @RowsDuplicate, @Status, @Message
    FROM etl.PackageLog WHERE LogID = @LogID;
END
GO

-- Завершення пакета лабораторних файлів: підсумки по всіх файлах
CREATE OR ALTER PROCEDURE etl.usp_LabPackageEnd
    @LogID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Read INT, @Loaded INT, @Rejected INT;
    SELECT @Read = ISNULL(SUM(RowsRead), 0), @Loaded = ISNULL(SUM(RowsLoaded), 0),
           @Rejected = ISNULL(SUM(RowsRejected), 0) + ISNULL(SUM(RowsDuplicate), 0)
    FROM etl.FileLog WHERE LogID = @LogID;
    EXEC etl.usp_PackageEnd @LogID = @LogID, @RowsRead = @Read, @RowsInserted = @Loaded, @RowsUpdated = 0, @RowsRejected = @Rejected;
END
GO

/* ===================== SCD TYPE 2: ПАЦІЄНТ ===================== */
CREATE OR ALTER PROCEDURE etl.usp_Merge_DimPatient
    @RunID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Inserted INT = 0, @Updated INT = 0, @Versions INT = 0;

    BEGIN TRANSACTION;

    -- SCD Type 1: виправлення ПІБ, статі, дати народження, групи крові — у всіх версіях
    UPDATE d
    SET LastName = s.LastName, FirstName = s.FirstName, MiddleName = s.MiddleName, FullName = s.FullName,
        Gender = s.Gender, GenderName = s.GenderName, BirthDate = s.BirthDate, BirthYear = s.BirthYear,
        BloodType = s.BloodType, ETLRunID = @RunID
    FROM dim.DimPatient d
    JOIN stg.Patient s ON s.PatientID = d.PatientID
    WHERE EXISTS (SELECT d.LastName, d.FirstName, d.MiddleName, d.Gender, d.BirthDate, d.BloodType
                  EXCEPT
                  SELECT s.LastName, s.FirstName, s.MiddleName, s.Gender, s.BirthDate, s.BloodType);
    SET @Updated = @@ROWCOUNT;

    -- SCD Type 2: зміна міста/регіону або страховки — закриваємо поточну версію...
    DECLARE @Changed TABLE (PatientID INT PRIMARY KEY);
    UPDATE d
    SET ValidTo = GREATEST(d.ValidFrom, DATEADD(DAY, -1, CAST(s.ModifiedAt AS DATE))), IsCurrent = 0, ETLRunID = @RunID
    OUTPUT inserted.PatientID INTO @Changed
    FROM dim.DimPatient d
    JOIN stg.Patient s ON s.PatientID = d.PatientID
    WHERE d.IsCurrent = 1
      AND EXISTS (SELECT d.City, d.Region, d.HasInsurance EXCEPT SELECT s.City, s.Region, s.HasInsurance);

    -- ...і додаємо нову
    INSERT dim.DimPatient (PatientID, LastName, FirstName, MiddleName, FullName, Gender, GenderName, BirthDate, BirthYear,
                           BloodType, City, Region, CityGroup, HasInsurance, ValidFrom, ValidTo, IsCurrent, ETLRunID)
    SELECT s.PatientID, s.LastName, s.FirstName, s.MiddleName, s.FullName, s.Gender, s.GenderName, s.BirthDate, s.BirthYear,
           s.BloodType, s.City, s.Region, s.CityGroup, s.HasInsurance, CAST(s.ModifiedAt AS DATE), '9999-12-31', 1, @RunID
    FROM stg.Patient s
    JOIN @Changed c ON c.PatientID = s.PatientID;
    SET @Versions = @@ROWCOUNT;

    -- Нові пацієнти: перша версія діє з 1900-01-01 (покриває всю історію фактів)
    INSERT dim.DimPatient (PatientID, LastName, FirstName, MiddleName, FullName, Gender, GenderName, BirthDate, BirthYear,
                           BloodType, City, Region, CityGroup, HasInsurance, ValidFrom, ValidTo, IsCurrent, ETLRunID)
    SELECT s.PatientID, s.LastName, s.FirstName, s.MiddleName, s.FullName, s.Gender, s.GenderName, s.BirthDate, s.BirthYear,
           s.BloodType, s.City, s.Region, s.CityGroup, s.HasInsurance, '1900-01-01', '9999-12-31', 1, @RunID
    FROM stg.Patient s
    WHERE NOT EXISTS (SELECT 1 FROM dim.DimPatient d WHERE d.PatientID = s.PatientID);
    SET @Inserted = @@ROWCOUNT;

    DECLARE @MaxDate DATETIME2(0) = (SELECT MAX(ModifiedAt) FROM stg.Patient);
    EXEC etl.usp_SetWatermark N'DimPatient', NULL, @MaxDate;

    COMMIT TRANSACTION;

    SELECT @Inserted AS RowsInserted, @Updated + @Versions AS RowsUpdated, @Versions AS NewVersions;
END
GO

/* ===================== SCD TYPE 2: ЛІКАР ===================== */
CREATE OR ALTER PROCEDURE etl.usp_Merge_DimDoctor
    @RunID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Inserted INT = 0, @Updated INT = 0, @Versions INT = 0;

    BEGIN TRANSACTION;

    -- SCD Type 1: ПІБ, дати прийому/звільнення, статус
    UPDATE d
    SET FullName = s.FullName, ShortName = s.ShortName, Gender = s.Gender, HireDate = s.HireDate,
        DismissalDate = s.DismissalDate, EmploymentStatus = s.EmploymentStatus, ETLRunID = @RunID
    FROM dim.DimDoctor d
    JOIN stg.Doctor s ON s.DoctorID = d.DoctorID
    WHERE EXISTS (SELECT d.FullName, d.Gender, d.HireDate, d.DismissalDate, d.EmploymentStatus
                  EXCEPT
                  SELECT s.FullName, s.Gender, s.HireDate, s.DismissalDate, s.EmploymentStatus);
    SET @Updated = @@ROWCOUNT;

    -- SCD Type 2: спеціальність, відділення, кваліфікаційна категорія
    DECLARE @Changed TABLE (DoctorID INT PRIMARY KEY);
    UPDATE d
    SET ValidTo = GREATEST(d.ValidFrom, DATEADD(DAY, -1, CAST(s.ModifiedAt AS DATE))), IsCurrent = 0, ETLRunID = @RunID
    OUTPUT inserted.DoctorID INTO @Changed
    FROM dim.DimDoctor d
    JOIN stg.Doctor s ON s.DoctorID = d.DoctorID
    WHERE d.IsCurrent = 1
      AND EXISTS (SELECT d.Specialty, d.Department, d.Category EXCEPT SELECT s.Specialty, s.Department, s.Category);

    INSERT dim.DimDoctor (DoctorID, FullName, ShortName, Gender, Specialty, Department, Category, HireDate, DismissalDate,
                          EmploymentStatus, ValidFrom, ValidTo, IsCurrent, ETLRunID)
    SELECT s.DoctorID, s.FullName, s.ShortName, s.Gender, s.Specialty, s.Department, s.Category, s.HireDate, s.DismissalDate,
           s.EmploymentStatus, CAST(s.ModifiedAt AS DATE), '9999-12-31', 1, @RunID
    FROM stg.Doctor s JOIN @Changed c ON c.DoctorID = s.DoctorID;
    SET @Versions = @@ROWCOUNT;

    INSERT dim.DimDoctor (DoctorID, FullName, ShortName, Gender, Specialty, Department, Category, HireDate, DismissalDate,
                          EmploymentStatus, ValidFrom, ValidTo, IsCurrent, ETLRunID)
    SELECT s.DoctorID, s.FullName, s.ShortName, s.Gender, s.Specialty, s.Department, s.Category, s.HireDate, s.DismissalDate,
           s.EmploymentStatus, '1900-01-01', '9999-12-31', 1, @RunID
    FROM stg.Doctor s
    WHERE NOT EXISTS (SELECT 1 FROM dim.DimDoctor d WHERE d.DoctorID = s.DoctorID);
    SET @Inserted = @@ROWCOUNT;

    DECLARE @MaxDate DATETIME2(0) = (SELECT MAX(ModifiedAt) FROM stg.Doctor);
    EXEC etl.usp_SetWatermark N'DimDoctor', NULL, @MaxDate;

    COMMIT TRANSACTION;

    SELECT @Inserted AS RowsInserted, @Updated + @Versions AS RowsUpdated, @Versions AS NewVersions;
END
GO

/* ===================== SCD TYPE 1: оновлення, виявлені в SSIS ===================== */
CREATE OR ALTER PROCEDURE etl.usp_Apply_DimDisease_Updates
    @RunID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE d
    SET ICDCode = s.ICDCode, DiseaseName = s.DiseaseName, DiseaseFullName = s.DiseaseFullName, ICDChapter = s.ICDChapter,
        CategoryName = s.CategoryName, IsChronic = s.IsChronic, CourseType = s.CourseType, IsInfectious = s.IsInfectious,
        Severity = s.Severity, SeverityName = s.SeverityName, AvgTreatmentDays = s.AvgTreatmentDays,
        Seasonality = s.Seasonality, ETLRunID = @RunID
    FROM dim.DimDisease d JOIN stg.DiseaseUpdate s ON s.DiseaseKey = d.DiseaseKey;
    SELECT @@ROWCOUNT AS RowsUpdated;
END
GO

CREATE OR ALTER PROCEDURE etl.usp_Apply_DimMedication_Updates
    @RunID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE d
    SET MedicationName = s.MedicationName, ActiveSubstance = s.ActiveSubstance, GroupName = s.GroupName,
        DosageForm = s.DosageForm, Manufacturer = s.Manufacturer, PrescriptionStatus = s.PrescriptionStatus,
        CurrentPrice = s.CurrentPrice, PriceCategory = s.PriceCategory, ETLRunID = @RunID
    FROM dim.DimMedication d JOIN stg.MedicationUpdate s ON s.MedicationKey = d.MedicationKey;
    SELECT @@ROWCOUNT AS RowsUpdated;
END
GO

/* ===================== ЗВІТИ ПРО ЯКІСТЬ ETL ===================== */
CREATE OR ALTER VIEW etl.vw_PackageRuns
AS
SELECT r.RunID, r.StartedAt AS RunStarted, r.Status AS RunStatus,
       p.PackageName, p.StartedAt, p.FinishedAt, p.DurationSec, p.Status,
       p.RowsRead, p.RowsInserted, p.RowsUpdated, p.RowsRejected,
       (SELECT COUNT(*) FROM etl.ErrorLog e WHERE e.LogID = p.LogID) AS Errors
FROM etl.ETLRun r
JOIN etl.PackageLog p ON p.RunID = r.RunID;
GO

CREATE OR ALTER VIEW etl.vw_RejectedSummary
AS
SELECT RunID, PackageName, RejectReason, COUNT(*) AS RowsRejected
FROM etl.RejectedRows
GROUP BY RunID, PackageName, RejectReason;
GO
