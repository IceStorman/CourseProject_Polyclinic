using System;
using System.Collections.Generic;
using System.Data;
using System.Data.OleDb;
using System.Linq;
using Microsoft.AnalysisServices;

namespace PolyclinicOlap
{
    public class CubeBuilder
    {
        public string SqlServer = "localhost";
        public string OlapServer = "localhost";
        public string DbName = "PolyclinicOLAP";
        public Action<string> Log = Console.WriteLine;
        public bool Verbose = false;

        Server srv;
        Database db;
        DataSource ds;
        DataSourceView dsv;
        OleDbConnection sql;

        string SqlConn { get { return "Provider=MSOLEDBSQL;Data Source=" + SqlServer + ";Initial Catalog=PolyclinicDW;Integrated Security=SSPI;"; } }

        public Database Build(bool process)
        {
            srv = new Server();
            srv.Connect("Data Source=" + OlapServer);
            sql = new OleDbConnection(SqlConn);
            sql.Open();
            try
            {
                Database old = srv.Databases.FindByName(DbName);
                if (old != null) { Log("Drop existing " + DbName); old.Drop(); }

                db = srv.Databases.Add(DbName, DbName);
                db.Description = "OLAP-куб «Поліклініка»: візити, призначення ліків, ефективність лікування, лабораторні аналізи (джерело — PolyclinicDW)";
                db.Language = 1058;
                db.Collation = "Ukrainian_CI_AS";
                db.Update();

                CreateDataSource();
                CreateDsv();
                Dictionary<string, Dimension> dims = CreateDimensions();
                Cube cube = CreateCube(dims);
                db.Update(UpdateOptions.ExpandFull);
                Log("Metadata deployed");

                if (process)
                {
                    Log("ProcessFull...");
                    DateTime t = DateTime.Now;
                    db.Process(ProcessType.ProcessFull);
                    Log(string.Format("Processed in {0:N0} s", (DateTime.Now - t).TotalSeconds));
                }
                return db;
            }
            catch
            {
                Disconnect();
                throw;
            }
        }

        public void Disconnect()
        {
            if (sql != null) sql.Close();
            if (srv != null && srv.Connected) srv.Disconnect();
        }

        void CreateDataSource()
        {
            RelationalDataSource r = new RelationalDataSource("PolyclinicDW", "PolyclinicDW");
            r.ConnectionString = "Provider=MSOLEDBSQL;Data Source=" + SqlServer + ";Initial Catalog=PolyclinicDW;Integrated Security=SSPI;";
            r.ImpersonationInfo = new ImpersonationInfo(ImpersonationMode.ImpersonateServiceAccount);
            r.Description = "Сховище даних PolyclinicDW";
            db.DataSources.Add(r);
            r.Update();
            ds = r;
        }

        void CreateDsv()
        {
            dsv = db.DataSourceViews.Add("PolyclinicDW", "PolyclinicDW");
            dsv.DataSourceID = ds.ID;
            dsv.Schema = new DataSet("PolyclinicDW");
            dsv.Schema.Locale = System.Globalization.CultureInfo.InvariantCulture;

            AddTable("dim", "DimDate");
            AddTable("dim", "DimDoctor");
            AddTable("dim", "DimDisease");
            AddTable("dim", "DimMedication");
            AddTable("dim", "DimAgeGroup");
            AddTable("dim", "DimVisitType");
            AddTable("dim", "DimOutcome");
            AddTable("dim", "DimLabTest");
            AddTable("fact", "FactVisit");
            AddTable("fact", "FactPrescription");
            AddTable("fact", "FactTreatment");
            AddTable("fact", "FactLabResult");

            AddNamedQuery("DimPatient", "PatientKey",
                "SELECT p.PatientKey, p.PatientID, p.FullName, p.GenderName, p.BirthYear, p.BloodType, p.City, p.Region, p.CityGroup, p.HasInsurance, p.IsCurrent, "
                + "CASE WHEN p.PatientKey < 0 THEN N'Невідомо' "
                + "WHEN DATEDIFF(YEAR, p.BirthDate, '2025-12-31') < 18 THEN N'0-17' WHEN DATEDIFF(YEAR, p.BirthDate, '2025-12-31') < 35 THEN N'18-34' "
                + "WHEN DATEDIFF(YEAR, p.BirthDate, '2025-12-31') < 50 THEN N'35-49' WHEN DATEDIFF(YEAR, p.BirthDate, '2025-12-31') < 65 THEN N'50-64' ELSE N'65+' END AS CurrentAgeGroup "
                + "FROM dim.DimPatient AS p",
                "Пацієнт з поточною (на 31.12.2025) віковою групою");
            AddNamedQuery("DiseaseChapter", "ICDChapter",
                "SELECT DISTINCT ICDChapter, ICDChapter + N' ' + CategoryName AS ChapterLabel FROM dim.DimDisease",
                "Класи МКХ-10 (для вибору класу у звітах)");

            Calc("DimDate", "DateName", "CONVERT(nvarchar(10), FullDate, 104)", "Дата у форматі дд.мм.рррр");
            Calc("DimDate", "QuarterYearName", "QuarterName + N' ' + CAST(YearNo AS nvarchar(4))", "Квартал з роком");
            Calc("DimDate", "HalfYearName", "CASE WHEN MonthNo <= 6 THEN N'I півріччя ' ELSE N'II півріччя ' END + CAST(YearNo AS nvarchar(4))", "Півріччя з роком");
            Calc("DimDate", "HalfYearNo", "YearNo * 10 + CASE WHEN MonthNo <= 6 THEN 1 ELSE 2 END", "Ключ півріччя");
            Calc("DimDate", "DayTypeName", "CASE WHEN IsHoliday = 1 THEN N'Святковий' WHEN IsWorkingDay = 0 THEN N'Вихідний' ELSE N'Робочий' END", "Тип дня");
            Calc("DimDoctor", "DoctorLabel", "ShortName + N' (' + Specialty + N')'", "Лікар зі спеціальністю");
            Calc("DimDisease", "InfectiousName", "CASE WHEN IsInfectious = 1 THEN N'Інфекційна' ELSE N'Неінфекційна' END", "Інфекційність");
            Calc("DimVisitType", "VisitTypeLabel", "VisitType + N' — ' + VisitStatus", "Тип і статус візиту");

            Rel("FactVisit", "DateKey", "DimDate", "DateKey");
            Rel("FactVisit", "PatientKey", "DimPatient", "PatientKey");
            Rel("FactVisit", "DoctorKey", "DimDoctor", "DoctorKey");
            Rel("FactVisit", "DiseaseKey", "DimDisease", "DiseaseKey");
            Rel("FactVisit", "VisitTypeKey", "DimVisitType", "VisitTypeKey");
            Rel("FactVisit", "AgeGroupKey", "DimAgeGroup", "AgeGroupKey");
            Rel("FactPrescription", "DateKey", "DimDate", "DateKey");
            Rel("FactPrescription", "PatientKey", "DimPatient", "PatientKey");
            Rel("FactPrescription", "DoctorKey", "DimDoctor", "DoctorKey");
            Rel("FactPrescription", "DiseaseKey", "DimDisease", "DiseaseKey");
            Rel("FactPrescription", "MedicationKey", "DimMedication", "MedicationKey");
            Rel("FactPrescription", "AgeGroupKey", "DimAgeGroup", "AgeGroupKey");
            Rel("FactTreatment", "CloseDateKey", "DimDate", "DateKey");
            Rel("FactTreatment", "OpenDateKey", "DimDate", "DateKey");
            Rel("FactTreatment", "PatientKey", "DimPatient", "PatientKey");
            Rel("FactTreatment", "DoctorKey", "DimDoctor", "DoctorKey");
            Rel("FactTreatment", "DiseaseKey", "DimDisease", "DiseaseKey");
            Rel("FactTreatment", "OutcomeKey", "DimOutcome", "OutcomeKey");
            Rel("FactTreatment", "AgeGroupKey", "DimAgeGroup", "AgeGroupKey");
            Rel("FactLabResult", "DateKey", "DimDate", "DateKey");
            Rel("FactLabResult", "PatientKey", "DimPatient", "PatientKey");
            Rel("FactLabResult", "LabTestKey", "DimLabTest", "LabTestKey");
            Rel("FactLabResult", "AgeGroupKey", "DimAgeGroup", "AgeGroupKey");
            Rel("DimDisease", "ICDChapter", "DiseaseChapter", "ICDChapter");

            dsv.Update();
        }

        DataTable AddTable(string schema, string table)
        {
            DataTable t = new DataTable(table);
            using (OleDbDataAdapter a = new OleDbDataAdapter("SELECT * FROM [" + schema + "].[" + table + "] WHERE 1 = 0", sql))
                a.FillSchema(t, SchemaType.Source);
            t.ExtendedProperties["TableType"] = "Table";
            t.ExtendedProperties["DbSchemaName"] = schema;
            t.ExtendedProperties["DbTableName"] = table;
            t.ExtendedProperties["FriendlyName"] = table;
            foreach (DataColumn c in t.Columns) { c.AutoIncrement = false; c.ReadOnly = false; }
            dsv.Schema.Tables.Add(t);
            return t;
        }

        DataTable AddNamedQuery(string name, string key, string query, string description)
        {
            DataTable t = new DataTable(name);
            using (OleDbDataAdapter a = new OleDbDataAdapter("SELECT * FROM (" + query + ") AS q WHERE 1 = 0", sql))
                a.FillSchema(t, SchemaType.Source);
            t.ExtendedProperties["QueryDefinition"] = query;
            t.ExtendedProperties["TableType"] = "View";
            t.ExtendedProperties["IsLogical"] = "True";
            t.ExtendedProperties["FriendlyName"] = name;
            t.ExtendedProperties["Description"] = description;
            t.PrimaryKey = new[] { t.Columns[key] };
            foreach (DataColumn c in t.Columns) { c.AutoIncrement = false; c.ReadOnly = false; }
            dsv.Schema.Tables.Add(t);
            return t;
        }

        void Calc(string table, string column, string expression, string description)
        {
            DataColumn c = new DataColumn(column, typeof(string));
            if (column.EndsWith("No")) c.DataType = typeof(int);
            c.MaxLength = c.DataType == typeof(string) ? 100 : -1;
            c.ExtendedProperties["ComputedColumnExpression"] = expression;
            c.ExtendedProperties["IsLogical"] = "True";
            c.ExtendedProperties["Description"] = description;
            dsv.Schema.Tables[table].Columns.Add(c);
        }

        void Rel(string fact, string fk, string dim, string pk)
        {
            DataColumn parent = dsv.Schema.Tables[dim].Columns[pk];
            DataColumn child = dsv.Schema.Tables[fact].Columns[fk];
            dsv.Schema.Relations.Add(new DataRelation(fact + "_" + fk + "_" + dim, parent, child, false));
        }

        static DataItem DI(string table, string column, System.Data.OleDb.OleDbType type, int size)
        {
            DataItem d = new DataItem(table, column, type);
            if (size > 0) d.DataSize = size;
            return d;
        }

        class DimDef
        {
            public Dimension D;
            public string Table;
            public DimDef(Database db, string id, string name, string table, string description, DataSourceView dsv)
            {
                Table = table;
                D = db.Dimensions.Add(name, id);
                D.Description = description;
                D.Source = new DataSourceViewBinding(dsv.ID);
                D.StorageMode = DimensionStorageMode.Molap;
                D.UnknownMember = UnknownMemberBehavior.None;
                D.ErrorConfiguration = new ErrorConfiguration();
                D.ErrorConfiguration.KeyDuplicate = ErrorOption.ReportAndStop;
            }

            public DimensionAttribute Attr(string id, string name, string keyCols, string nameCol, bool visible)
            {
                DimensionAttribute a = D.Attributes.Add(name, id);
                foreach (string k in keyCols.Split(','))
                {
                    string[] p = k.Split(':');
                    a.KeyColumns.Add(Item(p[0], p.Length > 1 ? p[1] : "int"));
                }
                if (nameCol != null) a.NameColumn = Item(nameCol, "str");
                else if (a.KeyColumns.Count > 1) throw new Exception("Name column required for composite key " + id);
                a.OrderBy = OrderBy.Key;
                a.AttributeHierarchyVisible = visible;
                return a;
            }

            DataItem Item(string col, string type)
            {
                switch (type)
                {
                    case "str": return DI(Table, col, System.Data.OleDb.OleDbType.WChar, 250);
                    case "smallint": return DI(Table, col, System.Data.OleDb.OleDbType.SmallInt, 0);
                    case "tinyint": return DI(Table, col, System.Data.OleDb.OleDbType.UnsignedTinyInt, 0);
                    case "bit": return DI(Table, col, System.Data.OleDb.OleDbType.Boolean, 0);
                    default: return DI(Table, col, System.Data.OleDb.OleDbType.Integer, 0);
                }
            }

            public void Rel(DimensionAttribute from, DimensionAttribute to, bool rigid)
            {
                AttributeRelationship r = from.AttributeRelationships.Add(to.ID);
                r.RelationshipType = rigid ? RelationshipType.Rigid : RelationshipType.Flexible;
            }

            public Hierarchy Hier(string id, string name, params DimensionAttribute[] levels)
            {
                Hierarchy h = D.Hierarchies.Add(name, id);
                foreach (DimensionAttribute a in levels) h.Levels.Add(a.Name, a.ID).SourceAttributeID = a.ID;
                return h;
            }
        }

        Dictionary<string, Dimension> CreateDimensions()
        {
            Dictionary<string, Dimension> r = new Dictionary<string, Dimension>();

            DimDef d = new DimDef(db, "Date", "Дата", "DimDate", "Календар 2015–2026", dsv);
            d.D.Type = DimensionType.Time;
            DimensionAttribute date = d.Attr("Date", "Дата", "DateKey", "DateName", false); date.Usage = AttributeUsage.Key; date.Type = AttributeType.Date;
            date.ValueColumn = DI("DimDate", "FullDate", System.Data.OleDb.OleDbType.Date, 0);
            DimensionAttribute month = d.Attr("Month", "Місяць", "YearNo:smallint,MonthNo:tinyint", "MonthYearName", false); month.Type = AttributeType.Months;
            DimensionAttribute quarter = d.Attr("Quarter", "Квартал", "YearNo:smallint,QuarterNo:tinyint", "QuarterYearName", false); quarter.Type = AttributeType.Quarters;
            DimensionAttribute half = d.Attr("HalfYear", "Півріччя", "HalfYearNo", "HalfYearName", false); half.Type = AttributeType.HalfYears;
            DimensionAttribute year = d.Attr("Year", "Рік", "YearNo:smallint", null, true); year.Type = AttributeType.Years;
            DimensionAttribute monthOfYear = d.Attr("MonthOfYear", "Місяць року", "MonthNo:tinyint", "MonthName", true); monthOfYear.Type = AttributeType.MonthOfYear;
            DimensionAttribute dow = d.Attr("DayOfWeek", "День тижня", "DayOfWeek:tinyint", "DayName", true); dow.Type = AttributeType.DayOfWeek;
            DimensionAttribute season = d.Attr("Season", "Сезон", "Season:str", null, true);
            DimensionAttribute dayType = d.Attr("DayType", "Тип дня", "DayTypeName:str", null, true);
            d.Rel(date, month, true); d.Rel(month, quarter, true); d.Rel(quarter, half, true); d.Rel(half, year, true);
            d.Rel(date, dow, true); d.Rel(date, dayType, true); d.Rel(month, monthOfYear, true); d.Rel(monthOfYear, season, true);
            d.Hier("Calendar", "Календар", year, half, quarter, month, date);
            r["Date"] = d.D;

            d = new DimDef(db, "Patient", "Пацієнт", "DimPatient", "Пацієнти (SCD Type 2: місто, страховка)", dsv);
            DimensionAttribute pat = d.Attr("Patient", "Пацієнт", "PatientKey", "FullName", false); pat.Usage = AttributeUsage.Key;
            DimensionAttribute city = d.Attr("City", "Місто", "City:str", null, true);
            DimensionAttribute region = d.Attr("Region", "Регіон", "Region:str", null, true);
            DimensionAttribute cityGroup = d.Attr("CityGroup", "Група міст", "CityGroup:str", null, true);
            DimensionAttribute gender = d.Attr("Gender", "Стать", "GenderName:str", null, true);
            DimensionAttribute birthYear = d.Attr("BirthYear", "Рік народження", "BirthYear:smallint", null, true);
            DimensionAttribute blood = d.Attr("BloodType", "Група крові", "BloodType:str", null, true);
            DimensionAttribute ins = d.Attr("Insurance", "Страховка", "HasInsurance:str", null, true);
            DimensionAttribute curAge = d.Attr("CurrentAgeGroup", "Поточна вікова група", "CurrentAgeGroup:str", null, true);
            DimensionAttribute patId = d.Attr("PatientID", "Код пацієнта", "PatientID", null, false); patId.AttributeHierarchyEnabled = false;
            d.Rel(pat, city, false); d.Rel(city, region, true); d.Rel(city, cityGroup, true);
            d.Rel(pat, gender, false); d.Rel(pat, birthYear, false); d.Rel(pat, blood, false); d.Rel(pat, ins, false);
            d.Rel(pat, curAge, false); d.Rel(pat, patId, true);
            d.Hier("Geography", "Географія", region, city, pat);
            r["Patient"] = d.D;

            d = new DimDef(db, "Doctor", "Лікар", "DimDoctor", "Лікарі (SCD Type 2: спеціальність, відділення, категорія)", dsv);
            DimensionAttribute doc = d.Attr("Doctor", "Лікар", "DoctorKey", "DoctorLabel", true); doc.Usage = AttributeUsage.Key;
            DimensionAttribute spec = d.Attr("Specialty", "Спеціальність", "Specialty:str", null, true);
            DimensionAttribute dept = d.Attr("Department", "Відділення", "Department:str", null, true);
            DimensionAttribute cat = d.Attr("Category", "Категорія", "Category:str", null, true);
            DimensionAttribute emp = d.Attr("Employment", "Статус працевлаштування", "EmploymentStatus:str", null, true);
            d.Rel(doc, spec, false); d.Rel(spec, dept, false); d.Rel(doc, cat, false); d.Rel(doc, emp, false);
            d.Hier("Structure", "Структура поліклініки", dept, spec, doc);
            r["Doctor"] = d.D;

            d = new DimDef(db, "Disease", "Хвороба", "DimDisease", "Хвороби МКХ-10", dsv);
            DimensionAttribute dis = d.Attr("Disease", "Хвороба", "DiseaseKey", "DiseaseFullName", true); dis.Usage = AttributeUsage.Key;
            DimensionAttribute chapter = d.Attr("Chapter", "Клас МКХ-10", "ICDChapter:str", "CategoryName", true);
            DimensionAttribute course = d.Attr("Course", "Перебіг", "CourseType:str", null, true);
            DimensionAttribute sev = d.Attr("Severity", "Тяжкість", "Severity:tinyint", "SeverityName", true);
            DimensionAttribute inf = d.Attr("Infectious", "Інфекційність", "InfectiousName:str", null, true);
            DimensionAttribute seas = d.Attr("Seasonality", "Сезонність", "Seasonality:str", null, true);
            d.Rel(dis, chapter, true); d.Rel(dis, course, true); d.Rel(dis, sev, true); d.Rel(dis, inf, true); d.Rel(dis, seas, true);
            d.Hier("ICD", "Класифікація МКХ-10", chapter, dis);
            r["Disease"] = d.D;

            d = new DimDef(db, "Medication", "Препарат", "DimMedication", "Лікарські засоби", dsv);
            DimensionAttribute med = d.Attr("Medication", "Препарат", "MedicationKey", "MedicationName", true); med.Usage = AttributeUsage.Key;
            DimensionAttribute grp = d.Attr("Group", "Фармгрупа", "GroupName:str", null, true);
            DimensionAttribute rx = d.Attr("Rx", "Відпуск", "PrescriptionStatus:str", null, true);
            DimensionAttribute price = d.Attr("PriceCategory", "Цінова категорія", "PriceCategory:str", null, true);
            DimensionAttribute manuf = d.Attr("Manufacturer", "Виробник", "Manufacturer:str", null, true);
            d.Rel(med, grp, true); d.Rel(med, rx, true); d.Rel(med, price, false); d.Rel(med, manuf, true);
            d.Hier("Groups", "Фармгрупи", grp, med);
            r["Medication"] = d.D;

            d = new DimDef(db, "AgeGroup", "Вікова група", "DimAgeGroup", "Вікова група пацієнта на дату події", dsv);
            DimensionAttribute ag = d.Attr("AgeGroup", "Вікова група", "AgeGroupKey", "AgeGroup", true); ag.Usage = AttributeUsage.Key;
            DimensionAttribute agc = d.Attr("AgeCategory", "Вікова категорія", "AgeCategory:str", null, true);
            d.Rel(ag, agc, true);
            d.Hier("Age", "Вік", agc, ag);
            r["AgeGroup"] = d.D;

            d = new DimDef(db, "VisitType", "Тип візиту", "DimVisitType", "Тип і статус візиту", dsv);
            DimensionAttribute vt = d.Attr("VisitTypeStatus", "Тип і статус", "VisitTypeKey", "VisitTypeLabel", true); vt.Usage = AttributeUsage.Key;
            DimensionAttribute vtype = d.Attr("VisitType", "Тип візиту", "VisitType:str", null, true);
            DimensionAttribute vstat = d.Attr("VisitStatus", "Статус візиту", "VisitStatus:str", null, true);
            d.Rel(vt, vtype, true); d.Rel(vt, vstat, true);
            d.Hier("TypeStatus", "Тип → статус", vtype, vt);
            r["VisitType"] = d.D;

            d = new DimDef(db, "Outcome", "Результат лікування", "DimOutcome", "Результат закритої історії хвороби", dsv);
            DimensionAttribute oc = d.Attr("Outcome", "Результат", "OutcomeKey", "Outcome", true); oc.Usage = AttributeUsage.Key;
            DimensionAttribute ocg = d.Attr("OutcomeGroup", "Група результату", "OutcomeGroup:str", null, true);
            d.Rel(oc, ocg, true);
            d.Hier("Outcomes", "Результати", ocg, oc);
            r["Outcome"] = d.D;

            d = new DimDef(db, "LabTest", "Аналіз", "DimLabTest", "Лабораторні аналізи", dsv);
            DimensionAttribute lt = d.Attr("LabTest", "Аналіз", "LabTestKey", "TestName", true); lt.Usage = AttributeUsage.Key;
            DimensionAttribute ltg = d.Attr("TestGroup", "Група аналізів", "TestGroup:str", null, true);
            d.Rel(lt, ltg, true);
            d.Hier("Tests", "Аналізи", ltg, lt);
            r["LabTest"] = d.D;

            foreach (Dimension dim in r.Values) dim.Update();
            return r;
        }

        Measure M(MeasureGroup mg, string id, string name, AggregationFunction f, string table, string column,
                  System.Data.OleDb.OleDbType type, string format, bool visible)
        {
            Measure m = mg.Measures.Add(name, id);
            m.AggregateFunction = f;
            if (column == null)
            {
                DataItem rowItem = new DataItem(new RowBinding(table));
                rowItem.DataType = System.Data.OleDb.OleDbType.Integer;
                m.Source = rowItem;
            }
            else m.Source = DI(table, column, type, 0);
            m.FormatString = format;
            m.Visible = visible;
            return m;
        }

        void Use(MeasureGroup mg, CubeDimension cd, string table, string fkColumn)
        {
            RegularMeasureGroupDimension rd = new RegularMeasureGroupDimension(cd.ID);
            mg.Dimensions.Add(rd);
            MeasureGroupAttribute a = rd.Attributes.Add(cd.Dimension.KeyAttribute.ID);
            a.Type = MeasureGroupAttributeType.Granularity;
            a.KeyColumns.Add(DI(table, fkColumn, System.Data.OleDb.OleDbType.Integer, 0));
        }

        long Scalar(string query)
        {
            using (OleDbCommand c = new OleDbCommand(query, sql)) return Convert.ToInt64(c.ExecuteScalar());
        }

        void YearPartitions(MeasureGroup mg, string table, string prefix)
        {
            for (int y = 2016; y <= 2026; y++)
            {
                string where = "DateKey BETWEEN " + y + "0101 AND " + y + "1231";
                Partition p = mg.Partitions.Add(prefix + " " + y, mg.ID + "_" + y);
                p.Source = new QueryBinding(ds.ID, "SELECT * FROM fact." + table + " WHERE " + where);
                p.StorageMode = StorageMode.Molap;
                p.Slice = "[Дата].[Рік].&[" + y + "]";
                p.EstimatedRows = Scalar("SELECT COUNT_BIG(*) FROM fact." + table + " WHERE " + where);
            }
        }

        Cube CreateCube(Dictionary<string, Dimension> dims)
        {
            Cube cube = db.Cubes.Add("Поліклініка", "Polyclinic");
            cube.Description = "Аналітика поліклініки: візити, призначення, ефективність лікування, лабораторні аналізи";
            cube.Source = new DataSourceViewBinding(dsv.ID);
            cube.StorageMode = StorageMode.Molap;
            cube.Language = 1058;
            cube.Collation = "Ukrainian_CI_AS";

            CubeDimension cDate = cube.Dimensions.Add(dims["Date"].ID, "Дата", "Date");
            CubeDimension cOpen = cube.Dimensions.Add(dims["Date"].ID, "Дата відкриття історії", "OpenDate");
            CubeDimension cPat = cube.Dimensions.Add(dims["Patient"].ID, "Пацієнт", "Patient");
            CubeDimension cDoc = cube.Dimensions.Add(dims["Doctor"].ID, "Лікар", "Doctor");
            CubeDimension cDis = cube.Dimensions.Add(dims["Disease"].ID, "Хвороба", "Disease");
            CubeDimension cMed = cube.Dimensions.Add(dims["Medication"].ID, "Препарат", "Medication");
            CubeDimension cAge = cube.Dimensions.Add(dims["AgeGroup"].ID, "Вікова група", "AgeGroup");
            CubeDimension cVt = cube.Dimensions.Add(dims["VisitType"].ID, "Тип візиту", "VisitType");
            CubeDimension cOut = cube.Dimensions.Add(dims["Outcome"].ID, "Результат лікування", "Outcome");
            CubeDimension cLab = cube.Dimensions.Add(dims["LabTest"].ID, "Аналіз", "LabTest");

            var I4 = System.Data.OleDb.OleDbType.Integer;
            var CUR = System.Data.OleDb.OleDbType.Currency;
            var DBL = System.Data.OleDb.OleDbType.Double;
            const string N0 = "#,##0", N2 = "#,##0.00";

            MeasureGroup v = cube.MeasureGroups.Add("Візити", "Visits");
            v.StorageMode = StorageMode.Molap;
            M(v, "VisitCount", "Кількість візитів", AggregationFunction.Count, "FactVisit", null, I4, N0, true);
            M(v, "Revenue", "Виручка", AggregationFunction.Sum, "FactVisit", "Cost", CUR, N2, true);
            M(v, "CompletedVisits", "Проведені візити", AggregationFunction.Sum, "FactVisit", "IsCompleted", I4, N0, true);
            M(v, "NoShows", "Неявки", AggregationFunction.Sum, "FactVisit", "IsNoShow", I4, N0, true);
            M(v, "DurationMin", "Хвилини прийомів", AggregationFunction.Sum, "FactVisit", "DurationMin", I4, N0, true);
            M(v, "MinVisitCost", "Мінімальна вартість візиту", AggregationFunction.Min, "FactVisit", "Cost", CUR, N2, true);
            M(v, "MaxVisitCost", "Максимальна вартість візиту", AggregationFunction.Max, "FactVisit", "Cost", CUR, N2, true);
            M(v, "AvgDailyVisits", "Середня кількість візитів на день", AggregationFunction.AverageOfChildren, "FactVisit", "IsCompleted", I4, "#,##0.0", true);
            M(v, "VisitMedCost", "Вартість ліків за візити", AggregationFunction.Sum, "FactVisit", "MedicationCost", CUR, N2, true);
            foreach (var u in new[] { Tuple.Create(cDate, "DateKey"), Tuple.Create(cPat, "PatientKey"), Tuple.Create(cDoc, "DoctorKey"),
                                      Tuple.Create(cDis, "DiseaseKey"), Tuple.Create(cVt, "VisitTypeKey"), Tuple.Create(cAge, "AgeGroupKey") })
                Use(v, u.Item1, "FactVisit", u.Item2);
            YearPartitions(v, "FactVisit", "Візити");

            MeasureGroup up = cube.MeasureGroups.Add("Унікальні пацієнти", "UniquePatients");
            up.StorageMode = StorageMode.Molap;
            M(up, "UniquePatients", "Унікальні пацієнти", AggregationFunction.DistinctCount, "FactVisit", "PatientKey", I4, N0, true);
            foreach (var u in new[] { Tuple.Create(cDate, "DateKey"), Tuple.Create(cPat, "PatientKey"), Tuple.Create(cDoc, "DoctorKey"),
                                      Tuple.Create(cDis, "DiseaseKey"), Tuple.Create(cVt, "VisitTypeKey"), Tuple.Create(cAge, "AgeGroupKey") })
                Use(up, u.Item1, "FactVisit", u.Item2);
            Partition upp = up.Partitions.Add("Унікальні пацієнти", "UniquePatients_All");
            upp.Source = new DsvTableBinding(dsv.ID, "FactVisit");
            upp.EstimatedRows = Scalar("SELECT COUNT_BIG(*) FROM fact.FactVisit");

            MeasureGroup pr = cube.MeasureGroups.Add("Призначення", "Prescriptions");
            pr.StorageMode = StorageMode.Molap;
            M(pr, "PrescriptionCount", "Кількість призначень", AggregationFunction.Count, "FactPrescription", null, I4, N0, true);
            M(pr, "Packages", "Кількість упаковок", AggregationFunction.Sum, "FactPrescription", "Quantity", I4, N0, true);
            M(pr, "PrescriptionCost", "Вартість призначень", AggregationFunction.Sum, "FactPrescription", "TotalCost", CUR, N2, true);
            M(pr, "MaxUnitPrice", "Максимальна ціна упаковки", AggregationFunction.Max, "FactPrescription", "UnitPrice", CUR, N2, true);
            M(pr, "MinUnitPrice", "Мінімальна ціна упаковки", AggregationFunction.Min, "FactPrescription", "UnitPrice", CUR, N2, true);
            foreach (var u in new[] { Tuple.Create(cDate, "DateKey"), Tuple.Create(cPat, "PatientKey"), Tuple.Create(cDoc, "DoctorKey"),
                                      Tuple.Create(cDis, "DiseaseKey"), Tuple.Create(cMed, "MedicationKey"), Tuple.Create(cAge, "AgeGroupKey") })
                Use(pr, u.Item1, "FactPrescription", u.Item2);
            YearPartitions(pr, "FactPrescription", "Призначення");

            MeasureGroup tr = cube.MeasureGroups.Add("Лікування", "Treatment");
            tr.StorageMode = StorageMode.Molap;
            M(tr, "Cases", "Випадки лікування", AggregationFunction.Count, "FactTreatment", null, I4, N0, true);
            M(tr, "TreatmentDays", "Дні лікування", AggregationFunction.Sum, "FactTreatment", "TreatmentDays", I4, N0, true);
            M(tr, "NormDays", "Нормативні дні лікування", AggregationFunction.Sum, "FactTreatment", "NormTreatmentDays", I4, N0, true);
            M(tr, "Recovered", "Одужання", AggregationFunction.Sum, "FactTreatment", "IsRecovered", I4, N0, true);
            M(tr, "Positive", "Позитивні результати", AggregationFunction.Sum, "FactTreatment", "IsPositive", I4, N0, true);
            M(tr, "WithinNorm", "Лікування в межах нормативу", AggregationFunction.Sum, "FactTreatment", "IsWithinNorm", I4, N0, true);
            M(tr, "TreatmentCost", "Вартість лікування", AggregationFunction.Sum, "FactTreatment", "TotalVisitCost", CUR, N2, true);
            M(tr, "MinTreatmentDays", "Мінімальна тривалість лікування", AggregationFunction.Min, "FactTreatment", "TreatmentDays", I4, N0, true);
            M(tr, "MaxTreatmentDays", "Максимальна тривалість лікування", AggregationFunction.Max, "FactTreatment", "TreatmentDays", I4, N0, true);
            M(tr, "Comorbidities", "Супутні захворювання", AggregationFunction.Sum, "FactTreatment", "ComorbidityCount", I4, N0, true);
            M(tr, "Complications", "Ускладнення", AggregationFunction.Sum, "FactTreatment", "ComplicationCount", I4, N0, true);
            foreach (var u in new[] { Tuple.Create(cDate, "CloseDateKey"), Tuple.Create(cOpen, "OpenDateKey"), Tuple.Create(cPat, "PatientKey"),
                                      Tuple.Create(cDoc, "DoctorKey"), Tuple.Create(cDis, "DiseaseKey"), Tuple.Create(cOut, "OutcomeKey"),
                                      Tuple.Create(cAge, "AgeGroupKey") })
                Use(tr, u.Item1, "FactTreatment", u.Item2);
            Partition trp = tr.Partitions.Add("Лікування", "Treatment_All");
            trp.Source = new DsvTableBinding(dsv.ID, "FactTreatment");
            trp.EstimatedRows = Scalar("SELECT COUNT_BIG(*) FROM fact.FactTreatment");

            MeasureGroup lab = cube.MeasureGroups.Add("Аналізи", "LabResults");
            lab.StorageMode = StorageMode.Holap;
            M(lab, "LabCount", "Кількість аналізів", AggregationFunction.Count, "FactLabResult", null, I4, N0, true);
            M(lab, "Abnormal", "Аналізи з відхиленням", AggregationFunction.Sum, "FactLabResult", "IsAbnormal", I4, N0, true);
            M(lab, "High", "Вище норми", AggregationFunction.Sum, "FactLabResult", "IsHigh", I4, N0, true);
            M(lab, "Low", "Нижче норми", AggregationFunction.Sum, "FactLabResult", "IsLow", I4, N0, true);
            M(lab, "ResultSum", "Сума значень", AggregationFunction.Sum, "FactLabResult", "ResultValue", DBL, "#,##0.000", false);
            M(lab, "MinResult", "Мінімальне значення аналізу", AggregationFunction.Min, "FactLabResult", "ResultValue", DBL, "#,##0.00", true);
            M(lab, "MaxResult", "Максимальне значення аналізу", AggregationFunction.Max, "FactLabResult", "ResultValue", DBL, "#,##0.00", true);
            foreach (var u in new[] { Tuple.Create(cDate, "DateKey"), Tuple.Create(cPat, "PatientKey"), Tuple.Create(cLab, "LabTestKey"),
                                      Tuple.Create(cAge, "AgeGroupKey") })
                Use(lab, u.Item1, "FactLabResult", u.Item2);
            Partition lp = lab.Partitions.Add("Аналізи", "LabResults_All");
            lp.Source = new DsvTableBinding(dsv.ID, "FactLabResult");
            lp.StorageMode = StorageMode.Holap;
            lp.EstimatedRows = Scalar("SELECT COUNT_BIG(*) FROM fact.FactLabResult");

            cube.MdxScripts.Add("MdxScript", "MdxScript").Commands.Add(new Command(MdxScript.Text));
            Kpis.Add(cube);
            Perspectives(cube);
            return cube;
        }

        void Perspectives(Cube cube)
        {
            AddPerspective(cube, "Finance", "Фінанси",
                new[] { "Visits", "Prescriptions" }, new[] { "Date", "Doctor", "Medication", "VisitType", "Disease" },
                new[] { "Середня вартість візиту", "Частка виручки", "Виручка YTD", "Виручка PY", "Ріст виручки YoY", "Виручка на годину прийому", "Рейтинг лікаря за виручкою" },
                new[] { "Топ-10 лікарів за виручкою" }, new[] { "KPI_RevenueGrowth" });
            AddPerspective(cube, "Clinical", "Клінічна аналітика",
                new[] { "Treatment", "Visits", "UniquePatients" }, new[] { "Date", "OpenDate", "Patient", "Doctor", "Disease", "Outcome", "AgeGroup" },
                new[] { "Середня тривалість лікування", "Рівень одужання", "Ефективність лікування", "Дотримання нормативу", "Перевищення нормативу (днів)", "Візитів на пацієнта", "Рейтинг хвороби за випадками" },
                new[] { "Топ-10 хвороб за випадками" }, new[] { "KPI_Effectiveness", "KPI_WithinNorm" });
            AddPerspective(cube, "Laboratory", "Лабораторія",
                new[] { "LabResults" }, new[] { "Date", "Patient", "LabTest", "AgeGroup" },
                new[] { "Середнє значення аналізу", "Частка аналізів з відхиленням" }, new string[0], new string[0]);
        }

        void AddPerspective(Cube cube, string id, string name, string[] mgs, string[] cubeDims, string[] calcs, string[] sets, string[] kpis)
        {
            Perspective p = cube.Perspectives.Add(name, id);
            foreach (string mgId in mgs)
            {
                MeasureGroup mg = cube.MeasureGroups[mgId];
                PerspectiveMeasureGroup pmg = p.MeasureGroups.Add(mgId);
                foreach (Measure m in mg.Measures) pmg.Measures.Add(m.ID);
            }
            foreach (string dId in cubeDims)
            {
                CubeDimension cd = cube.Dimensions[dId];
                PerspectiveDimension pd = p.Dimensions.Add(dId);
                foreach (CubeAttribute a in cd.Attributes) pd.Attributes.Add(a.AttributeID);
                foreach (CubeHierarchy h in cd.Hierarchies) pd.Hierarchies.Add(h.HierarchyID);
            }
            foreach (string c in calcs) p.Calculations.Add("[Measures].[" + c + "]", PerspectiveCalculationType.Member);
            foreach (string s in sets) p.Calculations.Add("[" + s + "]", PerspectiveCalculationType.Set);
            foreach (string k in kpis) p.Kpis.Add(k);
        }

        public void DesignAggregations(double targetPercent)
        {
            Cube cube = db.Cubes["Polyclinic"];
            foreach (Dimension dim in db.Dimensions)
                foreach (DimensionAttribute a in dim.Attributes)
                {
                    if (!a.AttributeHierarchyEnabled) continue;
                    try
                    {
                        a.EstimatedCount = Math.Max(1, CountMembers(cube, dim, a));
                    }
                    catch { a.EstimatedCount = 10; }
                }
            foreach (Dimension dim in db.Dimensions) dim.Update();

            foreach (CubeDimension cd in cube.Dimensions)
                foreach (CubeAttribute ca in cd.Attributes)
                    if (ca.Attribute.Usage != AttributeUsage.Key && ca.Attribute.AttributeHierarchyEnabled)
                        ca.AggregationUsage = AggregationUsage.Unrestricted;
            cube.Dimensions["Date"].Attributes["Month"].AggregationUsage = AggregationUsage.Full;
            foreach (CubeAttribute ca in cube.Dimensions["Patient"].Attributes)
                if (ca.AttributeID != "Region" && ca.AttributeID != "CityGroup" && ca.AttributeID != "Gender")
                    ca.AggregationUsage = AggregationUsage.None;

            foreach (MeasureGroup mg in cube.MeasureGroups)
            {
                foreach (Partition p in mg.Partitions) p.AggregationDesignID = null;
                mg.AggregationDesigns.Clear();
                long rows = 0;
                foreach (Partition p in mg.Partitions) rows += p.EstimatedRows;
                mg.EstimatedRows = rows;
                AggregationDesign ad = mg.AggregationDesigns.Add("AD " + mg.Name, "AD_" + mg.ID);
                ad.EstimatedRows = rows;
                ad.InitializeDesign();
                double optimization = 0, storage = 0;
                long count = 0;
                bool finished = false;
                int steps = 0;
                System.Text.StringBuilder trace = new System.Text.StringBuilder();
                while (!finished && optimization < targetPercent)
                {
                    ad.DesignAggregations(out optimization, out storage, out count, out finished);
                    steps++;
                    if (steps % 5 == 0) trace.Append(Math.Round(optimization) + " ");
                }
                if (Verbose) Log("      trace: " + trace);
                Log(string.Format("      steps={0} finished={1} storage={2:N0} bytes", steps, finished, storage));
                ad.FinalizeDesign();
                if (mg.ID == "Prescriptions")
                {
                    ManualAggregation(ad, "Фармгрупа × Місяць", "Date:Month", "Medication:Group");
                    ManualAggregation(ad, "Препарат × Місяць", "Date:Month", "Medication:Medication");
                    ManualAggregation(ad, "Спеціальність × Місяць", "Date:Month", "Doctor:Specialty");
                    ManualAggregation(ad, "Клас МКХ-10 × Місяць", "Date:Month", "Disease:Chapter");
                    ManualAggregation(ad, "Препарат × Вікова категорія × Рік", "Date:Year", "Medication:Medication", "AgeGroup:AgeCategory");
                    count += 5;
                }
                foreach (Partition p in mg.Partitions) p.AggregationDesignID = ad.ID;
                Log(string.Format("   {0}: {1} aggregations, optimization {2:N0}%", mg.Name, count, optimization));
            }
            cube.Update(UpdateOptions.ExpandFull);
            Log("ProcessIndexes (building aggregations)...");
            cube.Process(ProcessType.ProcessIndexes);
        }

        static void ManualAggregation(AggregationDesign ad, string name, params string[] dimAttrs)
        {
            Aggregation agg = ad.Aggregations.Add(name, "Manual_" + ad.Aggregations.Count);
            foreach (string da in dimAttrs)
            {
                string[] p = da.Split(':');
                AggregationDimension adim = agg.Dimensions.Find(p[0]) ?? agg.Dimensions.Add(p[0]);
                adim.Attributes.Add(p[1]);
            }
        }

        static string FindCubeDim(Cube cube, Dimension dim)
        {
            foreach (CubeDimension cd in cube.Dimensions) if (cd.DimensionID == dim.ID) return cd.Name;
            return dim.Name;
        }

        long CountMembers(Cube cube, Dimension dim, DimensionAttribute a)
        {
            string table = ((ColumnBinding)a.KeyColumns[0].Source).TableID;
            DataTable t = dsv.Schema.Tables[table];
            string cols = string.Join(", ", a.KeyColumns.Cast<DataItem>().Select(k => ColumnSql(t, ((ColumnBinding)k.Source).ColumnID)));
            string from = t.ExtendedProperties.ContainsKey("QueryDefinition")
                ? "(" + t.ExtendedProperties["QueryDefinition"] + ") AS q"
                : "[" + t.ExtendedProperties["DbSchemaName"] + "].[" + t.ExtendedProperties["DbTableName"] + "]";
            return Scalar("SELECT COUNT_BIG(*) FROM (SELECT DISTINCT " + cols + " FROM " + from + ") AS x");
        }

        static string ColumnSql(DataTable t, string column)
        {
            DataColumn c = t.Columns[column];
            return c.ExtendedProperties.ContainsKey("ComputedColumnExpression")
                ? "(" + c.ExtendedProperties["ComputedColumnExpression"] + ") AS [" + column + "]"
                : "[" + column + "]";
        }

        public void Attach(string dbName)
        {
            srv = new Server();
            srv.Connect("Data Source=" + OlapServer);
            db = srv.Databases.FindByName(dbName);
            dsv = db.DataSourceViews[0];
            ds = db.DataSources[0];
            sql = new OleDbConnection(SqlConn);
            sql.Open();
        }

        public void Backup(string file)
        {
            db.Backup(file, true);
            Log("Backup: " + file);
        }
    }
}
