/* =====================================================================
   Курсова робота NVBD, варіант 6 «Поліклініка»
   Генерація даних. Скрипт 3. Медичні дані за 2016–2025 рр.
     MedicalRecords ~560 000, Diagnoses ~650 000, Visits ~1 200 000,
     Prescriptions ~1 100 000

   Моделі реалістичності:
     - сезонність звернень (пік узимку, спад улітку), ріст бази по роках,
       локдаун 2020 р. та початок повномасштабної війни 2022 р.;
       неробочі неділі та державні свята
     - хвороба залежить від віку, статі пацієнта та сезону;
       COVID-19 — лише у березні 2020 – травні 2023
     - хронічні хвороби мають повторні звернення; хронічні хвороби з
       попередніх історій додаються як супутні діагнози
     - тривалість і результат лікування залежать від тяжкості, віку
       пацієнта та кваліфікаційної категорії лікаря
     - ціни на візити та ліки індексуються за роками (інфляція)
     - ліки підбираються за групою хвороби без абсолютних протипоказань
   Генерація набору даних — set-based (без курсорів), ~3–6 хв.
   ===================================================================== */
USE PolyclinicDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Тригери перевіряють поодинокі операції; при масовому завантаженні
-- правила гарантує генератор, а скрипт 04 перевіряє їх повторно
DISABLE TRIGGER ALL ON dbo.MedicalRecords;
DISABLE TRIGGER ALL ON dbo.Diagnoses;
DISABLE TRIGGER ALL ON dbo.Visits;
DISABLE TRIGGER ALL ON dbo.Prescriptions;
GO

/* =====================================================================
   1. Календар робочих днів з вагами інтенсивності звернень
   ===================================================================== */
RAISERROR(N'1. Календар...', 0, 1) WITH NOWAIT;

DROP TABLE IF EXISTS gen.Inflation;
SELECT * INTO gen.Inflation FROM (VALUES
 (2016, 0.45), (2017, 0.52), (2018, 0.58), (2019, 0.62), (2020, 0.66),
 (2021, 0.72), (2022, 0.85), (2023, 0.93), (2024, 0.97), (2025, 1.00)) v(Yr, K);

DROP TABLE IF EXISTS gen.Calendar;
WITH Days AS (
    SELECT CAST(DATEADD(DAY, N - 1, '2016-01-01') AS DATE) AS D
    FROM gen.Numbers WHERE N <= DATEDIFF(DAY, '2016-01-01', '2025-12-31') + 1
), Weighted AS (
    SELECT D,
           CHOOSE(MONTH(D), 1.30, 1.30, 1.10, 0.95, 0.85, 0.75, 0.65, 0.70, 1.00, 1.10, 1.20, 1.20)     -- сезонність
         * CHOOSE(YEAR(D) - 2015, 0.80, 0.84, 0.88, 0.92, 0.90, 1.00, 1.05, 1.08, 1.10, 1.12)          -- ріст бази
         * CASE WHEN DATEDIFF(DAY, '19000101', D) % 7 = 5 THEN 0.35 ELSE 1.0 END                        -- субота
         * CASE WHEN D BETWEEN '2020-03-17' AND '2020-05-31' THEN 0.45                                   -- локдаун
                WHEN D BETWEEN '2022-02-24' AND '2022-04-15' THEN 0.60                                   -- початок війни
                ELSE 1.0 END AS W
    FROM Days
    WHERE DATEDIFF(DAY, '19000101', D) % 7 <> 6                                                         -- неділя — вихідний
      AND NOT (MONTH(D) = 1 AND DAY(D) IN (1, 7))
      AND NOT (MONTH(D) = 3 AND DAY(D) = 8)
      AND NOT (MONTH(D) = 5 AND DAY(D) = 1)
      AND NOT (MONTH(D) = 8 AND DAY(D) = 24)
      AND NOT (MONTH(D) = 12 AND DAY(D) = 25)
)
SELECT ISNULL(D, '19000101') AS D,
       SUM(W) OVER (ORDER BY D ROWS UNBOUNDED PRECEDING) / SUM(W) OVER () AS CumTo,
       CAST(0 AS INT) AS EligibleCnt
INTO gen.Calendar
FROM Weighted;
ALTER TABLE gen.Calendar ADD CONSTRAINT PK_gen_Calendar PRIMARY KEY (D);
UPDATE gen.Calendar SET CumTo = 1.01 WHERE D = (SELECT MAX(D) FROM gen.Calendar);
CREATE INDEX IX_gen_Calendar_CumTo ON gen.Calendar (CumTo) INCLUDE (EligibleCnt);

-- Пацієнти в порядку прикріплення; EligibleCnt — скільки пацієнтів прикріплено на дату
DROP TABLE IF EXISTS gen.PatReg;
SELECT ISNULL(CAST(ROW_NUMBER() OVER (ORDER BY RegistrationDate, PatientID) AS INT), 0) AS Rn,
       PatientID, RegistrationDate, BirthDate, Gender
INTO gen.PatReg
FROM dbo.Patients;
ALTER TABLE gen.PatReg ADD CONSTRAINT PK_gen_PatReg PRIMARY KEY (Rn);
CREATE INDEX IX_gen_PatReg_Date ON gen.PatReg (RegistrationDate, Rn);

UPDATE c SET EligibleCnt = x.Cnt
FROM gen.Calendar c
CROSS APPLY (SELECT MAX(Rn) AS Cnt FROM gen.PatReg p WHERE p.RegistrationDate <= c.D) x;
GO

/* =====================================================================
   2. Кумулятивні ймовірності хвороб для кожної комбінації
      (вікова група × стать × сезон × період COVID)
   ===================================================================== */
RAISERROR(N'2. Ймовірності хвороб...', 0, 1) WITH NOWAIT;

DROP TABLE IF EXISTS #AgeFactor;
SELECT * INTO #AgeFactor FROM (VALUES
 ('all', 0, 1.0), ('all', 1, 1.0), ('all', 2, 1.0), ('all', 3, 1.0), ('all', 4, 1.0),
 ('child', 0, 4.0), ('child', 1, 0.3), ('child', 2, 0.1), ('child', 3, 0.1), ('child', 4, 0.1),
 ('young', 0, 1.0), ('young', 1, 2.0), ('young', 2, 0.6), ('young', 3, 0.2), ('young', 4, 0.1),
 ('adult', 0, 0.1), ('adult', 1, 1.0), ('adult', 2, 1.5), ('adult', 3, 1.2), ('adult', 4, 0.8),
 ('elderly', 0, 0.0), ('elderly', 1, 0.1), ('elderly', 2, 0.5), ('elderly', 3, 1.5), ('elderly', 4, 3.0)
) v(Profile, Band, F);

DROP TABLE IF EXISTS gen.DiseaseCum;
WITH Combos AS (
    SELECT b.Band, g.Gender, s.Season, c.Covid
    FROM (VALUES (0), (1), (2), (3), (4)) b(Band)
    CROSS JOIN (VALUES ('M'), ('F')) g(Gender)
    CROSS JOIN (VALUES (N'Зима'), (N'Весна'), (N'Літо'), (N'Осінь')) s(Season)
    CROSS JOIN (VALUES (0), (1)) c(Covid)
), W AS (
    SELECT cb.Band, cb.Gender, cb.Season, cb.Covid, dp.DiseaseID,
           CASE WHEN dp.ICDCode = 'U07.1' THEN CASE WHEN cb.Covid = 1 THEN 70.0 ELSE 0 END ELSE dp.Weight END
         * af.F
         * CASE WHEN dp.Seasonality = cb.Season THEN 2.5 WHEN dp.Seasonality = N'Всесезонна' THEN 1.0 ELSE 0.6 END
         * CASE WHEN dp.Gender IS NULL OR dp.Gender = cb.Gender THEN 1.0
                WHEN dp.ICDCode IN ('N95.1', 'N94.6', 'N76.0', 'M81.0', 'N40') THEN 0.0   -- лише одна стать
                ELSE 0.4 END AS W                                                         -- переважно одна стать
    FROM Combos cb
    CROSS JOIN gen.DiseaseProfile dp
    JOIN #AgeFactor af ON af.Profile = dp.AgeProfile AND af.Band = cb.Band
)
SELECT Band, Gender, Season, Covid, DiseaseID,
       SUM(W) OVER (PARTITION BY Band, Gender, Season, Covid ORDER BY DiseaseID ROWS UNBOUNDED PRECEDING)
     / SUM(W) OVER (PARTITION BY Band, Gender, Season, Covid) AS CumTo,
       ROW_NUMBER() OVER (PARTITION BY Band, Gender, Season, Covid ORDER BY DiseaseID DESC) AS RevRn
INTO gen.DiseaseCum
FROM W
WHERE W > 0;
UPDATE gen.DiseaseCum SET CumTo = 1.01 WHERE RevRn = 1;
CREATE CLUSTERED INDEX CIX_gen_DiseaseCum ON gen.DiseaseCum (Band, Gender, Season, Covid, CumTo);
GO

/* =====================================================================
   3. Слоти звернень: дата → пацієнт (прикріплений на дату) → хвороба
   ===================================================================== */
RAISERROR(N'3. Звернення...', 0, 1) WITH NOWAIT;

DECLARE @BaseRecords INT = 470000;

DROP TABLE IF EXISTS #S;
SELECT N AS SlotID,
       -- рівномірне [0; 1): 31 випадковий біт / 2^31
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) / 2147483648.0 AS RDate,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) / 2147483648.0 AS RPat,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) / 2147483648.0 AS RDis,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS RF1,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS RF2
INTO #S
FROM gen.Numbers WHERE N <= @BaseRecords;

DROP TABLE IF EXISTS #Base;
SELECT s.SlotID, c.D AS OpenDate, p.PatientID, dz.DiseaseID, s.RF1, s.RF2
INTO #Base
FROM #S s
CROSS APPLY (SELECT TOP (1) D, EligibleCnt FROM gen.Calendar WHERE CumTo >= s.RDate ORDER BY CumTo) c
JOIN gen.PatReg p ON p.Rn = 1 + CAST(s.RPat * c.EligibleCnt AS INT)
CROSS APPLY (SELECT DATEDIFF(YEAR, p.BirthDate, c.D)
                  - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.BirthDate, c.D), p.BirthDate) > c.D THEN 1 ELSE 0 END AS Age) a
CROSS APPLY (SELECT CASE WHEN a.Age < 18 THEN 0 WHEN a.Age < 35 THEN 1 WHEN a.Age < 50 THEN 2 WHEN a.Age < 65 THEN 3 ELSE 4 END AS Band,
                    CASE WHEN MONTH(c.D) IN (12, 1, 2) THEN N'Зима' WHEN MONTH(c.D) IN (3, 4, 5) THEN N'Весна'
                         WHEN MONTH(c.D) IN (6, 7, 8) THEN N'Літо' ELSE N'Осінь' END AS Season,
                    CASE WHEN c.D BETWEEN '2020-03-15' AND '2023-05-31' THEN 1 ELSE 0 END AS Covid) k
CROSS APPLY (SELECT TOP (1) dc.DiseaseID FROM gen.DiseaseCum dc
             WHERE dc.Band = k.Band AND dc.Gender = p.Gender AND dc.Season = k.Season AND dc.Covid = k.Covid
               AND dc.CumTo >= s.RDis
             ORDER BY dc.CumTo) dz;

-- Повторні звернення з хронічними хворобами: 25% випадків, 1–3 повтори через 4–12 місяців
DROP TABLE IF EXISTS #Slots;
SELECT OpenDate, PatientID, DiseaseID INTO #Slots FROM #Base;

INSERT #Slots (OpenDate, PatientID, DiseaseID)
SELECT fd.D, b.PatientID, b.DiseaseID
FROM #Base b
JOIN gen.DiseaseProfile dp ON dp.DiseaseID = b.DiseaseID AND dp.IsChronic = 1
JOIN gen.Numbers k ON k.N <= 1 + b.RF2 % 3
CROSS APPLY (SELECT DATEADD(DAY, k.N * (120 + (b.RF2 / 7 + k.N * 7919) % 245), b.OpenDate) AS D0) x
CROSS APPLY (SELECT CASE WHEN DATEDIFF(DAY, '19000101', x.D0) % 7 = 6 THEN DATEADD(DAY, 1, x.D0) ELSE x.D0 END AS D) fd
WHERE b.RF1 % 100 < 25
  AND fd.D <= '2025-12-27';

DECLARE @SlotCount INT = (SELECT COUNT(*) FROM #Slots);
RAISERROR(N'   звернень: %d', 0, 1, @SlotCount) WITH NOWAIT;
GO

/* =====================================================================
   4. Історії хвороб: лікар, тяжкість, тривалість, кількість візитів, результат
   ===================================================================== */
RAISERROR(N'4. Історії хвороб...', 0, 1) WITH NOWAIT;

DECLARE @Therapist INT = (SELECT SpecialtyID FROM dbo.Specialties WHERE Name = N'Терапевт'),
        @Family    INT = (SELECT SpecialtyID FROM dbo.Specialties WHERE Name = N'Сімейний лікар'),
        @Pediatr   INT = (SELECT SpecialtyID FROM dbo.Specialties WHERE Name = N'Педіатр');

DROP TABLE IF EXISTS #R0;
SELECT ROW_NUMBER() OVER (ORDER BY s.OpenDate, NEWID()) AS RecordID,
       s.PatientID, s.DiseaseID, s.OpenDate,
       a.Age,
       dp.IsChronic, dp.Severity AS DisSev, dp.AvgTreatmentDays, dp.Tag,
       -- дітей лікує педіатр; дорослих з «дитячими» хворобами — терапевт
       CASE WHEN a.Age < 18 AND dp.SpecialtyID IN (@Therapist, @Family) THEN @Pediatr
            WHEN a.Age >= 18 AND dp.SpecialtyID = @Pediatr THEN @Therapist
            ELSE dp.SpecialtyID END AS SpecialtyID,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 10 AS RSev,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 1000000 / 1000000.0 AS RDays,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 1000000 / 1000000.0 AS RVis,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 1000000 / 1000000.0 AS ROut,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 69 AS RTime
INTO #R0
FROM #Slots s
JOIN dbo.Patients p        ON p.PatientID = s.PatientID
JOIN gen.DiseaseProfile dp ON dp.DiseaseID = s.DiseaseID
CROSS APPLY (SELECT DATEDIFF(YEAR, p.BirthDate, s.OpenDate)
                  - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.BirthDate, s.OpenDate), p.BirthDate) > s.OpenDate THEN 1 ELSE 0 END AS Age) a;

-- Лікуючий лікар: випадковий лікар потрібної спеціальності, що працював на дату звернення
DROP TABLE IF EXISTS #Rec;
SELECT r.*,
       doc.DoctorID AS AttDoctorID, doc.Category AS DocCategory,
       CASE doc.Category WHEN N'Вища' THEN 0.88 WHEN N'Перша' THEN 0.94 WHEN N'Друга' THEN 1.00 ELSE 1.08 END AS CatDays,
       CASE doc.Category WHEN N'Вища' THEN 1.08 WHEN N'Перша' THEN 1.04 WHEN N'Друга' THEN 1.00 ELSE 0.94 END AS CatRecov,
       CAST(NULL AS TINYINT) AS Severity, CAST(NULL AS INT) AS ActualDays, CAST(NULL AS INT) AS NVisits,
       CAST(NULL AS DATE) AS CloseDate, CAST(NULL AS NVARCHAR(10)) AS Status, CAST(NULL AS NVARCHAR(30)) AS Outcome,
       DATEADD(MINUTE, 480 + r.RTime * 10, CAST(r.OpenDate AS DATETIME2(0))) AS OpenDateTime
INTO #Rec
FROM #R0 r
CROSS APPLY (SELECT TOP (1) d.DoctorID, d.Category
             FROM dbo.Doctors d
             WHERE d.SpecialtyID = r.SpecialtyID
               AND d.HireDate <= r.OpenDate
               AND (d.DismissalDate IS NULL OR d.DismissalDate >= r.OpenDate)
             ORDER BY CHECKSUM(NEWID(), r.RecordID)) doc;

CREATE UNIQUE CLUSTERED INDEX CIX_Rec ON #Rec (RecordID);

-- Тяжкість у конкретного пацієнта: тяжкість хвороби ±1
UPDATE #Rec SET Severity = CASE WHEN RSev <= 1 THEN IIF(DisSev > 1, DisSev - 1, 1)
                                WHEN RSev >= 8 THEN IIF(DisSev < 5, DisSev + 1, 5)
                                ELSE DisSev END;

-- Тривалість лікування: норматив × випадковий коефіцієнт × тяжкість × категорія лікаря
UPDATE #Rec SET ActualDays =
    CASE WHEN Tag IN ('CHECKUP', 'VACCINE') THEN 0
         ELSE GREATEST(1, CEILING(AvgTreatmentDays * (0.5 + RDays) * (1 + (CAST(Severity AS INT) - DisSev) * 0.25) * CatDays)) END;

-- Кількість візитів: 1–5, залежно від тривалості та тяжкості; не більше ніж днів лікування
UPDATE #Rec SET NVisits =
    CASE WHEN Tag IN ('CHECKUP', 'VACCINE') THEN 1
         ELSE LEAST(ActualDays + 1,
                    1 + FLOOR(RVis * LEAST(4.0, 1 + ActualDays / 8.0)) + IIF(Severity >= 4, 1, 0)) END;

-- Дата закриття (неділя → понеділок); історії, що не завершились до кінця 2025 р., залишаються відкритими
UPDATE #Rec SET CloseDate = x.D,
                Status = IIF(x.D > '2025-12-31', N'Відкрита', N'Закрита')
FROM #Rec
CROSS APPLY (SELECT DATEADD(DAY, ActualDays, OpenDate) AS D0) d0
CROSS APPLY (SELECT IIF(DATEDIFF(DAY, '19000101', d0.D0) % 7 = 6, DATEADD(DAY, 1, d0.D0), d0.D0) AS D) x;

-- Результат лікування
UPDATE r SET Outcome =
    CASE WHEN r.Status = N'Відкрита' THEN NULL
         WHEN r.Tag IN ('CHECKUP', 'VACCINE') THEN N'Без змін'
         WHEN r.IsChronic = 0 THEN
              CASE WHEN r.ROut < t.A1 THEN N'Одужання'
                   WHEN r.ROut < t.A1 + 0.02 THEN N'Перехід у хронічну форму'
                   WHEN r.ROut < t.A1 + 0.06 THEN N'Без змін'
                   WHEN r.ROut < t.A1 + 0.08 THEN N'Погіршення'
                   WHEN r.ROut < t.A1 + 0.08 + IIF(r.Severity >= 4, 0.07, 0.01) THEN N'Госпіталізація'
                   ELSE N'Покращення' END
         ELSE
              CASE WHEN r.ROut < t.C1 THEN N'Одужання'
                   WHEN r.ROut < t.C2 THEN N'Без змін'
                   WHEN r.ROut < t.C3 THEN N'Погіршення'
                   WHEN r.ROut < t.C3 + IIF(r.Severity >= 4, 0.08, 0.03) THEN N'Госпіталізація'
                   ELSE N'Покращення' END
    END
FROM #Rec r
CROSS APPLY (SELECT GREATEST(0.2, 0.72 * r.CatRecov - (CAST(r.Severity AS INT) - 2) * 0.06 - IIF(r.Age >= 65, 0.08, 0)) AS A1,
                    0.05 * r.CatRecov AS C1,
                    0.05 * r.CatRecov + 0.25 * (2 - r.CatRecov) AS C2,
                    0.05 * r.CatRecov + 0.25 * (2 - r.CatRecov) + 0.08 + IIF(r.Age >= 65, 0.03, 0) AS C3) t;

UPDATE #Rec SET CloseDate = NULL WHERE Status = N'Відкрита';

CREATE INDEX IX_Rec_Patient ON #Rec (PatientID, OpenDate) INCLUDE (DiseaseID, IsChronic);
GO

/* =====================================================================
   5. Візити
   ===================================================================== */
RAISERROR(N'5. Візити...', 0, 1) WITH NOWAIT;

DROP TABLE IF EXISTS #V0;
SELECT r.RecordID, k.N AS K, r.NVisits, r.SpecialtyID, r.AttDoctorID, r.Age, r.Severity,
       IIF(k.N = 1, r.OpenDateTime,
           DATEADD(MINUTE, 480 + ((CHECKSUM(NEWID()) & 0x7FFFFFFF) % 69) * 10, CAST(vd.D AS DATETIME2(0)))) AS VisitDateTime,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RType,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RStatus,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS RDur
INTO #V0
FROM #Rec r
JOIN gen.Numbers k ON k.N <= r.NVisits
CROSS APPLY (SELECT DATEADD(DAY, IIF(r.NVisits = 1, 0, ROUND(r.ActualDays * (k.N - 1) / (r.NVisits - 1.0), 0)), r.OpenDate) AS D0) d0
-- візит на неділю переноситься на суботу (дата не виходить за межі історії)
CROSS APPLY (SELECT IIF(DATEDIFF(DAY, '19000101', d0.D0) % 7 = 6, DATEADD(DAY, -1, d0.D0), d0.D0) AS D) vd
WHERE vd.D <= '2025-12-31';

ALTER TABLE #V0 ADD VisitType NVARCHAR(20), Status NVARCHAR(15), DoctorID INT;

UPDATE #V0 SET
    VisitType = CASE WHEN K = 1 THEN N'Первинний'
                     WHEN RType < 8 THEN N'Консультація'
                     WHEN Age >= 75 AND Severity >= 3 AND RType < 38 THEN N'Виклик додому'
                     ELSE N'Повторний' END,
    Status    = CASE WHEN K = 1 THEN N'Відбувся'
                     WHEN RStatus < 5 THEN N'Неявка'
                     WHEN RStatus < 8 THEN N'Скасовано'
                     ELSE N'Відбувся' END,
    DoctorID  = AttDoctorID;

-- Консультація — у лікаря іншої спеціальності
UPDATE v SET DoctorID = c.DoctorID
FROM #V0 v
CROSS APPLY (SELECT TOP (1) d.DoctorID FROM dbo.Doctors d
             WHERE d.SpecialtyID <> v.SpecialtyID
               AND d.HireDate <= CAST(v.VisitDateTime AS DATE)
               AND (d.DismissalDate IS NULL OR d.DismissalDate >= CAST(v.VisitDateTime AS DATE))
             ORDER BY CHECKSUM(NEWID(), v.RecordID, v.K)) c
WHERE v.VisitType = N'Консультація';

-- Якщо лікуючий лікар звільнився під час лікування — візит до колеги тієї ж спеціальності
UPDATE v SET DoctorID = c.DoctorID
FROM #V0 v
JOIN dbo.Doctors cur ON cur.DoctorID = v.DoctorID
CROSS APPLY (SELECT TOP (1) d.DoctorID FROM dbo.Doctors d
             WHERE d.SpecialtyID = cur.SpecialtyID
               AND d.HireDate <= CAST(v.VisitDateTime AS DATE)
               AND (d.DismissalDate IS NULL OR d.DismissalDate >= CAST(v.VisitDateTime AS DATE))
             ORDER BY CHECKSUM(NEWID(), v.RecordID, v.K)) c
WHERE CAST(v.VisitDateTime AS DATE) > cur.DismissalDate;

-- Скарги при первинному зверненні
DROP TABLE IF EXISTS #Complaints;
SELECT ROW_NUMBER() OVER (PARTITION BY Chapter ORDER BY Txt) AS Idx, COUNT(*) OVER (PARTITION BY Chapter) AS Cnt, *
INTO #Complaints
FROM (VALUES
 ('J00-J99', N'Кашель, нежить, підвищення температури'), ('J00-J99', N'Біль у горлі, слабкість'), ('J00-J99', N'Задишка, кашель з харкотинням'),
 ('I00-I99', N'Підвищення артеріального тиску, головний біль'), ('I00-I99', N'Біль за грудиною при навантаженні'), ('I00-I99', N'Серцебиття, задишка'),
 ('E00-E90', N'Спрага, сухість у роті, втомлюваність'), ('E00-E90', N'Зміна маси тіла, слабкість'),
 ('K00-K93', N'Біль в епігастрії, печія'), ('K00-K93', N'Нудота, здуття живота'), ('K00-K93', N'Біль у правому підребер''ї'),
 ('A00-B99', N'Діарея, підвищення температури'), ('A00-B99', N'Висип, гарячка'), ('A00-B99', N'Ураження нігтів'),
 ('U00-U85', N'Гарячка, кашель, втрата нюху'), ('U00-U85', N'Задишка, слабкість, температура'),
 ('G00-G99', N'Головний біль, запаморочення'), ('G00-G99', N'Оніміння пальців рук'), ('G00-G99', N'Безсоння'),
 ('M00-M99', N'Біль у спині, обмеження рухів'), ('M00-M99', N'Біль і набряк суглобів'), ('M00-M99', N'Біль у шиї'),
 ('S00-T98', N'Травма, біль, набряк'), ('S00-T98', N'Алергічна реакція'),
 ('L00-L99', N'Висип, свербіж шкіри'), ('L00-L99', N'Висипання на обличчі'),
 ('H00-H59', N'Почервоніння очей, сльозотеча'), ('H00-H59', N'Погіршення зору'),
 ('H60-H95', N'Біль у вусі, зниження слуху'), ('H60-H95', N'Закладеність вуха'),
 ('N00-N99', N'Часте болюче сечовипускання'), ('N00-N99', N'Біль у попереку'), ('N00-N99', N'Порушення менструального циклу'),
 ('D50-D89', N'Слабкість, блідість, запаморочення'),
 ('Z00-Z99', N'Профілактичний огляд'), ('Z00-Z99', N'Планова вакцинація')
) v(Chapter, Txt);

DROP TABLE IF EXISTS #V;
SELECT ROW_NUMBER() OVER (ORDER BY v.VisitDateTime, v.RecordID, v.K) AS VisitID,
       v.RecordID, v.K, v.DoctorID, v.VisitDateTime, v.VisitType, v.Status,
       CAST(CASE v.VisitType WHEN N'Первинний'     THEN 15 + v.RDur % 4 * 5
                             WHEN N'Повторний'     THEN 10 + v.RDur % 3 * 5
                             WHEN N'Консультація'  THEN 20 + v.RDur % 5 * 5
                             ELSE                       30 + v.RDur % 7 * 5 END AS SMALLINT) AS DurationMin,
       CAST(IIF(v.Status = N'Відбувся',
                ROUND(s.BaseVisitPrice
                      * CASE d.Category WHEN N'Вища' THEN 1.30 WHEN N'Перша' THEN 1.15 WHEN N'Друга' THEN 1.05 ELSE 1.00 END
                      * inf.K
                      * IIF(v.VisitType = N'Виклик додому', 1.5, 1.0), 0), 0) AS DECIMAL(10,2)) AS Cost,
       CASE WHEN v.K = 1 THEN cp.Txt END AS Complaints
INTO #V
FROM #V0 v
JOIN dbo.Doctors d       ON d.DoctorID = v.DoctorID
JOIN dbo.Specialties s   ON s.SpecialtyID = d.SpecialtyID
JOIN gen.Inflation inf   ON inf.Yr = YEAR(v.VisitDateTime)
JOIN #Rec r              ON r.RecordID = v.RecordID
JOIN dbo.Diseases ds     ON ds.DiseaseID = r.DiseaseID
JOIN dbo.DiseaseCategories dc ON dc.CategoryID = ds.CategoryID
OUTER APPLY (SELECT TOP (1) c.Txt FROM #Complaints c
             WHERE c.Chapter = dc.ICDChapter AND c.Idx = 1 + v.RDur % c.Cnt) cp;

CREATE UNIQUE CLUSTERED INDEX CIX_V ON #V (VisitID);
CREATE INDEX IX_V_Record ON #V (RecordID, K);
GO

/* =====================================================================
   6. Діагнози: основний + супутні (хронічні хвороби з попередніх історій)
      + ускладнення
   ===================================================================== */
RAISERROR(N'6. Діагнози...', 0, 1) WITH NOWAIT;

DROP TABLE IF EXISTS #Dg;
CREATE TABLE #Dg (RecordID INT, DiseaseID INT, DoctorID INT, DiagnosisDate DATE, DiagnosisType NVARCHAR(15), Severity TINYINT);

INSERT #Dg
SELECT RecordID, DiseaseID, AttDoctorID, OpenDate, N'Основний', Severity FROM #Rec;

-- Супутні: раніше діагностовані хронічні хвороби пацієнта (до 2 на історію, з імовірністю 50%)
INSERT #Dg
SELECT x.RecordID, x.DiseaseID, x.AttDoctorID, x.OpenDate, N'Супутній', x.DisSev
FROM (
    SELECT p.RecordID, p.DiseaseID, p.AttDoctorID, p.OpenDate, p.DisSev,
           ROW_NUMBER() OVER (PARTITION BY p.RecordID ORDER BY p.R) AS Rn
    FROM (
        SELECT DISTINCT r.RecordID, e.DiseaseID, r.AttDoctorID, r.OpenDate, dp.Severity AS DisSev,
               (CHECKSUM(r.RecordID, e.DiseaseID, 17) & 0x7FFFFFFF) % 1000 AS R
        FROM #Rec r
        JOIN #Rec e ON e.PatientID = r.PatientID AND e.OpenDate < r.OpenDate
                   AND e.IsChronic = 1 AND e.DiseaseID <> r.DiseaseID
        JOIN gen.DiseaseProfile dp ON dp.DiseaseID = e.DiseaseID
        WHERE r.Tag NOT IN ('CHECKUP', 'VACCINE')
    ) p
    WHERE p.R < 500
) x
WHERE x.Rn <= 2;

-- Ускладнення: встановлюються на другому візиті
INSERT #Dg
SELECT r.RecordID, c.ToDiseaseID, v.DoctorID, CAST(v.VisitDateTime AS DATE), N'Ускладнення',
       IIF(r.Severity < 5, r.Severity + 1, 5)
FROM #Rec r
JOIN gen.Complications c ON c.FromDiseaseID = r.DiseaseID
JOIN #V v ON v.RecordID = r.RecordID AND v.K = 2
-- RecordID у CHECKSUM не дає оптимізатору обчислити NEWID() один раз на правило (до з'єднання)
WHERE (CHECKSUM(NEWID(), r.RecordID) & 0x7FFFFFFF) % 10000 < c.Prob * 10000
  AND NOT EXISTS (SELECT 1 FROM #Dg d WHERE d.RecordID = r.RecordID AND d.DiseaseID = c.ToDiseaseID);
DECLARE @Compl INT = @@ROWCOUNT, @ComplRules INT = (SELECT COUNT(*) FROM gen.Complications);
RAISERROR(N'   ускладнень: %d (правил: %d)', 0, 1, @Compl, @ComplRules) WITH NOWAIT;

-- Унікальність (історія, хвороба)
WITH Dup AS (SELECT ROW_NUMBER() OVER (PARTITION BY RecordID, DiseaseID
                                       ORDER BY CASE DiagnosisType WHEN N'Основний' THEN 0 ELSE 1 END) AS Rn FROM #Dg)
DELETE FROM Dup WHERE Rn > 1;

CREATE CLUSTERED INDEX CIX_Dg ON #Dg (RecordID, DiseaseID);
GO

/* =====================================================================
   7. Призначення ліків
   ===================================================================== */
RAISERROR(N'7. Призначення...', 0, 1) WITH NOWAIT;

-- Кількість препаратів на візиті
DROP TABLE IF EXISTS #PV;
SELECT v.VisitID, v.RecordID, v.VisitDateTime, r.Tag, r.IsChronic, r.AvgTreatmentDays,
       CASE WHEN r.Tag = 'VACCINE' THEN 1
            WHEN r.Tag = 'CHECKUP' THEN IIF(x.R % 100 < 25, 1, 0)
            WHEN v.VisitType = N'Первинний' THEN CASE WHEN x.R % 10 = 0 THEN 0 WHEN x.R % 10 <= 4 THEN 1 WHEN x.R % 10 <= 7 THEN 2 ELSE 3 END
            WHEN v.VisitType = N'Виклик додому' THEN 1 + x.R % 2
            WHEN v.VisitType = N'Консультація' THEN IIF(x.R % 100 < 40, 1, 0)
            ELSE IIF(x.R % 100 < 35, 1, 0) END AS MedCount
INTO #PV
FROM #V v
JOIN #Rec r ON r.RecordID = v.RecordID
CROSS APPLY (SELECT (CHECKSUM(NEWID(), v.VisitID) & 0x7FFFFFFF) AS R) x
WHERE v.Status = N'Відбувся';

DELETE FROM #PV WHERE MedCount = 0;

-- Вибір препаратів за групою хвороби, без абсолютних протипоказань до діагнозів цієї історії
DROP TABLE IF EXISTS #Pr;
SELECT c.VisitID, c.MedicationID, c.VisitDateTime, c.IsChronic, c.AvgTreatmentDays, c.Tag
INTO #Pr
FROM (
    SELECT pv.VisitID, pv.VisitDateTime, pv.IsChronic, pv.AvgTreatmentDays, pv.Tag, pv.MedCount, mt.MedicationID,
           ROW_NUMBER() OVER (PARTITION BY pv.VisitID ORDER BY CHECKSUM(NEWID(), pv.VisitID, mt.MedicationID)) AS Rn
    FROM #PV pv
    JOIN gen.MedTag mt ON mt.Tag = pv.Tag
    WHERE NOT EXISTS (SELECT 1
                      FROM #Dg dg
                      JOIN dbo.Contraindications ci ON ci.DiseaseID = dg.DiseaseID AND ci.MedicationID = mt.MedicationID
                      WHERE dg.RecordID = pv.RecordID AND ci.ContraindicationType = N'Абсолютне')
) c
WHERE c.Rn <= c.MedCount;

DROP TABLE IF EXISTS #P2;
SELECT ROW_NUMBER() OVER (ORDER BY p.VisitID, p.MedicationID) AS PrescriptionID,
       p.VisitID, p.MedicationID, mi.Dosage, mi.TimesPerDay, dur.Days AS DurationDays,
       CAST(CASE WHEN mi.PackSize <= 1 THEN IIF(dur.Days > 20, 2, 1)
                 ELSE LEAST(12, GREATEST(1, CEILING(1.0 * mi.TimesPerDay * dur.Days / mi.PackSize))) END AS SMALLINT) AS Quantity,
       CAST(ROUND(m.UnitPrice * inf.K, 2) AS DECIMAL(10,2)) AS UnitPrice
INTO #P2
FROM #Pr p
JOIN gen.MedInfo mi     ON mi.MedicationID = p.MedicationID
JOIN dbo.Medications m  ON m.MedicationID = p.MedicationID
JOIN gen.Inflation inf  ON inf.Yr = YEAR(p.VisitDateTime)
CROSS APPLY (SELECT (CHECKSUM(NEWID(), p.VisitID, p.MedicationID) & 0x7FFFFFFF) AS R) x
CROSS APPLY (SELECT CAST(CASE WHEN p.Tag = 'VACCINE' THEN 1
                              WHEN p.IsChronic = 1 THEN CHOOSE(1 + x.R % 3, 30, 30, 60)
                              ELSE LEAST(14, GREATEST(3, p.AvgTreatmentDays - 2 + x.R % 5)) END AS SMALLINT) AS Days) dur;
GO

/* =====================================================================
   8. Завантаження в таблиці БД
   ===================================================================== */
RAISERROR(N'8. Завантаження в БД...', 0, 1) WITH NOWAIT;

SET IDENTITY_INSERT dbo.MedicalRecords ON;
INSERT dbo.MedicalRecords (RecordID, PatientID, AttendingDoctorID, OpenDate, CloseDate, Status, Outcome, Notes, CreatedAt, ModifiedAt)
SELECT RecordID, PatientID, AttDoctorID, OpenDate, CloseDate, Status, Outcome, NULL,
       OpenDateTime,
       IIF(CloseDate IS NULL, OpenDateTime, DATEADD(HOUR, 18, CAST(CloseDate AS DATETIME2(0))))
FROM #Rec ORDER BY RecordID;
SET IDENTITY_INSERT dbo.MedicalRecords OFF;
RAISERROR(N'   MedicalRecords: OK', 0, 1) WITH NOWAIT;

INSERT dbo.Diagnoses (RecordID, DiseaseID, DoctorID, DiagnosisDate, DiagnosisType, Severity)
SELECT RecordID, DiseaseID, DoctorID, DiagnosisDate, DiagnosisType, Severity
FROM #Dg ORDER BY DiagnosisDate, RecordID, CASE DiagnosisType WHEN N'Основний' THEN 0 ELSE 1 END;
RAISERROR(N'   Diagnoses: OK', 0, 1) WITH NOWAIT;

SET IDENTITY_INSERT dbo.Visits ON;
INSERT dbo.Visits (VisitID, RecordID, DoctorID, VisitDateTime, VisitType, Status, DurationMin, Cost, Complaints)
SELECT VisitID, RecordID, DoctorID, VisitDateTime, VisitType, Status, DurationMin, Cost, Complaints
FROM #V ORDER BY VisitID;
SET IDENTITY_INSERT dbo.Visits OFF;
RAISERROR(N'   Visits: OK', 0, 1) WITH NOWAIT;

SET IDENTITY_INSERT dbo.Prescriptions ON;
INSERT dbo.Prescriptions (PrescriptionID, VisitID, MedicationID, Dosage, TimesPerDay, DurationDays, Quantity, UnitPrice)
SELECT PrescriptionID, VisitID, MedicationID, Dosage, TimesPerDay, DurationDays, Quantity, UnitPrice
FROM #P2 ORDER BY PrescriptionID;
SET IDENTITY_INSERT dbo.Prescriptions OFF;
RAISERROR(N'   Prescriptions: OK', 0, 1) WITH NOWAIT;
GO

SELECT 'MedicalRecords' AS TableName, COUNT_BIG(*) AS Cnt FROM dbo.MedicalRecords UNION ALL
SELECT 'Diagnoses', COUNT_BIG(*) FROM dbo.Diagnoses UNION ALL
SELECT 'Visits', COUNT_BIG(*) FROM dbo.Visits UNION ALL
SELECT 'Prescriptions', COUNT_BIG(*) FROM dbo.Prescriptions;
GO
