import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from rdl import Report, DARK, MID, LIGHT, esc

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "PolyclinicReports")

S, I32, I16, DEC, DT = "System.String", "System.Int32", "System.Int16", "System.Decimal", "System.DateTime"
YEARS_SQL = ("SELECT DISTINCT YearNo, N'[Дата].[Рік].&[' + CAST(YearNo AS nvarchar(4)) + N']' AS YearMdx, "
             "N'[Дата].[Календар].[Рік].&[' + CAST(YearNo AS nvarchar(4)) + N']' AS YearCalMdx "
             "FROM dim.DimDate WHERE YearNo BETWEEN 2016 AND 2025 ORDER BY YearNo DESC")
YEARS_FIELDS = [("YearNo", I16), ("YearMdx", S), ("YearCalMdx", S)]
CLASSES_SQL = ("SELECT DISTINCT ICDChapter, ICDChapter + N' ' + CategoryName AS ClassLabel, "
               "N'[Хвороба].[Клас МКХ-10].&[' + ICDChapter + N']' AS ClassMdx FROM dim.DimDisease WHERE DiseaseKey > 0 ORDER BY ICDChapter")
CLASSES_FIELDS = [("ICDChapter", S), ("ClassLabel", S), ("ClassMdx", S)]


def H(r, text, sort=None, align="Center"):
    return r.tb(text, bold=True, bg=DARK, color="White", align=align, size=8, sort=sort)


def M(name, measure):
    return (name, "Measure", f"[Measures].[{measure}]")


def L(name, level):
    return (name, "Level", level)


def report01():
    r = Report("01_Лікарі_та_пацієнти", "Список лікарів та їх пацієнтів",
               "Табличний звіт: пацієнти кожного лікаря за період з підсумками по лікарях і відділеннях. "
               "Каскадні параметри Відділення → Спеціальність → Лікар, діапазон дат, перемикач «лише хронічні».")
    r.ds_sql("dsDepartments", "PolyclinicDW",
             "SELECT DISTINCT Department FROM dim.DimDoctor WHERE DoctorKey > 0 ORDER BY Department", [("Department", S)])
    r.ds_sql("dsSpecialties", "PolyclinicDW",
             "SELECT DISTINCT Specialty FROM dim.DimDoctor WHERE DoctorKey > 0 AND Department IN (@Department) ORDER BY Specialty",
             [("Specialty", S)], {"@Department": "=Parameters!Department.Value"})
    r.ds_sql("dsDoctors", "PolyclinicDW",
             "SELECT DISTINCT DoctorID, ShortName + N' (' + Specialty + N')' AS DoctorLabel FROM dim.DimDoctor "
             "WHERE DoctorKey > 0 AND IsCurrent = 1 AND Department IN (@Department) AND Specialty IN (@Specialty) ORDER BY DoctorLabel",
             [("DoctorID", I32), ("DoctorLabel", S)],
             {"@Department": "=Parameters!Department.Value", "@Specialty": "=Parameters!Specialty.Value"})
    r.ds_sql("dsMain", "PolyclinicDW", """
SELECT doc.Department, doc.Specialty, doc.DoctorID, doc.ShortName AS Doctor, doc.Category,
       p.PatientID, p.FullName AS Patient, p.GenderName, p.BirthYear, p.City,
       COUNT(*) AS Visits, SUM(f.IsCompleted) AS CompletedVisits, SUM(f.Cost) AS Revenue,
       MIN(d.FullDate) AS FirstVisit, MAX(d.FullDate) AS LastVisit,
       MAX(CASE WHEN dis.IsChronic = 1 THEN 1 ELSE 0 END) AS HasChronic
FROM fact.FactVisit f
JOIN dim.DimDate d      ON d.DateKey = f.DateKey
JOIN dim.DimDoctor doc  ON doc.DoctorKey = f.DoctorKey
JOIN dim.DimPatient p   ON p.PatientKey = f.PatientKey
JOIN dim.DimDisease dis ON dis.DiseaseKey = f.DiseaseKey
WHERE d.FullDate BETWEEN @DateFrom AND @DateTo
  AND doc.DoctorID IN (@Doctor)
GROUP BY doc.Department, doc.Specialty, doc.DoctorID, doc.ShortName, doc.Category,
         p.PatientID, p.FullName, p.GenderName, p.BirthYear, p.City
HAVING @OnlyChronic = 0 OR MAX(CASE WHEN dis.IsChronic = 1 THEN 1 ELSE 0 END) = 1""",
             [("Department", S), ("Specialty", S), ("DoctorID", I32), ("Doctor", S), ("Category", S), ("PatientID", I32),
              ("Patient", S), ("GenderName", S), ("BirthYear", I16), ("City", S), ("Visits", I32), ("CompletedVisits", I32),
              ("Revenue", DEC), ("FirstVisit", DT), ("LastVisit", DT), ("HasChronic", I32)],
             {"@DateFrom": "=Parameters!DateFrom.Value", "@DateTo": "=Parameters!DateTo.Value",
              "@Doctor": "=Parameters!Doctor.Value", "@OnlyChronic": "=Parameters!OnlyChronic.Value"})
    r.param("DateFrom", "Дата з", "DateTime", default="2025-12-01")
    r.param("DateTo", "Дата по", "DateTime", default="2025-12-31")
    r.param("Department", "Відділення", multi=True, values_ds=("dsDepartments", "Department", "Department"),
            default_ds=("dsDepartments", "Department"))
    r.param("Specialty", "Спеціальність", multi=True, values_ds=("dsSpecialties", "Specialty", "Specialty"),
            default_ds=("dsSpecialties", "Specialty"))
    r.param("Doctor", "Лікар", "Integer", multi=True, values_ds=("dsDoctors", "DoctorID", "DoctorLabel"),
            default_ds=("dsDoctors", "DoctorID"))
    r.param("OnlyChronic", "Лише пацієнти з хронічними хворобами", "Boolean", default="false")

    top = r.title_block('="Період: " & Format(Parameters!DateFrom.Value, "dd.MM.yyyy") & " – " & '
                        'Format(Parameters!DateTo.Value, "dd.MM.yyyy") & '
                        'IIF(Parameters!OnlyChronic.Value, " · лише пацієнти з хронічними хворобами", "")')
    r.add(r.tb("Помилка параметрів: дата початку періоду пізніша за дату кінця. Змініть діапазон дат.", bold=True,
               color="#C00000", bg="#FDE9E9", pos=(top, 0, r.body_w, 0.8),
               hidden="=Parameters!DateFrom.Value <= Parameters!DateTo.Value"), top + 0.8)
    top += 1.0

    widths = [6.5, 1.8, 1.6, 3.2, 1.8, 1.9, 2.6, 2.3, 2.3, 1.8]
    hdr = [H(r, "Пацієнт", "=Fields!Patient.Value", "Left"), H(r, "Стать"), H(r, "Рік нар.", "=Fields!BirthYear.Value"),
           H(r, "Місто", "=Fields!City.Value"), H(r, "Візитів", "=Fields!Visits.Value"), H(r, "Відбулися"),
           H(r, "Сума, грн", "=Fields!Revenue.Value"), H(r, "Перший візит", "=Fields!FirstVisit.Value"),
           H(r, "Останній візит", "=Fields!LastVisit.Value"), H(r, "Хронічні")]
    dept_row = [(r.tb("=Fields!Department.Value", bold=True, bg=MID, color=DARK, size=10), 4),
                r.tb("=Sum(Fields!Visits.Value)", bold=True, bg=MID, fmt="#,##0", align="Right"),
                r.tb("=Sum(Fields!CompletedVisits.Value)", bold=True, bg=MID, fmt="#,##0", align="Right"),
                r.tb("=Sum(Fields!Revenue.Value)", bold=True, bg=MID, fmt="#,##0.00", align="Right"),
                (r.tb('="Лікарів: " & CountDistinct(Fields!DoctorID.Value) & " · пацієнтів: " & CountDistinct(Fields!PatientID.Value)',
                      bg=MID, size=8), 3)]
    doc_row = [(r.tb('=Fields!Doctor.Value & " — " & Fields!Specialty.Value & ", категорія: " & Fields!Category.Value',
                     name="tbDoctor", bold=True, bg=LIGHT, toggle=True), 4),
               r.tb("=Sum(Fields!Visits.Value)", bold=True, bg=LIGHT, fmt="#,##0", align="Right"),
               r.tb("=Sum(Fields!CompletedVisits.Value)", bold=True, bg=LIGHT, fmt="#,##0", align="Right"),
               r.tb("=Sum(Fields!Revenue.Value)", bold=True, bg=LIGHT, fmt="#,##0.00", align="Right"),
               (r.tb('="Пацієнтів: " & CountDistinct(Fields!PatientID.Value)', bg=LIGHT, size=8), 3)]
    det = [r.tb("=Fields!Patient.Value", color='=IIF(Fields!HasChronic.Value = 1, "#8B0000", "Black")'),
           r.tb("=Fields!GenderName.Value", align="Center"),
           r.tb("=Fields!BirthYear.Value", align="Center"),
           r.tb("=Fields!City.Value"),
           r.tb("=Fields!Visits.Value", fmt="#,##0", align="Right",
                bold='=IIF(Fields!Visits.Value >= 4, "Bold", "Normal")'),
           r.tb("=Fields!CompletedVisits.Value", fmt="#,##0", align="Right"),
           r.tb("=Fields!Revenue.Value", fmt="#,##0.00", align="Right"),
           r.tb("=Fields!FirstVisit.Value", fmt="dd.MM.yyyy", align="Center"),
           r.tb("=Fields!LastVisit.Value", fmt="dd.MM.yyyy", align="Center"),
           r.tb('=IIF(Fields!HasChronic.Value = 1, "так", "")', align="Center", color="#8B0000")]
    tot = [(r.tb("Разом", bold=True, bg=DARK, color="White"), 4),
           r.tb("=Sum(Fields!Visits.Value)", bold=True, bg=DARK, color="White", fmt="#,##0", align="Right"),
           r.tb("=Sum(Fields!CompletedVisits.Value)", bold=True, bg=DARK, color="White", fmt="#,##0", align="Right"),
           r.tb("=Sum(Fields!Revenue.Value)", bold=True, bg=DARK, color="White", fmt="#,##0.00", align="Right"),
           (r.tb('="Лікарів: " & CountDistinct(Fields!DoctorID.Value) & " · пацієнтів: " & CountDistinct(Fields!PatientID.Value)',
                 bg=DARK, color="White", size=8), 3)]
    x, bottom = r.table("tblDoctorPatients", "dsMain", widths, [hdr],
                        [{"name": "grpDepartment", "expr": "=Fields!Department.Value", "sort": "=Fields!Department.Value",
                          "rows": [dept_row], "docmap": "=Fields!Department.Value", "pagebreak": True},
                         {"name": "grpDoctor", "expr": "=Fields!DoctorID.Value", "sort": "=Fields!Doctor.Value",
                          "rows": [doc_row], "docmap": "=Fields!Doctor.Value"}],
                        [det], [tot], pos=(top, 0), hidden="=Parameters!DateFrom.Value > Parameters!DateTo.Value",
                        detail_sort=[("=Fields!Patient.Value", False)], detail_hidden_by="tbDoctor", detail_expanded=True)
    r.add(x, bottom)
    r.add(r.tb("Темно-червоним виділено пацієнтів з хронічними хворобами; жирним — 4 і більше візити. "
               "Натисніть на лікаря, щоб розгорнути список пацієнтів; заголовки стовпців сортують дані.",
               size=7, italic=True, color="#7F7F7F", border=False, pos=(bottom + 0.2, 0, r.body_w, 0.6)), bottom + 0.8)
    return r


def report02():
    r = Report("02_Історія_хвороби_пацієнта", "Історія хвороби пацієнта",
               "Картка пацієнта та всі історії хвороб з діагнозами, візитами і призначеними ліками (вкладений звіт). "
               "Каскадний пошук: прізвище → пацієнт.", landscape=False)
    r.ds_sql("dsPatients", "PolyclinicDB",
             "SELECT TOP (500) PatientID, LastName + N' ' + FirstName + ISNULL(N' ' + MiddleName, N'') + N' (' + "
             "CONVERT(nvarchar(10), BirthDate, 104) + N')' AS PatientLabel FROM dbo.Patients "
             "WHERE LastName LIKE @LastName + N'%' ORDER BY LastName, FirstName, BirthDate",
             [("PatientID", I32), ("PatientLabel", S)], {"@LastName": "=Parameters!LastName.Value"})
    r.ds_sql("dsPatient", "PolyclinicDB", """
SELECT p.PatientID, p.LastName + N' ' + p.FirstName + ISNULL(N' ' + p.MiddleName, N'') AS FullName, p.BirthDate,
       dbo.fn_Age(p.BirthDate, CAST(GETDATE() AS date)) AS Age,
       CASE p.Gender WHEN 'F' THEN N'жінка' ELSE N'чоловік' END AS Gender,
       c.Name + ISNULL(N', ' + p.Address, N'') AS Address, ISNULL(p.Phone, N'—') AS Phone,
       ISNULL(p.InsurancePolicy, N'немає') AS Policy, ISNULL(p.BloodType, N'невідома') AS BloodType, p.RegistrationDate,
       (SELECT COUNT(*) FROM dbo.MedicalRecords r WHERE r.PatientID = p.PatientID) AS Records,
       (SELECT COUNT(*) FROM dbo.Visits v JOIN dbo.MedicalRecords r ON r.RecordID = v.RecordID WHERE r.PatientID = p.PatientID) AS Visits
FROM dbo.Patients p JOIN dbo.Cities c ON c.CityID = p.CityID
WHERE p.PatientID = @Patient""",
             [("PatientID", I32), ("FullName", S), ("BirthDate", DT), ("Age", I32), ("Gender", S), ("Address", S),
              ("Phone", S), ("Policy", S), ("BloodType", S), ("RegistrationDate", DT), ("Records", I32), ("Visits", I32)],
             {"@Patient": "=Parameters!Patient.Value"})
    r.ds_sql("dsHistory", "PolyclinicDB", """
SELECT r.RecordID, r.OpenDate, r.CloseDate, r.Status, r.Outcome,
       ds.ICDCode + N' ' + ds.Name AS MainDiagnosis,
       STUFF((SELECT N'; ' + d2.ICDCode + N' ' + d2.Name + N' (' + LOWER(x.DiagnosisType) + N')'
              FROM dbo.Diagnoses x JOIN dbo.Diseases d2 ON d2.DiseaseID = x.DiseaseID
              WHERE x.RecordID = r.RecordID AND x.DiagnosisType <> N'Основний'
              FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'') AS OtherDiagnoses,
       ad.LastName + N' ' + LEFT(ad.FirstName, 1) + N'.' AS AttendingDoctor,
       v.VisitID, v.VisitDateTime, v.VisitType, v.Status AS VisitStatus,
       vd.LastName + N' ' + LEFT(vd.FirstName, 1) + N'. (' + sp.Name + N')' AS VisitDoctor,
       v.Cost, v.Complaints, (SELECT COUNT(*) FROM dbo.Prescriptions pr WHERE pr.VisitID = v.VisitID) AS PrescriptionCount
FROM dbo.MedicalRecords r
JOIN dbo.Diagnoses dg  ON dg.RecordID = r.RecordID AND dg.DiagnosisType = N'Основний'
JOIN dbo.Diseases ds   ON ds.DiseaseID = dg.DiseaseID
JOIN dbo.Doctors ad    ON ad.DoctorID = r.AttendingDoctorID
JOIN dbo.Visits v      ON v.RecordID = r.RecordID
JOIN dbo.Doctors vd    ON vd.DoctorID = v.DoctorID
JOIN dbo.Specialties sp ON sp.SpecialtyID = vd.SpecialtyID
WHERE r.PatientID = @Patient""",
             [("RecordID", I32), ("OpenDate", DT), ("CloseDate", DT), ("Status", S), ("Outcome", S), ("MainDiagnosis", S),
              ("OtherDiagnoses", S), ("AttendingDoctor", S), ("VisitID", "System.Int64"), ("VisitDateTime", DT),
              ("VisitType", S), ("VisitStatus", S), ("VisitDoctor", S), ("Cost", DEC), ("Complaints", S),
              ("PrescriptionCount", I32)],
             {"@Patient": "=Parameters!Patient.Value"})
    r.param("LastName", "Прізвище (початок)", default="Шевченко")
    r.param("Patient", "Пацієнт", "Integer", values_ds=("dsPatients", "PatientID", "PatientLabel"),
            default_ds=("dsPatients", "PatientID"))

    top = r.title_block('="Пацієнт: " & First(Fields!FullName.Value, "dsPatient")')
    f = lambda c: f'First(Fields!{c}.Value, "dsPatient")'
    card = [
        r.tb(f'="Дата народження: " & Format({f("BirthDate")}, "dd.MM.yyyy") & " (" & {f("Age")} & " р.) · стать: " & {f("Gender")}'
             f' & " · група крові: " & {f("BloodType")}', border=False, pos=(0.15, 0.2, r.body_w - 0.4, 0.55)),
        r.tb(f'="Адреса: " & {f("Address")} & " · телефон: " & {f("Phone")}', border=False,
             pos=(0.7, 0.2, r.body_w - 0.4, 0.55)),
        r.tb(f'="Страховий поліс: " & {f("Policy")} & " · прикріплений з " & Format({f("RegistrationDate")}, "dd.MM.yyyy")'
             f' & " · історій хвороби: " & {f("Records")} & " · візитів: " & {f("Visits")}', border=False, bold=True,
             pos=(1.25, 0.2, r.body_w - 0.4, 0.55)),
    ]
    r.add(r.rectangle("rectCard", card, (top, 0, r.body_w, 1.95), bg=LIGHT), top + 1.95)
    top += 2.2

    widths = [2.7, 2.1, 1.9, 4.6, 4.1, 1.7, 1.5]
    hdr = [H(r, "Дата і час"), H(r, "Тип візиту"), H(r, "Статус"), H(r, "Лікар"), H(r, "Скарги"), H(r, "Вартість"), H(r, "Ліків")]
    outcome_color = ('=Switch(Fields!Status.Value = "Відкрита", "#1F4E79", Fields!Outcome.Value = "Одужання", "#2E7D32", '
                     'Fields!Outcome.Value = "Покращення", "#558B2F", Fields!Outcome.Value = "Погіршення" Or '
                     'Fields!Outcome.Value = "Госпіталізація", "#C00000", True, "#595959")')
    rec_row1 = [(r.tb('="№ " & Fields!RecordID.Value & " · " & Format(Fields!OpenDate.Value, "dd.MM.yyyy") & " – " & '
                      'IIF(IsNothing(Fields!CloseDate.Value), "триває", Format(Fields!CloseDate.Value, "dd.MM.yyyy"))',
                      name="tbRecord", bold=True, bg=MID, toggle=True), 3),
                (r.tb("=Fields!MainDiagnosis.Value", bold=True, bg=MID), 2),
                (r.tb('=IIF(Fields!Status.Value = "Відкрита", "Відкрита", Fields!Outcome.Value)', bg=MID, bold=True,
                     color=outcome_color, size=8, align="Center"), 2)]
    rec_row2 = [(r.tb('="Лікуючий лікар: " & Fields!AttendingDoctor.Value & IIF(IsNothing(Fields!OtherDiagnoses.Value), "", '
                      '" · інші діагнози: " & Fields!OtherDiagnoses.Value)', italic=True, size=8, bg=LIGHT), 7)]
    visit = [r.tb("=Fields!VisitDateTime.Value", fmt="dd.MM.yyyy HH:mm", align="Center"),
             r.tb("=Fields!VisitType.Value"),
             r.tb("=Fields!VisitStatus.Value", color='=IIF(Fields!VisitStatus.Value = "Відбувся", "Black", "#C00000")'),
             r.tb("=Fields!VisitDoctor.Value"),
             r.tb("=Fields!Complaints.Value", size=8, italic=True),
             r.tb("=Fields!Cost.Value", fmt="#,##0.00", align="Right"),
             r.tb("=Fields!PrescriptionCount.Value", align="Center")]
    sub = [(r.subreport("subPrescriptions", "02a_Призначення_візиту", {"VisitID": "=Fields!VisitID.Value"})
            .replace("<KeepTogether>", '<Visibility><Hidden>=Fields!PrescriptionCount.Value = 0</Hidden></Visibility><KeepTogether>'), 7)]
    tot = [(r.tb('="Усього історій: " & CountDistinct(Fields!RecordID.Value) & " · візитів: " & Count(Fields!VisitID.Value)',
                 bold=True, bg=DARK, color="White"), 5),
           r.tb("=Sum(Fields!Cost.Value)", bold=True, bg=DARK, color="White", fmt="#,##0.00", align="Right"),
           r.tb("=Sum(Fields!PrescriptionCount.Value)", bold=True, bg=DARK, color="White", align="Center")]
    x, bottom = r.table("tblHistory", "dsHistory", widths, [hdr],
                        [{"name": "grpRecord", "expr": "=Fields!RecordID.Value", "sort": ("=Fields!OpenDate.Value", True),
                          "rows": [rec_row1, rec_row2],
                          "docmap": '="№ " & Fields!RecordID.Value & " · " & Format(Fields!OpenDate.Value, "dd.MM.yyyy") & " · " & Fields!MainDiagnosis.Value'}],
                        [visit, sub], [tot], pos=(top, 0), detail_sort=[("=Fields!VisitDateTime.Value", False)],
                        detail_hidden_by="tbRecord", detail_expanded=True)
    r.add(x, bottom)
    return r


def report02a():
    r = Report("02a_Призначення_візиту", "Призначення ліків на візиті",
               "Вкладений звіт: ліки, призначені на візиті (параметр VisitID)", landscape=False)
    r.ds_sql("dsPrescriptions", "PolyclinicDB",
             "SELECT m.Name AS Medication, pr.Dosage, pr.TimesPerDay, pr.DurationDays, pr.Quantity, pr.TotalCost "
             "FROM dbo.Prescriptions pr JOIN dbo.Medications m ON m.MedicationID = pr.MedicationID "
             "WHERE pr.VisitID = @VisitID ORDER BY m.Name",
             [("Medication", S), ("Dosage", S), ("TimesPerDay", "System.Byte"), ("DurationDays", I16), ("Quantity", I16),
              ("TotalCost", DEC)], {"@VisitID": "=Parameters!VisitID.Value"})
    r.param("VisitID", "Візит", "Integer", default="1")
    sm = dict(size=7, bg="#F7F9FC")
    hdr = [r.tb(t, bold=True, size=7, bg=LIGHT, align="Center") for t in
           ("Призначений препарат", "Дозування", "Разів на день", "Днів", "Упаковок", "Сума, грн")]
    det = [r.tb("=Fields!Medication.Value", **sm), r.tb("=Fields!Dosage.Value", **sm),
           r.tb("=Fields!TimesPerDay.Value", align="Center", **sm), r.tb("=Fields!DurationDays.Value", align="Center", **sm),
           r.tb("=Fields!Quantity.Value", align="Center", **sm), r.tb("=Fields!TotalCost.Value", fmt="#,##0.00", align="Right", **sm)]
    x, bottom = r.table("tblPrescriptions", "dsPrescriptions", [6.0, 2.8, 2.0, 1.4, 1.6, 2.2], [hdr], [], [det],
                        pos=(0, 1.2), no_rows="Ліки не призначались", keep_header=False)
    r.add(x, bottom)
    r.body_w = 18.6
    return r


def report03():
    r = Report("03_Завантаженість_лікарів", "Завантаженість лікарів по місяцях",
               "Матричний звіт з OLAP-куба: проведені візити лікар × місяць, теплова карта завантаженості, "
               "підказка з годинами прийому та виручкою.")
    r.ds_sql("dsYears", "PolyclinicDW", YEARS_SQL, YEARS_FIELDS)
    r.ds_sql("dsDepartments", "PolyclinicDW",
             "SELECT DISTINCT Department, N'[Лікар].[Відділення].&[' + Department + N']' AS DeptMdx "
             "FROM dim.DimDoctor WHERE DoctorKey > 0 ORDER BY Department", [("Department", S), ("DeptMdx", S)])
    r.ds_mdx("dsWorkload", """
WITH MEMBER [Measures].[MonthNo] AS IIF(ISEMPTY([Measures].[Проведені візити]), NULL, [Дата].[Місяць року].CURRENTMEMBER.MEMBER_KEY)
SELECT NON EMPTY { [Measures].[Проведені візити], [Measures].[Хвилини прийомів], [Measures].[Виручка], [Measures].[MonthNo] } ON COLUMNS,
NON EMPTY ( STRTOSET(@Department, CONSTRAINED) * [Лікар].[Лікар].[Лікар].ALLMEMBERS * [Дата].[Місяць року].[Місяць року].ALLMEMBERS ) ON ROWS
FROM ( SELECT STRTOSET(@Year, CONSTRAINED) ON COLUMNS FROM [Поліклініка] )""",
             [L("Department", "[Лікар].[Відділення].[Відділення]"), L("Doctor", "[Лікар].[Лікар].[Лікар]"),
              L("Month", "[Дата].[Місяць року].[Місяць року]"), M("Visits", "Проведені візити"),
              M("Minutes", "Хвилини прийомів"), M("Revenue", "Виручка"), M("MonthNo", "MonthNo")],
             {"Department": "=Parameters!Department.Value", "Year": "=Parameters!Year.Value"})
    r.param("Year", "Рік", values_ds=("dsYears", "YearMdx", "YearNo"), default="[Дата].[Рік].&[2025]")
    r.param("Department", "Відділення", multi=True, values_ds=("dsDepartments", "DeptMdx", "Department"),
            default_ds=("dsDepartments", "DeptMdx"))
    top = r.title_block('="Рік: " & Parameters!Year.Label & " · кількість проведених візитів; наведіть курсор на комірку, '
                        'щоб побачити години прийому та виручку"')
    heat = ('=Switch(Sum(Fields!Visits.Value) >= 300, "#F8696B", Sum(Fields!Visits.Value) >= 220, "#FCB273", '
            'Sum(Fields!Visits.Value) >= 150, "#FFEB84", Sum(Fields!Visits.Value) > 0, "#B1D580", True, "White")')
    tip = ('="Години прийому: " & Format(Sum(Fields!Minutes.Value) / 60, "#,##0.0") & " · виручка: " & '
           'Format(Sum(Fields!Revenue.Value), "#,##0") & " грн"')
    cell = r.tb("=Sum(Fields!Visits.Value)", fmt="#,##0", align="Right", bg=heat, tooltip=tip, size=8)
    tcol = r.tb("=Sum(Fields!Visits.Value)", fmt="#,##0", align="Right", bold=True, bg=LIGHT, tooltip=tip, size=8)
    trow = (r.tb("=Sum(Fields!Visits.Value)", fmt="#,##0", align="Right", bold=True, bg=MID, size=8),
            r.tb("=Sum(Fields!Visits.Value)", fmt="#,##0", align="Right", bold=True, bg=MID, size=8))
    x, bottom = r.matrix("mtxWorkload", "dsWorkload",
                         [{"name": "grpDepartment", "expr": "=Fields!Department.Value", "sort": "=Fields!Department.Value",
                           "width": 3.8, "docmap": True,
                           "header": r.tb("=Fields!Department.Value", bold=True, bg=MID, valign="Top", size=8)},
                          {"name": "grpDoctor", "expr": "=Fields!Doctor.Value", "sort": "=Fields!Doctor.Value", "width": 4.9,
                           "header": r.tb("=Fields!Doctor.Value", size=8)}],
                         {"name": "grpMonth", "expr": "=Fields!Month.Value", "sort": "=CInt(Fields!MonthNo.Value)",
                          "header": r.tb("=Left(Fields!Month.Value, 3)", bold=True, bg=DARK, color="White", align="Center", size=7)},
                         cell, tcol, trow, [H(r, "Відділення", align="Left"), H(r, "Лікар", align="Left")],
                         pos=(top, 0), cell_width=1.3)
    r.add(x, bottom)
    legend = [("≥ 300", "#F8696B"), ("220–299", "#FCB273"), ("150–219", "#FFEB84"), ("1–149", "#B1D580")]
    lt = bottom + 0.4
    r.add(r.tb("Візитів за місяць:", size=7, border=False, pos=(lt, 0, 2.8, 0.5)), lt + 0.5)
    for i, (t, c) in enumerate(legend):
        r.add(r.tb(t, size=7, bg=c, align="Center", pos=(lt, 2.9 + i * 2.1, 2.0, 0.5)), lt + 0.5)
    return r


SUBCUBE = ("FROM ( SELECT ( STRTOSET(@Years, CONSTRAINED), FILTER(STRTOSET(@Classes, CONSTRAINED), @IncludeZ = \"True\" OR "
           "NOT ([Хвороба].[Клас МКХ-10].CURRENTMEMBER IS [Хвороба].[Клас МКХ-10].&[Z00-Z99])) ) ON COLUMNS FROM [Поліклініка] )")
P04 = {"Years": "=Parameters!Years.Value", "Classes": "=Parameters!Classes.Value", "IncludeZ": "=CStr(Parameters!IncludePreventive.Value)"}


def report04():
    r = Report("04_Ефективність_лікування", "Аналіз ефективності лікування",
               "Звіт з діаграмами (OLAP): ефективність за класами МКХ-10 (стовпчикова), динаміка по роках (лінійна), "
               "структура результатів (кругова), найкращі лікарі (горизонтальна); таблиця з умовним форматуванням.")
    r.ds_sql("dsYears", "PolyclinicDW", YEARS_SQL, YEARS_FIELDS)
    r.ds_sql("dsClasses", "PolyclinicDW", CLASSES_SQL, CLASSES_FIELDS)
    r.ds_mdx("dsByClass", """
WITH MEMBER [Measures].[ClassCode] AS IIF(ISEMPTY([Measures].[Випадки лікування]), NULL, [Хвороба].[Клас МКХ-10].CURRENTMEMBER.MEMBER_KEY)
SELECT NON EMPTY { [Measures].[Випадки лікування], [Measures].[Ефективність лікування], [Measures].[Рівень одужання],
                   [Measures].[Дотримання нормативу], [Measures].[Середня тривалість лікування], [Measures].[ClassCode] } ON COLUMNS,
NON EMPTY [Хвороба].[Клас МКХ-10].[Клас МКХ-10].ALLMEMBERS ON ROWS
""" + SUBCUBE,
             [L("ClassName", "[Хвороба].[Клас МКХ-10].[Клас МКХ-10]"), M("Cases", "Випадки лікування"),
              M("Eff", "Ефективність лікування"), M("Recovery", "Рівень одужання"), M("Norm", "Дотримання нормативу"),
              M("AvgDays", "Середня тривалість лікування"), M("ClassCode", "ClassCode")], P04)
    r.ds_mdx("dsByYear", """
SELECT NON EMPTY { [Measures].[Ефективність лікування], [Measures].[Рівень одужання], [Measures].[Дотримання нормативу] } ON COLUMNS,
NON EMPTY [Дата].[Рік].[Рік].ALLMEMBERS ON ROWS
""" + SUBCUBE,
             [L("Year", "[Дата].[Рік].[Рік]"), M("Eff", "Ефективність лікування"), M("Recovery", "Рівень одужання"),
              M("Norm", "Дотримання нормативу")], P04)
    r.ds_mdx("dsOutcome", """
SELECT NON EMPTY { [Measures].[Випадки лікування] } ON COLUMNS,
NON EMPTY [Результат лікування].[Результат].[Результат].ALLMEMBERS ON ROWS
""" + SUBCUBE, [L("Outcome", "[Результат лікування].[Результат].[Результат]"), M("Cases", "Випадки лікування")], P04)
    r.ds_mdx("dsTopDoctors", """
SELECT { [Measures].[Ефективність лікування], [Measures].[Випадки лікування] } ON COLUMNS,
TOPCOUNT(FILTER([Лікар].[Лікар].[Лікар].ALLMEMBERS, [Measures].[Випадки лікування] >= 300), 10, [Measures].[Ефективність лікування]) ON ROWS
""" + SUBCUBE, [L("Doctor", "[Лікар].[Лікар].[Лікар]"), M("Eff", "Ефективність лікування"), M("Cases", "Випадки лікування")], P04)
    r.param("Years", "Роки", multi=True, values_ds=("dsYears", "YearMdx", "YearNo"),
            default=[f"[Дата].[Рік].&[{y}]" for y in range(2021, 2026)])
    r.param("Classes", "Класи хвороб МКХ-10", multi=True, values_ds=("dsClasses", "ClassMdx", "ClassLabel"),
            default_ds=("dsClasses", "ClassMdx"))
    r.param("IncludePreventive", "Враховувати профілактичні огляди та вакцинацію (Z00-Z99)", "Boolean", default="false")

    top = r.title_block('="Роки: " & Join(Parameters!Years.Label, ", ") & IIF(Parameters!IncludePreventive.Value, "", '
                        '" · без профілактичних звернень")')
    w = (r.body_w - 0.5) / 2
    r.add(r.chart("chClasses", "dsByClass", "Column", "=Fields!ClassCode.Value",
                  [("Ефективність", "=Sum(Fields!Eff.Value)", None, "#4472C4"), ("Одужання", "=Sum(Fields!Recovery.Value)", None, "#A5A5A5")],
                  title="Ефективність і одужання за класами МКХ-10", pos=(top, 0, w, 6.6), value_format="0%", value_max=1,
                  category_sort=("=Fields!ClassCode.Value", False)), top + 6.6)
    r.add(r.chart("chYears", "dsByYear", "Line", "=Fields!Year.Value",
                  [("Ефективність", "=Sum(Fields!Eff.Value)", None, "#4472C4"),
                   ("Дотримання нормативу", "=Sum(Fields!Norm.Value)", None, "#ED7D31"),
                   ("Ціль 80%", "=0.8", None, "#C00000")],
                  title="Динаміка по роках", pos=(top, w + 0.5, w, 6.6), value_format="0%", value_min=0.4, value_max=1),
          top + 6.6)
    t2 = top + 6.9
    r.add(r.chart("chOutcome", "dsOutcome", "Shape", "=Fields!Outcome.Value", [("Випадки", "=Sum(Fields!Cases.Value)", None, None)],
                  title="Структура результатів лікування", pos=(t2, 0, w, 6.6), subtype="Pie", labels=True, label_text="#PERCENT{P1}",
                  colors=["#3BA55C", "#8BC34A", "#BDBDBD", "#F2C80F", "#ED7D31", "#E04B4B"]), t2 + 6.6)
    r.add(r.chart("chDoctors", "dsTopDoctors", "Bar", "=Fields!Doctor.Value", [("Ефективність", "=Sum(Fields!Eff.Value)", None, "#5B9BD5")],
                  title="Топ-10 лікарів за ефективністю (від 300 випадків)", pos=(t2, w + 0.5, w, 6.6), value_format="0%",
                  legend=False, labels=True, value_min=0.7, value_max=1, category_sort=("=Sum(Fields!Eff.Value)", False),
                  label_format="0.0%"),
          t2 + 6.6)
    t3 = t2 + 6.9
    eff_bg = '=IIF(Fields!Eff.Value < 0.75, "#F8CBAD", IIF(Fields!Eff.Value >= 0.85, "#C6EFCE", "White"))'
    hdr = [H(r, "Клас хвороб МКХ-10", align="Left"), H(r, "Випадки", "=Fields!Cases.Value"),
           H(r, "Ефективність", "=Fields!Eff.Value"), H(r, "Одужання"), H(r, "Дотримання нормативу"), H(r, "Сер. тривалість, днів")]
    det = [r.tb('=Fields!ClassCode.Value & " " & Fields!ClassName.Value'), r.tb("=Fields!Cases.Value", fmt="#,##0", align="Right"),
           r.tb("=Fields!Eff.Value", fmt="0.0%", align="Right", bg=eff_bg, bold=True),
           r.tb("=Fields!Recovery.Value", fmt="0.0%", align="Right"), r.tb("=Fields!Norm.Value", fmt="0.0%", align="Right"),
           r.tb("=Fields!AvgDays.Value", fmt="0.0", align="Right")]
    tot = [r.tb("Усього випадків", bold=True, bg=MID), r.tb("=Sum(Fields!Cases.Value)", fmt="#,##0", align="Right", bold=True, bg=MID),
           (r.tb("Червоним — ефективність нижче 75%, зеленим — 85% і вище", size=7, italic=True, bg=MID), 4)]
    x, bottom = r.table("tblClasses", "dsByClass", [11.0, 2.4, 2.6, 2.4, 3.0, 3.0], [hdr], [], [det], [tot], pos=(t3, 0),
                        detail_sort=[("=Fields!Cases.Value", True)])
    r.add(x, bottom)
    return r


def report05():
    r = Report("05_Статистика_захворювань", "Статистика захворювань",
               "Звіт з деталізацією (OLAP): клас МКХ-10 → хвороба → вікова група, з розгортанням груп, навігаційною "
               "картою і переходом до списку пацієнтів (drillthrough).")
    r.ds_sql("dsYears", "PolyclinicDW", YEARS_SQL, YEARS_FIELDS)
    r.ds_sql("dsClasses", "PolyclinicDW", CLASSES_SQL, CLASSES_FIELDS)
    r.ds_mdx("dsStats", """
WITH MEMBER [Measures].[DiseaseKey] AS IIF(ISEMPTY([Measures].[Випадки лікування]), NULL, [Хвороба].[Хвороба].CURRENTMEMBER.MEMBER_KEY)
     MEMBER [Measures].[ClassCode] AS IIF(ISEMPTY([Measures].[Випадки лікування]), NULL, [Хвороба].[Клас МКХ-10].CURRENTMEMBER.MEMBER_KEY)
SELECT NON EMPTY { [Measures].[Випадки лікування], [Measures].[Дні лікування], [Measures].[Позитивні результати],
                   [Measures].[Ускладнення], [Measures].[Супутні захворювання], [Measures].[DiseaseKey], [Measures].[ClassCode] } ON COLUMNS,
NON EMPTY ( STRTOSET(@Classes, CONSTRAINED) * [Хвороба].[Хвороба].[Хвороба].ALLMEMBERS
          * [Вікова група].[Вікова група].[Вікова група].ALLMEMBERS ) ON ROWS
FROM ( SELECT ( STRTOSET(@Years, CONSTRAINED), STRTOSET(@Genders, CONSTRAINED) ) ON COLUMNS FROM [Поліклініка] )""",
             [L("ClassName", "[Хвороба].[Клас МКХ-10].[Клас МКХ-10]"), L("Disease", "[Хвороба].[Хвороба].[Хвороба]"),
              L("AgeGroup", "[Вікова група].[Вікова група].[Вікова група]"), M("Cases", "Випадки лікування"),
              M("Days", "Дні лікування"), M("Positive", "Позитивні результати"), M("Complications", "Ускладнення"),
              M("Comorbid", "Супутні захворювання"), M("DiseaseKey", "DiseaseKey"), M("ClassCode", "ClassCode")],
             {"Classes": "=Parameters!Classes.Value", "Years": "=Parameters!Years.Value", "Genders": "=Parameters!Genders.Value"})
    r.ds_sql("dsClassesDefault", "PolyclinicDW",
             "SELECT DISTINCT N'[Хвороба].[Клас МКХ-10].&[' + ICDChapter + N']' AS ClassMdx FROM dim.DimDisease "
             "WHERE DiseaseKey > 0 AND ICDChapter <> N'Z00-Z99'", [("ClassMdx", S)])
    r.param("Years", "Роки", multi=True, values_ds=("dsYears", "YearMdx", "YearNo"), default=["[Дата].[Рік].&[2025]"])
    r.param("Genders", "Стать пацієнтів", multi=True,
            static_values=[("[Пацієнт].[Стать].&[Жінка]", "Жінки"), ("[Пацієнт].[Стать].&[Чоловік]", "Чоловіки")],
            default=["[Пацієнт].[Стать].&[Жінка]", "[Пацієнт].[Стать].&[Чоловік]"])
    r.param("Classes", "Класи хвороб МКХ-10", multi=True, values_ds=("dsClasses", "ClassMdx", "ClassLabel"),
            default_ds=("dsClassesDefault", "ClassMdx"))
    top = r.title_block('="Роки: " & Join(Parameters!Years.Label, ", ") & " · стать: " & Join(Parameters!Genders.Label, ", ") & '
                        '" · натисніть «+», щоб розгорнути клас і хворобу; назва хвороби відкриває список пацієнтів"')
    eff = "=IIF(Sum(Fields!Cases.Value) = 0, Nothing, Sum(Fields!Positive.Value) / Sum(Fields!Cases.Value))"
    days = "=IIF(Sum(Fields!Cases.Value) = 0, Nothing, Sum(Fields!Days.Value) / Sum(Fields!Cases.Value))"
    eff_color = ('=IIF(Sum(Fields!Positive.Value) / Sum(Fields!Cases.Value) < 0.7, "#C00000", '
                 'IIF(Sum(Fields!Positive.Value) / Sum(Fields!Cases.Value) >= 0.85, "#2E7D32", "Black"))')

    def nums(bg=None, bold=False):
        return [r.tb("=Sum(Fields!Cases.Value)", fmt="#,##0", align="Right", bg=bg, bold=bold),
                r.tb(days, fmt="0.0", align="Right", bg=bg, bold=bold),
                r.tb(eff, fmt="0.0%", align="Right", bg=bg, bold=True, color=eff_color),
                r.tb("=Sum(Fields!Complications.Value)", fmt="#,##0", align="Right", bg=bg, bold=bold),
                r.tb("=Sum(Fields!Comorbid.Value)", fmt="#,##0", align="Right", bg=bg, bold=bold)]

    hdr = [H(r, "Клас МКХ-10 / хвороба / вікова група", align="Left"), H(r, "Випадки"), H(r, "Сер. тривалість, днів"),
           H(r, "Ефективність"), H(r, "Ускладнення"), H(r, "Супутні діагнози")]
    cls = [r.tb('=Fields!ClassCode.Value & " " & Fields!ClassName.Value', name="tbClass", toggle=False, bold=True, bg=MID)] \
        + nums(MID, True)
    drill = r.drillthrough("07_Пацієнти_з_діагнозом",
                           {"DiseaseKey": "=CInt(Fields!DiseaseKey.Value)", "Years": "=Parameters!Years.Label"})
    dis = [r.tb("=Fields!Disease.Value", name="tbDisease", toggle=False, bg=LIGHT, color="#1F4E79", action=drill,
                tooltip="Відкрити список пацієнтів з цим діагнозом")] + nums(LIGHT)
    det = [r.tb('="      " & Fields!AgeGroup.Value', size=8)] + [
        r.tb("=Fields!Cases.Value", fmt="#,##0", align="Right", size=8),
        r.tb("=IIF(Fields!Cases.Value = 0, Nothing, Fields!Days.Value / Fields!Cases.Value)", fmt="0.0", align="Right", size=8),
        r.tb("=IIF(Fields!Cases.Value = 0, Nothing, Fields!Positive.Value / Fields!Cases.Value)", fmt="0.0%", align="Right", size=8),
        r.tb("=Fields!Complications.Value", fmt="#,##0", align="Right", size=8),
        r.tb("=Fields!Comorbid.Value", fmt="#,##0", align="Right", size=8)]
    tot = [r.tb("Разом", bold=True, bg=DARK, color="White")] + [
        r.tb(e, fmt=f, align="Right", bold=True, bg=DARK, color="White") for e, f in
        (("=Sum(Fields!Cases.Value)", "#,##0"), (days, "0.0"), (eff, "0.0%"), ("=Sum(Fields!Complications.Value)", "#,##0"),
         ("=Sum(Fields!Comorbid.Value)", "#,##0"))]
    x, bottom = r.table("tblStats", "dsStats", [11.2, 2.4, 3.0, 2.6, 2.6, 2.8], [hdr],
                        [{"name": "grpClass", "expr": "=Fields!ClassName.Value", "sort": ("=Sum(Fields!Cases.Value)", True),
                          "rows": [cls], "docmap": '=Fields!ClassCode.Value & " " & Fields!ClassName.Value'},
                         {"name": "grpDisease", "expr": "=Fields!Disease.Value", "sort": ("=Sum(Fields!Cases.Value)", True),
                          "rows": [dis], "docmap": "=Fields!Disease.Value", "hidden_by": "tbClass"}],
                        [det], [tot], pos=(top, 0), detail_hidden_by="tbDisease",
                        detail_sort=[("=Fields!AgeGroup.Value", False)])
    r.add(x, bottom)
    return r


def report06():
    r = Report("06_Дашборд", "Дашборд поліклініки",
               "Дашборд (OLAP): KPI з індикаторами стану, датчики, динаміка візитів, тренди відділень (спарклайни), "
               "топ-5 хвороб.")
    r.ds_sql("dsYears", "PolyclinicDW", YEARS_SQL, YEARS_FIELDS)
    kpis = [("Eff", "Ефективність лікування"), ("Norm", "Дотримання нормативу лікування"), ("NoShow", "Частка неявок"),
            ("Growth", "Ріст виручки")]
    withs = " ".join(f'MEMBER [Measures].[{k}{p}] AS KPI{fn}("{n}")' for k, n in kpis
                     for p, fn in (("Value", "Value"), ("Goal", "Goal"), ("Status", "Status")))
    flds = [M(f"{k}{p}", f"{k}{p}") for k, _ in kpis for p in ("Value", "Goal", "Status")]
    r.ds_mdx("dsKpi", f"""
WITH {withs}
SELECT {{ {", ".join(f"[Measures].[{k}{p}]" for k, _ in kpis for p in ("Value", "Goal", "Status"))},
          [Measures].[Кількість візитів], [Measures].[Виручка], [Measures].[Унікальні пацієнти], [Measures].[Випадки лікування] }} ON COLUMNS
FROM [Поліклініка] WHERE ( STRTOMEMBER(@YearCal, CONSTRAINED) )""",
             flds + [M("Visits", "Кількість візитів"), M("Revenue", "Виручка"), M("Patients", "Унікальні пацієнти"),
                     M("Cases", "Випадки лікування")], {"YearCal": "=Parameters!Year.Value"})
    r.ds_mdx("dsMonthly", """
SELECT NON EMPTY { [Measures].[Кількість візитів], [Measures].[Візити PY] } ON COLUMNS,
NON EMPTY DESCENDANTS(STRTOMEMBER(@YearCal, CONSTRAINED), [Дата].[Календар].[Місяць]) ON ROWS
FROM [Поліклініка]""", [L("Month", "[Дата].[Календар].[Місяць]"), M("Visits", "Кількість візитів"), M("VisitsPY", "Візити PY")],
             {"YearCal": "=Parameters!Year.Value"})
    r.ds_mdx("dsDepartments", """
SELECT NON EMPTY { [Measures].[Кількість візитів], [Measures].[Виручка], [Measures].[Виручка PY] } ON COLUMNS,
NON EMPTY ( [Лікар].[Відділення].[Відділення].ALLMEMBERS * DESCENDANTS(STRTOMEMBER(@YearCal, CONSTRAINED), [Дата].[Календар].[Місяць]) ) ON ROWS
FROM [Поліклініка]""", [L("Department", "[Лікар].[Відділення].[Відділення]"), L("Month", "[Дата].[Календар].[Місяць]"),
                        M("Visits", "Кількість візитів"), M("Revenue", "Виручка"), M("RevenuePY", "Виручка PY")],
             {"YearCal": "=Parameters!Year.Value"})
    r.ds_mdx("dsTopDiseases", """
SELECT { [Measures].[Випадки лікування], [Measures].[Ефективність лікування] } ON COLUMNS,
TOPCOUNT([Хвороба].[Хвороба].[Хвороба].MEMBERS, 5, [Measures].[Випадки лікування]) ON ROWS
FROM [Поліклініка] WHERE ( STRTOMEMBER(@YearCal, CONSTRAINED) )""",
             [L("Disease", "[Хвороба].[Хвороба].[Хвороба]"), M("Cases", "Випадки лікування"), M("Eff", "Ефективність лікування")],
             {"YearCal": "=Parameters!Year.Value"})
    r.param("Year", "Рік", values_ds=("dsYears", "YearCalMdx", "YearNo"), default="[Дата].[Календар].[Рік].&[2025]")
    top = r.title_block('="Рік: " & Parameters!Year.Label & " · показники порівнюються з цілями KPI та попереднім роком"')

    k = lambda c: f'First(Fields!{c}.Value, "dsKpi")'
    tiles = [("Ефективність лікування", "Eff", "0.0%"), ("Дотримання нормативу", "Norm", "0.0%"),
             ("Частка неявок", "NoShow", "0.0%"), ("Ріст виручки (рік до року)", "Growth", "+0.0%;-0.0%")]
    tw = 4.3
    for i, (label, key, fmt) in enumerate(tiles):
        left = i * (tw + 0.25)
        items = [r.tb(label, size=8, bold=True, color="#595959", border=False, pos=(0.1, 0.15, tw - 0.3, 0.5)),
                 r.tb(f"={k(key + 'Value')}", size=18, bold=True, color=DARK, border=False, fmt=fmt,
                      pos=(0.6, 0.15, tw - 1.4, 1.0)),
                 r.tb("●", size=22, border=False, align="Center",
                      tooltip="Статус KPI: зелений — ціль досягнуто, жовтий — близько до цілі, червоний — нижче цілі",
                      color=f'=Switch({k(key + "Status")} = 1, "#3BA55C", {k(key + "Status")} = 0, "#F2C80F", True, "#E04B4B")',
                      pos=(0.65, tw - 1.2, 0.9, 1.0)),
                 r.tb(f'="Ціль: " & Format({k(key + "Goal")}, "0%")', size=7, color="#7F7F7F", border=False,
                      pos=(1.65, 0.15, tw - 0.3, 0.45))]
        r.add(r.rectangle(f"rectKpi{key}", items, (top, left, tw, 2.2), bg="#F7F9FC"), top + 2.2)
    gl = 4 * (tw + 0.25)
    gw = (r.body_w - gl - 0.25) / 2
    r.add(r.radial_gauge("gEff", "dsKpi", f"={k('EffValue')} * 100", (top, gl, gw, 3.4), 100,
                         [(0, 75, "#E04B4B"), (75, 80, "#F2C80F"), (80, 100, "#3BA55C")], "Ефективність, %", "0.0"), top + 3.4)
    r.add(r.radial_gauge("gNoShow", "dsKpi", f"={k('NoShowValue')} * 100", (top, gl + gw + 0.25, gw, 3.4), 10,
                         [(0, 4, "#3BA55C"), (4, 6, "#F2C80F"), (6, 10, "#E04B4B")], "Неявки, %", "0.0"), top + 3.4)
    t1 = top + 2.4
    sums = [("Візитів", "Visits", "#,##0"), ("Виручка, грн", "Revenue", "#,##0"), ("Унікальних пацієнтів", "Patients", "#,##0"),
            ("Закритих випадків лікування", "Cases", "#,##0")]
    for i, (label, key, fmt) in enumerate(sums):
        r.add(r.tb(f'="{label}: " & Format({k(key)}, "{fmt}")', size=8, bold=True, color=DARK, bg=LIGHT,
                   pos=(t1, i * (tw + 0.25), tw, 0.6)), t1 + 0.6)
    t2 = top + 3.6
    w = (r.body_w - 0.5) / 2
    r.add(r.chart("chMonthly", "dsMonthly", "Line", "=Fields!Month.Value",
                  [("Цей рік", "=Sum(Fields!Visits.Value)", None, "#4472C4"),
                   ("Попередній рік", "=Sum(Fields!VisitsPY.Value)", None, "#A5A5A5")],
                  title="Візити по місяцях у порівнянні з попереднім роком", pos=(t2, 0, w, 5.6),
                  label_expr="=Left(Fields!Month.Value, 3)"), t2 + 5.6)
    hdr = [H(r, "Топ-5 хвороб за кількістю випадків", align="Left"), H(r, "Випадки"), H(r, "Ефективність")]
    det = [r.tb("=Fields!Disease.Value", size=8), r.tb("=Fields!Cases.Value", fmt="#,##0", align="Right", size=8),
           r.tb("=Fields!Eff.Value", fmt="0.0%", align="Right", size=8, bold=True,
                color='=IIF(Fields!Eff.Value < 0.75, "#C00000", "#2E7D32")')]
    x, b = r.table("tblTopDiseases", "dsTopDiseases", [w - 4.6, 2.2, 2.4], [hdr], [], [det], pos=(t2, w + 0.5),
                   detail_sort=[("=Fields!Cases.Value", True)])
    r.add(x, b)
    t3 = t2 + 5.9
    spark = r.chart("spDept", "dsDepartments", "Line", "=Fields!Month.Value",
                    [("Візити", "=Sum(Fields!Visits.Value)", None, "#4472C4")], legend=False, sparkline=True)
    yoy = ('=IIF(Sum(Fields!RevenuePY.Value) = 0, Nothing, (Sum(Fields!Revenue.Value) - Sum(Fields!RevenuePY.Value)) / '
           'Sum(Fields!RevenuePY.Value))')
    hdr = [H(r, "Відділення", align="Left"), H(r, "Візити по місяцях"), H(r, "Візитів"), H(r, "Виручка, грн"),
           H(r, "Виручка мин. року"), H(r, "Ріст")]
    grp_row = [r.tb("=Fields!Department.Value", size=8), spark,
               r.tb("=Sum(Fields!Visits.Value)", fmt="#,##0", align="Right", size=8),
               r.tb("=Sum(Fields!Revenue.Value)", fmt="#,##0", align="Right", size=8),
               r.tb("=Sum(Fields!RevenuePY.Value)", fmt="#,##0", align="Right", size=8),
               r.tb(yoy, fmt="+0.0%;-0.0%", align="Right", size=8, bold=True,
                    color='=IIF(Sum(Fields!Revenue.Value) < Sum(Fields!RevenuePY.Value), "#C00000", "#2E7D32")')]
    x, b = r.table("tblDepartments", "dsDepartments", [7.0, 7.0, 2.6, 3.4, 3.4, 2.4], [hdr],
                   [{"name": "grpDept", "expr": "=Fields!Department.Value", "sort": ("=Sum(Fields!Visits.Value)", True),
                     "rows": [grp_row]}], [], [], pos=(t3, 0))
    r.add(x, b)
    return r


def report07():
    r = Report("07_Пацієнти_з_діагнозом", "Пацієнти з діагнозом",
               "Список закритих випадків лікування з вибраним основним діагнозом (відкривається зі звіту «Статистика "
               "захворювань»).")
    r.ds_sql("dsDiseases", "PolyclinicDW",
             "SELECT DiseaseKey, DiseaseFullName FROM dim.DimDisease WHERE DiseaseKey > 0 ORDER BY ICDCode",
             [("DiseaseKey", I32), ("DiseaseFullName", S)])
    r.ds_sql("dsDefaultDisease", "PolyclinicDW",
             "SELECT TOP (1) DiseaseKey FROM fact.FactTreatment GROUP BY DiseaseKey ORDER BY COUNT(*) DESC", [("DiseaseKey", I32)])
    r.ds_sql("dsCases", "PolyclinicDW", """
SELECT p.FullName AS Patient, p.GenderName, ag.AgeGroup, p.City, od.FullDate AS OpenDate, cd.FullDate AS CloseDate,
       f.TreatmentDays, f.NormTreatmentDays, o.Outcome, o.IsPositive, doc.ShortName + N' (' + doc.Specialty + N')' AS Doctor,
       f.ComorbidityCount, dis.DiseaseFullName
FROM fact.FactTreatment f
JOIN dim.DimPatient p   ON p.PatientKey = f.PatientKey
JOIN dim.DimAgeGroup ag ON ag.AgeGroupKey = f.AgeGroupKey
JOIN dim.DimDate od     ON od.DateKey = f.OpenDateKey
JOIN dim.DimDate cd     ON cd.DateKey = f.CloseDateKey
JOIN dim.DimOutcome o   ON o.OutcomeKey = f.OutcomeKey
JOIN dim.DimDoctor doc  ON doc.DoctorKey = f.DoctorKey
JOIN dim.DimDisease dis ON dis.DiseaseKey = f.DiseaseKey
WHERE f.DiseaseKey = @DiseaseKey AND cd.YearNo IN (@Years)""",
             [("Patient", S), ("GenderName", S), ("AgeGroup", S), ("City", S), ("OpenDate", DT), ("CloseDate", DT),
              ("TreatmentDays", I32), ("NormTreatmentDays", I32), ("Outcome", S), ("IsPositive", "System.Boolean"),
              ("Doctor", S), ("ComorbidityCount", I32), ("DiseaseFullName", S)],
             {"@DiseaseKey": "=Parameters!DiseaseKey.Value", "@Years": "=Parameters!Years.Value"})
    r.param("DiseaseKey", "Діагноз", "Integer", values_ds=("dsDiseases", "DiseaseKey", "DiseaseFullName"),
            default_ds=("dsDefaultDisease", "DiseaseKey"))
    r.param("Years", "Роки закриття історії", multi=True, static_values=[(str(y), str(y)) for y in range(2025, 2015, -1)],
            default=["2025"])
    top = r.title_block('=Parameters!DiseaseKey.Label & " · роки: " & Join(Parameters!Years.Value, ", ")')
    hdr = [H(r, "Пацієнт", "=Fields!Patient.Value", "Left"), H(r, "Стать"), H(r, "Вік", "=Fields!AgeGroup.Value"),
           H(r, "Місто", "=Fields!City.Value"), H(r, "Відкрито", "=Fields!OpenDate.Value"),
           H(r, "Закрито", "=Fields!CloseDate.Value"), H(r, "Днів", "=Fields!TreatmentDays.Value"), H(r, "Норма"),
           H(r, "Результат", "=Fields!Outcome.Value"), H(r, "Лікуючий лікар", "=Fields!Doctor.Value")]
    det = [r.tb("=Fields!Patient.Value"), r.tb("=Fields!GenderName.Value", align="Center"), r.tb("=Fields!AgeGroup.Value", align="Center"),
           r.tb("=Fields!City.Value"), r.tb("=Fields!OpenDate.Value", fmt="dd.MM.yyyy", align="Center"),
           r.tb("=Fields!CloseDate.Value", fmt="dd.MM.yyyy", align="Center"),
           r.tb("=Fields!TreatmentDays.Value", align="Right",
                color='=IIF(Fields!TreatmentDays.Value > Fields!NormTreatmentDays.Value, "#C00000", "Black")'),
           r.tb("=Fields!NormTreatmentDays.Value", align="Right", color="#7F7F7F"),
           r.tb("=Fields!Outcome.Value", color='=IIF(Fields!IsPositive.Value, "#2E7D32", "#C00000")'),
           r.tb("=Fields!Doctor.Value", size=8)]
    tot = [(r.tb('="Випадків: " & CountRows() & " · ефективність: " & Format(Sum(IIF(Fields!IsPositive.Value, 1, 0)) / CountRows(), "0.0%")'
                 ' & " · середня тривалість: " & Format(Avg(Fields!TreatmentDays.Value), "0.0") & " дн."',
                 bold=True, bg=DARK, color="White"), 10)]
    x, bottom = r.table("tblCases", "dsCases", [5.0, 1.5, 1.5, 2.8, 2.1, 2.1, 1.3, 1.3, 3.6, 5.2], [hdr], [], [det], [tot],
                        pos=(top, 0), detail_sort=[("=Fields!CloseDate.Value", True)])
    r.add(x, bottom)
    return r


def write_project():
    os.makedirs(OUT, exist_ok=True)
    sources = {
        "PolyclinicDW": ("SQL", "Data Source=.;Initial Catalog=PolyclinicDW"),
        "PolyclinicDB": ("SQL", "Data Source=.;Initial Catalog=PolyclinicDB"),
        "PolyclinicOLAP": ("OLEDB-MD", "Data Source=localhost;Initial Catalog=PolyclinicOLAP"),
    }
    import uuid
    for name, (ext, conn) in sources.items():
        with open(os.path.join(OUT, name + ".rds"), "w", encoding="utf-8") as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                    f'<RptDataSource xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" Name="{name}">\n'
                    f"  <ConnectionProperties>\n    <Extension>{ext}</Extension>\n    <ConnectString>{conn}</ConnectString>\n"
                    "    <IntegratedSecurity>true</IntegratedSecurity>\n  </ConnectionProperties>\n"
                    f"  <DataSourceID>{uuid.uuid4()}</DataSourceID>\n</RptDataSource>\n")
    reports = [report01(), report02(), report02a(), report03(), report04(), report05(), report06(), report07()]
    for rep in reports:
        rep.save(OUT)
        print("  " + rep.name + ".rdl")
    cfg = ("    <FullPath>{0}</FullPath>\n    <OutputPath>bin\\{0}</OutputPath>\n    <ErrorLevel>2</ErrorLevel>\n"
           "    <OverwriteDatasets>False</OverwriteDatasets>\n    <OverwriteDataSources>False</OverwriteDataSources>\n"
           "    <TargetServerVersion>SSRS2016</TargetServerVersion>\n    <Platform>Win32</Platform>\n"
           "    <TargetReportFolder>Поліклініка</TargetReportFolder>\n    <TargetDatasetFolder>Поліклініка/Набори даних</TargetDatasetFolder>\n"
           "    <TargetDatasourceFolder>Поліклініка/Джерела даних</TargetDatasourceFolder>\n"
           "    <TargetReportPartFolder>Поліклініка/Частини звітів</TargetReportPartFolder>\n"
           "    <TargetServerURL>http://localhost/ReportServer</TargetServerURL>\n")
    items_ds = "".join(f'    <DataSource Include="{n}.rds" />\n' for n in sources)
    items_rep = "".join(f'    <Report Include="{rep.name}.rdl" />\n' for rep in reports)
    proj = ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<Project xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
            'ToolsVersion="2.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
            "  <PropertyGroup Condition=\" '$(Configuration)' == 'Debug' \">\n" + cfg.format("Debug") + "  </PropertyGroup>\n"
            "  <PropertyGroup Condition=\" '$(Configuration)' == 'Release' \">\n" + cfg.format("Release") + "  </PropertyGroup>\n"
            "  <PropertyGroup>\n    <DataSources>@(DataSource)</DataSources>\n    <DataSets>@(DataSet)</DataSets>\n"
            "    <Reports>@(Report)</Reports>\n  </PropertyGroup>\n"
            "  <ItemGroup>\n" + items_ds + "  </ItemGroup>\n  <ItemGroup>\n" + items_rep + "  </ItemGroup>\n"
            '  <Import Project="$(MSBuildExtensionsPath)\\Reporting Services\\Microsoft.ReportingServices.MSBuilder.targets" />\n'
            "</Project>\n")
    with open(os.path.join(OUT, "PolyclinicReports.rptproj"), "w", encoding="utf-8-sig") as f:
        f.write(proj)
    pg = "{E3B9F1C4-6A2D-4F7B-9C81-5D0E2A7B3C05}"
    sln = ("\nMicrosoft Visual Studio Solution File, Format Version 12.00\n# Visual Studio Version 17\n"
           "VisualStudioVersion = 17.0.31903.59\nMinimumVisualStudioVersion = 10.0.40219.1\n"
           f'Project("{{F14B399A-7131-4C87-9E4B-1186C45EF12D}}") = "PolyclinicReports", "PolyclinicReports\\PolyclinicReports.rptproj", "{pg}"\n'
           "EndProject\nGlobal\n\tGlobalSection(SolutionConfigurationPlatforms) = preSolution\n"
           "\t\tDebug|Default = Debug|Default\n\t\tRelease|Default = Release|Default\n\tEndGlobalSection\n"
           "\tGlobalSection(ProjectConfigurationPlatforms) = postSolution\n"
           f"\t\t{pg}.Debug|Default.ActiveCfg = Debug\n\t\t{pg}.Debug|Default.Build.0 = Debug\n"
           f"\t\t{pg}.Release|Default.ActiveCfg = Release\n\t\t{pg}.Release|Default.Build.0 = Release\n\tEndGlobalSection\n"
           "\tGlobalSection(SolutionProperties) = preSolution\n\t\tHideSolutionNode = FALSE\n\tEndGlobalSection\nEndGlobal\n")
    with open(os.path.join(ROOT, "PolyclinicReports.sln"), "w", encoding="utf-8-sig") as f:
        f.write(sln)
    print("Project: " + OUT)


if __name__ == "__main__":
    write_project()
