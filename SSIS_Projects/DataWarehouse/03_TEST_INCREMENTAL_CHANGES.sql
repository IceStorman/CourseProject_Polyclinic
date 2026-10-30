/* =====================================================================
   Курсова робота NVBD, варіант 6 «Поліклініка»
   Тест інкрементального завантаження та SCD.
   Вносить зміни в OLTP (PolyclinicDB). Після цього потрібно запустити
   00_Master.dtsx і виконати перевірочні запити в кінці скрипта.
     - 25 пацієнтів переїхали до іншого міста           → SCD Type 2 (нові версії)
     - 10 пацієнтів оформили страховий поліс            → SCD Type 2
     - 5 пацієнтам виправлено прізвище (помилка вводу)  → SCD Type 1 (перезапис)
     - 2 лікарі отримали вищу категорію                 → SCD Type 2
     - змінилась ціна 3 препаратів                       → SCD Type 1
     - новий візит + призначення, закрита історія хвороби → інкрементальні факти
   ===================================================================== */
USE PolyclinicDB;
GO
SET NOCOUNT ON;
GO

DECLARE @Kyiv INT = (SELECT CityID FROM dbo.Cities WHERE Name = N'Біла Церква');

-- Переїзд: пацієнти зі Львова → Біла Церква
UPDATE TOP (25) p SET CityID = @Kyiv
FROM dbo.Patients p JOIN dbo.Cities c ON c.CityID = p.CityID
WHERE c.Name = N'Львів' AND p.PatientID % 997 = 1;

-- Оформлення страхового поліса
UPDATE TOP (10) dbo.Patients
SET InsurancePolicy = 'UA9' + RIGHT('0000000' + CAST(PatientID AS VARCHAR(7)), 7)
WHERE InsurancePolicy IS NULL AND PatientID % 991 = 3;

-- Виправлення прізвища (SCD1): зайвий пробіл і зміна регістру видно в OLTP, у сховищі — очищене значення
UPDATE TOP (5) dbo.Patients SET LastName = LastName + N'-Петренко' WHERE PatientID % 983 = 5;

-- Підвищення категорії лікарів
UPDATE TOP (2) dbo.Doctors SET Category = N'Вища'
WHERE DismissalDate IS NULL AND Category = N'Перша';

-- Ціни препаратів
UPDATE dbo.Medications SET UnitPrice = UnitPrice * 1.10 WHERE Name IN (N'Парацетамол', N'Ібупрофен', N'Амлодипін');

-- Новий візит і призначення у відкритій історії хвороби, закриття іншої історії
DECLARE @Rec INT, @Doc INT, @Visit BIGINT, @Rec2 INT;
SELECT TOP (1) @Rec = r.RecordID, @Doc = r.AttendingDoctorID
FROM dbo.MedicalRecords r WHERE r.Status = N'Відкрита' ORDER BY r.RecordID;
EXEC dbo.usp_AddVisit @RecordID = @Rec, @DoctorID = @Doc, @VisitDateTime = '2026-01-12 10:30',
     @VisitType = N'Повторний', @VisitID = @Visit OUTPUT;
EXEC dbo.usp_PrescribeMedication @VisitID = @Visit, @MedicationID = 1, @Dosage = N'500 мг', @TimesPerDay = 3, @DurationDays = 5, @Quantity = 1;

SELECT TOP (1) @Rec2 = RecordID FROM dbo.MedicalRecords WHERE Status = N'Відкрита' AND RecordID <> @Rec ORDER BY RecordID;
EXEC dbo.usp_CloseMedicalRecord @RecordID = @Rec2, @CloseDate = '2026-01-15', @Outcome = N'Одужання';

PRINT CONCAT(N'Новий візит ', @Visit, N' в історії ', @Rec, N'; закрито історію ', @Rec2);
GO

/* ---------- Перевірка після запуску 00_Master.dtsx ----------
USE PolyclinicDW;
SELECT PackageName, RowsRead, RowsInserted, RowsUpdated FROM etl.vw_PackageRuns WHERE RunID = (SELECT MAX(RunID) FROM etl.ETLRun);
-- історія пацієнта (SCD2): дві версії з різними містами
SELECT PatientID, FullName, City, HasInsurance, ValidFrom, ValidTo, IsCurrent
FROM dim.DimPatient WHERE PatientID IN (SELECT PatientID FROM dim.DimPatient GROUP BY PatientID HAVING COUNT(*) > 1)
ORDER BY PatientID, ValidFrom;
SELECT DoctorID, ShortName, Category, ValidFrom, ValidTo, IsCurrent
FROM dim.DimDoctor WHERE DoctorID IN (SELECT DoctorID FROM dim.DimDoctor GROUP BY DoctorID HAVING COUNT(*) > 1);
----------------------------------------------------------------- */
