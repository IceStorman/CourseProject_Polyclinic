USE PolyclinicDB;
GO
SET NOCOUNT ON;
GO

CREATE TABLE dbo.Regions (
    RegionID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Regions PRIMARY KEY,
    Name              NVARCHAR(100)     NOT NULL
);

CREATE TABLE dbo.Cities (
    CityID            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cities PRIMARY KEY,
    RegionID          INT               NOT NULL,
    Name              NVARCHAR(100)     NOT NULL,
    IsRegionalCenter  BIT               NOT NULL
);

CREATE TABLE dbo.Specialties (
    SpecialtyID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Specialties PRIMARY KEY,
    Name              NVARCHAR(100)     NOT NULL,
    BaseVisitPrice    DECIMAL(10,2)     NOT NULL,
    Description       NVARCHAR(300)     NULL
);

CREATE TABLE dbo.Departments (
    DepartmentID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Departments PRIMARY KEY,
    Name              NVARCHAR(100)     NOT NULL,
    Floor             TINYINT           NOT NULL,
    Phone             VARCHAR(20)       NULL
);

CREATE TABLE dbo.Doctors (
    DoctorID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Doctors PRIMARY KEY,
    LastName          NVARCHAR(50)      NOT NULL,
    FirstName         NVARCHAR(50)      NOT NULL,
    MiddleName        NVARCHAR(50)      NULL,
    Gender            CHAR(1)           NOT NULL,
    BirthDate         DATE              NOT NULL,
    SpecialtyID       INT               NOT NULL,
    DepartmentID      INT               NOT NULL,
    Category          NVARCHAR(20)      NOT NULL,
    HireDate          DATE              NOT NULL,
    DismissalDate     DATE              NULL,
    Phone             VARCHAR(20)       NULL,
    Email             VARCHAR(100)      NULL,
    CreatedAt         DATETIME2(0)      NOT NULL,
    ModifiedAt        DATETIME2(0)      NOT NULL
);

CREATE TABLE dbo.Patients (
    PatientID         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Patients PRIMARY KEY,
    LastName          NVARCHAR(50)      NOT NULL,
    FirstName         NVARCHAR(50)      NOT NULL,
    MiddleName        NVARCHAR(50)      NULL,
    Gender            CHAR(1)           NOT NULL,
    BirthDate         DATE              NOT NULL,
    CityID            INT               NOT NULL,
    Address           NVARCHAR(200)     NULL,
    Phone             VARCHAR(20)       NULL,
    Email             VARCHAR(100)      NULL,
    InsurancePolicy   VARCHAR(20)       NULL,
    BloodType         VARCHAR(3)        NULL,
    RegistrationDate  DATE              NOT NULL,
    IsActive          BIT               NOT NULL,
    CreatedAt         DATETIME2(0)      NOT NULL,
    ModifiedAt        DATETIME2(0)      NOT NULL
);

CREATE TABLE dbo.DiseaseCategories (
    CategoryID        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DiseaseCategories PRIMARY KEY,
    ICDChapter        VARCHAR(10)       NOT NULL,
    Name              NVARCHAR(150)     NOT NULL
);

CREATE TABLE dbo.Diseases (
    DiseaseID         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Diseases PRIMARY KEY,
    ICDCode           VARCHAR(10)       NOT NULL,
    Name              NVARCHAR(200)     NOT NULL,
    CategoryID        INT               NOT NULL,
    IsChronic         BIT               NOT NULL,
    IsInfectious      BIT               NOT NULL,
    Severity          TINYINT           NOT NULL,
    AvgTreatmentDays  SMALLINT          NOT NULL,
    Seasonality       NVARCHAR(20)      NOT NULL
);

CREATE TABLE dbo.MedicationGroups (
    GroupID           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MedicationGroups PRIMARY KEY,
    Name              NVARCHAR(100)     NOT NULL
);

CREATE TABLE dbo.Medications (
    MedicationID      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Medications PRIMARY KEY,
    Name              NVARCHAR(150)     NOT NULL,
    ActiveSubstance   NVARCHAR(150)     NOT NULL,
    GroupID           INT               NOT NULL,
    DosageForm        NVARCHAR(50)      NOT NULL,
    Manufacturer      NVARCHAR(100)     NULL,
    UnitPrice         DECIMAL(10,2)     NOT NULL,
    IsPrescriptionOnly BIT              NOT NULL
);

CREATE TABLE dbo.Contraindications (
    MedicationID          INT           NOT NULL,
    DiseaseID             INT           NOT NULL,
    ContraindicationType  NVARCHAR(20)  NOT NULL,
    Description           NVARCHAR(300) NULL,
    CONSTRAINT PK_Contraindications PRIMARY KEY (MedicationID, DiseaseID)
);

CREATE TABLE dbo.MedicalRecords (
    RecordID          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MedicalRecords PRIMARY KEY,
    PatientID         INT               NOT NULL,
    AttendingDoctorID INT               NOT NULL,
    OpenDate          DATE              NOT NULL,
    CloseDate         DATE              NULL,
    Status            NVARCHAR(10)      NOT NULL,
    Outcome           NVARCHAR(30)      NULL,
    Notes             NVARCHAR(500)     NULL,
    CreatedAt         DATETIME2(0)      NOT NULL,
    ModifiedAt        DATETIME2(0)      NOT NULL
);

CREATE TABLE dbo.Diagnoses (
    DiagnosisID       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Diagnoses PRIMARY KEY,
    RecordID          INT               NOT NULL,
    DiseaseID         INT               NOT NULL,
    DoctorID          INT               NOT NULL,
    DiagnosisDate     DATE              NOT NULL,
    DiagnosisType     NVARCHAR(15)      NOT NULL,
    Severity          TINYINT           NOT NULL,
    Notes             NVARCHAR(300)     NULL
);

CREATE TABLE dbo.Visits (
    VisitID           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Visits PRIMARY KEY,
    RecordID          INT               NOT NULL,
    DoctorID          INT               NOT NULL,
    VisitDateTime     DATETIME2(0)      NOT NULL,
    VisitType         NVARCHAR(20)      NOT NULL,
    Status            NVARCHAR(15)      NOT NULL,
    DurationMin       SMALLINT          NOT NULL,
    Cost              DECIMAL(10,2)     NOT NULL,
    Complaints        NVARCHAR(300)     NULL
);

CREATE TABLE dbo.Prescriptions (
    PrescriptionID    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Prescriptions PRIMARY KEY,
    VisitID           BIGINT            NOT NULL,
    MedicationID      INT               NOT NULL,
    Dosage            NVARCHAR(50)      NOT NULL,
    TimesPerDay       TINYINT           NOT NULL,
    DurationDays      SMALLINT          NOT NULL,
    Quantity          SMALLINT          NOT NULL,
    UnitPrice         DECIMAL(10,2)     NOT NULL,
    TotalCost         AS CAST(Quantity * UnitPrice AS DECIMAL(12,2)) PERSISTED
);

CREATE TABLE dbo.AuditLog (
    AuditID           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditLog PRIMARY KEY,
    TableName         SYSNAME           NOT NULL,
    Operation         VARCHAR(6)        NOT NULL,
    RecordKey         INT               NOT NULL,
    ChangedAt         DATETIME2(0)      NOT NULL,
    ChangedBy         SYSNAME           NOT NULL,
    OldData           NVARCHAR(MAX)     NULL,
    NewData           NVARCHAR(MAX)     NULL
);
GO
