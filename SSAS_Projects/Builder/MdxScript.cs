// =====================================================================
// MDX-скрипт куба «Поліклініка»: обчислювані міри, Time Intelligence,
// ковзне середнє, рейтинги, іменовані набори, бізнес-показники.
// =====================================================================
namespace PolyclinicOlap
{
    public static class MdxScript
    {
        public const string Text = @"CALCULATE;

/* ================== Середні показники ================== */
CREATE MEMBER CURRENTCUBE.[Measures].[Середня вартість візиту] AS
    IIF([Measures].[Проведені візити] = 0, NULL, [Measures].[Виручка] / [Measures].[Проведені візити]),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Середні показники', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Середня тривалість лікування] AS
    IIF([Measures].[Випадки лікування] = 0, NULL, [Measures].[Дні лікування] / [Measures].[Випадки лікування]),
    FORMAT_STRING = ""#,##0.0"", VISIBLE = 1, DISPLAY_FOLDER = 'Середні показники', ASSOCIATED_MEASURE_GROUP = 'Лікування';

CREATE MEMBER CURRENTCUBE.[Measures].[Середнє значення аналізу] AS
    IIF([Measures].[Кількість аналізів] = 0, NULL, [Measures].[Сума значень] / [Measures].[Кількість аналізів]),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Середні показники', ASSOCIATED_MEASURE_GROUP = 'Аналізи';

CREATE MEMBER CURRENTCUBE.[Measures].[Візитів на пацієнта] AS
    IIF([Measures].[Унікальні пацієнти] = 0, NULL, [Measures].[Кількість візитів] / [Measures].[Унікальні пацієнти]),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Середні показники', ASSOCIATED_MEASURE_GROUP = 'Візити';

/* ================== Відсоткові показники ================== */
CREATE MEMBER CURRENTCUBE.[Measures].[Рівень одужання] AS
    IIF([Measures].[Випадки лікування] = 0, NULL, [Measures].[Одужання] / [Measures].[Випадки лікування]),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Відсоткові показники', ASSOCIATED_MEASURE_GROUP = 'Лікування';

CREATE MEMBER CURRENTCUBE.[Measures].[Ефективність лікування] AS
    IIF([Measures].[Випадки лікування] = 0, NULL, [Measures].[Позитивні результати] / [Measures].[Випадки лікування]),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Відсоткові показники', ASSOCIATED_MEASURE_GROUP = 'Лікування';

CREATE MEMBER CURRENTCUBE.[Measures].[Дотримання нормативу] AS
    IIF([Measures].[Випадки лікування] = 0, NULL, [Measures].[Лікування в межах нормативу] / [Measures].[Випадки лікування]),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Відсоткові показники', ASSOCIATED_MEASURE_GROUP = 'Лікування';

CREATE MEMBER CURRENTCUBE.[Measures].[Частка неявок] AS
    IIF([Measures].[Кількість візитів] = 0, NULL, [Measures].[Неявки] / [Measures].[Кількість візитів]),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Відсоткові показники', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Частка аналізів з відхиленням] AS
    IIF([Measures].[Кількість аналізів] = 0, NULL, [Measures].[Аналізи з відхиленням] / [Measures].[Кількість аналізів]),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Відсоткові показники', ASSOCIATED_MEASURE_GROUP = 'Аналізи';

/* частка від загальної виручки (за всіма вимірами, крім часу) */
CREATE MEMBER CURRENTCUBE.[Measures].[Частка виручки] AS
    IIF(([Measures].[Виручка], Root([Лікар]), Root([Хвороба]), Root([Пацієнт]), Root([Тип візиту]), Root([Вікова група])) = 0, NULL,
        [Measures].[Виручка] / ([Measures].[Виручка], Root([Лікар]), Root([Хвороба]), Root([Пацієнт]), Root([Тип візиту]), Root([Вікова група]))),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Відсоткові показники', ASSOCIATED_MEASURE_GROUP = 'Візити';

/* ================== Time Intelligence ================== */
CREATE MEMBER CURRENTCUBE.[Measures].[Виручка YTD] AS
    AGGREGATE(YTD([Дата].[Календар].CurrentMember), [Measures].[Виручка]),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Динаміка', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Виручка PY] AS
    ([Measures].[Виручка], ParallelPeriod([Дата].[Календар].[Рік], 1, [Дата].[Календар].CurrentMember)),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Динаміка', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Ріст виручки YoY] AS
    IIF(ISEMPTY([Measures].[Виручка PY]) OR [Measures].[Виручка PY] = 0, NULL,
        ([Measures].[Виручка] - [Measures].[Виручка PY]) / [Measures].[Виручка PY]),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Динаміка', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Візити PY] AS
    ([Measures].[Кількість візитів], ParallelPeriod([Дата].[Календар].[Рік], 1, [Дата].[Календар].CurrentMember)),
    FORMAT_STRING = ""#,##0"", VISIBLE = 1, DISPLAY_FOLDER = 'Динаміка', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Ріст візитів YoY] AS
    IIF(ISEMPTY([Measures].[Візити PY]) OR [Measures].[Візити PY] = 0, NULL,
        ([Measures].[Кількість візитів] - [Measures].[Візити PY]) / [Measures].[Візити PY]),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Динаміка', ASSOCIATED_MEASURE_GROUP = 'Візити';

/* зміна до попереднього періоду того самого рівня (на рівні місяця — MoM) */
CREATE MEMBER CURRENTCUBE.[Measures].[Ріст візитів MoM] AS
    IIF([Дата].[Календар].CurrentMember.Level IS [Дата].[Календар].[Місяць]
        AND NOT ISEMPTY(([Measures].[Кількість візитів], [Дата].[Календар].CurrentMember.PrevMember)),
        ([Measures].[Кількість візитів] - ([Measures].[Кількість візитів], [Дата].[Календар].CurrentMember.PrevMember))
            / ([Measures].[Кількість візитів], [Дата].[Календар].CurrentMember.PrevMember), NULL),
    FORMAT_STRING = ""Percent"", VISIBLE = 1, DISPLAY_FOLDER = 'Динаміка', ASSOCIATED_MEASURE_GROUP = 'Візити';

/* ================== Ковзне середнє ================== */
CREATE MEMBER CURRENTCUBE.[Measures].[Ковзне середнє візитів (3 періоди)] AS
    AVG(LastPeriods(3, [Дата].[Календар].CurrentMember), [Measures].[Кількість візитів]),
    FORMAT_STRING = ""#,##0"", VISIBLE = 1, DISPLAY_FOLDER = 'Динаміка', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Ковзне середнє виручки (12 місяців)] AS
    IIF([Дата].[Календар].CurrentMember.Level IS [Дата].[Календар].[Місяць],
        AVG(LastPeriods(12, [Дата].[Календар].CurrentMember), [Measures].[Виручка]), NULL),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Динаміка', ASSOCIATED_MEASURE_GROUP = 'Візити';

/* ================== Рейтинги ================== */
CREATE DYNAMIC SET CURRENTCUBE.[Топ-10 лікарів за виручкою] AS
    TOPCOUNT([Лікар].[Лікар].[Лікар].MEMBERS, 10, [Measures].[Виручка]), DISPLAY_FOLDER = 'Рейтинги';

CREATE DYNAMIC SET CURRENTCUBE.[Топ-10 хвороб за випадками] AS
    TOPCOUNT([Хвороба].[Хвороба].[Хвороба].MEMBERS, 10, [Measures].[Випадки лікування]), DISPLAY_FOLDER = 'Рейтинги';

CREATE DYNAMIC SET CURRENTCUBE.[Топ-10 препаратів за вартістю] AS
    TOPCOUNT([Препарат].[Препарат].[Препарат].MEMBERS, 10, [Measures].[Вартість призначень]), DISPLAY_FOLDER = 'Рейтинги';

CREATE MEMBER CURRENTCUBE.[Measures].[Рейтинг лікаря за виручкою] AS
    IIF([Лікар].[Лікар].CurrentMember.Level.Ordinal = 0 OR ISEMPTY([Measures].[Виручка]), NULL,
        RANK([Лікар].[Лікар].CurrentMember,
             ORDER(NONEMPTY([Лікар].[Лікар].[Лікар].MEMBERS, [Measures].[Виручка]), [Measures].[Виручка], BDESC))),
    FORMAT_STRING = ""#,##0"", VISIBLE = 1, DISPLAY_FOLDER = 'Рейтинги', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Рейтинг хвороби за випадками] AS
    IIF([Хвороба].[Хвороба].CurrentMember.Level.Ordinal = 0 OR ISEMPTY([Measures].[Випадки лікування]), NULL,
        RANK([Хвороба].[Хвороба].CurrentMember,
             ORDER(NONEMPTY([Хвороба].[Хвороба].[Хвороба].MEMBERS, [Measures].[Випадки лікування]), [Measures].[Випадки лікування], BDESC))),
    FORMAT_STRING = ""#,##0"", VISIBLE = 1, DISPLAY_FOLDER = 'Рейтинги', ASSOCIATED_MEASURE_GROUP = 'Лікування';

/* ================== Бізнес-показники ================== */
CREATE MEMBER CURRENTCUBE.[Measures].[Виручка на годину прийому] AS
    IIF([Measures].[Хвилини прийомів] = 0, NULL, [Measures].[Виручка] / ([Measures].[Хвилини прийомів] / 60)),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Бізнес-показники', ASSOCIATED_MEASURE_GROUP = 'Візити';

CREATE MEMBER CURRENTCUBE.[Measures].[Вартість лікування на випадок] AS
    IIF([Measures].[Випадки лікування] = 0, NULL, [Measures].[Вартість лікування] / [Measures].[Випадки лікування]),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Бізнес-показники', ASSOCIATED_MEASURE_GROUP = 'Лікування';

CREATE MEMBER CURRENTCUBE.[Measures].[Перевищення нормативу (днів)] AS
    IIF([Measures].[Випадки лікування] = 0, NULL,
        ([Measures].[Дні лікування] - [Measures].[Нормативні дні лікування]) / [Measures].[Випадки лікування]),
    FORMAT_STRING = ""#,##0.0"", VISIBLE = 1, DISPLAY_FOLDER = 'Бізнес-показники', ASSOCIATED_MEASURE_GROUP = 'Лікування';

CREATE MEMBER CURRENTCUBE.[Measures].[Ліки на один візит] AS
    IIF([Measures].[Проведені візити] = 0, NULL, [Measures].[Вартість ліків за візити] / [Measures].[Проведені візити]),
    FORMAT_STRING = ""#,##0.00"", VISIBLE = 1, DISPLAY_FOLDER = 'Бізнес-показники', ASSOCIATED_MEASURE_GROUP = 'Візити';
";
    }
}
