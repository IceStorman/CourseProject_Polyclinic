using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Microsoft.SqlServer.Dts.Runtime;
using Microsoft.SqlServer.Dts.Pipeline.Wrapper;
using Microsoft.SqlServer.Dts.Tasks.FileSystemTask;
using RW = Microsoft.SqlServer.Dts.Runtime.Wrapper;

namespace PolyclinicEtl
{
    public static partial class Packages
    {
        const string LabHeader = "LabOrderNo;PatientRef;PatientName;TestName;Result;Unit;SampleDate;Laboratory";

        static void AddLab(List<KeyValuePair<string, Func<Pkg>>> defs)
        {
            defs.Add(new KeyValuePair<string, Func<Pkg>>("06", LabResults));
            defs.Add(new KeyValuePair<string, Func<Pkg>>("00", Master));
        }

        static TaskHost MoveFile(IDTSSequence container, string name, string sourceVar, string destVar)
        {
            TaskHost th = (TaskHost)container.Executables.Add("STOCK:FileSystemTask");
            th.Name = name;
            FileSystemTask t = (FileSystemTask)th.InnerObject;
            t.Operation = DTSFileSystemOperation.MoveFile;
            t.IsSourcePathVariable = true;
            t.Source = sourceVar;
            t.IsDestinationPathVariable = true;
            t.Destination = destVar;
            t.OverwriteDestinationFile = true;
            return th;
        }

        static string Q(string var)
        {
            return "REPLACE(@[User::" + var + "], \"'\", \"''\")";
        }

        public static Pkg LabResults()
        {
            Pkg k = new Pkg("06_Load_LabResults.dtsx",
                "Обробка всіх CSV-файлів лабораторії (For Each Loop): перевірка структури (Script Task), очищення та перетворення даних, "
                + "відсів некоректних і дубльованих рядків, завантаження fact.FactLabResult, архівування файлів");

            string inbox = Path.Combine(Cfg.LabRoot, "Inbox");
            string archive = Path.Combine(Cfg.LabRoot, "Archive");
            string rejected = Path.Combine(Cfg.LabRoot, "Rejected");
            string sampleDir = Path.Combine(Cfg.LabRoot, "Sample");
            foreach (string dir in new[] { inbox, archive, rejected, sampleDir }) Directory.CreateDirectory(dir);
            string sample = Path.Combine(sampleDir, "lab_results_sample.csv");
            File.WriteAllLines(sample, new[] { LabHeader,
                "LAB-2501-0000001;P-000123;Шевченко О.;Glucose;5,4;ммоль/л;15.01.2025;Лабораторія «Діалаб»" }, new UTF8Encoding(false));

            k.Var("InboxFolder", inbox);
            k.Var("ArchiveFolder", archive);
            k.Var("RejectedFolder", rejected);
            k.Var("ExpectedHeader", LabHeader);
            k.Var("CurrentFile", sample);
            k.VarExpr("FileName", "", "RIGHT(@[User::CurrentFile], FINDSTRING(REVERSE(@[User::CurrentFile]), \"\\\\\", 1) - 1)");
            k.Var("FileIsValid", false);
            k.Var("FileLineCount", 0);
            k.Var("FileSizeKB", 0);
            k.Var("FileMessage", "");
            foreach (string v in new[] { "FileRowsRead", "FileRowsValid", "FileRowsUnique", "FileRowsLoaded", "FileRowsRejected" }) k.Var(v, 0);

            ConnectionManager ff = k.P.Connections.Add("FLATFILE");
            ff.Name = "FF_LabFile";
            ff.Description = "Поточний файл лабораторії (шлях задає For Each Loop)";
            ff.ConnectionString = sample;
            ff.Properties["Format"].SetValue(ff, "Delimited");
            ff.Properties["ColumnNamesInFirstDataRow"].SetValue(ff, true);
            ff.Properties["CodePage"].SetValue(ff, 65001);
            ff.Properties["Unicode"].SetValue(ff, false);
            ff.Properties["HeaderRowDelimiter"].SetValue(ff, "\r\n");
            RW.IDTSConnectionManagerFlatFile100 ffc = (RW.IDTSConnectionManagerFlatFile100)ff.InnerObject;
            string[] cols = LabHeader.Split(';');
            for (int i = 0; i < cols.Length; i++)
            {
                RW.IDTSConnectionManagerFlatFileColumn100 c = ffc.Columns.Add();
                c.ColumnType = "Delimited";
                c.ColumnDelimiter = i == cols.Length - 1 ? "\r\n" : ";";
                c.DataType = RW.DataType.DT_STR;
                c.MaximumWidth = 255;
                c.TextQualified = false;
                ((RW.IDTSName100)c).Name = "src" + cols[i];
            }
            ff.SetExpression("ConnectionString", "@[User::CurrentFile]");

            ForEachLoop loop = (ForEachLoop)k.P.Executables.Add("STOCK:FOREACHLOOP");
            loop.Name = "FELC Файли лабораторії";
            loop.Description = "Для кожного *.csv у папці Inbox";
            ForEachEnumeratorInfo info = null;
            foreach (ForEachEnumeratorInfo fi in k.App.ForEachEnumeratorInfos)
                if (fi.Name == "Foreach File Enumerator") info = fi;
            ForEachEnumeratorHost eh = info.CreateNew();
            eh.Properties["Directory"].SetValue(eh, inbox);
            eh.Properties["FileSpec"].SetValue(eh, "*.csv");
            eh.SetExpression("Directory", "@[User::InboxFolder]");
            loop.ForEachEnumerator = eh;
            ForEachVariableMapping vm = loop.VariableMappings.Add();
            vm.VariableName = "User::CurrentFile";
            vm.ValueIndex = 0;
            k.Then(loop);

            TaskHost scr = ScriptTaskFactory.Create(loop, "SCR Перевірка файлу",
                "Перевірка файлу лабораторії перед завантаженням: розмір, заголовок (структура колонок), кількість рядків",
                "User::CurrentFile,User::ExpectedHeader", "User::FileIsValid,User::FileLineCount,User::FileSizeKB,User::FileMessage",
@"            string path = Dts.Variables[""User::CurrentFile""].Value.ToString();
            string expected = Dts.Variables[""User::ExpectedHeader""].Value.ToString();
            bool valid = false;
            string message;
            int lines = 0, sizeKb = 0;
            try
            {
                FileInfo fi = new FileInfo(path);
                sizeKb = (int)Math.Ceiling(fi.Length / 1024.0);
                string header;
                using (StreamReader r = new StreamReader(path, Encoding.UTF8))
                {
                    header = r.ReadLine();
                    while (r.ReadLine() != null) lines++;
                }
                if (fi.Length == 0 || header == null) message = ""Порожній файл"";
                else if (header.Trim().TrimStart('﻿') != expected) message = ""Неочікувана структура файлу. Заголовок: "" + header;
                else if (lines == 0) message = ""Файл не містить рядків даних"";
                else { valid = true; message = ""OK""; }
            }
            catch (Exception ex)
            {
                message = ""Помилка читання файлу: "" + ex.Message;
            }
            Dts.Variables[""User::FileIsValid""].Value = valid;
            Dts.Variables[""User::FileLineCount""].Value = lines;
            Dts.Variables[""User::FileSizeKB""].Value = sizeKb;
            Dts.Variables[""User::FileMessage""].Value = message;
            bool fireAgain = true;
            Dts.Events.FireInformation(0, ""Перевірка файлу"", Path.GetFileName(path) + "": "" + message, """", 0, ref fireAgain);
            Dts.TaskResult = (int)ScriptResults.Success;");

            TaskHost del = Pkg.Sql(loop, "SQL Видалення попередніх даних файлу", k.Dw, "SELECT 1",
                "\"DELETE FROM fact.FactLabResult WHERE SourceFile = N'\" + " + Q("FileName") + " + \"'\"");

            Flow f = new Flow(k, loop, "DFT Завантаження файлу", "CSV → очищення → перевірки → fact.FactLabResult; відхилені рядки → etl.RejectedRows");
            f.Task.DelayValidation = true;
            var src = f.FlatFileSource("FF_SRC Файл лабораторії", ff, "Рядки CSV (UTF-8, роздільник ;)");
            var rcRead = f.RowCount("RC Прочитано", f.Out(src), "User::FileRowsRead", "Рядків у файлі");
            var uni = f.Convert("DCNV Текст у Unicode", f.Out(rcRead), false, "DT_STR (UTF-8) → DT_WSTR",
                Col.WStr("uLabOrderNo", 255, "srcLabOrderNo"), Col.WStr("uPatientRef", 255, "srcPatientRef"),
                Col.WStr("uTestName", 255, "srcTestName"), Col.WStr("uResult", 255, "srcResult"), Col.WStr("uSampleDate", 255, "srcSampleDate"));
            string d = "TRIM(REPLACENULL([uSampleDate], \"\"))";
            var cln = f.Derived("DER Очищення даних", f.Out(uni),
                "Пробіли, регістр, префікс P-, десяткова кома → крапка, три формати дат → ISO yyyy-MM-dd",
                Col.WStr("LabOrderNo", 20, "(DT_WSTR,20)TRIM(REPLACENULL([uLabOrderNo], \"\"))"),
                Col.WStr("PatientIdText", 20, "(DT_WSTR,20)REPLACE(REPLACE(UPPER(TRIM(REPLACENULL([uPatientRef], \"\"))), \"P-\", \"\"), \" \", \"\")"),
                Col.WStr("TestAlias", 50, "(DT_WSTR,50)REPLACE(REPLACE(UPPER(TRIM(REPLACENULL([uTestName], \"\"))), \" \", \"\"), \"-\", \"\")"),
                Col.WStr("ResultText", 30, "(DT_WSTR,30)REPLACE(TRIM(REPLACENULL([uResult], \"\")), \",\", \".\")"),
                Col.WStr("DateText", 10, "(DT_WSTR,10)(FINDSTRING(" + d + ", \"-\", 1) == 5 ? " + d
                    + " : FINDSTRING(" + d + ", \".\", 1) == 3 ? SUBSTRING(" + d + ", 7, 4) + \"-\" + SUBSTRING(" + d + ", 4, 2) + \"-\" + SUBSTRING(" + d + ", 1, 2)"
                    + " : FINDSTRING(" + d + ", \"/\", 1) == 3 ? SUBSTRING(" + d + ", 7, 4) + \"-\" + SUBSTRING(" + d + ", 1, 2) + \"-\" + SUBSTRING(" + d + ", 4, 2)"
                    + " : \"\")"),
                Col.WStr("RawRow", 500, "(DT_WSTR,500)(REPLACENULL([uPatientRef], \"\") + \";\" + REPLACENULL([uTestName], \"\") + \";\" + REPLACENULL([uResult], \"\") + \";\" + REPLACENULL([uSampleDate], \"\"))"),
                Col.WStr("SourceFile", 260, "@[User::FileName]"));
            var spl = f.Split("CSPL Обов'язкові поля", f.Out(cln), "Заповнені", "Порожні ідентифікатор, пацієнт, результат або дата",
                "Порожні значення", "LEN([LabOrderNo]) == 0 || LEN([PatientIdText]) == 0 || LEN([ResultText]) == 0 || LEN([DateText]) == 0");
            var r1 = f.Derived("DER Причина Порожні", f.Out(spl, "Порожні значення"), "Причина відхилення",
                Col.WStr("RejectReason", 200, "\"Порожнє обов'язкове значення\""));
            var cnv = f.Convert("DCNV Типи даних", f.Out(spl, "Заповнені"), true, "Текст → INT, NUMERIC(10,3), DATE; помилки перетворення → окремий вихід",
                Col.I4("PatientID", "PatientIdText"), Col.Num("ResultValue", 10, 3, "ResultText"), Col.Date("SampleDate", "DateText"));
            var r2 = f.Derived("DER Причина Формат", f.ErrorOut(cnv), "Причина відхилення",
                Col.WStr("RejectReason", 200, "\"Некоректний формат числа, дати або ідентифікатора\""));
            var rcValid = f.RowCount("RC Коректні", f.Out(cnv), "User::FileRowsValid", "Рядків до видалення дублікатів");
            var srt = f.Sort("SRT Видалення дублікатів", f.Out(rcValid), true, "Однакові замовлення + аналіз залишаються в одному екземплярі",
                "LabOrderNo", "TestAlias");
            var rcUnique = f.RowCount("RC Унікальні", f.Out(srt), "User::FileRowsUnique", "Рядків після видалення дублікатів");
            var lt = f.Lookup("LKP Аналіз за назвою", f.Out(rcUnique), k.Dw, "SELECT Alias, LabTestKey FROM dim.LabTestAlias",
                new[] { "TestAlias=Alias" }, 1, "Словник варіантів назв (GLU, Glucose, глюкоза → GLU)", Col.I4("LabTestKey", "LabTestKey"));
            var r3 = f.Derived("DER Причина Аналіз", f.Out(lt, "Lookup No Match Output"), "Причина відхилення",
                Col.WStr("RejectReason", 200, "\"Невідомий аналіз\""));
            var lpat = f.Lookup("LKP Пацієнт", f.Out(lt, "Lookup Match Output"), k.Dw,
                "SELECT PatientID, PatientKey, BirthDate FROM dim.DimPatient WHERE IsCurrent = 1 AND PatientKey > 0",
                new[] { "PatientID=PatientID" }, 1, "Пацієнт має бути в сховищі", Col.I4("PatientKey", "PatientKey"), Col.Date("BirthDate", "BirthDate"));
            var r4 = f.Derived("DER Причина Пацієнт", f.Out(lpat, "Lookup No Match Output"), "Причина відхилення",
                Col.WStr("RejectReason", 200, "\"Пацієнта не знайдено\""));
            var lrng = f.Lookup("LKP Норми аналізу", f.Out(lpat, "Lookup Match Output"), k.Dw,
                "SELECT LabTestKey, RefMin, RefMax, PlausibleMax FROM dim.DimLabTest", new[] { "LabTestKey=LabTestKey" }, 0,
                "Референтні межі і максимально можливе значення",
                Col.Num("RefMin", 10, 3, "RefMin"), Col.Num("RefMax", 10, 3, "RefMax"), Col.Num("PlausibleMax", 10, 3, "PlausibleMax"));
            var spl2 = f.Split("CSPL Достовірність", f.Out(lrng), "Достовірні", "Від'ємні та фізіологічно неможливі значення — помилка введення",
                "Неможливе значення", "[ResultValue] < 0 || [ResultValue] > [PlausibleMax]");
            var r5 = f.Derived("DER Причина Значення", f.Out(spl2, "Неможливе значення"), "Причина відхилення",
                Col.WStr("RejectReason", 200, "\"Неможливе значення результату\""));
            string age = "(DATEDIFF(\"dd\", [BirthDate], [SampleDate]) / 365.25)";
            var flg = f.Derived("DER Ознаки відхилення від норми", f.Out(spl2, "Достовірні"), "Вище/нижче норми, ключ дати, вікова група",
                Col.I4("DateKey", DateKeyExpr("SampleDate")),
                Col.I4("AgeGroupKey", AgeGroupExpr.Replace("[AgeAtEvent]", age)),
                Col.I4("IsHigh", "[ResultValue] > [RefMax] ? 1 : 0"),
                Col.I4("IsLow", "[ResultValue] < [RefMin] ? 1 : 0"),
                Col.I4("IsAbnormal", "[ResultValue] > [RefMax] || [ResultValue] < [RefMin] ? 1 : 0"),
                Col.I4("ETLRunID", "@[User::RunID]"));
            var rcLoad = f.RowCount("RC Завантажено", f.Out(flg), "User::FileRowsLoaded", "Завантажено результатів");
            f.Dest("OLE_DST FactLabResult", f.Out(rcLoad), k.Dw, "[fact].[FactLabResult]", "Fast load у fact.FactLabResult");

            var un = f.Union("UNION Відхилені рядки", new[] { "LabOrderNo", "RawRow", "SourceFile", "RejectReason" },
                "Усі відхилені рядки з причиною", f.Out(r1), f.Out(r2), f.Out(r3), f.Out(r4), f.Out(r5));
            var meta = f.Derived("DER Дані журналу", f.Out(un), "Пакет, запуск, ключ рядка",
                Col.WStr("PackageName", 100, "@[System::PackageName]"),
                Col.I4("RunID", "@[User::RunID]"),
                Col.WStr("SourceKey", 100, "LEN([LabOrderNo]) == 0 ? \"—\" : [LabOrderNo]"),
                Col.WStr("RowData", 1000, "[RawRow]"));
            var rcRej = f.RowCount("RC Відхилено", f.Out(meta), "User::FileRowsRejected", "Відхилених рядків");
            f.Dest("OLE_DST RejectedRows", f.Out(rcRej), k.Dw, "[etl].[RejectedRows]", "Журнал відхилених рядків");

            TaskHost logOk = Pkg.Sql(loop, "SQL Журнал файлу", k.Dw, "SELECT 1",
                "\"EXEC etl.usp_LogFile @LogID = \" + (DT_WSTR,12)@[User::LogID] + \", @FileName = N'\" + " + Q("FileName")
                + " + \"', @FileSizeKB = \" + (DT_WSTR,12)@[User::FileSizeKB] + \", @LineCount = \" + (DT_WSTR,12)@[User::FileLineCount]"
                + " + \", @RowsRead = \" + (DT_WSTR,12)@[User::FileRowsRead] + \", @RowsLoaded = \" + (DT_WSTR,12)@[User::FileRowsLoaded]"
                + " + \", @RowsRejected = \" + (DT_WSTR,12)@[User::FileRowsRejected]"
                + " + \", @RowsDuplicate = \" + (DT_WSTR,12)(@[User::FileRowsValid] - @[User::FileRowsUnique])"
                + " + \", @Status = N'Loaded', @Message = N'OK'\"");
            TaskHost toArchive = MoveFile(loop, "FST Перенесення в архів", "User::CurrentFile", "User::ArchiveFolder");
            TaskHost logBad = Pkg.Sql(loop, "SQL Журнал відхиленого файлу", k.Dw, "SELECT 1",
                "\"EXEC etl.usp_LogFile @LogID = \" + (DT_WSTR,12)@[User::LogID] + \", @FileName = N'\" + " + Q("FileName")
                + " + \"', @FileSizeKB = \" + (DT_WSTR,12)@[User::FileSizeKB] + \", @LineCount = \" + (DT_WSTR,12)@[User::FileLineCount]"
                + " + \", @RowsRead = 0, @RowsLoaded = 0, @RowsRejected = 0, @RowsDuplicate = 0, @Status = N'Rejected', @Message = N'\" + "
                + Q("FileMessage") + " + \"'\"");
            TaskHost toRejected = MoveFile(loop, "FST Перенесення у відхилені", "User::CurrentFile", "User::RejectedFolder");

            Pkg.LinkIf(loop, scr, del, "@[User::FileIsValid] == TRUE");
            Pkg.Link(loop, del, f.Task);
            Pkg.Link(loop, f.Task, logOk);
            Pkg.Link(loop, logOk, toArchive);
            Pkg.LinkIf(loop, scr, logBad, "@[User::FileIsValid] == FALSE");
            Pkg.Link(loop, logBad, toRejected);

            k.Then(Pkg.Sql(k.P, "SQL Завершення пакета", k.Dw, "SELECT 1",
                "\"EXEC etl.usp_LabPackageEnd @LogID = \" + (DT_WSTR,12)@[User::LogID]"));
            return k;
        }

        public static Pkg Master()
        {
            Pkg k = new Pkg("00_Master.dtsx",
                "Головний пакет: повний запуск ETL — календар і виміри, потім факти (паралельно), потім файли лабораторії", true);
            k.Var("PackagesFolder", Cfg.PackagesDir);

            Func<IDTSSequence, string, TaskHost> run = (container, file) =>
            {
                ConnectionManager cm = k.P.Connections.Add("FILE");
                cm.Name = "PKG " + file.Replace(".dtsx", "");
                cm.ConnectionString = Path.Combine(Cfg.PackagesDir, file);
                cm.SetExpression("ConnectionString", "@[User::PackagesFolder] + \"\\\\" + file + "\"");
                TaskHost th = (TaskHost)container.Executables.Add("STOCK:ExecutePackageTask");
                th.Name = "EPT " + file.Replace(".dtsx", "");
                th.Properties["UseProjectReference"].SetValue(th, false);
                th.Properties["Connection"].SetValue(th, cm.Name);
                return th;
            };

            Sequence dims = k.Then(k.Seq("SEQ Виміри"));
            TaskHost d1 = run(dims, "01_Load_DimDate.dtsx");
            TaskHost d2 = run(dims, "02_Load_Dimensions.dtsx");
            Pkg.Link(dims, d1, d2);

            Sequence facts = k.Then(k.Seq("SEQ Факти (паралельно)"));
            run(facts, "03_Load_FactVisit.dtsx");
            run(facts, "04_Load_FactPrescription.dtsx");
            run(facts, "05_Load_FactTreatment.dtsx");

            k.Then(run(k.P, "06_Load_LabResults.dtsx"));
            k.Finish("0", "0", "0", "0");
            k.Then(Pkg.Sql(k.P, "SQL Завершення запуску ETL", k.Dw, "SELECT 1",
                "\"EXEC etl.usp_RunEnd @RunID = \" + (DT_WSTR,12)@[User::RunID]"));
            return k;
        }
    }

    public static class ProjectWriter
    {
        static string X(string s) { return System.Security.SecurityElement.Escape(s ?? ""); }

        public static void Write(string root)
        {
            string dir = Cfg.PackagesDir;
            Application app = new Application();
            string[] files = Directory.GetFiles(dir, "*.dtsx").Select(Path.GetFileName).OrderBy(x => x).ToArray();
            string projectId = "{6b1e9a5c-2d1f-4c2e-9a77-3f1c0d6e0601}";

            StringBuilder pk = new StringBuilder();
            StringBuilder meta = new StringBuilder();
            foreach (string f in files)
            {
                Package p = app.LoadPackage(Path.Combine(dir, f), null);
                pk.AppendLine("          <SSIS:Package SSIS:Name=\"" + f + "\" SSIS:EntryPoint=\"1\" />");
                meta.AppendLine("            <SSIS:PackageMetaData SSIS:Name=\"" + f + "\">");
                meta.AppendLine("              <SSIS:Properties>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"ID\">" + p.ID + "</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"Name\">" + X(p.Name) + "</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"VersionMajor\">" + p.VersionMajor + "</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"VersionMinor\">" + p.VersionMinor + "</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"VersionBuild\">" + p.VersionBuild + "</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"VersionComments\">" + X(p.VersionComments) + "</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"VersionGUID\">" + p.VersionGUID + "</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"PackageFormatVersion\">8</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"Description\">" + X(p.Description) + "</SSIS:Property>");
                meta.AppendLine("                <SSIS:Property SSIS:Name=\"ProtectionLevel\">0</SSIS:Property>");
                meta.AppendLine("              </SSIS:Properties>");
                meta.AppendLine("              <SSIS:Parameters />");
                meta.AppendLine("            </SSIS:PackageMetaData>");
            }

            string dtproj =
@"<?xml version=""1.0"" encoding=""utf-8""?>
<Project xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns:xsd=""http://www.w3.org/2001/XMLSchema"">
  <DeploymentModel>Project</DeploymentModel>
  <ProductVersion>16.0.5467.0</ProductVersion>
  <SchemaVersion>9.0.1.0</SchemaVersion>
  <Database>
    <Name>PolyclinicETL.database</Name>
    <FullPath>PolyclinicETL.database</FullPath>
  </Database>
  <DataSources />
  <DataSourceViews />
  <DeploymentModelSpecificContent>
    <Manifest>
      <SSIS:Project SSIS:ProtectionLevel=""DontSaveSensitive"" xmlns:SSIS=""www.microsoft.com/SqlServer/SSIS"">
        <SSIS:Properties>
          <SSIS:Property SSIS:Name=""ID"">" + projectId + @"</SSIS:Property>
          <SSIS:Property SSIS:Name=""Name"">PolyclinicETL</SSIS:Property>
          <SSIS:Property SSIS:Name=""VersionMajor"">1</SSIS:Property>
          <SSIS:Property SSIS:Name=""VersionMinor"">0</SSIS:Property>
          <SSIS:Property SSIS:Name=""VersionBuild"">0</SSIS:Property>
          <SSIS:Property SSIS:Name=""VersionComments""></SSIS:Property>
          <SSIS:Property SSIS:Name=""CreationDate"">2026-10-30T20:00:00</SSIS:Property>
          <SSIS:Property SSIS:Name=""CreatorName"">" + X(Environment.UserName) + @"</SSIS:Property>
          <SSIS:Property SSIS:Name=""CreatorComputerName"">" + X(Environment.MachineName) + @"</SSIS:Property>
          <SSIS:Property SSIS:Name=""Description"">ETL «Поліклініка»: PolyclinicDB (OLTP) + CSV лабораторії → PolyclinicDW</SSIS:Property>
          <SSIS:Property SSIS:Name=""FormatVersion"">1</SSIS:Property>
        </SSIS:Properties>
        <SSIS:Packages>
" + pk + @"        </SSIS:Packages>
        <SSIS:ConnectionManagers />
        <SSIS:DeploymentInfo>
          <SSIS:ProjectConnectionParameters />
          <SSIS:PackageInfo>
" + meta + @"          </SSIS:PackageInfo>
        </SSIS:DeploymentInfo>
      </SSIS:Project>
    </Manifest>
  </DeploymentModelSpecificContent>
  <ControlFlowParts />
  <Miscellaneous />
  <Configurations>
    <Configuration>
      <Name>Development</Name>
      <Options>
        <OutputPath>bin</OutputPath>
        <ConnectionMappings />
        <ConnectionProviderMappings />
        <ConnectionSecurityMappings />
        <DatabaseStorageLocations />
        <TargetServerVersion>SQLServer2022</TargetServerVersion>
        <ParameterConfigurationValues />
      </Options>
    </Configuration>
  </Configurations>
</Project>
";
            UTF8Encoding utf8 = new UTF8Encoding(true);
            File.WriteAllText(Path.Combine(dir, "PolyclinicETL.dtproj"), dtproj, utf8);
            File.WriteAllText(Path.Combine(dir, "Project.params"),
                "<?xml version=\"1.0\"?>\r\n<SSIS:Parameters xmlns:SSIS=\"www.microsoft.com/SqlServer/SSIS\" />\r\n", utf8);
            File.WriteAllText(Path.Combine(dir, "PolyclinicETL.database"),
@"<Database xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns=""http://schemas.microsoft.com/analysisservices/2003/engine"">
  <ID>PolyclinicETL</ID>
  <Name>PolyclinicETL</Name>
  <CreatedTimestamp>0001-01-01T00:00:00Z</CreatedTimestamp>
  <LastSchemaUpdate>0001-01-01T00:00:00Z</LastSchemaUpdate>
  <LastProcessed>0001-01-01T00:00:00Z</LastProcessed>
  <State>Unprocessed</State>
  <LastUpdate>0001-01-01T00:00:00Z</LastUpdate>
  <DataSourceImpersonationInfo>
    <ImpersonationMode>Default</ImpersonationMode>
    <ImpersonationInfoSecurity>Unchanged</ImpersonationInfoSecurity>
  </DataSourceImpersonationInfo>
</Database>
", utf8);

            string projGuid = "{6B1E9A5C-2D1F-4C2E-9A77-3F1C0D6E0601}";
            string sln =
@"
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project(""{159641D6-6404-4A2A-AE62-294DE0FE8301}"") = ""PolyclinicETL"", ""PolyclinicETL\PolyclinicETL.dtproj"", """ + projGuid + @"""
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Development|Default = Development|Default
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		" + projGuid + @".Development|Default.ActiveCfg = Development
		" + projGuid + @".Development|Default.Build.0 = Development
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
EndGlobal
";
            File.WriteAllText(Path.Combine(root, @"SSIS_Projects\PolyclinicETL.sln"), sln, utf8);
            Console.WriteLine("Project files written: PolyclinicETL.dtproj, PolyclinicETL.sln (" + files.Length + " packages)");
        }
    }
}
