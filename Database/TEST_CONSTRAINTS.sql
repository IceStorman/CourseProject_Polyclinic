/* =====================================================================
   Курсова робота NVBD, варіант 6 «Поліклініка»
   Тестування обмежень цілісності, тригерів і процедур.
   Усі зміни виконуються в транзакції і відкочуються в кінці —
   скрипт можна запускати на заповненій БД.
   ===================================================================== */
USE PolyclinicDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
GO

IF OBJECT_ID('tempdb..#Results') IS NOT NULL DROP TABLE #Results;
CREATE TABLE #Results (TestNo INT IDENTITY, TestName NVARCHAR(200), Expected NVARCHAR(10), Actual NVARCHAR(10), Message NVARCHAR(400));
GO

/* ---------- Тестові довідникові дані ---------- */
-- Кожен тест виконується у власній (авто)транзакції: помилка в тригері
-- відкочує лише перевірювану операцію. Тестові дані видаляються в кінці.
DECLARE @AuditStart BIGINT = ISNULL((SELECT MAX(AuditID) FROM dbo.AuditLog), 0);
DECLARE @RegionID INT, @CityID INT, @SpecID INT, @DepID INT, @Doc1 INT, @Doc2 INT,
        @CatID INT, @Flu INT, @Ulcer INT, @Asthma INT, @GrpID INT, @Aspirin INT, @Ibuprofen INT, @Paracetamol INT,
        @PatID INT, @RecID INT, @VisitID BIGINT, @Warn NVARCHAR(400), @PrID BIGINT;

INSERT dbo.Regions (Name) VALUES (N'Тестова область');            SET @RegionID = SCOPE_IDENTITY();
INSERT dbo.Cities (RegionID, Name) VALUES (@RegionID, N'Тестове'); SET @CityID = SCOPE_IDENTITY();
INSERT dbo.Specialties (Name, BaseVisitPrice) VALUES (N'Тест-терапевт', 400); SET @SpecID = SCOPE_IDENTITY();
INSERT dbo.Departments (Name, Floor) VALUES (N'Тестове відділення', 1);      SET @DepID = SCOPE_IDENTITY();
INSERT dbo.Doctors (LastName, FirstName, Gender, BirthDate, SpecialtyID, DepartmentID, Category, HireDate)
VALUES (N'Тестенко', N'Іван', 'M', '1980-01-01', @SpecID, @DepID, N'Вища', '2010-01-01');
SET @Doc1 = SCOPE_IDENTITY();
INSERT dbo.Doctors (LastName, FirstName, Gender, BirthDate, SpecialtyID, DepartmentID, Category, HireDate, DismissalDate)
VALUES (N'Звільнений', N'Петро', 'M', '1975-01-01', @SpecID, @DepID, N'Перша', '2005-01-01', '2018-12-31');
SET @Doc2 = SCOPE_IDENTITY();
INSERT dbo.DiseaseCategories (ICDChapter, Name) VALUES ('X00-X01', N'Тестовий клас'); SET @CatID = SCOPE_IDENTITY();
INSERT dbo.Diseases (ICDCode, Name, CategoryID, IsChronic, IsInfectious, Severity, AvgTreatmentDays, Seasonality)
VALUES ('X00.1', N'Тест-грип', @CatID, 0, 1, 2, 7, N'Зима');                       SET @Flu = SCOPE_IDENTITY();
INSERT dbo.Diseases (ICDCode, Name, CategoryID, IsChronic, IsInfectious, Severity, AvgTreatmentDays, Seasonality)
VALUES ('X00.2', N'Тест-виразка', @CatID, 1, 0, 3, 30, N'Всесезонна');             SET @Ulcer = SCOPE_IDENTITY();
INSERT dbo.Diseases (ICDCode, Name, CategoryID, IsChronic, IsInfectious, Severity, AvgTreatmentDays, Seasonality)
VALUES ('X00.3', N'Тест-астма', @CatID, 1, 0, 3, 30, N'Всесезонна');               SET @Asthma = SCOPE_IDENTITY();
INSERT dbo.MedicationGroups (Name) VALUES (N'Тест-НПЗП');                          SET @GrpID = SCOPE_IDENTITY();
INSERT dbo.Medications (Name, ActiveSubstance, GroupID, DosageForm, UnitPrice) VALUES (N'Тест-Аспірин', N'АСК', @GrpID, N'Таблетки', 50);      SET @Aspirin = SCOPE_IDENTITY();
INSERT dbo.Medications (Name, ActiveSubstance, GroupID, DosageForm, UnitPrice) VALUES (N'Тест-Ібупрофен', N'Ібупрофен', @GrpID, N'Таблетки', 80); SET @Ibuprofen = SCOPE_IDENTITY();
INSERT dbo.Medications (Name, ActiveSubstance, GroupID, DosageForm, UnitPrice) VALUES (N'Тест-Парацетамол', N'Парацетамол', @GrpID, N'Таблетки', 30); SET @Paracetamol = SCOPE_IDENTITY();
INSERT dbo.Contraindications (MedicationID, DiseaseID, ContraindicationType) VALUES (@Aspirin, @Ulcer, N'Абсолютне');
INSERT dbo.Contraindications (MedicationID, DiseaseID, ContraindicationType) VALUES (@Ibuprofen, @Asthma, N'Відносне');

EXEC dbo.usp_RegisterPatient @LastName = N'Пацієнтенко', @FirstName = N'Олена', @Gender = 'F',
     @BirthDate = '1990-05-05', @CityID = @CityID, @InsurancePolicy = 'TEST-0001', @PatientID = @PatID OUTPUT;

/* ---------- Макрос перевірки: очікуємо помилку (FAIL) або успіх (OK) ---------- */
-- 1. CHECK: невірна стать
BEGIN TRY
    INSERT dbo.Patients (LastName, FirstName, Gender, BirthDate, CityID) VALUES (N'Х', N'Х', 'X', '1990-01-01', @CityID);
    INSERT #Results VALUES (N'CHECK стать пацієнта (X)', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'CHECK стать пацієнта (X)', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 2. CHECK: дата народження в майбутньому відносно реєстрації
BEGIN TRY
    INSERT dbo.Patients (LastName, FirstName, Gender, BirthDate, CityID, RegistrationDate) VALUES (N'Х', N'Х', 'M', '2030-01-01', @CityID, '2020-01-01');
    INSERT #Results VALUES (N'CHECK дата народження > дати реєстрації', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'CHECK дата народження > дати реєстрації', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 3. CHECK: невірний формат телефону
BEGIN TRY
    INSERT dbo.Patients (LastName, FirstName, Gender, BirthDate, CityID, Phone) VALUES (N'Х', N'Х', 'M', '1990-01-01', @CityID, '12345');
    INSERT #Results VALUES (N'CHECK формат телефону', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'CHECK формат телефону', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 4. UNIQUE (фільтрований індекс): повторний страховий поліс
BEGIN TRY
    INSERT dbo.Patients (LastName, FirstName, Gender, BirthDate, CityID, InsurancePolicy) VALUES (N'Х', N'Х', 'M', '1990-01-01', @CityID, 'TEST-0001');
    INSERT #Results VALUES (N'UNIQUE страховий поліс', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'UNIQUE страховий поліс', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 5. FOREIGN KEY: неіснуюче місто
BEGIN TRY
    INSERT dbo.Patients (LastName, FirstName, Gender, BirthDate, CityID) VALUES (N'Х', N'Х', 'M', '1990-01-01', -1);
    INSERT #Results VALUES (N'FOREIGN KEY неіснуюче місто', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'FOREIGN KEY неіснуюче місто', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 6. Процедура: відкриття історії хвороби (історія + діагноз + візит)
BEGIN TRY
    EXEC dbo.usp_OpenMedicalRecord @PatientID = @PatID, @DoctorID = @Doc1, @DiseaseID = @Ulcer,
         @OpenDateTime = '2020-03-10 10:00', @RecordID = @RecID OUTPUT;
    INSERT #Results SELECT N'usp_OpenMedicalRecord створює 1 діагноз і 1 візит', 'OK',
           CASE WHEN (SELECT COUNT(*) FROM dbo.Diagnoses WHERE RecordID = @RecID) = 1
                 AND (SELECT COUNT(*) FROM dbo.Visits WHERE RecordID = @RecID) = 1 THEN 'OK' ELSE 'FAIL' END, NULL;
END TRY BEGIN CATCH INSERT #Results VALUES (N'usp_OpenMedicalRecord створює 1 діагноз і 1 візит', 'OK', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 7. Вартість візиту: 400 × 1.30 (вища категорія) = 520
INSERT #Results SELECT N'Вартість візиту за категорією (520.00)', 'OK',
       CASE WHEN (SELECT Cost FROM dbo.Visits WHERE RecordID = @RecID) = 520.00 THEN 'OK' ELSE 'FAIL' END, NULL;

-- 8. UNIQUE (фільтрований): другий основний діагноз
BEGIN TRY
    EXEC dbo.usp_AddDiagnosis @RecordID = @RecID, @DiseaseID = @Asthma, @DoctorID = @Doc1, @DiagnosisDate = '2020-03-10', @DiagnosisType = N'Основний';
    INSERT #Results VALUES (N'Один основний діагноз на історію', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Один основний діагноз на історію', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 9. Супутній діагноз — дозволено
BEGIN TRY
    EXEC dbo.usp_AddDiagnosis @RecordID = @RecID, @DiseaseID = @Asthma, @DoctorID = @Doc1, @DiagnosisDate = '2020-03-10';
    INSERT #Results VALUES (N'Додавання супутнього діагнозу', 'OK', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Додавання супутнього діагнозу', 'OK', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 10. Тригер: діагноз раніше відкриття історії
BEGIN TRY
    EXEC dbo.usp_AddDiagnosis @RecordID = @RecID, @DiseaseID = @Flu, @DoctorID = @Doc1, @DiagnosisDate = '2019-01-01';
    INSERT #Results VALUES (N'Тригер: діагноз до відкриття історії', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Тригер: діагноз до відкриття історії', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 11. Тригер: візит до звільненого лікаря
BEGIN TRY
    EXEC dbo.usp_AddVisit @RecordID = @RecID, @DoctorID = @Doc2, @VisitDateTime = '2020-03-15 11:00', @VisitID = @VisitID OUTPUT;
    INSERT #Results VALUES (N'Тригер: візит до звільненого лікаря', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Тригер: візит до звільненого лікаря', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 12. CHECK: візит поза робочими годинами
BEGIN TRY
    EXEC dbo.usp_AddVisit @RecordID = @RecID, @DoctorID = @Doc1, @VisitDateTime = '2020-03-15 23:00', @VisitID = @VisitID OUTPUT;
    INSERT #Results VALUES (N'CHECK візит о 23:00', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'CHECK візит о 23:00', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 13. Нормальний повторний візит
BEGIN TRY
    EXEC dbo.usp_AddVisit @RecordID = @RecID, @DoctorID = @Doc1, @VisitDateTime = '2020-03-17 12:00', @VisitID = @VisitID OUTPUT;
    INSERT #Results VALUES (N'Повторний візит', 'OK', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Повторний візит', 'OK', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 14. Тригер: абсолютне протипоказання (аспірин при виразці)
BEGIN TRY
    EXEC dbo.usp_PrescribeMedication @VisitID = @VisitID, @MedicationID = @Aspirin, @Dosage = N'500 мг';
    INSERT #Results VALUES (N'Тригер: абсолютне протипоказання', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Тригер: абсолютне протипоказання', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 15. Відносне протипоказання (ібупрофен при астмі): дозволено з попередженням
BEGIN TRY
    SET @Warn = NULL;
    EXEC dbo.usp_PrescribeMedication @VisitID = @VisitID, @MedicationID = @Ibuprofen, @Dosage = N'200 мг', @Warning = @Warn OUTPUT;
    INSERT #Results VALUES (N'Відносне протипоказання → попередження', 'OK', CASE WHEN @Warn IS NOT NULL THEN 'OK' ELSE 'FAIL' END, @Warn);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Відносне протипоказання → попередження', 'OK', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 16. Призначення без протипоказань + обчислювана TotalCost
BEGIN TRY
    EXEC dbo.usp_PrescribeMedication @VisitID = @VisitID, @MedicationID = @Paracetamol, @Dosage = N'500 мг', @Quantity = 3, @PrescriptionID = @PrID OUTPUT;
    INSERT #Results SELECT N'Призначення + TotalCost = 3 × 30 = 90', 'OK',
           CASE WHEN (SELECT TotalCost FROM dbo.Prescriptions WHERE PrescriptionID = @PrID) = 90 THEN 'OK' ELSE 'FAIL' END, NULL;
END TRY BEGIN CATCH INSERT #Results VALUES (N'Призначення + TotalCost = 3 × 30 = 90', 'OK', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 17. Тригер: закриття історії раніше останнього візиту
BEGIN TRY
    EXEC dbo.usp_CloseMedicalRecord @RecordID = @RecID, @CloseDate = '2020-03-12', @Outcome = N'Одужання';
    INSERT #Results VALUES (N'Тригер: закриття раніше останнього візиту', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Тригер: закриття раніше останнього візиту', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 18. CHECK: закрита історія без результату
BEGIN TRY
    UPDATE dbo.MedicalRecords SET Status = N'Закрита', CloseDate = '2020-03-20' WHERE RecordID = @RecID;
    INSERT #Results VALUES (N'CHECK закрита історія без результату', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'CHECK закрита історія без результату', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 19. Коректне закриття історії
BEGIN TRY
    EXEC dbo.usp_CloseMedicalRecord @RecordID = @RecID, @CloseDate = '2020-03-20', @Outcome = N'Покращення';
    INSERT #Results VALUES (N'Закриття історії хвороби', 'OK', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Закриття історії хвороби', 'OK', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 20. Візит до закритої історії
BEGIN TRY
    EXEC dbo.usp_AddVisit @RecordID = @RecID, @DoctorID = @Doc1, @VisitDateTime = '2020-03-25 12:00', @VisitID = @VisitID OUTPUT;
    INSERT #Results VALUES (N'Візит до закритої історії', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Візит до закритої історії', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 21. Хронічна хвороба з іншої (закритої) історії блокує аспірин у новій історії
BEGIN TRY
    DECLARE @Rec2 INT, @Visit2 BIGINT;
    EXEC dbo.usp_OpenMedicalRecord @PatientID = @PatID, @DoctorID = @Doc1, @DiseaseID = @Flu,
         @OpenDateTime = '2022-01-10 09:00', @RecordID = @Rec2 OUTPUT;
    SELECT @Visit2 = VisitID FROM dbo.Visits WHERE RecordID = @Rec2;
    EXEC dbo.usp_PrescribeMedication @VisitID = @Visit2, @MedicationID = @Aspirin, @Dosage = N'500 мг';
    INSERT #Results VALUES (N'Тригер: хронічна хвороба з іншої історії', 'FAIL', 'OK', NULL);
END TRY BEGIN CATCH INSERT #Results VALUES (N'Тригер: хронічна хвороба з іншої історії', 'FAIL', 'FAIL', ERROR_MESSAGE()); END CATCH;

-- 22. Аудит: зміна телефону пацієнта пишеться в AuditLog
BEGIN TRY
    UPDATE dbo.Patients SET Phone = '+380501234567' WHERE PatientID = @PatID;
    INSERT #Results SELECT N'Тригер аудиту пацієнта', 'OK',
           CASE WHEN EXISTS (SELECT 1 FROM dbo.AuditLog WHERE TableName = N'Patients' AND RecordKey = @PatID
                             AND JSON_VALUE(NewData, '$.Phone') = '+380501234567') THEN 'OK' ELSE 'FAIL' END, NULL;
END TRY BEGIN CATCH INSERT #Results VALUES (N'Тригер аудиту пацієнта', 'OK', 'FAIL', ERROR_MESSAGE()); END CATCH;

/* ---------- Видалення тестових даних ---------- */
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
DELETE r FROM dbo.MedicalRecords r JOIN dbo.Patients p ON p.PatientID = r.PatientID WHERE p.CityID = @CityID; -- каскадно: діагнози, візити, призначення
DELETE dbo.Patients          WHERE CityID = @CityID;
DELETE dbo.Medications       WHERE GroupID = @GrpID;                                                       -- каскадно: протипоказання
DELETE dbo.MedicationGroups  WHERE GroupID = @GrpID;
DELETE dbo.Diseases          WHERE CategoryID = @CatID;
DELETE dbo.DiseaseCategories WHERE CategoryID = @CatID;
DELETE dbo.Doctors           WHERE DepartmentID = @DepID;
DELETE dbo.Departments       WHERE DepartmentID = @DepID;
DELETE dbo.Specialties       WHERE SpecialtyID = @SpecID;
DELETE dbo.Cities            WHERE CityID = @CityID;
DELETE dbo.Regions           WHERE RegionID = @RegionID;
DELETE dbo.AuditLog          WHERE AuditID > @AuditStart;

SELECT TestNo, TestName, Expected, Actual,
       CASE WHEN Expected = Actual THEN N'PASSED' ELSE N'*** FAILED ***' END AS Result,
       Message
FROM #Results ORDER BY TestNo;

SELECT COUNT(*) AS Total, SUM(CASE WHEN Expected = Actual THEN 1 ELSE 0 END) AS Passed FROM #Results;
GO
