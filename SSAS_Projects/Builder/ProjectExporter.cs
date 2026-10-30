// =====================================================================
// Експорт розгорнутої бази SSAS у проєкт Visual Studio
// (Analysis Services Multidimensional Project: .dwproj, .ds, .dsv, .dim, .cube, .partitions).
// =====================================================================
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using Microsoft.AnalysisServices;

namespace PolyclinicOlap
{
    public static class ProjectExporter
    {
        static readonly XNamespace Eng = "http://schemas.microsoft.com/analysisservices/2003/engine";

        static XDocument Serialize(MajorObject obj)
        {
            StringBuilder sb = new StringBuilder();
            using (XmlWriter w = XmlWriter.Create(sb, new XmlWriterSettings { Indent = true, OmitXmlDeclaration = true }))
                Utils.Serialize(w, obj, false);
            XDocument doc = XDocument.Parse(sb.ToString());
            // службові позначки стану сервера не потрібні у вихідних файлах проєкту
            foreach (string n in new[] { "CreatedTimestamp", "LastSchemaUpdate", "LastProcessed", "State", "LastUpdate", "CurrentStorageMode" })
                doc.Root.Elements(Eng + n).Remove();
            return doc;
        }

        static void Save(XDocument doc, string path)
        {
            XmlWriterSettings s = new XmlWriterSettings { Indent = true, Encoding = new UTF8Encoding(true) };
            using (XmlWriter w = XmlWriter.Create(path, s)) doc.Save(w);
        }

        public static void Export(string serverName, string dbName, string projectDir)
        {
            Server srv = new Server();
            srv.Connect("Data Source=" + serverName);
            try
            {
                Database db = srv.Databases.FindByName(dbName);
                Directory.CreateDirectory(projectDir);
                string proj = "PolyclinicOLAP";

                // .database
                XDocument dbDoc = Serialize(db);
                foreach (string n in new[] { "Dimensions", "Cubes", "DataSources", "DataSourceViews", "Roles", "Assemblies", "MiningStructures", "Accounts", "DatabasePermissions" })
                    dbDoc.Root.Elements(Eng + n).Remove();
                Save(dbDoc, Path.Combine(projectDir, proj + ".database"));

                StringBuilder items = new StringBuilder();
                Func<string, string> item = f => "    <ProjectItem>\r\n      <Name>" + f + "</Name>\r\n      <FullPath>" + f + "</FullPath>\r\n    </ProjectItem>\r\n";

                string dsXml = "", dsvXml = "", dimXml = "", cubeXml = "";
                foreach (DataSource ds in db.DataSources)
                {
                    string f = ds.ID + ".ds";
                    Save(Serialize(ds), Path.Combine(projectDir, f));
                    dsXml += item(f);
                }
                foreach (DataSourceView v in db.DataSourceViews)
                {
                    string f = v.ID + ".dsv";
                    Save(Serialize(v), Path.Combine(projectDir, f));
                    dsvXml += item(f);
                }
                foreach (Dimension d in db.Dimensions)
                {
                    string f = d.ID + ".dim";
                    Save(Serialize(d), Path.Combine(projectDir, f));
                    dimXml += item(f);
                }
                foreach (Cube c in db.Cubes)
                {
                    XDocument cubeDoc = Serialize(c);
                    // .partitions — лише партиції та дизайни агрегацій груп мір
                    XElement partsRoot = new XElement(cubeDoc.Root.Name, cubeDoc.Root.Attributes(),
                        cubeDoc.Root.Element(Eng + "ID"), cubeDoc.Root.Element(Eng + "Name"),
                        new XElement(Eng + "MeasureGroups",
                            cubeDoc.Root.Element(Eng + "MeasureGroups").Elements(Eng + "MeasureGroup").Select(mg =>
                                new XElement(Eng + "MeasureGroup", mg.Element(Eng + "ID"), mg.Element(Eng + "Name"),
                                    mg.Element(Eng + "Partitions"), mg.Element(Eng + "AggregationDesigns")))));
                    foreach (XElement mg in cubeDoc.Root.Element(Eng + "MeasureGroups").Elements(Eng + "MeasureGroup"))
                    {
                        mg.Elements(Eng + "Partitions").Remove();
                        mg.Elements(Eng + "AggregationDesigns").Remove();
                    }
                    string fc = c.ID + ".cube", fp = c.ID + ".partitions";
                    Save(cubeDoc, Path.Combine(projectDir, fc));
                    Save(new XDocument(partsRoot), Path.Combine(projectDir, fp));
                    cubeXml += "    <ProjectItem>\r\n      <Name>" + fc + "</Name>\r\n      <FullPath>" + fc + "</FullPath>\r\n"
                             + "      <Dependencies>\r\n        <ProjectItem>\r\n          <Name>" + fp + "</Name>\r\n          <FullPath>" + fp
                             + "</FullPath>\r\n        </ProjectItem>\r\n      </Dependencies>\r\n    </ProjectItem>\r\n";
                }

                string dwproj =
@"<?xml version=""1.0"" encoding=""utf-8""?>
<Project xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"">
  <ProductVersion>15.0.2000.0</ProductVersion>
  <SchemaVersion>9.0.4.10</SchemaVersion>
  <Database>
    <Name>" + proj + @".database</Name>
    <FullPath>" + proj + @".database</FullPath>
  </Database>
  <Cubes>
" + cubeXml + @"  </Cubes>
  <Dimensions>
" + dimXml + @"  </Dimensions>
  <DataSources>
" + dsXml + @"  </DataSources>
  <DataSourceViews>
" + dsvXml + @"  </DataSourceViews>
  <MiningModels />
  <Roles />
  <Assemblies />
  <Configurations>
    <Configuration>
      <Name>Development</Name>
      <Options>
        <ConnectionString>Data Source=localhost</ConnectionString>
        <Database>" + dbName + @"</Database>
        <ProcessingOption>Default</ProcessingOption>
      </Options>
    </Configuration>
  </Configurations>
</Project>
";
                File.WriteAllText(Path.Combine(projectDir, proj + ".dwproj"), dwproj, new UTF8Encoding(true));
                Console.WriteLine("Project exported: " + projectDir);
            }
            finally
            {
                srv.Disconnect();
            }
        }
    }
}
