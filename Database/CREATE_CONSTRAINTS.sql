USE PolyclinicDB;
GO
SET NOCOUNT ON;
GO

ALTER TABLE dbo.Cities         ADD CONSTRAINT FK_Cities_Regions          FOREIGN KEY (RegionID)          REFERENCES dbo.Regions(RegionID);
ALTER TABLE dbo.Doctors        ADD CONSTRAINT FK_Doctors_Specialties     FOREIGN KEY (SpecialtyID)       REFERENCES dbo.Specialties(SpecialtyID);
ALTER TABLE dbo.Doctors        ADD CONSTRAINT FK_Doctors_Departments     FOREIGN KEY (DepartmentID)      REFERENCES dbo.Departments(DepartmentID);
ALTER TABLE dbo.Patients       ADD CONSTRAINT FK_Patients_Cities         FOREIGN KEY (CityID)            REFERENCES dbo.Cities(CityID);
ALTER TABLE dbo.Diseases       ADD CONSTRAINT FK_Diseases_Categories     FOREIGN KEY (CategoryID)        REFERENCES dbo.DiseaseCategories(CategoryID);
ALTER TABLE dbo.Medications    ADD CONSTRAINT FK_Medications_Groups      FOREIGN KEY (GroupID)           REFERENCES dbo.MedicationGroups(GroupID);
ALTER TABLE dbo.Contraindications ADD CONSTRAINT FK_Contra_Medications   FOREIGN KEY (MedicationID)      REFERENCES dbo.Medications(MedicationID) ON DELETE CASCADE;
ALTER TABLE dbo.Contraindications ADD CONSTRAINT FK_Contra_Diseases      FOREIGN KEY (DiseaseID)         REFERENCES dbo.Diseases(DiseaseID)       ON DELETE CASCADE;
ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT FK_MedicalRecords_Patients FOREIGN KEY (PatientID)         REFERENCES dbo.Patients(PatientID);
ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT FK_MedicalRecords_Doctors  FOREIGN KEY (AttendingDoctorID) REFERENCES dbo.Doctors(DoctorID);
ALTER TABLE dbo.Diagnoses      ADD CONSTRAINT FK_Diagnoses_Records       FOREIGN KEY (RecordID)          REFERENCES dbo.MedicalRecords(RecordID) ON DELETE CASCADE;
ALTER TABLE dbo.Diagnoses      ADD CONSTRAINT FK_Diagnoses_Diseases      FOREIGN KEY (DiseaseID)         REFERENCES dbo.Diseases(DiseaseID);
ALTER TABLE dbo.Diagnoses      ADD CONSTRAINT FK_Diagnoses_Doctors       FOREIGN KEY (DoctorID)          REFERENCES dbo.Doctors(DoctorID);
ALTER TABLE dbo.Visits         ADD CONSTRAINT FK_Visits_Records          FOREIGN KEY (RecordID)          REFERENCES dbo.MedicalRecords(RecordID) ON DELETE CASCADE;
ALTER TABLE dbo.Visits         ADD CONSTRAINT FK_Visits_Doctors          FOREIGN KEY (DoctorID)          REFERENCES dbo.Doctors(DoctorID);
ALTER TABLE dbo.Prescriptions  ADD CONSTRAINT FK_Prescriptions_Visits    FOREIGN KEY (VisitID)           REFERENCES dbo.Visits(VisitID) ON DELETE CASCADE;
ALTER TABLE dbo.Prescriptions  ADD CONSTRAINT FK_Prescriptions_Medications FOREIGN KEY (MedicationID)    REFERENCES dbo.Medications(MedicationID);
GO

ALTER TABLE dbo.Regions           ADD CONSTRAINT UQ_Regions_Name           UNIQUE (Name);
ALTER TABLE dbo.Cities            ADD CONSTRAINT UQ_Cities_Region_Name     UNIQUE (RegionID, Name);
ALTER TABLE dbo.Specialties       ADD CONSTRAINT UQ_Specialties_Name       UNIQUE (Name);
ALTER TABLE dbo.Departments       ADD CONSTRAINT UQ_Departments_Name       UNIQUE (Name);
ALTER TABLE dbo.DiseaseCategories ADD CONSTRAINT UQ_DiseaseCategories_ICD  UNIQUE (ICDChapter);
ALTER TABLE dbo.Diseases          ADD CONSTRAINT UQ_Diseases_ICDCode       UNIQUE (ICDCode);
ALTER TABLE dbo.MedicationGroups  ADD CONSTRAINT UQ_MedicationGroups_Name  UNIQUE (Name);
ALTER TABLE dbo.Medications       ADD CONSTRAINT UQ_Medications_Name       UNIQUE (Name);
ALTER TABLE dbo.Diagnoses         ADD CONSTRAINT UQ_Diagnoses_Record_Disease UNIQUE (RecordID, DiseaseID);
ALTER TABLE dbo.Prescriptions     ADD CONSTRAINT UQ_Prescriptions_Visit_Med  UNIQUE (VisitID, MedicationID);
GO

ALTER TABLE dbo.Specialties ADD CONSTRAINT CK_Specialties_Price  CHECK (BaseVisitPrice >= 0);
ALTER TABLE dbo.Departments ADD CONSTRAINT CK_Departments_Floor  CHECK (Floor BETWEEN 1 AND 10);
ALTER TABLE dbo.Doctors ADD CONSTRAINT CK_Doctors_Gender         CHECK (Gender IN ('M', 'F'));
ALTER TABLE dbo.Doctors ADD CONSTRAINT CK_Doctors_Category       CHECK (Category IN (N'Вища', N'Перша', N'Друга', N'Без категорії'));
ALTER TABLE dbo.Doctors ADD CONSTRAINT CK_Doctors_HireAge         CHECK (DATEDIFF(YEAR, BirthDate, HireDate) >= 22);
ALTER TABLE dbo.Doctors ADD CONSTRAINT CK_Doctors_Dismissal       CHECK (DismissalDate IS NULL OR DismissalDate >= HireDate);
ALTER TABLE dbo.Doctors ADD CONSTRAINT CK_Doctors_Phone           CHECK (Phone IS NULL OR Phone LIKE '+380[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]');
ALTER TABLE dbo.Doctors ADD CONSTRAINT CK_Doctors_Email           CHECK (Email IS NULL OR Email LIKE '%_@_%._%');

ALTER TABLE dbo.Patients ADD CONSTRAINT CK_Patients_Gender        CHECK (Gender IN ('M', 'F'));
ALTER TABLE dbo.Patients ADD CONSTRAINT CK_Patients_BirthDate     CHECK (BirthDate >= '1900-01-01' AND BirthDate <= RegistrationDate);
ALTER TABLE dbo.Patients ADD CONSTRAINT CK_Patients_BloodType     CHECK (BloodType IS NULL OR BloodType IN ('O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'));
ALTER TABLE dbo.Patients ADD CONSTRAINT CK_Patients_Phone         CHECK (Phone IS NULL OR Phone LIKE '+380[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]');
ALTER TABLE dbo.Patients ADD CONSTRAINT CK_Patients_Email         CHECK (Email IS NULL OR Email LIKE '%_@_%._%');

ALTER TABLE dbo.Diseases ADD CONSTRAINT CK_Diseases_ICDCode       CHECK (ICDCode LIKE '[A-Z][0-9][0-9]%');
ALTER TABLE dbo.Diseases ADD CONSTRAINT CK_Diseases_Severity      CHECK (Severity BETWEEN 1 AND 5);
ALTER TABLE dbo.Diseases ADD CONSTRAINT CK_Diseases_TreatmentDays CHECK (AvgTreatmentDays > 0);
ALTER TABLE dbo.Diseases ADD CONSTRAINT CK_Diseases_Seasonality   CHECK (Seasonality IN (N'Зима', N'Весна', N'Літо', N'Осінь', N'Всесезонна'));
ALTER TABLE dbo.Medications ADD CONSTRAINT CK_Medications_Price   CHECK (UnitPrice > 0);
ALTER TABLE dbo.Contraindications ADD CONSTRAINT CK_Contra_Type   CHECK (ContraindicationType IN (N'Абсолютне', N'Відносне'));

ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT CK_MedicalRecords_Status  CHECK (Status IN (N'Відкрита', N'Закрита'));
ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT CK_MedicalRecords_Outcome CHECK (Outcome IS NULL OR Outcome IN
    (N'Одужання', N'Покращення', N'Без змін', N'Погіршення', N'Перехід у хронічну форму', N'Госпіталізація'));
ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT CK_MedicalRecords_Dates   CHECK (CloseDate IS NULL OR CloseDate >= OpenDate);
ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT CK_MedicalRecords_StatusConsistency CHECK (
       (Status = N'Відкрита' AND CloseDate IS NULL     AND Outcome IS NULL)
    OR (Status = N'Закрита'  AND CloseDate IS NOT NULL AND Outcome IS NOT NULL));

ALTER TABLE dbo.Diagnoses ADD CONSTRAINT CK_Diagnoses_Type        CHECK (DiagnosisType IN (N'Основний', N'Супутній', N'Ускладнення'));
ALTER TABLE dbo.Diagnoses ADD CONSTRAINT CK_Diagnoses_Severity    CHECK (Severity BETWEEN 1 AND 5);

ALTER TABLE dbo.Visits ADD CONSTRAINT CK_Visits_Type              CHECK (VisitType IN (N'Первинний', N'Повторний', N'Консультація', N'Виклик додому'));
ALTER TABLE dbo.Visits ADD CONSTRAINT CK_Visits_Status            CHECK (Status IN (N'Відбувся', N'Скасовано', N'Неявка'));
ALTER TABLE dbo.Visits ADD CONSTRAINT CK_Visits_Duration          CHECK (DurationMin BETWEEN 5 AND 120);
ALTER TABLE dbo.Visits ADD CONSTRAINT CK_Visits_Cost              CHECK (Cost >= 0);
ALTER TABLE dbo.Visits ADD CONSTRAINT CK_Visits_CostByStatus      CHECK (Status = N'Відбувся' OR Cost = 0);
ALTER TABLE dbo.Visits ADD CONSTRAINT CK_Visits_WorkingHours      CHECK (DATEPART(HOUR, VisitDateTime) BETWEEN 7 AND 20);

ALTER TABLE dbo.Prescriptions ADD CONSTRAINT CK_Prescriptions_TimesPerDay CHECK (TimesPerDay BETWEEN 1 AND 6);
ALTER TABLE dbo.Prescriptions ADD CONSTRAINT CK_Prescriptions_Duration    CHECK (DurationDays BETWEEN 1 AND 365);
ALTER TABLE dbo.Prescriptions ADD CONSTRAINT CK_Prescriptions_Quantity    CHECK (Quantity > 0);
ALTER TABLE dbo.Prescriptions ADD CONSTRAINT CK_Prescriptions_Price       CHECK (UnitPrice > 0);

ALTER TABLE dbo.AuditLog ADD CONSTRAINT CK_AuditLog_Operation     CHECK (Operation IN ('INSERT', 'UPDATE', 'DELETE'));
GO

ALTER TABLE dbo.Cities         ADD CONSTRAINT DF_Cities_IsRegionalCenter DEFAULT (0)             FOR IsRegionalCenter;
ALTER TABLE dbo.Doctors        ADD CONSTRAINT DF_Doctors_Category        DEFAULT (N'Без категорії') FOR Category;
ALTER TABLE dbo.Doctors        ADD CONSTRAINT DF_Doctors_CreatedAt       DEFAULT (SYSDATETIME())  FOR CreatedAt;
ALTER TABLE dbo.Doctors        ADD CONSTRAINT DF_Doctors_ModifiedAt      DEFAULT (SYSDATETIME())  FOR ModifiedAt;
ALTER TABLE dbo.Patients       ADD CONSTRAINT DF_Patients_RegDate        DEFAULT (CAST(GETDATE() AS DATE)) FOR RegistrationDate;
ALTER TABLE dbo.Patients       ADD CONSTRAINT DF_Patients_IsActive       DEFAULT (1)              FOR IsActive;
ALTER TABLE dbo.Patients       ADD CONSTRAINT DF_Patients_CreatedAt      DEFAULT (SYSDATETIME())  FOR CreatedAt;
ALTER TABLE dbo.Patients       ADD CONSTRAINT DF_Patients_ModifiedAt     DEFAULT (SYSDATETIME())  FOR ModifiedAt;
ALTER TABLE dbo.Diseases       ADD CONSTRAINT DF_Diseases_IsChronic      DEFAULT (0)              FOR IsChronic;
ALTER TABLE dbo.Diseases       ADD CONSTRAINT DF_Diseases_IsInfectious   DEFAULT (0)              FOR IsInfectious;
ALTER TABLE dbo.Diseases       ADD CONSTRAINT DF_Diseases_Seasonality    DEFAULT (N'Всесезонна')  FOR Seasonality;
ALTER TABLE dbo.Medications    ADD CONSTRAINT DF_Medications_RxOnly      DEFAULT (0)              FOR IsPrescriptionOnly;
ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT DF_MedicalRecords_Status   DEFAULT (N'Відкрита')    FOR Status;
ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT DF_MedicalRecords_CreatedAt  DEFAULT (SYSDATETIME()) FOR CreatedAt;
ALTER TABLE dbo.MedicalRecords ADD CONSTRAINT DF_MedicalRecords_ModifiedAt DEFAULT (SYSDATETIME()) FOR ModifiedAt;
ALTER TABLE dbo.Diagnoses      ADD CONSTRAINT DF_Diagnoses_Type          DEFAULT (N'Основний')    FOR DiagnosisType;
ALTER TABLE dbo.Diagnoses      ADD CONSTRAINT DF_Diagnoses_Severity      DEFAULT (2)              FOR Severity;
ALTER TABLE dbo.Visits         ADD CONSTRAINT DF_Visits_Status           DEFAULT (N'Відбувся')    FOR Status;
ALTER TABLE dbo.Visits         ADD CONSTRAINT DF_Visits_Duration         DEFAULT (15)             FOR DurationMin;
ALTER TABLE dbo.Prescriptions  ADD CONSTRAINT DF_Prescriptions_TimesPerDay DEFAULT (1)            FOR TimesPerDay;
ALTER TABLE dbo.Prescriptions  ADD CONSTRAINT DF_Prescriptions_Quantity  DEFAULT (1)              FOR Quantity;
ALTER TABLE dbo.AuditLog       ADD CONSTRAINT DF_AuditLog_ChangedAt      DEFAULT (SYSDATETIME())  FOR ChangedAt;
ALTER TABLE dbo.AuditLog       ADD CONSTRAINT DF_AuditLog_ChangedBy      DEFAULT (SUSER_SNAME())  FOR ChangedBy;
GO
