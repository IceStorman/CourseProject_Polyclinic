USE PolyclinicDB;
GO
SET NOCOUNT ON;
GO

CREATE UNIQUE INDEX UX_Patients_InsurancePolicy ON dbo.Patients (InsurancePolicy) WHERE InsurancePolicy IS NOT NULL;
CREATE UNIQUE INDEX UX_Patients_Email           ON dbo.Patients (Email)           WHERE Email IS NOT NULL;
CREATE UNIQUE INDEX UX_Doctors_Email            ON dbo.Doctors  (Email)           WHERE Email IS NOT NULL;
CREATE UNIQUE INDEX UX_Diagnoses_OnePrimary     ON dbo.Diagnoses (RecordID)       WHERE DiagnosisType = N'Основний';
GO

CREATE INDEX IX_Cities_RegionID           ON dbo.Cities (RegionID);
CREATE INDEX IX_Doctors_SpecialtyID       ON dbo.Doctors (SpecialtyID);
CREATE INDEX IX_Doctors_DepartmentID      ON dbo.Doctors (DepartmentID);
CREATE INDEX IX_Patients_CityID           ON dbo.Patients (CityID);
CREATE INDEX IX_Diseases_CategoryID       ON dbo.Diseases (CategoryID);
CREATE INDEX IX_Medications_GroupID       ON dbo.Medications (GroupID);
CREATE INDEX IX_Contra_DiseaseID          ON dbo.Contraindications (DiseaseID) INCLUDE (ContraindicationType);
CREATE INDEX IX_Diagnoses_DoctorID        ON dbo.Diagnoses (DoctorID);
CREATE INDEX IX_Prescriptions_MedicationID ON dbo.Prescriptions (MedicationID) INCLUDE (Quantity, UnitPrice);
GO

CREATE INDEX IX_MedicalRecords_Patient_Open ON dbo.MedicalRecords (PatientID, OpenDate)
    INCLUDE (AttendingDoctorID, CloseDate, Status, Outcome);
CREATE INDEX IX_MedicalRecords_Doctor_Open  ON dbo.MedicalRecords (AttendingDoctorID, OpenDate)
    INCLUDE (PatientID, Status);
CREATE INDEX IX_MedicalRecords_Closed       ON dbo.MedicalRecords (CloseDate)
    INCLUDE (OpenDate, Outcome, AttendingDoctorID) WHERE Status = N'Закрита';

CREATE INDEX IX_Diagnoses_RecordID          ON dbo.Diagnoses (RecordID) INCLUDE (DiseaseID, DiagnosisType);
CREATE INDEX IX_Diagnoses_Disease_Date      ON dbo.Diagnoses (DiseaseID, DiagnosisDate) INCLUDE (RecordID, DiagnosisType);

CREATE INDEX IX_Visits_Doctor_Date          ON dbo.Visits (DoctorID, VisitDateTime) INCLUDE (Status, DurationMin, Cost);
CREATE INDEX IX_Visits_RecordID             ON dbo.Visits (RecordID) INCLUDE (VisitDateTime, Status);
CREATE INDEX IX_Visits_Date                 ON dbo.Visits (VisitDateTime) INCLUDE (DoctorID, Status, Cost);

CREATE INDEX IX_Prescriptions_VisitID       ON dbo.Prescriptions (VisitID);

CREATE INDEX IX_Patients_Name               ON dbo.Patients (LastName, FirstName) INCLUDE (BirthDate);

CREATE INDEX IX_Patients_ModifiedAt         ON dbo.Patients (ModifiedAt);
CREATE INDEX IX_Doctors_ModifiedAt          ON dbo.Doctors (ModifiedAt);
CREATE INDEX IX_MedicalRecords_ModifiedAt   ON dbo.MedicalRecords (ModifiedAt);
GO
