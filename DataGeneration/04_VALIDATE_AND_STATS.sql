USE PolyclinicDB;
GO
SET NOCOUNT ON;
GO

DELETE pr
FROM dbo.Prescriptions pr
WHERE EXISTS (
    SELECT 1
    FROM dbo.Visits v
    JOIN dbo.MedicalRecords cur  ON cur.RecordID = v.RecordID
    JOIN dbo.MedicalRecords oth  ON oth.PatientID = cur.PatientID
    JOIN dbo.Diagnoses dg        ON dg.RecordID = oth.RecordID
    JOIN dbo.Diseases ds         ON ds.DiseaseID = dg.DiseaseID
    JOIN dbo.Contraindications c ON c.MedicationID = pr.MedicationID AND c.DiseaseID = dg.DiseaseID
    WHERE v.VisitID = pr.VisitID
      AND c.ContraindicationType = N'Абсолютне'
      AND dg.DiagnosisDate <= CAST(v.VisitDateTime AS DATE)
      AND (oth.RecordID = cur.RecordID OR ds.IsChronic = 1 OR oth.CloseDate IS NULL
           OR oth.CloseDate >= CAST(v.VisitDateTime AS DATE)));
DECLARE @Removed INT = @@ROWCOUNT;
PRINT CONCAT(N'Видалено призначень з абсолютним протипоказанням до хронічних хвороб з інших історій: ', @Removed);

SELECT Rule_ = N'Візити поза періодом історії хвороби', Violations = COUNT(*)
FROM dbo.Visits v JOIN dbo.MedicalRecords r ON r.RecordID = v.RecordID
WHERE CAST(v.VisitDateTime AS DATE) < r.OpenDate OR CAST(v.VisitDateTime AS DATE) > r.CloseDate
UNION ALL
SELECT N'Візити до лікаря, що не працював на дату візиту', COUNT(*)
FROM dbo.Visits v JOIN dbo.Doctors d ON d.DoctorID = v.DoctorID
WHERE CAST(v.VisitDateTime AS DATE) < d.HireDate OR CAST(v.VisitDateTime AS DATE) > d.DismissalDate
UNION ALL
SELECT N'Діагнози поза періодом історії хвороби', COUNT(*)
FROM dbo.Diagnoses dg JOIN dbo.MedicalRecords r ON r.RecordID = dg.RecordID
WHERE dg.DiagnosisDate < r.OpenDate OR dg.DiagnosisDate > r.CloseDate
UNION ALL
SELECT N'Історії без рівно одного основного діагнозу', COUNT(*)
FROM dbo.MedicalRecords r
WHERE (SELECT COUNT(*) FROM dbo.Diagnoses d WHERE d.RecordID = r.RecordID AND d.DiagnosisType = N'Основний') <> 1
UNION ALL
SELECT N'Історії без жодного візиту', COUNT(*)
FROM dbo.MedicalRecords r WHERE NOT EXISTS (SELECT 1 FROM dbo.Visits v WHERE v.RecordID = r.RecordID)
UNION ALL
SELECT N'Історії, відкриті до народження або прикріплення пацієнта', COUNT(*)
FROM dbo.MedicalRecords r JOIN dbo.Patients p ON p.PatientID = r.PatientID
WHERE r.OpenDate < p.BirthDate OR r.OpenDate < p.RegistrationDate
UNION ALL
SELECT N'Візити в неділю', COUNT(*)
FROM dbo.Visits WHERE DATEDIFF(DAY, '19000101', VisitDateTime) % 7 = 6
UNION ALL
SELECT N'Призначення на візитах, що не відбулися', COUNT(*)
FROM dbo.Prescriptions pr JOIN dbo.Visits v ON v.VisitID = pr.VisitID
WHERE v.Status <> N'Відбувся'
UNION ALL
SELECT N'Оплата за візити, що не відбулися', COUNT(*)
FROM dbo.Visits WHERE Status <> N'Відбувся' AND Cost <> 0
UNION ALL
SELECT N'Дорослі пацієнти у педіатра (первинне звернення)', COUNT(*)
FROM dbo.MedicalRecords r
JOIN dbo.Patients p ON p.PatientID = r.PatientID
JOIN dbo.Doctors d ON d.DoctorID = r.AttendingDoctorID
JOIN dbo.Specialties s ON s.SpecialtyID = d.SpecialtyID
WHERE s.Name = N'Педіатр' AND dbo.fn_Age(p.BirthDate, r.OpenDate) >= 18;
GO

ENABLE TRIGGER ALL ON dbo.MedicalRecords;
ENABLE TRIGGER ALL ON dbo.Diagnoses;
ENABLE TRIGGER ALL ON dbo.Visits;
ENABLE TRIGGER ALL ON dbo.Prescriptions;
SELECT COUNT(*) AS UntrustedConstraints
FROM (SELECT is_not_trusted FROM sys.foreign_keys UNION ALL SELECT is_not_trusted FROM sys.check_constraints) c
WHERE c.is_not_trusted = 1;
EXEC sp_updatestats;
GO

PRINT N'--- 3.1 Кількість записів ---';
SELECT t.name AS TableName, SUM(p.rows) AS Rows_
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.schema_id = SCHEMA_ID('dbo')
GROUP BY t.name
ORDER BY Rows_ DESC;

SELECT SUM(p.rows) AS TotalRows
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.schema_id = SCHEMA_ID('dbo');

EXEC sp_spaceused;

PRINT N'--- 3.2 Історії хвороб і візити по роках ---';
SELECT YEAR(r.OpenDate) AS Year_, COUNT(*) AS Records,
       COUNT(DISTINCT r.PatientID) AS Patients,
       SUM(CASE WHEN r.Status = N'Відкрита' THEN 1 ELSE 0 END) AS OpenRecords
FROM dbo.MedicalRecords r GROUP BY YEAR(r.OpenDate) ORDER BY Year_;

SELECT YEAR(VisitDateTime) AS Year_, COUNT(*) AS Visits, SUM(Cost) AS Revenue, CAST(AVG(NULLIF(Cost, 0)) AS DECIMAL(10,2)) AS AvgVisitCost
FROM dbo.Visits GROUP BY YEAR(VisitDateTime) ORDER BY Year_;

PRINT N'--- 3.3 Сезонність (звернення по місяцях за всі роки) ---';
SELECT MONTH(OpenDate) AS Month_, COUNT(*) AS Records,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct
FROM dbo.MedicalRecords GROUP BY MONTH(OpenDate) ORDER BY Month_;

PRINT N'--- 3.4 Пацієнти: стать і вік (на 31.12.2025) ---';
SELECT Gender, COUNT(*) AS Patients, CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct
FROM dbo.Patients GROUP BY Gender;
SELECT dbo.fn_AgeGroup(BirthDate, '2025-12-31') AS AgeGroup, COUNT(*) AS Patients,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct
FROM dbo.Patients GROUP BY dbo.fn_AgeGroup(BirthDate, '2025-12-31') ORDER BY AgeGroup;
SELECT TOP (5) c.Name AS City, COUNT(*) AS Patients, CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct
FROM dbo.Patients p JOIN dbo.Cities c ON c.CityID = p.CityID GROUP BY c.Name ORDER BY Patients DESC;
SELECT MIN(Cnt) AS MinRecordsPerPatient, MAX(Cnt) AS MaxRecordsPerPatient, CAST(AVG(1.0 * Cnt) AS DECIMAL(6,2)) AS AvgRecordsPerPatient
FROM (SELECT PatientID, COUNT(*) AS Cnt FROM dbo.MedicalRecords GROUP BY PatientID) x;

PRINT N'--- 3.5 Найпоширеніші хвороби (основний діагноз) ---';
SELECT TOP (15) ds.ICDCode, ds.Name, COUNT(*) AS Cases, CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct
FROM dbo.Diagnoses dg JOIN dbo.Diseases ds ON ds.DiseaseID = dg.DiseaseID
WHERE dg.DiagnosisType = N'Основний'
GROUP BY ds.ICDCode, ds.Name ORDER BY Cases DESC;

SELECT dc.ICDChapter, dc.Name, COUNT(*) AS Cases
FROM dbo.Diagnoses dg JOIN dbo.Diseases ds ON ds.DiseaseID = dg.DiseaseID JOIN dbo.DiseaseCategories dc ON dc.CategoryID = ds.CategoryID
WHERE dg.DiagnosisType = N'Основний'
GROUP BY dc.ICDChapter, dc.Name ORDER BY Cases DESC;

SELECT DiagnosisType, COUNT(*) AS Diagnoses FROM dbo.Diagnoses GROUP BY DiagnosisType;

PRINT N'--- 3.6 COVID-19 по роках ---';
SELECT YEAR(dg.DiagnosisDate) AS Year_, COUNT(*) AS CovidCases
FROM dbo.Diagnoses dg JOIN dbo.Diseases ds ON ds.DiseaseID = dg.DiseaseID
WHERE ds.ICDCode = 'U07.1' GROUP BY YEAR(dg.DiagnosisDate) ORDER BY Year_;

PRINT N'--- 3.7 Результати лікування ---';
SELECT r.Outcome, COUNT(*) AS Records, CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct
FROM dbo.MedicalRecords r WHERE r.Status = N'Закрита' GROUP BY r.Outcome ORDER BY Records DESC;

SELECT d.Category,
       COUNT(*) AS ClosedRecords,
       CAST(100.0 * SUM(CASE WHEN r.Outcome IN (N'Одужання', N'Покращення') THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS EffectivenessPct,
       CAST(AVG(1.0 * DATEDIFF(DAY, r.OpenDate, r.CloseDate)) AS DECIMAL(6,2)) AS AvgDays
FROM dbo.MedicalRecords r
JOIN dbo.Doctors d ON d.DoctorID = r.AttendingDoctorID
JOIN dbo.Diagnoses dg ON dg.RecordID = r.RecordID AND dg.DiagnosisType = N'Основний'
JOIN dbo.Diseases ds ON ds.DiseaseID = dg.DiseaseID
WHERE r.Status = N'Закрита' AND ds.ICDCode NOT LIKE 'Z%'
GROUP BY d.Category ORDER BY EffectivenessPct DESC;

PRINT N'--- 3.8 Візити ---';
SELECT VisitType, Status, COUNT(*) AS Visits FROM dbo.Visits GROUP BY VisitType, Status ORDER BY VisitType, Status;
SELECT CAST(1.0 * (SELECT COUNT(*) FROM dbo.Visits) / (SELECT COUNT(*) FROM dbo.MedicalRecords) AS DECIMAL(6,2)) AS AvgVisitsPerRecord,
       CAST(1.0 * (SELECT COUNT(*) FROM dbo.Prescriptions) / (SELECT COUNT(*) FROM dbo.Visits WHERE Status = N'Відбувся') AS DECIMAL(6,2)) AS AvgPrescriptionsPerVisit;

SELECT s.Name AS Specialty, COUNT(DISTINCT v.DoctorID) AS Doctors, COUNT(*) AS Visits,
       CAST(1.0 * COUNT(*) / COUNT(DISTINCT CONCAT(v.DoctorID, '|', CAST(v.VisitDateTime AS DATE))) AS DECIMAL(6,2)) AS VisitsPerDoctorDay
FROM dbo.Visits v JOIN dbo.Doctors d ON d.DoctorID = v.DoctorID JOIN dbo.Specialties s ON s.SpecialtyID = d.SpecialtyID
GROUP BY s.Name ORDER BY Visits DESC;

PRINT N'--- 3.9 Ліки ---';
SELECT TOP (10) m.Name, COUNT(*) AS Prescriptions, SUM(pr.TotalCost) AS TotalCost
FROM dbo.Prescriptions pr JOIN dbo.Medications m ON m.MedicationID = pr.MedicationID
GROUP BY m.Name ORDER BY Prescriptions DESC;
GO

DECLARE @sql NVARCHAR(MAX) = N'';
SELECT @sql += N'DROP TABLE gen.' + QUOTENAME(name) + N';' FROM sys.tables WHERE schema_id = SCHEMA_ID('gen');
SELECT @sql += N'DROP FUNCTION gen.' + QUOTENAME(name) + N';' FROM sys.objects WHERE schema_id = SCHEMA_ID('gen') AND type IN ('FN', 'IF', 'TF');
EXEC sp_executesql @sql;
IF SCHEMA_ID('gen') IS NOT NULL DROP SCHEMA gen;
PRINT N'Допоміжну схему gen видалено.';
GO
