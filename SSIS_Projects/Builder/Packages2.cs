// =====================================================================
// Курсова робота NVBD, варіант 6 «Поліклініка» — пакети фактів.
// =====================================================================
using System;
using System.Collections.Generic;
using Microsoft.SqlServer.Dts.Runtime;
using Microsoft.SqlServer.Dts.Pipeline.Wrapper;

namespace PolyclinicEtl
{
    public static partial class Packages
    {
        public static void AddMore(List<KeyValuePair<string, Func<Pkg>>> defs)
        {
            defs.Add(new KeyValuePair<string, Func<Pkg>>("03", FactVisit));
            defs.Add(new KeyValuePair<string, Func<Pkg>>("04", FactPrescription));
            defs.Add(new KeyValuePair<string, Func<Pkg>>("05", FactTreatment));
            AddLab(defs);
        }

        // Пошук сурогатних ключів поточних версій вимірів (невідомий ключ → NULL, далі → -1)
        static IDTSComponentMetaData100 LookupPatient(Flow f, Pkg k, IDTSComponentMetaData100 up)
        {
            return f.Lookup("LKP DimPatient", f.Out(up), k.Dw,
                "SELECT PatientKey AS PatientKeyLkp, PatientID FROM dim.DimPatient WHERE IsCurrent = 1",
                new[] { "PatientID=PatientID" }, 0, "Сурогатний ключ поточної версії пацієнта (SCD2)",
                Col.I4("PatientKeyLkp", "PatientKeyLkp"));
        }
        static IDTSComponentMetaData100 LookupDoctor(Flow f, Pkg k, IDTSComponentMetaData100 up)
        {
            return f.Lookup("LKP DimDoctor", f.Out(up), k.Dw,
                "SELECT DoctorKey AS DoctorKeyLkp, DoctorID FROM dim.DimDoctor WHERE IsCurrent = 1",
                new[] { "DoctorID=DoctorID" }, 0, "Сурогатний ключ поточної версії лікаря (SCD2)",
                Col.I4("DoctorKeyLkp", "DoctorKeyLkp"));
        }
        static IDTSComponentMetaData100 LookupDisease(Flow f, Pkg k, IDTSComponentMetaData100 up)
        {
            return f.Lookup("LKP DimDisease", f.Out(up), k.Dw,
                "SELECT DiseaseKey AS DiseaseKeyLkp, DiseaseID FROM dim.DimDisease",
                new[] { "DiseaseID=DiseaseID" }, 0, "Сурогатний ключ хвороби (основний діагноз)",
                Col.I4("DiseaseKeyLkp", "DiseaseKeyLkp"));
        }

        static string WatermarkUpdate(string table, string idColumn)
        {
            return "DECLARE @m BIGINT = (SELECT MAX(" + idColumn + ") FROM fact." + table + "); "
                 + "EXEC etl.usp_SetWatermark N'" + table + "', @m, NULL;";
        }

        // =============================================================
        // 03. Факт «Візит»
        // =============================================================
        public static Pkg FactVisit()
        {
            Pkg k = new Pkg("03_Load_FactVisit.dtsx",
                "Інкрементальне завантаження fact.FactVisit (VisitID > watermark): пошук ключів вимірів, невідомі ключі → -1 і журнал etl.RejectedRows");
            k.Var("LastVisitID", "0");
            k.VarExpr("SqlVisits", "",
                "\"SELECT v.VisitID, v.RecordID, CAST(v.VisitDateTime AS date) AS VisitDate, DATEPART(HOUR, v.VisitDateTime) AS VisitHourRaw, "
                + "r.PatientID, v.DoctorID, dg.DiseaseID, v.VisitType, v.Status AS VisitStatus, v.DurationMin, CAST(v.Cost AS decimal(12,2)) AS Cost, "
                + AgeSql("p.BirthDate", "CAST(v.VisitDateTime AS date)") + " AS AgeAtEvent, "
                + "ISNULL(pr.Cnt, 0) AS PrescriptionCount, CAST(ISNULL(pr.Total, 0) AS decimal(12,2)) AS MedicationCost "
                + "FROM dbo.Visits v JOIN dbo.MedicalRecords r ON r.RecordID = v.RecordID JOIN dbo.Patients p ON p.PatientID = r.PatientID "
                + "JOIN dbo.Diagnoses dg ON dg.RecordID = r.RecordID AND dg.DiagnosisType = N'Основний' "
                + "OUTER APPLY (SELECT COUNT(*) AS Cnt, SUM(x.TotalCost) AS Total FROM dbo.Prescriptions x WHERE x.VisitID = v.VisitID) pr "
                + "WHERE v.VisitID > \" + @[User::LastVisitID]");

            k.Then(Pkg.Sql(k.P, "SQL Watermark", k.Dw,
                "SELECT CAST(LastID AS varchar(20)) AS LastID FROM etl.Watermark WHERE TableName = N'FactVisit'", null,
                "LastID=User::LastVisitID"));

            Flow f = new Flow(k, k.P, "DFT FactVisit", "Візити з OLTP → fact.FactVisit");
            k.Then(f.Task);
            var src = f.SourceFromVar("OLE_SRC Візити (інкрементально)", k.Oltp, "User::SqlVisits", "VisitID > watermark; основний діагноз, вік, кількість і вартість ліків");
            var rc = f.RowCount("RC Прочитано", f.Out(src), "User::RowsRead", "Прочитано рядків");
            var der = f.Derived("DER Ключі дати та ознаки", f.Out(rc), "Ключ дати, година, вікова група, ознаки відбувся/неявка",
                Col.I4("DateKey", DateKeyExpr("VisitDate")),
                Col.UI1("VisitHour", "(DT_UI1)[VisitHourRaw]"),
                Col.I4("AgeGroupKey", AgeGroupExpr),
                Col.I4("IsCompleted", "[VisitStatus] == \"Відбувся\" ? 1 : 0"),
                Col.I4("IsNoShow", "[VisitStatus] == \"Неявка\" ? 1 : 0"),
                Col.I4("ETLRunID", "@[User::RunID]"));
            var lp = LookupPatient(f, k, der);
            var ld = LookupDoctor(f, k, lp);
            var ldis = LookupDisease(f, k, ld);
            var lvt = f.Lookup("LKP DimVisitType", f.Out(ldis), k.Dw,
                "SELECT VisitTypeKey AS VisitTypeKeyLkp, VisitType, VisitStatus FROM dim.DimVisitType",
                new[] { "VisitType=VisitType", "VisitStatus=VisitStatus" }, 0, "Ключ junk-виміру за типом і статусом візиту",
                Col.I4("VisitTypeKeyLkp", "VisitTypeKeyLkp"));
            var keys = f.Derived("DER Невідомі члени", f.Out(lvt), "Ненайдений ключ → -1 (невідомий член виміру)",
                Col.I4("PatientKey", "REPLACENULL([PatientKeyLkp], -1)"),
                Col.I4("DoctorKey", "REPLACENULL([DoctorKeyLkp], -1)"),
                Col.I4("DiseaseKey", "REPLACENULL([DiseaseKeyLkp], -1)"),
                Col.I4("VisitTypeKey", "REPLACENULL([VisitTypeKeyLkp], -1)"));
            var spl = f.Split("CSPL Контроль ключів", f.Out(keys), "Коректні", "Рядки з невідомими членами вимірів окремо журналюються",
                "Невідомі ключі", "[PatientKey] == -1 || [DoctorKey] == -1 || [DiseaseKey] == -1 || [VisitTypeKey] == -1");
            var mc = f.Multicast("MC Невідомі ключі", f.Out(spl, "Невідомі ключі"), 2, "Завантажити з ключем -1 і записати в журнал");
            var rej = f.Derived("DER Опис відхилення", f.OutAt(mc, 1), "Причина і дані рядка для etl.RejectedRows",
                Col.WStr("PackageName", 100, "@[System::PackageName]"),
                Col.I4("RunID", "@[User::RunID]"),
                Col.WStr("SourceKey", 100, "\"VisitID=\" + (DT_WSTR,20)[VisitID]"),
                Col.WStr("RejectReason", 200, "\"Невідомий член виміру:\" + ([PatientKey] == -1 ? \" пацієнт\" : \"\") + ([DoctorKey] == -1 ? \" лікар\" : \"\") + ([DiseaseKey] == -1 ? \" хвороба\" : \"\") + ([VisitTypeKey] == -1 ? \" тип візиту\" : \"\") + \" (завантажено з ключем -1)\""),
                Col.WStr("RowData", 1000, "\"RecordID=\" + (DT_WSTR,12)[RecordID] + \"; PatientID=\" + (DT_WSTR,12)[PatientID] + \"; DoctorID=\" + (DT_WSTR,12)[DoctorID] + \"; DiseaseID=\" + (DT_WSTR,12)[DiseaseID]"));
            var rcRej = f.RowCount("RC Відхилено", f.Out(rej), "User::RowsRejected", "Рядки з невідомими ключами");
            f.Dest("OLE_DST RejectedRows", f.Out(rcRej), k.Dw, "[etl].[RejectedRows]", "Журнал відхилених рядків");

            string[] factCols = { "VisitID", "RecordID", "DateKey", "PatientKey", "DoctorKey", "DiseaseKey", "VisitTypeKey", "AgeGroupKey",
                                  "VisitHour", "DurationMin", "Cost", "IsCompleted", "IsNoShow", "PrescriptionCount", "MedicationCost", "ETLRunID" };
            var un = f.Union("UNION Усі візити", factCols, "Коректні рядки + рядки з невідомими членами",
                f.Out(spl, "Коректні"), f.OutAt(mc, 0));
            var rcIns = f.RowCount("RC Завантажено", f.Out(un), "User::RowsInserted", "Завантажено у факт");
            f.Dest("OLE_DST FactVisit", f.Out(rcIns), k.Dw, "[fact].[FactVisit]", "Fast load у fact.FactVisit");

            k.Then(Pkg.Sql(k.P, "SQL Оновлення watermark", k.Dw, WatermarkUpdate("FactVisit", "VisitID"), null));
            k.Finish();
            return k;
        }

        // =============================================================
        // 04. Факт «Призначення ліків»
        // =============================================================
        public static Pkg FactPrescription()
        {
            Pkg k = new Pkg("04_Load_FactPrescription.dtsx",
                "Інкрементальне завантаження fact.FactPrescription (PrescriptionID > watermark)");
            k.Var("LastPrescriptionID", "0");
            k.VarExpr("SqlPrescriptions", "",
                "\"SELECT pr.PrescriptionID, pr.VisitID, CAST(v.VisitDateTime AS date) AS VisitDate, r.PatientID, v.DoctorID, dg.DiseaseID, pr.MedicationID, "
                + AgeSql("p.BirthDate", "CAST(v.VisitDateTime AS date)") + " AS AgeAtEvent, "
                + "pr.Quantity, pr.UnitPrice, CAST(pr.TotalCost AS decimal(12,2)) AS TotalCost, pr.DurationDays, pr.TimesPerDay "
                + "FROM dbo.Prescriptions pr JOIN dbo.Visits v ON v.VisitID = pr.VisitID JOIN dbo.MedicalRecords r ON r.RecordID = v.RecordID "
                + "JOIN dbo.Patients p ON p.PatientID = r.PatientID JOIN dbo.Diagnoses dg ON dg.RecordID = r.RecordID AND dg.DiagnosisType = N'Основний' "
                + "WHERE pr.PrescriptionID > \" + @[User::LastPrescriptionID]");

            k.Then(Pkg.Sql(k.P, "SQL Watermark", k.Dw,
                "SELECT CAST(LastID AS varchar(20)) AS LastID FROM etl.Watermark WHERE TableName = N'FactPrescription'", null,
                "LastID=User::LastPrescriptionID"));

            Flow f = new Flow(k, k.P, "DFT FactPrescription", "Призначення з OLTP → fact.FactPrescription");
            k.Then(f.Task);
            var src = f.SourceFromVar("OLE_SRC Призначення (інкрементально)", k.Oltp, "User::SqlPrescriptions", "PrescriptionID > watermark");
            var rc = f.RowCount("RC Прочитано", f.Out(src), "User::RowsRead", "Прочитано рядків");
            var der = f.Derived("DER Ключ дати та вікова група", f.Out(rc), "Ключ дати і вікова група на дату візиту",
                Col.I4("DateKey", DateKeyExpr("VisitDate")),
                Col.I4("AgeGroupKey", AgeGroupExpr),
                Col.I4("ETLRunID", "@[User::RunID]"));
            var lp = LookupPatient(f, k, der);
            var ld = LookupDoctor(f, k, lp);
            var ldis = LookupDisease(f, k, ld);
            var lm = f.Lookup("LKP DimMedication", f.Out(ldis), k.Dw,
                "SELECT MedicationKey AS MedicationKeyLkp, MedicationID FROM dim.DimMedication",
                new[] { "MedicationID=MedicationID" }, 0, "Сурогатний ключ препарату",
                Col.I4("MedicationKeyLkp", "MedicationKeyLkp"));
            var keys = f.Derived("DER Невідомі члени", f.Out(lm), "Ненайдений ключ → -1",
                Col.I4("PatientKey", "REPLACENULL([PatientKeyLkp], -1)"),
                Col.I4("DoctorKey", "REPLACENULL([DoctorKeyLkp], -1)"),
                Col.I4("DiseaseKey", "REPLACENULL([DiseaseKeyLkp], -1)"),
                Col.I4("MedicationKey", "REPLACENULL([MedicationKeyLkp], -1)"));
            var rcIns = f.RowCount("RC Завантажено", f.Out(keys), "User::RowsInserted", "Завантажено у факт");
            f.Dest("OLE_DST FactPrescription", f.Out(rcIns), k.Dw, "[fact].[FactPrescription]", "Fast load у fact.FactPrescription");

            k.Then(Pkg.Sql(k.P, "SQL Оновлення watermark", k.Dw, WatermarkUpdate("FactPrescription", "PrescriptionID"), null));
            k.Finish();
            return k;
        }

        // =============================================================
        // 05. Факт «Випадок лікування» (закрита історія хвороби)
        // =============================================================
        public static Pkg FactTreatment()
        {
            Pkg k = new Pkg("05_Load_FactTreatment.dtsx",
                "Закриті історії хвороб → fact.FactTreatment: агрегування візитів (Aggregate), показники ефективності лікування");
            k.Var("TreatmentWatermark", "1900-01-01 00:00:00");
            k.Var("NewTreatmentWatermark", "1900-01-01 00:00:00");
            k.VarExpr("SqlTreatment", "",
                "\"SELECT r.RecordID, r.PatientID, r.AttendingDoctorID AS DoctorID, dg.DiseaseID, r.OpenDate, r.CloseDate, r.Outcome, dg.Severity, "
                + "ds.AvgTreatmentDays, " + AgeSql("p.BirthDate", "r.OpenDate") + " AS AgeAtEvent, cm.Comorbidities, cm.Complications, "
                + "v.Cost, CASE WHEN v.Status = N'Відбувся' THEN 1 ELSE 0 END AS IsCompletedVisit "
                + "FROM dbo.MedicalRecords r JOIN dbo.Patients p ON p.PatientID = r.PatientID "
                + "JOIN dbo.Diagnoses dg ON dg.RecordID = r.RecordID AND dg.DiagnosisType = N'Основний' "
                + "JOIN dbo.Diseases ds ON ds.DiseaseID = dg.DiseaseID JOIN dbo.Visits v ON v.RecordID = r.RecordID "
                + "CROSS APPLY (SELECT SUM(CASE WHEN x.DiagnosisType = N'Супутній' THEN 1 ELSE 0 END) AS Comorbidities, "
                + "SUM(CASE WHEN x.DiagnosisType = N'Ускладнення' THEN 1 ELSE 0 END) AS Complications FROM dbo.Diagnoses x WHERE x.RecordID = r.RecordID) cm "
                + "WHERE r.Status = N'Закрита' AND r.ModifiedAt > '\" + @[User::TreatmentWatermark] + \"' AND r.ModifiedAt <= '\" + @[User::NewTreatmentWatermark] + \"'\"");

            k.Then(Pkg.Sql(k.P, "SQL Watermark", k.Dw,
                "SELECT CONVERT(varchar(19), LastDate, 120) AS WM FROM etl.Watermark WHERE TableName = N'FactTreatment'", null,
                "WM=User::TreatmentWatermark"));
            k.Then(Pkg.Sql(k.P, "SQL Нова межа завантаження", k.Oltp,
                "SELECT CONVERT(varchar(19), ISNULL(MAX(ModifiedAt), '1900-01-01'), 120) AS WM FROM dbo.MedicalRecords WHERE Status = N'Закрита'", null,
                "WM=User::NewTreatmentWatermark"));

            Flow f = new Flow(k, k.P, "DFT FactTreatment", "Візити закритих історій → агрегування по історії → fact.FactTreatment");
            k.Then(f.Task);
            var src = f.SourceFromVar("OLE_SRC Візити закритих історій", k.Oltp, "User::SqlTreatment",
                "Один рядок на візит з атрибутами історії хвороби; ModifiedAt у межах (watermark; нова межа]");
            var rc = f.RowCount("RC Прочитано", f.Out(src), "User::RowsRead", "Прочитано візитів");
            var agg = f.Aggregate("AGG Візити по історії хвороби", f.Out(rc), "Групування за історією: кількість візитів, відбулися, вартість",
                new Agg("RecordID", 0, "RecordID"), new Agg("PatientID", 0, "PatientID"), new Agg("DoctorID", 0, "DoctorID"),
                new Agg("DiseaseID", 0, "DiseaseID"), new Agg("OpenDate", 0, "OpenDate"), new Agg("CloseDate", 0, "CloseDate"),
                new Agg("Outcome", 0, "Outcome"), new Agg("Severity", 0, "Severity"), new Agg("AvgTreatmentDays", 0, "AvgTreatmentDays"),
                new Agg("AgeAtEvent", 0, "AgeAtEvent"), new Agg("Comorbidities", 0, "Comorbidities"), new Agg("Complications", 0, "Complications"),
                new Agg("VisitCountAgg", 2, null), new Agg("CompletedVisitsAgg", 4, "IsCompletedVisit"), new Agg("TotalCostAgg", 4, "Cost"));
            var lex = f.Lookup("LKP Вже завантажені", f.Out(agg), k.Dw, "SELECT RecordID FROM fact.FactTreatment",
                new[] { "RecordID=RecordID" }, 1, "Захист від повторного завантаження: далі йдуть лише нові історії");
            var der = f.Derived("DER Показники лікування", f.Out(lex, "Lookup No Match Output"),
                "Тривалість, відхилення від нормативу, ознаки одужання/позитивного результату",
                Col.I4("OpenDateKey", DateKeyExpr("OpenDate")),
                Col.I4("CloseDateKey", DateKeyExpr("CloseDate")),
                Col.I4("AgeGroupKey", AgeGroupExpr),
                Col.I4("TreatmentDays", "DATEDIFF(\"dd\", [OpenDate], [CloseDate])"),
                Col.I4("NormTreatmentDays", "(DT_I4)[AvgTreatmentDays]"),
                Col.I4("DaysOverNorm", "DATEDIFF(\"dd\", [OpenDate], [CloseDate]) - (DT_I4)[AvgTreatmentDays]"),
                Col.I4("VisitCount", "(DT_I4)[VisitCountAgg]"),
                Col.I4("CompletedVisitCount", "(DT_I4)[CompletedVisitsAgg]"),
                Col.Num("TotalVisitCost", 12, 2, "(DT_NUMERIC,12,2)[TotalCostAgg]"),
                Col.I4("ComorbidityCount", "(DT_I4)[Comorbidities]"),
                Col.I4("ComplicationCount", "(DT_I4)[Complications]"),
                Col.I4("IsRecovered", "[Outcome] == \"Одужання\" ? 1 : 0"),
                Col.I4("IsPositive", "[Outcome] == \"Одужання\" || [Outcome] == \"Покращення\" ? 1 : 0"),
                Col.I4("IsWithinNorm", "DATEDIFF(\"dd\", [OpenDate], [CloseDate]) <= (DT_I4)[AvgTreatmentDays] ? 1 : 0"),
                Col.I4("ETLRunID", "@[User::RunID]"));
            var lp = LookupPatient(f, k, der);
            var ld = LookupDoctor(f, k, lp);
            var ldis = LookupDisease(f, k, ld);
            var lo = f.Lookup("LKP DimOutcome", f.Out(ldis), k.Dw, "SELECT OutcomeKey AS OutcomeKeyLkp, Outcome FROM dim.DimOutcome",
                new[] { "Outcome=Outcome" }, 0, "Ключ результату лікування", Col.I4("OutcomeKeyLkp", "OutcomeKeyLkp"));
            var keys = f.Derived("DER Невідомі члени", f.Out(lo), "Ненайдений ключ → -1",
                Col.I4("PatientKey", "REPLACENULL([PatientKeyLkp], -1)"),
                Col.I4("DoctorKey", "REPLACENULL([DoctorKeyLkp], -1)"),
                Col.I4("DiseaseKey", "REPLACENULL([DiseaseKeyLkp], -1)"),
                Col.I4("OutcomeKey", "REPLACENULL([OutcomeKeyLkp], -1)"));
            var rcIns = f.RowCount("RC Завантажено", f.Out(keys), "User::RowsInserted", "Завантажено історій");
            f.Dest("OLE_DST FactTreatment", f.Out(rcIns), k.Dw, "[fact].[FactTreatment]", "Fast load у fact.FactTreatment");

            k.Then(Pkg.Sql(k.P, "SQL Оновлення watermark", k.Dw, "SELECT 1",
                "\"EXEC etl.usp_SetWatermark N'FactTreatment', NULL, '\" + @[User::NewTreatmentWatermark] + \"'\""));
            k.Finish();
            return k;
        }
    }
}
