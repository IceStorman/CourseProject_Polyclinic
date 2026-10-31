USE PolyclinicDB;
GO
SET NOCOUNT ON;
GO

DECLARE @Kyiv INT = (SELECT CityID FROM dbo.Cities WHERE Name = N'Біла Церква');

UPDATE TOP (25) p SET CityID = @Kyiv
FROM dbo.Patients p JOIN dbo.Cities c ON c.CityID = p.CityID
WHERE c.Name = N'Львів' AND p.PatientID % 997 = 1;

UPDATE TOP (10) dbo.Patients
SET InsurancePolicy = 'UA9' + RIGHT('0000000' + CAST(PatientID AS VARCHAR(7)), 7)
WHERE InsurancePolicy IS NULL AND PatientID % 991 = 3;

UPDATE TOP (5) dbo.Patients SET LastName = LastName + N'-Петренко' WHERE PatientID % 983 = 5;

UPDATE TOP (2) dbo.Doctors SET Category = N'Вища'
WHERE DismissalDate IS NULL AND Category = N'Перша';

UPDATE dbo.Medications SET UnitPrice = UnitPrice * 1.10 WHERE Name IN (N'Парацетамол', N'Ібупрофен', N'Амлодипін');

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
