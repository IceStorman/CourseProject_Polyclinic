using System;
using System.CodeDom.Compiler;
using System.IO;
using System.IO.Compression;
using System.Text;
using Microsoft.SqlServer.Dts.Runtime;
using Microsoft.SqlServer.Dts.Tasks.ScriptTask;
using Microsoft.SqlServer.VSTAHosting;

namespace PolyclinicEtl
{
    public static class ScriptTaskFactory
    {
        const string TemplatePath = @"C:\Program Files (x86)\Microsoft SQL Server\160\DTS\Binn\VSTA_SQL16_IS_ST_CS_Template.vstax";

        public static TaskHost Create(IDTSSequence container, string name, string description,
                                      string readOnlyVars, string readWriteVars, string body)
        {
            TaskHost th = (TaskHost)container.Executables.Add("STOCK:ScriptTask");
            th.Name = name;
            th.Description = description;
            ScriptTask task = (ScriptTask)th.InnerObject;
            task.ScriptLanguage = "Microsoft Visual C# 2019";
            task.ReadOnlyVariables = readOnlyVars;
            task.ReadWriteVariables = readWriteVars;
            string project = task.ScriptProjectName;

            string scriptMain =
                "#region Namespaces\r\nusing System;\r\nusing System.Data;\r\nusing System.IO;\r\nusing System.Text;\r\nusing Microsoft.SqlServer.Dts.Runtime;\r\n#endregion\r\n\r\n"
                + "namespace " + project + "\r\n{\r\n"
                + "    /// <summary>\r\n    /// " + description + "\r\n    /// </summary>\r\n"
                + "    [Microsoft.SqlServer.Dts.Tasks.ScriptTask.SSISScriptTaskEntryPointAttribute]\r\n"
                + "    public partial class ScriptMain : Microsoft.SqlServer.Dts.Tasks.ScriptTask.VSTARTScriptObjectModelBase\r\n    {\r\n"
                + "        public void Main()\r\n        {\r\n" + body + "\r\n        }\r\n\r\n"
                + "        #region ScriptResults declaration\r\n"
                + "        enum ScriptResults\r\n        {\r\n"
                + "            Success = Microsoft.SqlServer.Dts.Runtime.DTSExecResult.Success,\r\n"
                + "            Failure = Microsoft.SqlServer.Dts.Runtime.DTSExecResult.Failure\r\n        };\r\n"
                + "        #endregion\r\n    }\r\n}\r\n";

            VSTAScriptProjectStorage storage = task.ScriptStorage;
            using (ZipArchive zip = ZipFile.OpenRead(TemplatePath))
            {
                AddFromTemplate(storage, zip, "IS%20Script%20Task%20Project.csproj", project + ".csproj", project);
                AddFromTemplate(storage, zip, "AssemblyInfo.cs", @"Properties\AssemblyInfo.cs", project);
                AddFromTemplate(storage, zip, "Resources.resx", @"Properties\Resources.resx", project);
                AddFromTemplate(storage, zip, "Resources.Designer.cs", @"Properties\Resources.Designer.cs", project);
                AddFromTemplate(storage, zip, "Settings.settings", @"Properties\Settings.settings", project);
                AddFromTemplate(storage, zip, "Settings.Designer.cs", @"Properties\Settings.Designer.cs", project);
            }
            storage.ScriptFiles["ScriptMain.cs"] = new VSTAScriptProjectStorage.VSTAScriptFile(VSTAScriptProjectStorage.Encoding.UTF8, scriptMain);
            storage.AssemblyName = project;
            storage.AssemblyCode = Compile(project, scriptMain);
            return th;
        }

        static void AddFromTemplate(VSTAScriptProjectStorage storage, ZipArchive zip, string entry, string target, string project)
        {
            string text;
            using (StreamReader r = new StreamReader(zip.GetEntry(entry).Open(), Encoding.UTF8))
                text = r.ReadToEnd();
            text = text.Replace("$safeprojectname$", project).Replace("$projectname$", project)
                       .Replace("$guid1$", Guid.NewGuid().ToString()).Replace("$guid2$", Guid.NewGuid().ToString())
                       .Replace("$registeredorganization$", "NULP").Replace("$year$", "2026")
                       .Replace("$safeprojectname", project);
            storage.ScriptFiles[target] = new VSTAScriptProjectStorage.VSTAScriptFile(VSTAScriptProjectStorage.Encoding.UTF8, text);
        }

        static byte[] Compile(string project, string scriptMain)
        {
            string v = "Version=16.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91";
            CompilerParameters cp = new CompilerParameters();
            cp.GenerateExecutable = false;
            cp.OutputAssembly = Path.Combine(Path.GetTempPath(), project + ".dll");
            cp.ReferencedAssemblies.Add("System.dll");
            cp.ReferencedAssemblies.Add("System.Data.dll");
            cp.ReferencedAssemblies.Add("System.Xml.dll");
            cp.ReferencedAssemblies.Add(System.Reflection.Assembly.Load("Microsoft.SqlServer.ManagedDTS, " + v).Location);
            cp.ReferencedAssemblies.Add(System.Reflection.Assembly.Load("Microsoft.SqlServer.ScriptTask, " + v).Location);
            string assemblyInfo = "using System.Reflection;\r\n[assembly: AssemblyTitle(\"" + project + "\")]\r\n[assembly: AssemblyVersion(\"1.0.0.0\")]\r\n";
            using (Microsoft.CSharp.CSharpCodeProvider provider = new Microsoft.CSharp.CSharpCodeProvider())
            {
                CompilerResults res = provider.CompileAssemblyFromSource(cp, scriptMain, assemblyInfo);
                if (res.Errors.HasErrors)
                {
                    StringBuilder sb = new StringBuilder("Script compile errors:");
                    foreach (CompilerError e in res.Errors) sb.AppendLine().Append(e.ToString());
                    throw new Exception(sb.ToString());
                }
            }
            byte[] bytes = File.ReadAllBytes(cp.OutputAssembly);
            File.Delete(cp.OutputAssembly);
            return bytes;
        }
    }
}
