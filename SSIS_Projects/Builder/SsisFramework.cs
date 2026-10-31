using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.SqlServer.Dts.Runtime;
using Microsoft.SqlServer.Dts.Pipeline.Wrapper;
using Microsoft.SqlServer.Dts.Tasks.ExecuteSQLTask;
using RW = Microsoft.SqlServer.Dts.Runtime.Wrapper;

namespace PolyclinicEtl
{
    public class Col
    {
        public string Name;
        public string Expr;
        public RW.DataType Type;
        public int Len, Prec, Scale, CodePage;

        public static Col Make(string name, RW.DataType type, int len, int prec, int scale, int codePage, string expr)
        {
            Col c = new Col();
            c.Name = name; c.Type = type; c.Len = len; c.Prec = prec; c.Scale = scale; c.CodePage = codePage; c.Expr = expr;
            return c;
        }
        public static Col WStr(string name, int len, string expr) { return Make(name, RW.DataType.DT_WSTR, len, 0, 0, 0, expr); }
        public static Col I4(string name, string expr)  { return Make(name, RW.DataType.DT_I4, 0, 0, 0, 0, expr); }
        public static Col I8(string name, string expr)  { return Make(name, RW.DataType.DT_I8, 0, 0, 0, 0, expr); }
        public static Col I2(string name, string expr)  { return Make(name, RW.DataType.DT_I2, 0, 0, 0, 0, expr); }
        public static Col UI1(string name, string expr) { return Make(name, RW.DataType.DT_UI1, 0, 0, 0, 0, expr); }
        public static Col Bool(string name, string expr) { return Make(name, RW.DataType.DT_BOOL, 0, 0, 0, 0, expr); }
        public static Col Date(string name, string expr) { return Make(name, RW.DataType.DT_DBDATE, 0, 0, 0, 0, expr); }
        public static Col Num(string name, int prec, int scale, string expr) { return Make(name, RW.DataType.DT_NUMERIC, 0, prec, scale, 0, expr); }
    }

    public class Agg
    {
        public string Name, Source; public int Type;
        public Agg(string name, int type, string source) { Name = name; Type = type; Source = source; }
    }

    public static class Cfg
    {
        public static string Server = ".";
        public static string OutDir;
        public static string LabRoot;
        public static string PackagesDir;
        public static bool Verbose = true;
    }

    public class Pkg
    {
        public Application App = new Application();
        public Package P;
        public ConnectionManager Oltp, Dw;
        public string FileName;
        Executable last;

        public Pkg(string fileName, string description) : this(fileName, description, false) { }

        public Pkg(string fileName, string description, bool startsRun)
        {
            FileName = fileName;
            P = new Package();
            P.Name = fileName.Replace(".dtsx", "");
            P.Description = description;
            P.ProtectionLevel = DTSProtectionLevel.DontSaveSensitive;
            P.LocaleID = 1033;
            P.CreatorName = "PolyclinicETL builder";

            Var("ServerName", Cfg.Server);
            Var("RunID", 0); Var("LogID", 0);
            Var("RowsRead", 0); Var("RowsInserted", 0); Var("RowsUpdated", 0); Var("RowsRejected", 0);

            Oltp = OleDb("OLTP_PolyclinicDB", "PolyclinicDB");
            Dw = OleDb("DW_PolyclinicDW", "PolyclinicDW");

            Executable start = Sql(P, "SQL Початок пакета", Dw,
                "EXEC etl.usp_PackageStart @PackageName = N'" + P.Name + "'", null, "RunID=User::RunID", "LogID=User::LogID");
            if (startsRun)
            {
                Executable run = Sql(P, "SQL Новий запуск ETL", Dw, "EXEC etl.usp_RunStart", null, "RunID=User::RunID");
                Link(P, run, start);
            }
            last = start;

            DtsEventHandler onError = (DtsEventHandler)P.EventHandlers.Add("OnError");
            Sql(onError, "SQL Журнал помилки", Dw, "SELECT 1",
                "\"EXEC etl.usp_LogError @LogID = \" + (DT_WSTR,12)@[User::LogID] + \", @PackageName = N'\" + @[System::PackageName] + \"'"
                + ", @SourceName = N'\" + REPLACE(@[System::SourceName], \"'\", \"''\") + \"', @ErrorCode = \" + (DT_WSTR,12)@[System::ErrorCode]"
                + " + \", @ErrorMessage = N'\" + REPLACE(LEFT(@[System::ErrorDescription], 3500), \"'\", \"''\") + \"'\"");
        }

        public ConnectionManager OleDb(string name, string database)
        {
            ConnectionManager cm = P.Connections.Add("OLEDB");
            cm.Name = name;
            cm.ConnectionString = ConnStr(Cfg.Server, database);
            cm.SetExpression("ConnectionString",
                "\"Data Source=\" + @[User::ServerName] + \";Initial Catalog=" + database
                + ";Provider=MSOLEDBSQL;Integrated Security=SSPI;Application Name=PolyclinicETL;Auto Translate=False;\"");
            return cm;
        }

        public static string ConnStr(string server, string db)
        {
            return "Data Source=" + server + ";Initial Catalog=" + db + ";Provider=MSOLEDBSQL;Integrated Security=SSPI;Application Name=PolyclinicETL;Auto Translate=False;";
        }

        public Variable Var(string name, object value)
        {
            return P.Variables.Add(name, false, "User", value);
        }

        public Variable VarExpr(string name, object value, string expression)
        {
            Variable v = P.Variables.Add(name, false, "User", value);
            v.EvaluateAsExpression = true;
            v.Expression = expression;
            return v;
        }

        public static TaskHost Sql(IDTSSequence container, string name, ConnectionManager cm, string sql, string sqlExpression, params string[] bindings)
        {
            TaskHost th = (TaskHost)container.Executables.Add("STOCK:SQLTask");
            th.Name = name;
            th.Properties["Connection"].SetValue(th, cm.ID);
            th.Properties["SqlStatementSource"].SetValue(th, sql);
            th.Properties["TimeOut"].SetValue(th, (uint)0);
            if (sqlExpression != null) th.SetExpression("SqlStatementSource", sqlExpression);
            if (bindings.Length > 0)
            {
                ExecuteSQLTask t = (ExecuteSQLTask)th.InnerObject;
                t.ResultSetType = ResultSetType.ResultSetType_SingleRow;
                foreach (string b in bindings)
                {
                    string[] parts = b.Split('=');
                    IDTSResultBinding rb = (IDTSResultBinding)t.ResultSetBindings.Add();
                    rb.ResultName = parts[0];
                    rb.DtsVariableName = parts[1];
                }
            }
            return th;
        }

        public static PrecedenceConstraint Link(IDTSSequence container, Executable from, Executable to)
        {
            return container.PrecedenceConstraints.Add(from, to);
        }

        public static PrecedenceConstraint LinkIf(IDTSSequence container, Executable from, Executable to, string expression)
        {
            PrecedenceConstraint pc = container.PrecedenceConstraints.Add(from, to);
            pc.EvalOp = DTSPrecedenceEvalOp.ExpressionAndConstraint;
            pc.Value = DTSExecResult.Success;
            pc.Expression = expression;
            return pc;
        }

        public T Then<T>(T exec) where T : Executable
        {
            Link(P, last, exec);
            last = exec;
            return exec;
        }

        public Sequence Seq(string name)
        {
            Sequence s = (Sequence)P.Executables.Add("STOCK:SEQUENCE");
            s.Name = name;
            return s;
        }

        public void Finish(string rowsReadExpr, string rowsInsertedExpr, string rowsUpdatedExpr, string rowsRejectedExpr)
        {
            Then(Sql(P, "SQL Завершення пакета", Dw, "SELECT 1",
                "\"EXEC etl.usp_PackageEnd @LogID = \" + (DT_WSTR,12)@[User::LogID]"
                + " + \", @RowsRead = \" + (DT_WSTR,12)(" + rowsReadExpr + ")"
                + " + \", @RowsInserted = \" + (DT_WSTR,12)(" + rowsInsertedExpr + ")"
                + " + \", @RowsUpdated = \" + (DT_WSTR,12)(" + rowsUpdatedExpr + ")"
                + " + \", @RowsRejected = \" + (DT_WSTR,12)(" + rowsRejectedExpr + ")"));
        }

        public void Finish()
        {
            Finish("@[User::RowsRead]", "@[User::RowsInserted]", "@[User::RowsUpdated]", "@[User::RowsRejected]");
        }

        public string Save()
        {
            string path = System.IO.Path.Combine(Cfg.PackagesDir, FileName);
            App.SaveToXml(path, P, null);
            return path;
        }
    }

    public class Flow
    {
        public TaskHost Task;
        public MainPipe MP;
        Pkg owner;
        Dictionary<int, CManagedComponentWrapper> inst = new Dictionary<int, CManagedComponentWrapper>();

        public Flow(Pkg pkg, IDTSSequence container, string name, string description)
        {
            owner = pkg;
            Task = (TaskHost)container.Executables.Add("STOCK:PipelineTask");
            Task.Name = name;
            Task.Description = description;
            MP = (MainPipe)Task.InnerObject;
            Task.Properties["DefaultBufferMaxRows"].SetValue(Task, 50000);
            Task.Properties["DefaultBufferSize"].SetValue(Task, 50 * 1024 * 1024);
        }

        CManagedComponentWrapper I(IDTSComponentMetaData100 c) { return inst[c.ID]; }

        IDTSComponentMetaData100 New(string classId, string name, string description)
        {
            if (Cfg.Verbose) Console.WriteLine("      + " + name);
            IDTSComponentMetaData100 c = MP.ComponentMetaDataCollection.New();
            c.ComponentClassID = classId;
            CManagedComponentWrapper w = c.Instantiate();
            w.ProvideComponentProperties();
            c.Name = name;
            c.Description = description ?? "";
            inst[c.ID] = w;
            return c;
        }

        void SetConn(IDTSComponentMetaData100 c, ConnectionManager cm)
        {
            c.RuntimeConnectionCollection[0].ConnectionManagerID = cm.ID;
            c.RuntimeConnectionCollection[0].ConnectionManager = DtsConvert.GetExtendedInterface(cm);
        }

        void Refresh(IDTSComponentMetaData100 c)
        {
            CManagedComponentWrapper w = I(c);
            w.AcquireConnections(null);
            w.ReinitializeMetaData();
            w.ReleaseConnections();
        }

        public IDTSOutput100 Out(IDTSComponentMetaData100 c, string outputName)
        {
            foreach (IDTSOutput100 o in c.OutputCollection) if (o.Name == outputName) return o;
            throw new Exception("Output '" + outputName + "' not found in " + c.Name);
        }

        public IDTSOutput100 Out(IDTSComponentMetaData100 c) { return Out0(c); }

        static IDTSOutput100 Out0(IDTSComponentMetaData100 c)
        {
            foreach (IDTSOutput100 o in c.OutputCollection) if (!o.IsErrorOut) return o;
            throw new Exception("No output in " + c.Name);
        }

        public IDTSOutput100 ErrorOut(IDTSComponentMetaData100 c)
        {
            foreach (IDTSOutput100 o in c.OutputCollection) if (o.IsErrorOut) return o;
            throw new Exception("No error output in " + c.Name);
        }

        void Attach(IDTSOutput100 from, IDTSInput100 to)
        {
            IDTSPath100 p = MP.PathCollection.New();
            p.AttachPathAndPropagateNotifications(from, to);
        }

        static IDTSVirtualInputColumn100 VCol(IDTSVirtualInput100 vi, string name, string owner)
        {
            foreach (IDTSVirtualInputColumn100 vc in vi.VirtualInputColumnCollection)
                if (string.Equals(vc.Name, name, StringComparison.OrdinalIgnoreCase)) return vc;
            throw new Exception("Column '" + name + "' not found in input of " + owner);
        }

        IDTSInputColumn100 Select(IDTSComponentMetaData100 c, IDTSInput100 input, string name)
        {
            IDTSVirtualInput100 vi = input.GetVirtualInput();
            IDTSVirtualInputColumn100 vc = VCol(vi, name, c.Name);
            return I(c).SetUsageType(input.ID, vi, vc.LineageID, DTSUsageType.UT_READONLY);
        }

        void SelectReferenced(IDTSComponentMetaData100 c, IDTSInput100 input, IEnumerable<string> expressions)
        {
            string all = string.Join(" ", expressions);
            IDTSVirtualInput100 vi = input.GetVirtualInput();
            foreach (IDTSVirtualInputColumn100 vc in vi.VirtualInputColumnCollection)
                if (all.IndexOf("[" + vc.Name + "]", StringComparison.OrdinalIgnoreCase) >= 0)
                    I(c).SetUsageType(input.ID, vi, vc.LineageID, DTSUsageType.UT_READONLY);
        }

        void SelectAll(IDTSComponentMetaData100 c, IDTSInput100 input)
        {
            IDTSVirtualInput100 vi = input.GetVirtualInput();
            foreach (IDTSVirtualInputColumn100 vc in vi.VirtualInputColumnCollection)
                I(c).SetUsageType(input.ID, vi, vc.LineageID, DTSUsageType.UT_READONLY);
        }

        public IDTSComponentMetaData100 Source(string name, ConnectionManager cm, string sql, string description)
        {
            IDTSComponentMetaData100 c = New("Microsoft.OLEDBSource", name, description);
            SetConn(c, cm);
            I(c).SetComponentProperty("AccessMode", 2);
            I(c).SetComponentProperty("SqlCommand", sql);
            Refresh(c);
            return c;
        }

        public IDTSComponentMetaData100 SourceFromVar(string name, ConnectionManager cm, string variable, string description)
        {
            IDTSComponentMetaData100 c = New("Microsoft.OLEDBSource", name, description);
            SetConn(c, cm);
            I(c).SetComponentProperty("AccessMode", 3);
            I(c).SetComponentProperty("SqlCommandVariable", variable);
            Refresh(c);
            return c;
        }

        public IDTSComponentMetaData100 FlatFileSource(string name, ConnectionManager ff, string description)
        {
            IDTSComponentMetaData100 c = New("Microsoft.FlatFileSource", name, description);
            SetConn(c, ff);
            I(c).SetComponentProperty("RetainNulls", true);
            Refresh(c);
            return c;
        }

        public IDTSComponentMetaData100 Derived(string name, IDTSOutput100 up, string description, params Col[] cols)
        {
            IDTSComponentMetaData100 c = New("Microsoft.DerivedColumn", name, description);
            Attach(up, c.InputCollection[0]);
            SelectReferenced(c, c.InputCollection[0], cols.Select(x => x.Expr));
            IDTSOutput100 output = Out0(c);
            foreach (Col col in cols)
            {
                IDTSOutputColumn100 oc = output.OutputColumnCollection.New();
                oc.Name = col.Name;
                oc.SetDataTypeProperties(col.Type, col.Len, col.Prec, col.Scale, col.CodePage);
                oc.ErrorRowDisposition = DTSRowDisposition.RD_FailComponent;
                oc.TruncationRowDisposition = DTSRowDisposition.RD_FailComponent;
                IDTSCustomProperty100 e = oc.CustomPropertyCollection.New();
                e.Name = "Expression"; e.Value = col.Expr;
                IDTSCustomProperty100 f = oc.CustomPropertyCollection.New();
                f.Name = "FriendlyExpression"; f.Value = col.Expr;
            }
            return c;
        }

        public IDTSComponentMetaData100 Convert(string name, IDTSOutput100 up, bool redirectErrors, string description, params Col[] cols)
        {
            IDTSComponentMetaData100 c = New("Microsoft.DataConvert", name, description);
            Attach(up, c.InputCollection[0]);
            IDTSOutput100 output = Out0(c);
            int i = 0;
            foreach (Col col in cols)
            {
                IDTSInputColumn100 ic = Select(c, c.InputCollection[0], col.Expr);
                IDTSOutputColumn100 oc = I(c).InsertOutputColumnAt(output.ID, i++, col.Name, "");
                I(c).SetOutputColumnProperty(output.ID, oc.ID, "SourceInputColumnLineageID", ic.LineageID);
                I(c).SetOutputColumnDataTypeProperties(output.ID, oc.ID, col.Type, col.Len, col.Prec, col.Scale, col.CodePage);
                DTSRowDisposition d = redirectErrors ? DTSRowDisposition.RD_RedirectRow : DTSRowDisposition.RD_FailComponent;
                oc.ErrorRowDisposition = d;
                oc.TruncationRowDisposition = d;
            }
            return c;
        }

        public IDTSComponentMetaData100 Lookup(string name, IDTSOutput100 up, ConnectionManager cm, string sql, string[] joins,
                                               int noMatch, string description, params Col[] outs)
        {
            IDTSComponentMetaData100 c = New("Microsoft.Lookup", name, description);
            SetConn(c, cm);
            I(c).SetComponentProperty("SqlCommand", sql);
            I(c).SetComponentProperty("CacheType", 0);
            I(c).SetComponentProperty("NoMatchBehavior", noMatch);
            Attach(up, c.InputCollection[0]);
            Refresh(c);
            IDTSInput100 input = c.InputCollection[0];
            foreach (string j in joins)
            {
                string[] p = j.Split('=');
                IDTSInputColumn100 ic = Select(c, input, p[0]);
                I(c).SetInputColumnProperty(input.ID, ic.ID, "JoinToReferenceColumn", p[1]);
            }
            IDTSOutput100 match = Out(c, "Lookup Match Output");
            int i = 0;
            foreach (Col o in outs)
            {
                IDTSOutputColumn100 oc = I(c).InsertOutputColumnAt(match.ID, i++, o.Name, "");
                oc.SetDataTypeProperties(o.Type, o.Len, o.Prec, o.Scale, o.CodePage);
                I(c).SetOutputColumnProperty(match.ID, oc.ID, "CopyFromReferenceColumn", o.Expr);
            }
            return c;
        }

        public IDTSComponentMetaData100 Split(string name, IDTSOutput100 up, string defaultName, string description, params string[] pairs)
        {
            IDTSComponentMetaData100 c = New("Microsoft.ConditionalSplit", name, description);
            Attach(up, c.InputCollection[0]);
            SelectReferenced(c, c.InputCollection[0], pairs.Where((x, i) => i % 2 == 1));
            IDTSOutput100 def = null;
            foreach (IDTSOutput100 o in c.OutputCollection)
                if (!o.IsErrorOut) def = o;
            def.Name = defaultName;
            for (int i = 0; i < pairs.Length; i += 2)
            {
                IDTSOutput100 o = I(c).InsertOutput(DTSInsertPlacement.IP_BEFORE, def.ID);
                o.Name = pairs[i];
                o.Description = pairs[i];
                I(c).SetOutputProperty(o.ID, "Expression", pairs[i + 1]);
                I(c).SetOutputProperty(o.ID, "FriendlyExpression", pairs[i + 1]);
                I(c).SetOutputProperty(o.ID, "EvaluationOrder", i / 2);
            }
            return c;
        }

        public IDTSComponentMetaData100 Multicast(string name, IDTSOutput100 up, int outputs, string description)
        {
            IDTSComponentMetaData100 c = New("Microsoft.Multicast", name, description);
            Attach(up, c.InputCollection[0]);
            IDTSOutput100 first = Out0(c);
            first.Name = "Multicast Output 1";
            IDTSOutput100 prev = first;
            for (int i = 1; i < outputs; i++)
            {
                prev = I(c).InsertOutput(DTSInsertPlacement.IP_AFTER, prev.ID);
                prev.Name = "Multicast Output " + (i + 1);
            }
            return c;
        }

        public IDTSOutput100 OutAt(IDTSComponentMetaData100 c, int index)
        {
            int i = 0;
            foreach (IDTSOutput100 o in c.OutputCollection)
            {
                if (o.IsErrorOut) continue;
                if (i++ == index) return o;
            }
            throw new Exception("Output #" + index + " not found in " + c.Name);
        }

        public IDTSComponentMetaData100 Sort(string name, IDTSOutput100 up, bool dedupe, string description, params string[] keys)
        {
            IDTSComponentMetaData100 c = New("Microsoft.Sort", name, description);
            I(c).SetComponentProperty("EliminateDuplicates", dedupe);
            Attach(up, c.InputCollection[0]);
            IDTSInput100 input = c.InputCollection[0];
            SelectAll(c, input);
            int pos = 1;
            foreach (string k in keys)
            {
                foreach (IDTSInputColumn100 ic in input.InputColumnCollection)
                    if (string.Equals(ic.Name, k, StringComparison.OrdinalIgnoreCase))
                        I(c).SetInputColumnProperty(input.ID, ic.ID, "NewSortKeyPosition", pos++);
            }
            return c;
        }

        public IDTSComponentMetaData100 Aggregate(string name, IDTSOutput100 up, string description, params Agg[] aggs)
        {
            IDTSComponentMetaData100 c = New("Microsoft.Aggregate", name, description);
            Attach(up, c.InputCollection[0]);
            IDTSInput100 input = c.InputCollection[0];
            IDTSOutput100 output = Out0(c);
            int i = 0;
            foreach (Agg a in aggs)
            {
                int lineage = 0;
                if (a.Source != null)
                {
                    IDTSInputColumn100 ic = null;
                    foreach (IDTSInputColumn100 x in input.InputColumnCollection)
                        if (x.Name == a.Source) ic = x;
                    if (ic == null) ic = Select(c, input, a.Source);
                    lineage = ic.LineageID;
                }
                IDTSOutputColumn100 oc = I(c).InsertOutputColumnAt(output.ID, i++, a.Name, "");
                I(c).SetOutputColumnProperty(output.ID, oc.ID, "AggregationColumnId", lineage);
                I(c).SetOutputColumnProperty(output.ID, oc.ID, "AggregationType", a.Type);
            }
            return c;
        }

        public IDTSComponentMetaData100 Union(string name, string[] columns, string description, params IDTSOutput100[] ups)
        {
            IDTSComponentMetaData100 c = New("Microsoft.UnionAll", name, description);
            IDTSOutput100 output = Out0(c);
            Dictionary<string, int> outLineage = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            for (int n = 0; n < ups.Length; n++)
            {
                IDTSInput100 input = null;
                foreach (IDTSInput100 x in c.InputCollection) if (!x.IsAttached) { input = x; break; }
                if (input == null) input = c.InputCollection.New();
                Attach(ups[n], input);
                IDTSVirtualInput100 vi = input.GetVirtualInput();
                foreach (IDTSVirtualInputColumn100 vc in vi.VirtualInputColumnCollection)
                {
                    if (columns != null && !columns.Contains(vc.Name, StringComparer.OrdinalIgnoreCase)) continue;
                    if (n > 0 && !outLineage.ContainsKey(vc.Name)) continue;
                    IDTSInputColumn100 ic = I(c).SetUsageType(input.ID, vi, vc.LineageID, DTSUsageType.UT_READONLY);
                    IDTSCustomProperty100 prop = ic.CustomPropertyCollection["OutputColumnLineageID"];
                    int current = System.Convert.ToInt32(prop.Value);
                    if (n == 0)
                    {
                        if (current <= 0)
                        {
                            IDTSOutputColumn100 oc = output.OutputColumnCollection.New();
                            oc.Name = vc.Name;
                            oc.SetDataTypeProperties(vc.DataType, vc.Length, vc.Precision, vc.Scale, vc.CodePage);
                            prop.Value = oc.LineageID;
                            current = oc.LineageID;
                        }
                        outLineage[vc.Name] = current;
                    }
                    else if (current != outLineage[vc.Name])
                    {
                        prop.Value = outLineage[vc.Name];
                        foreach (IDTSOutputColumn100 oc in output.OutputColumnCollection)
                            if (oc.LineageID == current && !outLineage.ContainsValue(current))
                            {
                                output.OutputColumnCollection.RemoveObjectByID(oc.ID);
                                break;
                            }
                    }
                }
            }
            if (columns != null)
            {
                List<IDTSOutputColumn100> extra = new List<IDTSOutputColumn100>();
                foreach (IDTSOutputColumn100 oc in output.OutputColumnCollection)
                    if (!columns.Contains(oc.Name, StringComparer.OrdinalIgnoreCase)) extra.Add(oc);
                foreach (IDTSOutputColumn100 oc in extra)
                {
                    foreach (IDTSInput100 input in c.InputCollection)
                    {
                        IDTSVirtualInput100 vi = input.GetVirtualInput();
                        List<int> lineages = new List<int>();
                        foreach (IDTSInputColumn100 ic in input.InputColumnCollection)
                            if (System.Convert.ToInt32(ic.CustomPropertyCollection["OutputColumnLineageID"].Value) == oc.LineageID)
                                lineages.Add(ic.LineageID);
                        foreach (int l in lineages)
                            I(c).SetUsageType(input.ID, vi, l, DTSUsageType.UT_IGNORED);
                    }
                    output.OutputColumnCollection.RemoveObjectByID(oc.ID);
                }
            }
            return c;
        }

        public IDTSComponentMetaData100 RowCount(string name, IDTSOutput100 up, string variable, string description)
        {
            IDTSComponentMetaData100 c = New("Microsoft.RowCount", name, description);
            I(c).SetComponentProperty("VariableName", variable);
            Attach(up, c.InputCollection[0]);
            return c;
        }

        public IDTSComponentMetaData100 Dest(string name, IDTSOutput100 up, ConnectionManager cm, string table, string description)
        {
            IDTSComponentMetaData100 c = New("Microsoft.OLEDBDestination", name, description);
            SetConn(c, cm);
            I(c).SetComponentProperty("AccessMode", 3);
            I(c).SetComponentProperty("OpenRowset", table);
            I(c).SetComponentProperty("FastLoadOptions", "TABLOCK,CHECK_CONSTRAINTS");
            I(c).SetComponentProperty("FastLoadMaxInsertCommitSize", 100000);
            Refresh(c);
            Attach(up, c.InputCollection[0]);
            IDTSInput100 input = c.InputCollection[0];
            IDTSVirtualInput100 vi = input.GetVirtualInput();
            List<string> unmapped = new List<string>();
            foreach (IDTSExternalMetadataColumn100 ext in input.ExternalMetadataColumnCollection)
            {
                IDTSVirtualInputColumn100 match = null;
                foreach (IDTSVirtualInputColumn100 vc in vi.VirtualInputColumnCollection)
                    if (string.Equals(vc.Name, ext.Name, StringComparison.OrdinalIgnoreCase)) match = vc;
                if (match == null) { unmapped.Add(ext.Name); continue; }
                IDTSInputColumn100 ic = I(c).SetUsageType(input.ID, vi, match.LineageID, DTSUsageType.UT_READONLY);
                I(c).MapInputColumn(input.ID, ic.ID, ext.ID);
            }
            if (unmapped.Count > 0)
                Console.WriteLine("   [" + c.Name + "] not mapped: " + string.Join(", ", unmapped));
            return c;
        }
    }
}
