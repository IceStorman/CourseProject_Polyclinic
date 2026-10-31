USE PolyclinicDB;
GO

CREATE OR ALTER TRIGGER dbo.trg_Patients_Audit
ON dbo.Patients
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(@@PROCID) > 1 OR NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @Operation VARCHAR(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN 'UPDATE' ELSE 'DELETE' END;

    IF @Operation = 'UPDATE' AND NOT UPDATE(ModifiedAt)
        UPDATE p SET ModifiedAt = SYSDATETIME()
        FROM dbo.Patients p JOIN inserted i ON i.PatientID = p.PatientID;

    INSERT dbo.AuditLog (TableName, Operation, RecordKey, OldData, NewData)
    SELECT N'Patients', @Operation, d.PatientID,
           (SELECT x.* FROM deleted x     WHERE x.PatientID = d.PatientID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT x.* FROM dbo.Patients x WHERE x.PatientID = d.PatientID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM deleted d;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Doctors_Audit
ON dbo.Doctors
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(@@PROCID) > 1 OR NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @Operation VARCHAR(6) = CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN 'UPDATE' ELSE 'DELETE' END;

    IF @Operation = 'UPDATE' AND NOT UPDATE(ModifiedAt)
        UPDATE d SET ModifiedAt = SYSDATETIME()
        FROM dbo.Doctors d JOIN inserted i ON i.DoctorID = d.DoctorID;

    INSERT dbo.AuditLog (TableName, Operation, RecordKey, OldData, NewData)
    SELECT N'Doctors', @Operation, d.DoctorID,
           (SELECT x.* FROM deleted x    WHERE x.DoctorID = d.DoctorID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT x.* FROM dbo.Doctors x WHERE x.DoctorID = d.DoctorID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM deleted d;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_MedicalRecords_Validate
ON dbo.MedicalRecords
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(@@PROCID) > 1 OR NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.Visits v ON v.RecordID = i.RecordID
        WHERE i.CloseDate IS NOT NULL
          AND CAST(v.VisitDateTime AS DATE) > i.CloseDate)
        THROW 50001, N'Дата закриття історії хвороби раніше дати останнього візиту.', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.Patients p ON p.PatientID = i.PatientID
        WHERE i.OpenDate < p.BirthDate)
        THROW 50002, N'Дата відкриття історії хвороби раніше дати народження пацієнта.', 1;

    IF EXISTS (SELECT 1 FROM deleted) AND NOT UPDATE(ModifiedAt)
        UPDATE r SET ModifiedAt = SYSDATETIME()
        FROM dbo.MedicalRecords r JOIN inserted i ON i.RecordID = r.RecordID;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Diagnoses_Validate
ON dbo.Diagnoses
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.MedicalRecords r ON r.RecordID = i.RecordID
        WHERE i.DiagnosisDate < r.OpenDate
           OR (r.CloseDate IS NOT NULL AND i.DiagnosisDate > r.CloseDate))
        THROW 50003, N'Дата діагнозу виходить за межі періоду історії хвороби.', 1;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Visits_Validate
ON dbo.Visits
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.MedicalRecords r ON r.RecordID = i.RecordID
        WHERE CAST(i.VisitDateTime AS DATE) < r.OpenDate
           OR (r.CloseDate IS NOT NULL AND CAST(i.VisitDateTime AS DATE) > r.CloseDate))
        THROW 50010, N'Дата візиту виходить за межі періоду історії хвороби.', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.Doctors d ON d.DoctorID = i.DoctorID
        WHERE CAST(i.VisitDateTime AS DATE) < d.HireDate
           OR CAST(i.VisitDateTime AS DATE) > d.DismissalDate)
        THROW 50011, N'Лікар не працював у поліклініці на дату візиту.', 1;
END
GO

CREATE OR ALTER TRIGGER dbo.trg_Prescriptions_CheckContraindications
ON dbo.Prescriptions
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) RETURN;

    DECLARE @Message NVARCHAR(400);

    SELECT TOP (1)
        @Message = CONCAT(N'Призначення заборонене: препарат «', m.Name,
                          N'» має абсолютне протипоказання при хворобі ', ds.ICDCode, N' «', ds.Name, N'».')
    FROM inserted i
    JOIN dbo.Visits v             ON v.VisitID = i.VisitID
    JOIN dbo.MedicalRecords cur   ON cur.RecordID = v.RecordID
    JOIN dbo.MedicalRecords pr    ON pr.PatientID = cur.PatientID
    JOIN dbo.Diagnoses dg         ON dg.RecordID = pr.RecordID
    JOIN dbo.Diseases ds          ON ds.DiseaseID = dg.DiseaseID
    JOIN dbo.Contraindications c  ON c.MedicationID = i.MedicationID AND c.DiseaseID = dg.DiseaseID
    JOIN dbo.Medications m        ON m.MedicationID = i.MedicationID
    WHERE c.ContraindicationType = N'Абсолютне'
      AND dg.DiagnosisDate <= CAST(v.VisitDateTime AS DATE)
      AND (   pr.RecordID = cur.RecordID
           OR ds.IsChronic = 1
           OR pr.CloseDate IS NULL
           OR pr.CloseDate >= CAST(v.VisitDateTime AS DATE));

    IF @Message IS NOT NULL
        THROW 50020, @Message, 1;
END
GO
