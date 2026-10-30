// =====================================================================
// KPI куба «Поліклініка»: значення, ціль, статус (світлофор), тренд (рік до року).
// =====================================================================
using Microsoft.AnalysisServices;

namespace PolyclinicOlap
{
    public static class Kpis
    {
        // Тренд: порівняння зі значенням за аналогічний період попереднього року
        static string Trend(string name, bool higherIsBetter)
        {
            string prev = "(KPIValue(\"" + name + "\"), ParallelPeriod([Дата].[Календар].[Рік], 1, [Дата].[Календар].CurrentMember))";
            string better = higherIsBetter ? ">" : "<";
            string worse = higherIsBetter ? "<" : ">";
            return "CASE WHEN ISEMPTY(" + prev + ") THEN 0 "
                 + "WHEN KPIValue(\"" + name + "\") " + better + " " + prev + " THEN 1 "
                 + "WHEN KPIValue(\"" + name + "\") " + worse + " " + prev + " THEN -1 ELSE 0 END";
        }

        static Kpi Add(Cube cube, string id, string name, string description, string folder, string measureGroup,
                       string value, string goal, string status, bool higherIsBetter)
        {
            Kpi k = cube.Kpis.Add(name, id);
            k.Description = description;
            k.DisplayFolder = folder;
            k.AssociatedMeasureGroupID = measureGroup;
            k.Value = value;
            k.Goal = goal;
            k.Status = status;
            k.Trend = Trend(name, higherIsBetter);
            k.StatusGraphic = "Traffic Light - Single";
            k.TrendGraphic = "Standard Arrow";
            return k;
        }

        public static void Add(Cube cube)
        {
            Add(cube, "KPI_Effectiveness", "Ефективність лікування",
                "Частка закритих випадків з одужанням або покращенням. Ціль — 80%.", "Клінічні", "Treatment",
                "[Measures].[Ефективність лікування]", "0.80",
                "CASE WHEN KPIValue(\"Ефективність лікування\") >= KPIGoal(\"Ефективність лікування\") THEN 1 "
                + "WHEN KPIValue(\"Ефективність лікування\") >= 0.75 THEN 0 ELSE -1 END", true);

            Add(cube, "KPI_WithinNorm", "Дотримання нормативу лікування",
                "Частка випадків, вилікуваних за нормативний строк. Ціль — 60%.", "Клінічні", "Treatment",
                "[Measures].[Дотримання нормативу]", "0.60",
                "CASE WHEN KPIValue(\"Дотримання нормативу лікування\") >= KPIGoal(\"Дотримання нормативу лікування\") THEN 1 "
                + "WHEN KPIValue(\"Дотримання нормативу лікування\") >= 0.50 THEN 0 ELSE -1 END", true);

            Add(cube, "KPI_NoShow", "Частка неявок",
                "Частка запланованих візитів, на які пацієнт не з'явився. Ціль — не більше 4%.", "Операційні", "Visits",
                "[Measures].[Частка неявок]", "0.04",
                "CASE WHEN KPIValue(\"Частка неявок\") <= KPIGoal(\"Частка неявок\") THEN 1 "
                + "WHEN KPIValue(\"Частка неявок\") <= 0.06 THEN 0 ELSE -1 END", false);

            Add(cube, "KPI_RevenueGrowth", "Ріст виручки",
                "Зміна виручки порівняно з аналогічним періодом попереднього року. Ціль — +5%.", "Фінансові", "Visits",
                "[Measures].[Ріст виручки YoY]", "0.05",
                "CASE WHEN ISEMPTY(KPIValue(\"Ріст виручки\")) THEN 0 "
                + "WHEN KPIValue(\"Ріст виручки\") >= KPIGoal(\"Ріст виручки\") THEN 1 "
                + "WHEN KPIValue(\"Ріст виручки\") >= 0 THEN 0 ELSE -1 END", true);
        }
    }
}
