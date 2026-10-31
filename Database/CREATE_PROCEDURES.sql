USE PolyclinicDB;
GO

CREATE OR ALTER FUNCTION dbo.fn_VisitPrice (@DoctorID INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN (
        SELECT CAST(s.BaseVisitPrice *
                    CASE d.Category WHEN N'Вища'  THEN 1.30
                                    WHEN N'Перша' THEN 1.15
                                    WHEN N'Друга' THEN 1.05
                                    ELSE 1.00 END AS DECIMAL(10,2))
        FROM dbo.Doctors d
        JOIN dbo.Specialties s ON s.SpecialtyID = d.SpecialtyID
        WHERE d.DoctorID = @DoctorID);
END
GO

CREATE OR ALTER FUNCTION dbo.fn_Age (@BirthDate DATE, @AtDate DATE)
RETURNS INT
AS
BEGIN
    RETURN DATEDIFF(YEAR, @BirthDate, @AtDate)
         - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, @BirthDate, @AtDate), @BirthDate) > @AtDate THEN 1 ELSE 0 END;
END
GO

CREATE OR ALTER FUNCTION dbo.fn_AgeGroup (@BirthDate DATE, @AtDate DATE)
RETURNS NVARCHAR(10)
AS
BEGIN
    DECLARE @Age INT = dbo.fn_Age(@BirthDate, @AtDate);
    RETURN CASE WHEN @Age < 18 THEN N'0-17'
                WHEN @Age < 35 THEN N'18-34'
                WHEN @Age < 50 THEN N'35-49'
                WHEN @Age < 65 THEN N'50-64'
                ELSE N'65+' END;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_RegisterPatient
    @LastName        NVARCHAR(50),
    @FirstName       NVARCHAR(50),
    @MiddleName      NVARCHAR(50) = NULL,
    @Gender          CHAR(1),
    @BirthDate       DATE,
    @CityID          INT,
    @Address         NVARCHAR(200) = NULL,
    @Phone           VARCHAR(20)   = NULL,
    @Email           VARCHAR(100)  = NULL,
    @InsurancePolicy VARCHAR(20)   = NULL,
    @BloodType       VARCHAR(3)    = NULL,
    @PatientID       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @InsurancePolicy IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.Patients WHERE InsurancePolicy = @InsurancePolicy)
        THROW 50100, N'Пацієнт з таким страховим полісом уже зареєстрований.', 1;

    INSERT dbo.Patients (LastName, FirstName, MiddleName, Gender, BirthDate, CityID, Address,
                         Phone, Email, InsurancePolicy, BloodType)
    VALUES (@LastName, @FirstName, @MiddleName, @Gender, @BirthDate, @CityID, @Address,
            @Phone, @Email, @InsurancePolicy, @BloodType);

    SET @PatientID = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_OpenMedicalRecord
    @PatientID     INT,
    @DoctorID      INT,
    @DiseaseID     INT,
    @OpenDateTime  DATETIME2(0),
    @Severity      TINYINT       = 2,
    @Complaints    NVARCHAR(300) = NULL,
    @RecordID      INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Patients WHERE PatientID = @PatientID AND IsActive = 1)
        THROW 50110, N'Пацієнта не знайдено або він не прикріплений до поліклініки.', 1;

    DECLARE @OpenDate DATE = CAST(@OpenDateTime AS DATE);

    BEGIN TRANSACTION;

        INSERT dbo.MedicalRecords (PatientID, AttendingDoctorID, OpenDate)
        VALUES (@PatientID, @DoctorID, @OpenDate);
        SET @RecordID = SCOPE_IDENTITY();

        INSERT dbo.Diagnoses (RecordID, DiseaseID, DoctorID, DiagnosisDate, DiagnosisType, Severity)
        VALUES (@RecordID, @DiseaseID, @DoctorID, @OpenDate, N'Основний', @Severity);

        INSERT dbo.Visits (RecordID, DoctorID, VisitDateTime, VisitType, Status, DurationMin, Cost, Complaints)
        VALUES (@RecordID, @DoctorID, @OpenDateTime, N'Первинний', N'Відбувся', 20, dbo.fn_VisitPrice(@DoctorID), @Complaints);

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_AddDiagnosis
    @RecordID      INT,
    @DiseaseID     INT,
    @DoctorID      INT,
    @DiagnosisDate DATE,
    @DiagnosisType NVARCHAR(15) = N'Супутній',
    @Severity      TINYINT      = 2
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.MedicalRecords WHERE RecordID = @RecordID AND Status = N'Закрита')
        THROW 50120, N'Неможливо додати діагноз до закритої історії хвороби.', 1;

    INSERT dbo.Diagnoses (RecordID, DiseaseID, DoctorID, DiagnosisDate, DiagnosisType, Severity)
    VALUES (@RecordID, @DiseaseID, @DoctorID, @DiagnosisDate, @DiagnosisType, @Severity);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_AddVisit
    @RecordID      INT,
    @DoctorID      INT,
    @VisitDateTime DATETIME2(0),
    @VisitType     NVARCHAR(20)  = N'Повторний',
    @Status        NVARCHAR(15)  = N'Відбувся',
    @DurationMin   SMALLINT      = 15,
    @Complaints    NVARCHAR(300) = NULL,
    @VisitID       BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.MedicalRecords WHERE RecordID = @RecordID AND Status = N'Закрита')
        THROW 50130, N'Неможливо додати візит до закритої історії хвороби.', 1;

    INSERT dbo.Visits (RecordID, DoctorID, VisitDateTime, VisitType, Status, DurationMin, Cost, Complaints)
    VALUES (@RecordID, @DoctorID, @VisitDateTime, @VisitType, @Status, @DurationMin,
            CASE WHEN @Status = N'Відбувся' THEN dbo.fn_VisitPrice(@DoctorID) ELSE 0 END,
            @Complaints);

    SET @VisitID = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_PrescribeMedication
    @VisitID        BIGINT,
    @MedicationID   INT,
    @Dosage         NVARCHAR(50),
    @TimesPerDay    TINYINT  = 1,
    @DurationDays   SMALLINT = 7,
    @Quantity       SMALLINT = 1,
    @Warning        NVARCHAR(400) = NULL OUTPUT,
    @PrescriptionID BIGINT        = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Visits WHERE VisitID = @VisitID AND Status = N'Відбувся')
        THROW 50140, N'Призначати ліки можна лише на візиті, що відбувся.', 1;

    SELECT TOP (1)
        @Warning = CONCAT(N'Увага: відносне протипоказання при хворобі ', ds.ICDCode, N' «', ds.Name, N'».')
    FROM dbo.Visits v
    JOIN dbo.MedicalRecords cur  ON cur.RecordID = v.RecordID
    JOIN dbo.MedicalRecords pr   ON pr.PatientID = cur.PatientID
    JOIN dbo.Diagnoses dg        ON dg.RecordID = pr.RecordID
    JOIN dbo.Diseases ds         ON ds.DiseaseID = dg.DiseaseID
    JOIN dbo.Contraindications c ON c.DiseaseID = dg.DiseaseID AND c.MedicationID = @MedicationID
    WHERE v.VisitID = @VisitID
      AND c.ContraindicationType = N'Відносне'
      AND dg.DiagnosisDate <= CAST(v.VisitDateTime AS DATE)
      AND (pr.RecordID = cur.RecordID OR ds.IsChronic = 1 OR pr.CloseDate IS NULL
           OR pr.CloseDate >= CAST(v.VisitDateTime AS DATE));

    INSERT dbo.Prescriptions (VisitID, MedicationID, Dosage, TimesPerDay, DurationDays, Quantity, UnitPrice)
    SELECT @VisitID, @MedicationID, @Dosage, @TimesPerDay, @DurationDays, @Quantity, m.UnitPrice
    FROM dbo.Medications m
    WHERE m.MedicationID = @MedicationID;

    SET @PrescriptionID = SCOPE_IDENTITY();

    IF @Warning IS NOT NULL
        PRINT @Warning;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_CloseMedicalRecord
    @RecordID  INT,
    @CloseDate DATE,
    @Outcome   NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.MedicalRecords WHERE RecordID = @RecordID AND Status = N'Відкрита')
        THROW 50150, N'Історію хвороби не знайдено або вона вже закрита.', 1;

    UPDATE dbo.MedicalRecords
    SET Status = N'Закрита', CloseDate = @CloseDate, Outcome = @Outcome
    WHERE RecordID = @RecordID;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_DoctorPatients
    @DoctorID INT  = NULL,
    @DateFrom DATE = '2016-01-01',
    @DateTo   DATE = '2025-12-31'
AS
BEGIN
    SET NOCOUNT ON;

    SELECT dep.Name                                            AS Department,
           sp.Name                                             AS Specialty,
           d.DoctorID,
           CONCAT(d.LastName, N' ', d.FirstName, N' ', d.MiddleName) AS DoctorName,
           d.Category,
           p.PatientID,
           CONCAT(p.LastName, N' ', p.FirstName, N' ', p.MiddleName) AS PatientName,
           p.BirthDate,
           COUNT(DISTINCT r.RecordID)                          AS RecordsCount,
           MIN(r.OpenDate)                                     AS FirstOpenDate,
           MAX(r.OpenDate)                                     AS LastOpenDate,
           SUM(CASE WHEN r.Status = N'Відкрита' THEN 1 ELSE 0 END) AS OpenRecords
    FROM dbo.Doctors d
    JOIN dbo.Specialties sp    ON sp.SpecialtyID = d.SpecialtyID
    JOIN dbo.Departments dep   ON dep.DepartmentID = d.DepartmentID
    JOIN dbo.MedicalRecords r  ON r.AttendingDoctorID = d.DoctorID
    JOIN dbo.Patients p        ON p.PatientID = r.PatientID
    WHERE (@DoctorID IS NULL OR d.DoctorID = @DoctorID)
      AND r.OpenDate BETWEEN @DateFrom AND @DateTo
    GROUP BY dep.Name, sp.Name, d.DoctorID, d.LastName, d.FirstName, d.MiddleName, d.Category,
             p.PatientID, p.LastName, p.FirstName, p.MiddleName, p.BirthDate
    ORDER BY Department, DoctorName, PatientName;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_PatientHistory
    @PatientID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.RecordID,
           r.OpenDate,
           r.CloseDate,
           r.Status,
           r.Outcome,
           CONCAT(ad.LastName, N' ', LEFT(ad.FirstName, 1), N'.') AS AttendingDoctor,
           STUFF((SELECT N'; ' + ds.ICDCode + N' ' + ds.Name + N' (' + dg.DiagnosisType + N')'
                  FROM dbo.Diagnoses dg JOIN dbo.Diseases ds ON ds.DiseaseID = dg.DiseaseID
                  WHERE dg.RecordID = r.RecordID
                  ORDER BY CASE dg.DiagnosisType WHEN N'Основний' THEN 0 ELSE 1 END
                  FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N'') AS Diagnoses,
           v.VisitID,
           v.VisitDateTime,
           v.VisitType,
           v.Status                                            AS VisitStatus,
           CONCAT(vd.LastName, N' ', LEFT(vd.FirstName, 1), N'.') AS VisitDoctor,
           vs.Name                                             AS VisitSpecialty,
           v.Cost                                              AS VisitCost,
           m.Name                                              AS Medication,
           pr.Dosage,
           pr.TimesPerDay,
           pr.DurationDays,
           pr.TotalCost                                        AS MedicationCost
    FROM dbo.MedicalRecords r
    JOIN dbo.Doctors ad          ON ad.DoctorID = r.AttendingDoctorID
    JOIN dbo.Visits v            ON v.RecordID = r.RecordID
    JOIN dbo.Doctors vd          ON vd.DoctorID = v.DoctorID
    JOIN dbo.Specialties vs      ON vs.SpecialtyID = vd.SpecialtyID
    LEFT JOIN dbo.Prescriptions pr ON pr.VisitID = v.VisitID
    LEFT JOIN dbo.Medications m    ON m.MedicationID = pr.MedicationID
    WHERE r.PatientID = @PatientID
    ORDER BY r.OpenDate DESC, v.VisitDateTime;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_DoctorWorkloadByMonth
    @Year         INT,
    @DepartmentID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @From DATETIME2(0) = DATEFROMPARTS(@Year, 1, 1),
            @To   DATETIME2(0) = DATEFROMPARTS(@Year + 1, 1, 1);

    SELECT dep.Name                                            AS Department,
           d.DoctorID,
           CONCAT(d.LastName, N' ', d.FirstName, N' ', d.MiddleName) AS DoctorName,
           sp.Name                                             AS Specialty,
           MONTH(v.VisitDateTime)                              AS MonthNo,
           COUNT(*)                                            AS PlannedVisits,
           SUM(CASE WHEN v.Status = N'Відбувся' THEN 1 ELSE 0 END)  AS CompletedVisits,
           SUM(CASE WHEN v.Status = N'Неявка'   THEN 1 ELSE 0 END)  AS NoShows,
           CAST(SUM(CASE WHEN v.Status = N'Відбувся' THEN v.DurationMin ELSE 0 END) / 60.0 AS DECIMAL(10,1)) AS WorkHours,
           SUM(v.Cost)                                         AS Revenue
    FROM dbo.Visits v
    JOIN dbo.Doctors d         ON d.DoctorID = v.DoctorID
    JOIN dbo.Specialties sp    ON sp.SpecialtyID = d.SpecialtyID
    JOIN dbo.Departments dep   ON dep.DepartmentID = d.DepartmentID
    WHERE v.VisitDateTime >= @From AND v.VisitDateTime < @To
      AND (@DepartmentID IS NULL OR d.DepartmentID = @DepartmentID)
    GROUP BY dep.Name, d.DoctorID, d.LastName, d.FirstName, d.MiddleName, sp.Name, MONTH(v.VisitDateTime)
    ORDER BY Department, DoctorName, MonthNo;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_TreatmentEffectiveness
    @DateFrom   DATE = '2016-01-01',
    @DateTo     DATE = '2025-12-31',
    @CategoryID INT  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT dc.Name                                              AS DiseaseCategory,
           ds.ICDCode,
           ds.Name                                              AS Disease,
           ds.AvgTreatmentDays                                  AS NormTreatmentDays,
           COUNT(*)                                             AS ClosedCases,
           CAST(AVG(1.0 * DATEDIFF(DAY, r.OpenDate, r.CloseDate)) AS DECIMAL(10,1)) AS AvgActualDays,
           SUM(CASE WHEN r.Outcome IN (N'Одужання', N'Покращення') THEN 1 ELSE 0 END) AS PositiveOutcomes,
           CAST(100.0 * SUM(CASE WHEN r.Outcome = N'Одужання' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS RecoveryPct,
           CAST(100.0 * SUM(CASE WHEN r.Outcome IN (N'Одужання', N'Покращення') THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS EffectivenessPct,
           CAST(100.0 * SUM(CASE WHEN r.Outcome IN (N'Погіршення', N'Госпіталізація') THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS NegativePct,
           CAST(100.0 * SUM(CASE WHEN DATEDIFF(DAY, r.OpenDate, r.CloseDate) <= ds.AvgTreatmentDays THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS WithinNormPct
    FROM dbo.MedicalRecords r
    JOIN dbo.Diagnoses dg           ON dg.RecordID = r.RecordID AND dg.DiagnosisType = N'Основний'
    JOIN dbo.Diseases ds            ON ds.DiseaseID = dg.DiseaseID
    JOIN dbo.DiseaseCategories dc   ON dc.CategoryID = ds.CategoryID
    WHERE r.Status = N'Закрита'
      AND r.CloseDate BETWEEN @DateFrom AND @DateTo
      AND (@CategoryID IS NULL OR ds.CategoryID = @CategoryID)
    GROUP BY dc.Name, ds.ICDCode, ds.Name, ds.AvgTreatmentDays
    ORDER BY DiseaseCategory, ClosedCases DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Report_DiseaseStatistics
    @DateFrom   DATE = '2016-01-01',
    @DateTo     DATE = '2025-12-31',
    @CategoryID INT  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT dc.Name                                              AS DiseaseCategory,
           ds.ICDCode,
           ds.Name                                              AS Disease,
           YEAR(dg.DiagnosisDate)                               AS DiagnosisYear,
           dbo.fn_AgeGroup(p.BirthDate, dg.DiagnosisDate)       AS AgeGroup,
           p.Gender,
           COUNT(*)                                             AS Cases,
           COUNT(DISTINCT p.PatientID)                          AS UniquePatients
    FROM dbo.Diagnoses dg
    JOIN dbo.Diseases ds            ON ds.DiseaseID = dg.DiseaseID
    JOIN dbo.DiseaseCategories dc   ON dc.CategoryID = ds.CategoryID
    JOIN dbo.MedicalRecords r       ON r.RecordID = dg.RecordID
    JOIN dbo.Patients p             ON p.PatientID = r.PatientID
    WHERE dg.DiagnosisDate BETWEEN @DateFrom AND @DateTo
      AND (@CategoryID IS NULL OR ds.CategoryID = @CategoryID)
    GROUP BY dc.Name, ds.ICDCode, ds.Name, YEAR(dg.DiagnosisDate),
             dbo.fn_AgeGroup(p.BirthDate, dg.DiagnosisDate), p.Gender
    ORDER BY DiseaseCategory, Disease, DiagnosisYear;
END
GO
