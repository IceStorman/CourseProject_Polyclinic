// =====================================================================
// Курсова робота NVBD, варіант 6 «Поліклініка» — визначення SSIS-пакетів.
// =====================================================================
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.SqlServer.Dts.Runtime;
using Microsoft.SqlServer.Dts.Pipeline.Wrapper;

namespace PolyclinicEtl
{
    public static partial class Packages
    {
        // Спільні вирази
        const string AgeGroupExpr =
            "[AgeAtEvent] < 18 ? 1 : [AgeAtEvent] < 35 ? 2 : [AgeAtEvent] < 50 ? 3 : [AgeAtEvent] < 65 ? 4 : 5";
        static string DateKeyExpr(string col)
        {
            return "YEAR([" + col + "]) * 10000 + MONTH([" + col + "]) * 100 + DAY([" + col + "])";
        }
        // Вік на дату події (повні роки) — SQL-фрагмент для джерел
        static string AgeSql(string birth, string at)
        {
            return "DATEDIFF(YEAR, " + birth + ", " + at + ") - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, " + birth + ", " + at + "), "
                 + birth + ") > " + at + " THEN 1 ELSE 0 END";
        }

        // =============================================================
        // 01. Календарний вимір
        // =============================================================
        public static Pkg DimDate()
        {
            Pkg k = new Pkg("01_Load_DimDate.dtsx", "Генерація календарного виміру dim.DimDate (2015–2026)");
            k.Then(Pkg.Sql(k.P, "SQL Генерація календаря", k.Dw,
                "EXEC etl.usp_Load_DimDate @DateFrom = '2015-01-01', @DateTo = '2026-12-31'", null,
                "RowsInserted=User::RowsInserted"));
            k.Finish();
            return k;
        }

        // =============================================================
        // 02. Виміри: хвороби та ліки (SCD1), пацієнти та лікарі (SCD2)
        // =============================================================
        public static Pkg Dimensions()
        {
            Pkg k = new Pkg("02_Load_Dimensions.dtsx",
                "Завантаження вимірів: DimDisease, DimMedication (SCD Type 1, виявлення змін у SSIS), DimPatient, DimDoctor (SCD Type 2, інкрементально за ModifiedAt)");
            foreach (string v in new[] { "DiseaseRead", "DiseaseNew", "DiseaseChanged", "DiseaseUpdated", "MedRead", "MedNew", "MedChanged", "MedUpdated",
                                         "PatientRead", "PatInserted", "PatUpdated", "DoctorRead", "DocInserted", "DocUpdated" })
                k.Var(v, 0);
            k.Var("PatientWatermark", "1900-01-01 00:00:00");
            k.Var("DoctorWatermark", "1900-01-01 00:00:00");
            k.VarExpr("SqlPatients", "",
                "\"SELECT p.PatientID, p.LastName AS LastNameRaw, p.FirstName AS FirstNameRaw, p.MiddleName AS MiddleNameRaw, "
                + "p.Gender AS GenderRaw, p.BirthDate, p.BloodType AS BloodTypeRaw, c.Name AS City, r.Name AS Region, p.InsurancePolicy, p.ModifiedAt "
                + "FROM dbo.Patients p JOIN dbo.Cities c ON c.CityID = p.CityID JOIN dbo.Regions r ON r.RegionID = c.RegionID "
                + "WHERE p.ModifiedAt > '\" + @[User::PatientWatermark] + \"'\"");
            k.VarExpr("SqlDoctors", "",
                "\"SELECT d.DoctorID, d.LastName, d.FirstName, d.MiddleName, d.Gender AS GenderRaw, s.Name AS Specialty, dep.Name AS Department, "
                + "d.Category, d.HireDate, d.DismissalDate, d.ModifiedAt "
                + "FROM dbo.Doctors d JOIN dbo.Specialties s ON s.SpecialtyID = d.SpecialtyID JOIN dbo.Departments dep ON dep.DepartmentID = d.DepartmentID "
                + "WHERE d.ModifiedAt > '\" + @[User::DoctorWatermark] + \"'\"");

            // ---------- SCD Type 1 ----------
            Sequence s1 = k.Then(k.Seq("SEQ Довідникові виміри (SCD Type 1)"));
            Executable trunc = Pkg.Sql(s1, "SQL Очищення staging SCD1", k.Dw,
                "TRUNCATE TABLE stg.DiseaseUpdate; TRUNCATE TABLE stg.MedicationUpdate;", null);

            Flow fd = new Flow(k, s1, "DFT DimDisease", "Хвороби МКХ-10: нові рядки → вимір, змінені → staging для оновлення");
            var src = fd.Source("OLE_SRC Хвороби", k.Oltp,
                "SELECT d.DiseaseID, d.ICDCode AS ICDCodeRaw, d.Name AS DiseaseName, c.ICDChapter AS ICDChapterRaw, c.Name AS CategoryName, "
                + "d.IsChronic, d.IsInfectious, d.Severity, d.AvgTreatmentDays, d.Seasonality "
                + "FROM dbo.Diseases d JOIN dbo.DiseaseCategories c ON c.CategoryID = d.CategoryID", "Хвороби та класи МКХ-10 з OLTP");
            var rc = fd.RowCount("RC Прочитано", fd.Out(src), "User::DiseaseRead", "Кількість прочитаних рядків");
            var cnv = fd.Convert("DCNV Коди МКХ у Unicode", fd.Out(rc), false, "varchar (DT_STR) → nvarchar (DT_WSTR)",
                Col.WStr("ICDCode", 10, "ICDCodeRaw"), Col.WStr("ICDChapter", 10, "ICDChapterRaw"));
            var der = fd.Derived("DER Атрибути хвороби", fd.Out(cnv), "Повна назва, тип перебігу, назва тяжкості",
                Col.WStr("DiseaseFullName", 220, "[ICDCode] + \" \" + [DiseaseName]"),
                Col.WStr("CourseType", 15, "[IsChronic] ? \"Хронічна\" : \"Гостра\""),
                Col.WStr("SeverityName", 20, "[Severity] == 1 ? \"Легка\" : [Severity] == 2 ? \"Середня\" : [Severity] == 3 ? \"Помірна\" : [Severity] == 4 ? \"Тяжка\" : \"Дуже тяжка\""),
                Col.I4("ETLRunID", "@[User::RunID]"));
            var lkp = fd.Lookup("LKP Наявна хвороба", fd.Out(der), k.Dw,
                "SELECT DiseaseKey, DiseaseID, DiseaseName AS OldName, CategoryName AS OldCategory, Severity AS OldSeverity, "
                + "AvgTreatmentDays AS OldDays, IsChronic AS OldChronic FROM dim.DimDisease",
                new[] { "DiseaseID=DiseaseID" }, 1, "Пошук хвороби у вимірі за бізнес-ключем",
                Col.I4("DiseaseKey", "DiseaseKey"), Col.WStr("OldName", 200, "OldName"), Col.WStr("OldCategory", 150, "OldCategory"),
                Col.UI1("OldSeverity", "OldSeverity"), Col.I2("OldDays", "OldDays"), Col.Bool("OldChronic", "OldChronic"));
            var rcNew = fd.RowCount("RC Нові", fd.Out(lkp, "Lookup No Match Output"), "User::DiseaseNew", "Нові хвороби");
            fd.Dest("OLE_DST DimDisease", fd.Out(rcNew), k.Dw, "[dim].[DimDisease]", "Вставка нових хвороб");
            var spl = fd.Split("CSPL Чи змінилась", fd.Out(lkp, "Lookup Match Output"), "Без змін", "Порівняння атрибутів SCD Type 1",
                "Змінені", "[DiseaseName] != [OldName] || [CategoryName] != [OldCategory] || [Severity] != [OldSeverity] || [AvgTreatmentDays] != [OldDays] || [IsChronic] != [OldChronic]");
            var rcCh = fd.RowCount("RC Змінені", fd.Out(spl, "Змінені"), "User::DiseaseChanged", "Змінені хвороби");
            fd.Dest("OLE_DST stg_DiseaseUpdate", fd.Out(rcCh), k.Dw, "[stg].[DiseaseUpdate]", "Змінені рядки для UPDATE");

            Executable applyDis = Pkg.Sql(s1, "SQL Оновлення змінених хвороб", k.Dw, "SELECT 0 AS RowsUpdated",
                "\"EXEC etl.usp_Apply_DimDisease_Updates @RunID = \" + (DT_WSTR,12)@[User::RunID]", "RowsUpdated=User::DiseaseUpdated");

            Flow fm = new Flow(k, s1, "DFT DimMedication", "Лікарські засоби: нові → вимір, змінені → staging");
            var msrc = fm.Source("OLE_SRC Ліки", k.Oltp,
                "SELECT m.MedicationID, m.Name AS MedicationName, m.ActiveSubstance, g.Name AS GroupName, m.DosageForm, "
                + "m.Manufacturer AS ManufacturerRaw, m.IsPrescriptionOnly, m.UnitPrice AS CurrentPrice "
                + "FROM dbo.Medications m JOIN dbo.MedicationGroups g ON g.GroupID = m.GroupID", "Ліки та фармгрупи з OLTP");
            var mrc = fm.RowCount("RC Прочитано", fm.Out(msrc), "User::MedRead", "Кількість прочитаних рядків");
            var mder = fm.Derived("DER Атрибути ліків", fm.Out(mrc), "Очищення NULL, статус відпуску, цінова категорія",
                Col.WStr("Manufacturer", 100, "REPLACENULL([ManufacturerRaw], \"Невідомо\")"),
                Col.WStr("PrescriptionStatus", 20, "[IsPrescriptionOnly] ? \"За рецептом\" : \"Без рецепта\""),
                Col.WStr("PriceCategory", 20, "[CurrentPrice] < 100 ? \"до 100 грн\" : [CurrentPrice] <= 500 ? \"100–500 грн\" : \"понад 500 грн\""),
                Col.I4("ETLRunID", "@[User::RunID]"));
            var mlkp = fm.Lookup("LKP Наявні ліки", fm.Out(mder), k.Dw,
                "SELECT MedicationKey, MedicationID, MedicationName AS OldName, CurrentPrice AS OldPrice, GroupName AS OldGroup FROM dim.DimMedication",
                new[] { "MedicationID=MedicationID" }, 1, "Пошук препарату у вимірі",
                Col.I4("MedicationKey", "MedicationKey"), Col.WStr("OldName", 150, "OldName"), Col.Num("OldPrice", 10, 2, "OldPrice"),
                Col.WStr("OldGroup", 100, "OldGroup"));
            var mrcNew = fm.RowCount("RC Нові", fm.Out(mlkp, "Lookup No Match Output"), "User::MedNew", "Нові препарати");
            fm.Dest("OLE_DST DimMedication", fm.Out(mrcNew), k.Dw, "[dim].[DimMedication]", "Вставка нових препаратів");
            var mspl = fm.Split("CSPL Чи змінились", fm.Out(mlkp, "Lookup Match Output"), "Без змін", "Порівняння атрибутів SCD Type 1",
                "Змінені", "[MedicationName] != [OldName] || [CurrentPrice] != [OldPrice] || [GroupName] != [OldGroup]");
            var mrcCh = fm.RowCount("RC Змінені", fm.Out(mspl, "Змінені"), "User::MedChanged", "Змінені препарати");
            fm.Dest("OLE_DST stg_MedicationUpdate", fm.Out(mrcCh), k.Dw, "[stg].[MedicationUpdate]", "Змінені рядки для UPDATE");

            Executable applyMed = Pkg.Sql(s1, "SQL Оновлення змінених ліків", k.Dw, "SELECT 0 AS RowsUpdated",
                "\"EXEC etl.usp_Apply_DimMedication_Updates @RunID = \" + (DT_WSTR,12)@[User::RunID]", "RowsUpdated=User::MedUpdated");

            Pkg.Link(s1, trunc, fd.Task); Pkg.Link(s1, fd.Task, applyDis);
            Pkg.Link(s1, trunc, fm.Task); Pkg.Link(s1, fm.Task, applyMed);

            // ---------- SCD Type 2 ----------
            Sequence s2 = k.Then(k.Seq("SEQ Пацієнти та лікарі (SCD Type 2)"));
            Executable wm = Pkg.Sql(s2, "SQL Watermark та очищення staging", k.Dw,
                "TRUNCATE TABLE stg.Patient; TRUNCATE TABLE stg.Doctor; "
                + "SELECT (SELECT CONVERT(varchar(19), LastDate, 120) FROM etl.Watermark WHERE TableName = N'DimPatient') AS PatientWM, "
                + "(SELECT CONVERT(varchar(19), LastDate, 120) FROM etl.Watermark WHERE TableName = N'DimDoctor') AS DoctorWM",
                null, "PatientWM=User::PatientWatermark", "DoctorWM=User::DoctorWatermark");

            Flow fp = new Flow(k, s2, "DFT Staging пацієнтів", "Пацієнти, змінені після останнього завантаження → stg.Patient");
            var psrc = fp.SourceFromVar("OLE_SRC Пацієнти (інкрементально)", k.Oltp, "User::SqlPatients", "WHERE ModifiedAt > watermark");
            var prc = fp.RowCount("RC Прочитано", fp.Out(psrc), "User::PatientRead", "Кількість змінених пацієнтів");
            var pder = fp.Derived("DER Очищення та атрибути", fp.Out(prc), "TRIM ПІБ, NULL → «Невідомо», групи міст, наявність страховки",
                Col.WStr("LastName", 50, "TRIM([LastNameRaw])"),
                Col.WStr("FirstName", 50, "TRIM([FirstNameRaw])"),
                Col.WStr("MiddleName", 50, "TRIM([MiddleNameRaw])"),
                Col.WStr("FullName", 160, "TRIM([LastNameRaw]) + \" \" + TRIM([FirstNameRaw]) + (ISNULL([MiddleNameRaw]) ? \"\" : \" \" + TRIM([MiddleNameRaw]))"),
                Col.WStr("Gender", 1, "(DT_WSTR,1)[GenderRaw]"),
                Col.WStr("GenderName", 10, "(DT_WSTR,1)[GenderRaw] == \"F\" ? \"Жінка\" : \"Чоловік\""),
                Col.I2("BirthYear", "(DT_I2)YEAR([BirthDate])"),
                Col.WStr("BloodType", 10, "REPLACENULL((DT_WSTR,10)[BloodTypeRaw], \"Невідомо\")"),
                Col.WStr("CityGroup", 30, "[City] == \"Львів\" ? \"Львів\" : [Region] == \"Львівська область\" ? \"Львівська область\" : \"Інші регіони\""),
                Col.WStr("HasInsurance", 10, "ISNULL([InsurancePolicy]) ? \"Ні\" : \"Так\""));
            fp.Dest("OLE_DST stg_Patient", fp.Out(pder), k.Dw, "[stg].[Patient]", "Staging пацієнтів");

            Flow fdoc = new Flow(k, s2, "DFT Staging лікарів", "Лікарі, змінені після останнього завантаження → stg.Doctor");
            var dsrc = fdoc.SourceFromVar("OLE_SRC Лікарі (інкрементально)", k.Oltp, "User::SqlDoctors", "WHERE ModifiedAt > watermark");
            var drc = fdoc.RowCount("RC Прочитано", fdoc.Out(dsrc), "User::DoctorRead", "Кількість змінених лікарів");
            var dder = fdoc.Derived("DER Атрибути лікаря", fdoc.Out(drc), "ПІБ, ініціали, статус працевлаштування",
                Col.WStr("FullName", 160, "[LastName] + \" \" + [FirstName] + (ISNULL([MiddleName]) ? \"\" : \" \" + [MiddleName])"),
                Col.WStr("ShortName", 80, "[LastName] + \" \" + SUBSTRING([FirstName], 1, 1) + \".\" + (ISNULL([MiddleName]) ? \"\" : \" \" + SUBSTRING([MiddleName], 1, 1) + \".\")"),
                Col.WStr("Gender", 1, "(DT_WSTR,1)[GenderRaw]"),
                Col.WStr("EmploymentStatus", 20, "ISNULL([DismissalDate]) ? \"Працює\" : \"Звільнений\""));
            fdoc.Dest("OLE_DST stg_Doctor", fdoc.Out(dder), k.Dw, "[stg].[Doctor]", "Staging лікарів");

            Executable mp = Pkg.Sql(s2, "SQL SCD2 DimPatient", k.Dw, "SELECT 0 AS RowsInserted, 0 AS RowsUpdated",
                "\"EXEC etl.usp_Merge_DimPatient @RunID = \" + (DT_WSTR,12)@[User::RunID]",
                "RowsInserted=User::PatInserted", "RowsUpdated=User::PatUpdated");
            Executable md = Pkg.Sql(s2, "SQL SCD2 DimDoctor", k.Dw, "SELECT 0 AS RowsInserted, 0 AS RowsUpdated",
                "\"EXEC etl.usp_Merge_DimDoctor @RunID = \" + (DT_WSTR,12)@[User::RunID]",
                "RowsInserted=User::DocInserted", "RowsUpdated=User::DocUpdated");

            Pkg.Link(s2, wm, fp.Task); Pkg.Link(s2, fp.Task, mp);
            Pkg.Link(s2, wm, fdoc.Task); Pkg.Link(s2, fdoc.Task, md);

            k.Finish("@[User::DiseaseRead] + @[User::MedRead] + @[User::PatientRead] + @[User::DoctorRead]",
                     "@[User::DiseaseNew] + @[User::MedNew] + @[User::PatInserted] + @[User::DocInserted]",
                     "@[User::DiseaseUpdated] + @[User::MedUpdated] + @[User::PatUpdated] + @[User::DocUpdated]",
                     "0");
            return k;
        }
    }

    public static class Builder
    {
        public static List<string> Build(string root, string server, string only)
        {
            Cfg.Server = server;
            Cfg.PackagesDir = System.IO.Path.Combine(root, @"SSIS_Projects\PolyclinicETL");
            Cfg.LabRoot = System.IO.Path.Combine(root, @"SSIS_Projects\LabFiles");
            System.IO.Directory.CreateDirectory(Cfg.PackagesDir);

            var defs = new List<KeyValuePair<string, Func<Pkg>>>();
            defs.Add(new KeyValuePair<string, Func<Pkg>>("01", Packages.DimDate));
            defs.Add(new KeyValuePair<string, Func<Pkg>>("02", Packages.Dimensions));
            Packages.AddMore(defs);

            List<string> saved = new List<string>();
            foreach (var d in defs)
            {
                if (!string.IsNullOrEmpty(only) && !only.Split(',').Contains(d.Key)) continue;
                Console.WriteLine("Building " + d.Key + "...");
                try
                {
                    Pkg k = d.Value();
                    saved.Add(k.Save());
                }
                catch (Exception ex)
                {
                    Console.WriteLine(ex.ToString());
                    throw;
                }
            }
            if (string.IsNullOrEmpty(only) || only.Split(',').Contains("proj"))
                ProjectWriter.Write(root);
            return saved;
        }
    }
}
