/* =====================================================================
   Курсова робота NVBD, варіант 6 «Поліклініка»
   Генерація даних. Скрипт 2. Лікарі та пацієнти.
     - ~100 лікарів (75 штатних позицій + ротація кадрів 2016–2025)
     - 55 000 пацієнтів: реалістичні українські ПІБ, вікова структура,
       прикріплення до поліклініки 2008–2025, ~60% зі Львова
   ===================================================================== */
USE PolyclinicDB;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ---------- Транслітерація (для e-mail) ---------- */
CREATE OR ALTER FUNCTION gen.fn_Translit (@s NVARCHAR(100))
RETURNS VARCHAR(100)
AS
BEGIN
    SET @s = LOWER(@s);
    SET @s = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@s,
             N'щ', N'shch'), N'ж', N'zh'), N'х', N'kh'), N'ц', N'ts'), N'ч', N'ch'), N'ш', N'sh'),
             N'ю', N'iu'), N'я', N'ia'), N'є', N'ie'), N'ї', N'i'), N'ь', N''), N'''', N''), N' ', N'');
    SET @s = TRANSLATE(@s, N'абвгґдезиійклмнопрстуф', N'abvhgdezyiiklmnoprstuf');
    RETURN CAST(@s AS VARCHAR(100));
END
GO

/* ---------- Словники імен ---------- */
DROP TABLE IF EXISTS gen.Surnames, gen.MaleNames, gen.FemaleNames, gen.Streets;
CREATE TABLE gen.Surnames    (ID INT IDENTITY PRIMARY KEY, Name NVARCHAR(50));
CREATE TABLE gen.MaleNames   (ID INT IDENTITY PRIMARY KEY, Name NVARCHAR(50), PatrM NVARCHAR(50), PatrF NVARCHAR(50));
CREATE TABLE gen.FemaleNames (ID INT IDENTITY PRIMARY KEY, Name NVARCHAR(50));
CREATE TABLE gen.Streets     (ID INT IDENTITY PRIMARY KEY, Name NVARCHAR(100));

INSERT gen.Surnames (Name) SELECT value FROM STRING_SPLIT(
 N'Шевченко,Коваленко,Бондаренко,Ткаченко,Кравченко,Олійник,Шевчук,Поліщук,Бойко,Ткачук,Мельник,Кравчук,Савчук,Марченко,' +
 N'Лисенко,Руденко,Петренко,Павленко,Мороз,Левченко,Гнатюк,Кушнір,Федорів,Іванів,Петрів,Романів,Гнатишин,Мартинюк,Стасюк,' +
 N'Дмитрук,Ковальчук,Сидоренко,Гуменюк,Костюк,Яковенко,Онищенко,Хоменко,Литвиненко,Захарчук,Пасічник,Гончарук,Василишин,' +
 N'Галушка,Дячук,Паньків,Стефанишин,Микитюк,Козак,Вовк,Гаврилюк,Юрчишин,Тимошенко,Демчук,Боднар,Гриценко,Наумович,Сенишин,' +
 N'Процик,Возняк,Баран,Гуцул,Дзюба,Карпенко,Зайченко,Мацюк,Білик,Чорновол,Яремчук,Волошин,Ничипорук,Пилипів,Котик,Савків,' +
 N'Ярема,Гладун,Борисенко,Остапчук,Тарасюк,Мельничук,Фединишин,Рибак,Грицишин,Гордієнко,Приходько,Нестерук,Олексюк,' +
 N'Андрусишин,Лесів,Дорош,Курило,Головко,Степаненко,Максимчук,Жук,Гук,Сорока,Гриньків,Малик,Попович,Кравець,Коваль,Швець,' +
 N'Гнатів,Яцишин,Бабій,Кузик,Луців,Стецько,Чубай,Ференц,Гірняк,Свистун,Семенюк,Климків,Дацюк,Пелех,Кобилянський,' +
 N'Ониськів,Гайдук,Шуст,Філь,Когут,Лозинський,Зварич,Мисак,Петришин,Тичина', ',');
-- прізвища на -ський мають жіночу форму -ська: обробляються при генерації

INSERT gen.MaleNames (Name, PatrM, PatrF) VALUES
 (N'Олександр', N'Олександрович', N'Олександрівна'), (N'Андрій', N'Андрійович', N'Андріївна'),
 (N'Іван', N'Іванович', N'Іванівна'), (N'Микола', N'Миколайович', N'Миколаївна'),
 (N'Сергій', N'Сергійович', N'Сергіївна'), (N'Василь', N'Васильович', N'Василівна'),
 (N'Петро', N'Петрович', N'Петрівна'), (N'Михайло', N'Михайлович', N'Михайлівна'),
 (N'Володимир', N'Володимирович', N'Володимирівна'), (N'Юрій', N'Юрійович', N'Юріївна'),
 (N'Богдан', N'Богданович', N'Богданівна'), (N'Тарас', N'Тарасович', N'Тарасівна'),
 (N'Роман', N'Романович', N'Романівна'), (N'Ігор', N'Ігорович', N'Ігорівна'),
 (N'Олег', N'Олегович', N'Олегівна'), (N'Дмитро', N'Дмитрович', N'Дмитрівна'),
 (N'Степан', N'Степанович', N'Степанівна'), (N'Ярослав', N'Ярославович', N'Ярославівна'),
 (N'Віктор', N'Вікторович', N'Вікторівна'), (N'Анатолій', N'Анатолійович', N'Анатоліївна'),
 (N'Григорій', N'Григорович', N'Григорівна'), (N'Орест', N'Орестович', N'Орестівна'),
 (N'Остап', N'Остапович', N'Остапівна'), (N'Максим', N'Максимович', N'Максимівна'),
 (N'Назар', N'Назарович', N'Назарівна'), (N'Денис', N'Денисович', N'Денисівна'),
 (N'Артем', N'Артемович', N'Артемівна'), (N'Євген', N'Євгенович', N'Євгенівна'),
 (N'Віталій', N'Віталійович', N'Віталіївна'), (N'Руслан', N'Русланович', N'Русланівна'),
 (N'Павло', N'Павлович', N'Павлівна'), (N'Леонід', N'Леонідович', N'Леонідівна'),
 (N'Зіновій', N'Зіновійович', N'Зіновіївна'), (N'Мирослав', N'Мирославович', N'Мирославівна'),
 (N'Костянтин', N'Костянтинович', N'Костянтинівна'), (N'Олексій', N'Олексійович', N'Олексіївна'),
 (N'Валерій', N'Валерійович', N'Валеріївна'), (N'Любомир', N'Любомирович', N'Любомирівна'),
 (N'Святослав', N'Святославович', N'Святославівна'), (N'Матвій', N'Матвійович', N'Матвіївна'),
 (N'Марко', N'Маркович', N'Марківна'), (N'Данило', N'Данилович', N'Данилівна');

INSERT gen.FemaleNames (Name) SELECT value FROM STRING_SPLIT(
 N'Олена,Наталія,Ірина,Оксана,Тетяна,Марія,Ольга,Світлана,Юлія,Галина,Людмила,Надія,Анна,Катерина,Христина,Софія,' +
 N'Соломія,Ярослава,Мирослава,Іванна,Анастасія,Вікторія,Дарина,Уляна,Лілія,Леся,Зоряна,Роксолана,Богдана,Віра,Любов,' +
 N'Ганна,Марта,Тамара,Валентина,Ніна,Лариса,Алла,Інна,Діана,Аліна,Маргарита,Євгенія,Злата,Олеся,Стефанія,Емілія,Василина', ',');

INSERT gen.Streets (Name) SELECT value FROM STRING_SPLIT(
 N'вул. Городоцька,вул. Личаківська,вул. Зелена,вул. Стрийська,вул. Наукова,просп. Шевченка,вул. Івана Франка,' +
 N'вул. Степана Бандери,вул. Сихівська,вул. Тарнавського,вул. Хоткевича,вул. Кульпарківська,вул. Володимира Великого,' +
 N'вул. Княгині Ольги,вул. Пасічна,вул. Миколайчука,вул. Антоновича,вул. Січових Стрільців,вул. Дорошенка,' +
 N'вул. Залізнична,вул. Виговського,вул. Варшавська,вул. Замарстинівська,вул. Липинського,вул. Шептицьких,' +
 N'вул. Пекарська,вул. Коновальця,вул. Мазепи,просп. Червоної Калини,вул. Довженка,вул. Трускавецька,вул. Шухевича', ',');
GO

/* ===================== ЛІКАРІ ===================== */
DECLARE @SurCnt INT = (SELECT COUNT(*) FROM gen.Surnames),
        @MCnt   INT = (SELECT COUNT(*) FROM gen.MaleNames),
        @FCnt   INT = (SELECT COUNT(*) FROM gen.FemaleNames);

-- Штатні позиції
DROP TABLE IF EXISTS #Pos;
SELECT ROW_NUMBER() OVER (ORDER BY s.SpecialtyID, n.N) AS PosID, s.SpecialtyID, d.DepartmentID
INTO #Pos
FROM gen.SpecialtyPlan sp
JOIN gen.Numbers n      ON n.N <= sp.Positions
JOIN dbo.Specialties s  ON s.Name = sp.SpecialtyName
JOIN dbo.Departments d  ON d.Name = sp.DepartmentName;

-- Перший лікар на позиції (прийнятий до 2016 р.); ~35% звільняються у 2016–2025
DROP TABLE IF EXISTS #DocA;
SELECT PosID, SpecialtyID, DepartmentID,
       DATEADD(DAY, (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 7670, '1995-01-01') AS HireDate,
       CASE WHEN (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 < 35
            THEN DATEADD(DAY, (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 3315, '2016-06-01') END AS DismissalDate
INTO #DocA
FROM #Pos;

-- Склад лікарів: перший на позиції + його наступник (з наступного дня після звільнення)
DROP TABLE IF EXISTS #Doc;
SELECT IDENTITY(INT, 1, 1) AS Seq, x.*,
       CASE WHEN (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 < 65 THEN 'F' ELSE 'M' END AS Gender,
       1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % @SurCnt AS SurID,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS R1,
       1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % @MCnt   AS FatherID,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS R2,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS R3,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS R4
INTO #Doc
FROM (
    SELECT SpecialtyID, DepartmentID, HireDate, DismissalDate, 1 AS IsFirst FROM #DocA
    UNION ALL
    SELECT SpecialtyID, DepartmentID, DATEADD(DAY, 1, DismissalDate), NULL, 0 FROM #DocA WHERE DismissalDate IS NOT NULL
) x;

INSERT dbo.Doctors (LastName, FirstName, MiddleName, Gender, BirthDate, SpecialtyID, DepartmentID, Category,
                    HireDate, DismissalDate, Phone, Email, CreatedAt, ModifiedAt)
SELECT CASE WHEN d.Gender = 'F' AND s.Name LIKE N'%ський' THEN LEFT(s.Name, LEN(s.Name) - 2) + N'ка' ELSE s.Name END,
       CASE WHEN d.Gender = 'F' THEN fn.Name ELSE mn.Name END,
       CASE WHEN d.Gender = 'F' THEN fa.PatrF ELSE fa.PatrM END,
       d.Gender,
       -- вік при прийнятті: 24–44 роки
       DATEADD(DAY, -(8766 + d.R2 % 7305), d.HireDate),
       d.SpecialtyID, d.DepartmentID,
       CASE WHEN exp.Years >= 20 THEN N'Вища'
            WHEN exp.Years >= 12 THEN N'Перша'
            WHEN exp.Years >= 6  THEN N'Друга'
            ELSE N'Без категорії' END,
       d.HireDate, d.DismissalDate,
       '+380' + op.Code + RIGHT('0000000' + CAST(d.R3 % 10000000 AS VARCHAR(7)), 7),
       NULL,
       DATEADD(HOUR, 9, CAST(d.HireDate AS DATETIME2(0))),
       DATEADD(HOUR, 9, CAST(ISNULL(d.DismissalDate, d.HireDate) AS DATETIME2(0)))
FROM #Doc d
JOIN gen.Surnames s     ON s.ID = d.SurID
JOIN gen.MaleNames fa   ON fa.ID = d.FatherID
JOIN gen.MaleNames mn   ON mn.ID = 1 + d.R1 % @MCnt
JOIN gen.FemaleNames fn ON fn.ID = 1 + d.R1 % @FCnt
CROSS APPLY (SELECT DATEDIFF(YEAR, d.HireDate, ISNULL(d.DismissalDate, '2025-12-31')) + d.R4 % 5 - 2 AS Years) exp
CROSS APPLY (SELECT CHOOSE(1 + d.R4 % 12, '67','68','96','97','98','50','66','95','99','63','73','93') AS Code) op
ORDER BY d.HireDate;

-- Службова пошта лікаря: прізвище.ім'я.ID@polyclinic.lviv.ua
-- (тригер аудиту вимкнено: це частина первинного заповнення, а не зміна даних)
DISABLE TRIGGER dbo.trg_Doctors_Audit ON dbo.Doctors;
UPDATE dbo.Doctors
SET Email = gen.fn_Translit(LastName) + '.' + gen.fn_Translit(FirstName) + CAST(DoctorID AS VARCHAR(10)) + '@polyclinic.lviv.ua';
ENABLE TRIGGER dbo.trg_Doctors_Audit ON dbo.Doctors;
GO

/* ===================== ПАЦІЄНТИ ===================== */
DECLARE @PatientCount INT = 55000;
DECLARE @SurCnt INT = (SELECT COUNT(*) FROM gen.Surnames),
        @MCnt   INT = (SELECT COUNT(*) FROM gen.MaleNames),
        @FCnt   INT = (SELECT COUNT(*) FROM gen.FemaleNames),
        @StCnt  INT = (SELECT COUNT(*) FROM gen.Streets);

-- Списки міст для зваженого вибору: Львів 60%, область 30%, інші регіони 10%
DROP TABLE IF EXISTS #CityOblast, #CityOther;
SELECT ROW_NUMBER() OVER (ORDER BY c.CityID) AS Idx, c.CityID INTO #CityOblast
FROM dbo.Cities c JOIN dbo.Regions r ON r.RegionID = c.RegionID
WHERE r.Name = N'Львівська область' AND c.Name <> N'Львів';
SELECT ROW_NUMBER() OVER (ORDER BY c.CityID) AS Idx, c.CityID INTO #CityOther
FROM dbo.Cities c JOIN dbo.Regions r ON r.RegionID = c.RegionID
WHERE r.Name <> N'Львівська область';
DECLARE @LvivID INT = (SELECT CityID FROM dbo.Cities WHERE Name = N'Львів'),
        @OblCnt INT = (SELECT COUNT(*) FROM #CityOblast),
        @OthCnt INT = (SELECT COUNT(*) FROM #CityOther);

-- Випадкові параметри кожного пацієнта (матеріалізуються, щоб NEWID() не перераховувався)
DROP TABLE IF EXISTS #P;
SELECT n.N AS PatientID,
       CASE WHEN (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 < 53 THEN 'F' ELSE 'M' END AS Gender,
       1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % @SurCnt AS SurID,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS RName,
       1 + (CHECKSUM(NEWID()) & 0x7FFFFFFF) % @MCnt   AS FatherID,
       CASE WHEN (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 < 18 THEN 1 ELSE 0 END AS IsChild,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 1000000 / 1000000.0 AS R1,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 1000000 / 1000000.0 AS R2,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 1000000 / 1000000.0 AS R3,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RReg,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RCity,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS RCityIdx,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS RAddr,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) AS RPhone,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RHasPhone,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RHasEmail,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RHasPolicy,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RBlood,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 100 AS RActive,
       (CHECKSUM(NEWID()) & 0x7FFFFFFF) % 600 AS RMinutes
INTO #P
FROM gen.Numbers n
WHERE n.N <= @PatientCount;

-- Дата народження: діти 2005–2025 (рівномірно); дорослі 1930–2005 — суміш рівномірного (60%)
-- і трикутного (40%, пік ~1968) розподілів: поліклініку частіше відвідують старші люди
ALTER TABLE #P ADD BirthDate DATE, RegistrationDate DATE;
UPDATE #P SET BirthDate = CASE WHEN IsChild = 1
                               THEN DATEADD(DAY, CAST(R1 * 7485 AS INT), '2005-01-01')
                               WHEN RName % 10 < 6
                               THEN DATEADD(DAY, CAST(R1 * 27393 AS INT), '1930-01-01')
                               ELSE DATEADD(DAY, CAST((R1 + R2) / 2 * 27393 AS INT), '1930-01-01') END;
-- Прикріплення: новонароджені — у перші 2 місяці життя; решта 75% до 2016 р., 25% у 2016–2025
UPDATE #P SET RegistrationDate =
    CASE WHEN BirthDate >= '2008-01-01' THEN DATEADD(DAY, RReg % 60, BirthDate)
         ELSE GREATEST(BirthDate,
                       CASE WHEN RReg < 75 THEN DATEADD(DAY, CAST(R3 * 2921 AS INT), '2008-01-01')
                            ELSE DATEADD(DAY, CAST(R3 * 3468 AS INT), '2016-01-01') END) END;

SET IDENTITY_INSERT dbo.Patients ON;

INSERT dbo.Patients (PatientID, LastName, FirstName, MiddleName, Gender, BirthDate, CityID, Address, Phone, Email,
                     InsurancePolicy, BloodType, RegistrationDate, IsActive, CreatedAt, ModifiedAt)
SELECT p.PatientID,
       CASE WHEN p.Gender = 'F' AND s.Name LIKE N'%ський' THEN LEFT(s.Name, LEN(s.Name) - 2) + N'ка' ELSE s.Name END,
       CASE WHEN p.Gender = 'F' THEN fn.Name ELSE mn.Name END,
       CASE WHEN p.Gender = 'F' THEN fa.PatrF ELSE fa.PatrM END,
       p.Gender,
       p.BirthDate,
       CASE WHEN p.RCity < 60 THEN @LvivID
            WHEN p.RCity < 90 THEN (SELECT CityID FROM #CityOblast WHERE Idx = 1 + p.RCityIdx % @OblCnt)
            ELSE                   (SELECT CityID FROM #CityOther  WHERE Idx = 1 + p.RCityIdx % @OthCnt) END,
       CONCAT(st.Name, N', ', 1 + p.RAddr % 150,
              CASE WHEN p.RAddr % 100 < 60 THEN CONCAT(N', кв. ', 1 + p.RAddr % 120) END),
       CASE WHEN p.RHasPhone < 92
            THEN '+380' + CHOOSE(1 + p.RPhone % 12, '67','68','96','97','98','50','66','95','99','63','73','93')
                        + RIGHT('0000000' + CAST(p.RPhone % 10000000 AS VARCHAR(7)), 7) END,
       NULL,
       CASE WHEN p.RHasPolicy < 55
            THEN 'UA' + RIGHT('00000000' + CAST(CAST(p.PatientID AS BIGINT) * 7919 % 100000000 AS VARCHAR(8)), 8) END,
       CASE WHEN p.RBlood < 20 THEN NULL
            WHEN p.RBlood < 46 THEN 'O+' WHEN p.RBlood < 73 THEN 'A+' WHEN p.RBlood < 85 THEN 'B+'
            WHEN p.RBlood < 90 THEN 'AB+' WHEN p.RBlood < 94 THEN 'O-' WHEN p.RBlood < 98 THEN 'A-'
            WHEN p.RBlood < 99 THEN 'B-' ELSE 'AB-' END,
       p.RegistrationDate,
       CASE WHEN p.RActive < 97 THEN 1 ELSE 0 END,
       DATEADD(MINUTE, 480 + p.RMinutes, CAST(p.RegistrationDate AS DATETIME2(0))),
       DATEADD(MINUTE, 480 + p.RMinutes, CAST(p.RegistrationDate AS DATETIME2(0)))
FROM #P p
JOIN gen.Surnames s     ON s.ID = p.SurID
JOIN gen.MaleNames fa   ON fa.ID = p.FatherID
JOIN gen.MaleNames mn   ON mn.ID = 1 + p.RName % @MCnt
JOIN gen.FemaleNames fn ON fn.ID = 1 + p.RName % @FCnt
JOIN gen.Streets st     ON st.ID = 1 + p.RAddr % @StCnt;

SET IDENTITY_INSERT dbo.Patients OFF;

-- Особиста пошта є у ~40% дорослих пацієнтів
DISABLE TRIGGER dbo.trg_Patients_Audit ON dbo.Patients;
UPDATE p
SET Email = gen.fn_Translit(p.LastName) + '.' + gen.fn_Translit(p.FirstName) + CAST(p.PatientID AS VARCHAR(10)) + '@'
          + CHOOSE(1 + p.PatientID % 5, 'gmail.com', 'ukr.net', 'i.ua', 'meta.ua', 'outlook.com')
FROM dbo.Patients p
JOIN #P x ON x.PatientID = p.PatientID
WHERE x.RHasEmail < 40 AND dbo.fn_Age(p.BirthDate, '2025-12-31') >= 16;
ENABLE TRIGGER dbo.trg_Patients_Audit ON dbo.Patients;
GO

SELECT 'Doctors' AS TableName, COUNT(*) AS Cnt FROM dbo.Doctors UNION ALL
SELECT 'Doctors (active now)', COUNT(*) FROM dbo.Doctors WHERE DismissalDate IS NULL UNION ALL
SELECT 'Patients', COUNT(*) FROM dbo.Patients;
GO
