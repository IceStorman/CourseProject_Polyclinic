# -*- coding: utf-8 -*-
"""
Курсова робота NVBD, варіант 6 «Поліклініка».
Бібліотека для створення звітів SSRS (RDL 2016): джерела та набори даних (SQL, MDX),
параметри, текстові поля, таблиці з групуванням, матриці, діаграми, датчики, індикатори,
вкладені звіти. Звіти описуються в reports.py.
"""
import uuid
from xml.sax.saxutils import escape

RDL_NS = ('xmlns="http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition" '
          'xmlns:rd="http://schemas.microsoft.com/SQLServer/reporting/reportdesigner" '
          'xmlns:df="http://schemas.microsoft.com/sqlserver/reporting/2016/01/reportdefinition/defaultfontfamily" '
          'MustUnderstand="df"')

# Кольори оформлення
DARK = "#1F4E79"
MID = "#D6E4F0"
LIGHT = "#EEF3F9"
GRID = "#BFBFBF"


def esc(s):
    return escape(str(s), {'"': "&quot;"})


def cm(v):
    return f"{v:g}cm"


def guid():
    return str(uuid.uuid4())


class Report:
    def __init__(self, name, title, description, landscape=True):
        self.name = name
        self.title = title
        self.description = description
        self.landscape = landscape
        self.page_w = 29.7 if landscape else 21.0
        self.page_h = 21.0 if landscape else 29.7
        self.margin = 1.2
        self.body_w = self.page_w - 2 * self.margin
        self.n = 0
        self.sources = []
        self.datasets = []
        self.params = []
        self.items = []
        self.body_h = 1.0
        self.code = None

    def nm(self, prefix):
        self.n += 1
        return f"{prefix}{self.n}"

    # ------------------------------------------------------------------ дані
    def source(self, name):
        if name not in self.sources:
            self.sources.append(name)

    def ds_sql(self, name, source, query, fields, params=None, filters=None):
        """fields: [(назва, тип .NET)], params: {"@Param": "=вираз"}"""
        self.source(source)
        qp = "".join(f'<QueryParameter Name="{esc(k)}"><Value>{esc(v)}</Value></QueryParameter>'
                     for k, v in (params or {}).items())
        fl = "".join(f'<Field Name="{esc(f)}"><DataField>{esc(f)}</DataField><rd:TypeName>{t}</rd:TypeName></Field>'
                     for f, t in fields)
        self.datasets.append(
            f'<DataSet Name="{esc(name)}"><Query><DataSourceName>{esc(source)}</DataSourceName>'
            + (f"<QueryParameters>{qp}</QueryParameters>" if qp else "")
            + f"<CommandText>{esc(query)}</CommandText></Query><Fields>{fl}</Fields>"
            + self._filters(filters) + "</DataSet>")

    def ds_mdx(self, name, query, fields, params=None, filters=None, source="PolyclinicOLAP"):
        """fields: [(назва, "Level"|"Measure", UniqueName)]; параметри MDX — без «@» в назві"""
        self.source(source)
        qp = "".join(f'<QueryParameter Name="{esc(k)}"><Value>{esc(v)}</Value></QueryParameter>'
                     for k, v in (params or {}).items())
        fl = ""
        for f, kind, un in fields:
            df = ('<?xml version="1.0" encoding="utf-8"?><Field xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                  f'xsi:type="{kind}" UniqueName="{un}" />')
            fl += f'<Field Name="{esc(f)}"><DataField>{esc(df)}</DataField></Field>'
        self.datasets.append(
            f'<DataSet Name="{esc(name)}"><Query><DataSourceName>{esc(source)}</DataSourceName>'
            + (f"<QueryParameters>{qp}</QueryParameters>" if qp else "")
            + f"<CommandText>{esc(query)}</CommandText></Query><Fields>{fl}</Fields>"
            + self._filters(filters) + "</DataSet>")

    @staticmethod
    def _filters(filters):
        if not filters:
            return ""
        x = ""
        for expr, op, val in filters:
            x += (f"<Filter><FilterExpression>{esc(expr)}</FilterExpression><Operator>{op}</Operator>"
                  f"<FilterValues><FilterValue>{esc(val)}</FilterValue></FilterValues></Filter>")
        return f"<Filters>{x}</Filters>"

    def param(self, name, prompt, dtype="String", default=None, default_ds=None, multi=False, values_ds=None,
              static_values=None, hidden=False, nullable=False, allow_blank=False):
        """default: значення або список; default_ds: (набір, поле); values_ds: (набір, поле значення, поле назви)"""
        x = f'<ReportParameter Name="{name}"><DataType>{dtype}</DataType>'
        if nullable:
            x += "<Nullable>true</Nullable>"
        if allow_blank:
            x += "<AllowBlank>true</AllowBlank>"
        if default_ds:
            x += (f"<DefaultValue><DataSetReference><DataSetName>{default_ds[0]}</DataSetName>"
                  f"<ValueField>{default_ds[1]}</ValueField></DataSetReference></DefaultValue>")
        elif default is not None:
            vals = default if isinstance(default, list) else [default]
            x += "<DefaultValue><Values>" + "".join(f"<Value>{esc(v)}</Value>" for v in vals) + "</Values></DefaultValue>"
        x += f"<Prompt>{esc(prompt)}</Prompt>"
        if values_ds:
            x += (f"<ValidValues><DataSetReference><DataSetName>{values_ds[0]}</DataSetName>"
                  f"<ValueField>{values_ds[1]}</ValueField><LabelField>{values_ds[2]}</LabelField>"
                  f"</DataSetReference></ValidValues>")
        elif static_values:
            x += "<ValidValues><ParameterValues>" + "".join(
                f"<ParameterValue><Value>{esc(v)}</Value><Label>{esc(l)}</Label></ParameterValue>"
                for v, l in static_values) + "</ParameterValues></ValidValues>"
        if multi:
            x += "<MultiValue>true</MultiValue>"
        if hidden:
            x += "<Hidden>true</Hidden>"
        x += "</ReportParameter>"
        self.params.append(x)

    # --------------------------------------------------------- елементи звіту
    def tb(self, value, name=None, fmt=None, bold=False, size=9, color=None, bg=None, align=None, border=True,
           pos=None, sort=None, toggle=None, action=None, tooltip=None, italic=False, hidden=None, valign="Middle",
           padding=2, can_grow=True, colspan=None, docmap=None, font="Segoe UI"):
        name = name or self.nm("tb")
        v = esc(value)
        run_style = f"<FontFamily>{font}</FontFamily><FontSize>{size}pt</FontSize>"
        if bold:
            run_style += f"<FontWeight>{esc(bold) if isinstance(bold, str) else 'Bold'}</FontWeight>"
        if italic:
            run_style += "<FontStyle>Italic</FontStyle>"
        if fmt:
            run_style += f"<Format>{esc(fmt)}</Format>"
        if color:
            run_style += f"<Color>{esc(color)}</Color>"
        par_style = f"<TextAlign>{align}</TextAlign>" if align else ""
        box = ""
        if border:
            box += f"<Border><Color>{GRID}</Color><Style>Solid</Style></Border>"
        if bg:
            box += f"<BackgroundColor>{esc(bg)}</BackgroundColor>"
        box += (f"<VerticalAlign>{valign}</VerticalAlign><PaddingLeft>{padding}pt</PaddingLeft>"
                f"<PaddingRight>{padding}pt</PaddingRight><PaddingTop>1pt</PaddingTop><PaddingBottom>1pt</PaddingBottom>")
        x = (f'<Textbox Name="{name}"><CanGrow>{"true" if can_grow else "false"}</CanGrow><KeepTogether>true</KeepTogether>'
             f"<Paragraphs><Paragraph><TextRuns><TextRun><Value>{v}</Value><Style>{run_style}</Style></TextRun></TextRuns>"
             f"<Style>{par_style}</Style></Paragraph></Paragraphs>")
        if sort:
            x += f"<UserSort><SortExpression>{esc(sort)}</SortExpression></UserSort>"
        if toggle is not None:
            x += f"<ToggleImage><InitialState>{'true' if toggle else 'false'}</InitialState></ToggleImage>"
        if action:
            x += action
        if tooltip:
            x += f"<ToolTip>{esc(tooltip)}</ToolTip>"
        if docmap:
            x += f"<DocumentMapLabel>{esc(docmap)}</DocumentMapLabel>"
        if hidden:
            x += f"<Visibility><Hidden>{esc(hidden)}</Hidden></Visibility>"
        if pos:
            x += self._pos(pos)
        x += f"<Style>{box}</Style></Textbox>"
        return x

    @staticmethod
    def _pos(pos):
        top, left, w, h = pos
        return f"<Top>{cm(top)}</Top><Left>{cm(left)}</Left><Height>{cm(h)}</Height><Width>{cm(w)}</Width>"

    @staticmethod
    def drillthrough(report, params):
        p = "".join(f'<Parameter Name="{k}"><Value>{esc(v)}</Value></Parameter>' for k, v in params.items())
        return (f"<ActionInfo><Actions><Action><Drillthrough><ReportName>{esc(report)}</ReportName>"
                f"<Parameters>{p}</Parameters></Drillthrough></Action></Actions></ActionInfo>")

    def add(self, xml, bottom):
        self.items.append(xml)
        self.body_h = max(self.body_h, bottom)

    def title_block(self, subtitle_expr=None, top=0):
        self.add(self.tb(self.title, size=16, bold=True, color=DARK, border=False, pos=(top, 0, self.body_w, 0.9),
                         padding=0), top + 0.9)
        if subtitle_expr:
            self.add(self.tb(subtitle_expr, size=9, color="#595959", border=False,
                             pos=(top + 0.9, 0, self.body_w, 0.6), padding=0), top + 1.5)
        return top + (1.6 if subtitle_expr else 1.0)

    # ------------------------------------------------------------ таблиця
    def table(self, name, dataset, widths, header, groups, details, total=None, pos=(0, 0), hidden=None,
              no_rows="Немає даних за вибраними параметрами", detail_sort=None, keep_header=True, detail_hidden_by=None,
              detail_expanded=False):
        """
        header / details / total: список рядків; рядок — список комірок (xml текстового поля або (xml, colspan))
        groups: [{"name","expr","sort","rows":[рядок...],"docmap","pagebreak","toggle_by": textbox, "hidden": bool}]
        Групи вкладені одна в одну; деталі — найглибший рівень (detail_hidden_by: textbox-перемикач).
        """
        ncols = len(widths)
        rows_xml = []

        def row_xml(row, height=0.6):
            cells = ""
            used = 0
            for c in row:
                xml, span = (c if isinstance(c, tuple) else (c, 1))
                cells += "<TablixCell><CellContents>" + xml + (f"<ColSpan>{span}</ColSpan>" if span > 1 else "") \
                         + "</CellContents></TablixCell>"
                cells += "<TablixCell />" * (span - 1)
                used += span
            if used != ncols:
                raise ValueError(f"{name}: row has {used} cells, expected {ncols}")
            return f"<TablixRow><Height>{cm(height)}</Height><TablixCells>{cells}</TablixCells></TablixRow>"

        def static_members(rows, keep, repeat=False):
            m = ""
            for r in rows:
                rows_xml.append(row_xml(r))
                m += ("<TablixMember>" + (f"<KeepWithGroup>{keep}</KeepWithGroup>" if keep else "")
                      + ("<RepeatOnNewPage>true</RepeatOnNewPage>" if repeat else "") + "</TablixMember>")
            return m

        members = static_members(header, "After", keep_header)

        def build(level):
            if level == len(groups):
                if not details:
                    return ""
                vis = ""
                if detail_hidden_by:
                    vis = (f"<Visibility><Hidden>{'false' if detail_expanded else 'true'}</Hidden>"
                           f"<ToggleItem>{detail_hidden_by}</ToggleItem></Visibility>")
                sort = ""
                if detail_sort:
                    sort = "<SortExpressions>" + "".join(
                        f"<SortExpression><Value>{esc(e)}</Value>" + ("<Direction>Descending</Direction>" if d else "")
                        + "</SortExpression>" for e, d in detail_sort) + "</SortExpressions>"
                if len(details) == 1:
                    rows_xml.append(row_xml(details[0]))
                    return f'<TablixMember><Group Name="{name}_Details" />{sort}{vis}</TablixMember>'
                inner = ""
                for r in details:
                    rows_xml.append(row_xml(r))
                    inner += "<TablixMember />"
                return (f'<TablixMember><Group Name="{name}_Details" />{sort}<TablixMembers>{inner}</TablixMembers>'
                        f"{vis}</TablixMember>")
            g = groups[level]
            grp = (f'<Group Name="{g["name"]}"><GroupExpressions><GroupExpression>{esc(g["expr"])}</GroupExpression>'
                   "</GroupExpressions>")
            if g.get("pagebreak"):
                grp += "<PageBreak><BreakLocation>Between</BreakLocation></PageBreak>"
            if g.get("docmap"):
                grp += f"<DocumentMapLabel>{esc(g['docmap'])}</DocumentMapLabel>"
            grp += "</Group>"
            srt = ""
            if g.get("sort"):
                e, desc = g["sort"] if isinstance(g["sort"], tuple) else (g["sort"], False)
                srt = (f"<SortExpressions><SortExpression><Value>{esc(e)}</Value>"
                       + ("<Direction>Descending</Direction>" if desc else "") + "</SortExpression></SortExpressions>")
            inner = static_members(g.get("rows", []), "After")
            child = build(level + 1)
            inner += child
            inner += static_members(g.get("footer", []), "Before")
            vis = ""
            if g.get("hidden_by"):
                vis = f"<Visibility><Hidden>true</Hidden><ToggleItem>{g['hidden_by']}</ToggleItem></Visibility>"
            return f"<TablixMember>{grp}{srt}<TablixMembers>{inner}</TablixMembers>{vis}</TablixMember>"

        members += build(0)
        if total:
            members += static_members(total, "Before")
        cols = "".join(f"<TablixColumn><Width>{cm(w)}</Width></TablixColumn>" for w in widths)
        colmembers = "<TablixMember />" * ncols
        top, left = pos
        x = (f'<Tablix Name="{name}"><TablixBody><TablixColumns>{cols}</TablixColumns>'
             f"<TablixRows>{''.join(rows_xml)}</TablixRows></TablixBody>"
             f"<TablixColumnHierarchy><TablixMembers>{colmembers}</TablixMembers></TablixColumnHierarchy>"
             f"<TablixRowHierarchy><TablixMembers>{members}</TablixMembers></TablixRowHierarchy>"
             f"<DataSetName>{dataset}</DataSetName>"
             + (f"<NoRowsMessage>{esc(no_rows)}</NoRowsMessage>" if no_rows else "")
             + (f"<Visibility><Hidden>{esc(hidden)}</Hidden></Visibility>" if hidden else "")
             + f"<Top>{cm(top)}</Top><Left>{cm(left)}</Left><Height>{cm(0.6 * len(rows_xml))}</Height>"
               f"<Width>{cm(sum(widths))}</Width><Style><Border><Style>None</Style></Border></Style></Tablix>")
        return x, top + 0.6 * len(rows_xml)

    # ------------------------------------------------------------ матриця
    def matrix(self, name, dataset, row_groups, col_group, cell, total_col_cell, total_row_cells, corner, pos,
               cell_width=1.6, col_total_header="Разом", row_total_label="Разом"):
        """
        row_groups: [{"name","expr","sort","header": xml, "width"}] (2 рівні)
        col_group: {"name","expr","sort","header": xml}
        cell: xml комірки даних; total_col_cell: xml комірки «Разом» праворуч
        total_row_cells: (xml для місяця, xml для «Разом») — підсумковий рядок
        corner: [xml для кожного стовпця заголовків рядків]
        """
        g1, g2 = row_groups
        cols = f"<TablixColumn><Width>{cm(cell_width)}</Width></TablixColumn>" * 2
        rows = (f"<TablixRow><Height>0.6cm</Height><TablixCells><TablixCell><CellContents>{cell}</CellContents></TablixCell>"
                f"<TablixCell><CellContents>{total_col_cell}</CellContents></TablixCell></TablixCells></TablixRow>"
                f"<TablixRow><Height>0.6cm</Height><TablixCells><TablixCell><CellContents>{total_row_cells[0]}</CellContents></TablixCell>"
                f"<TablixCell><CellContents>{total_row_cells[1]}</CellContents></TablixCell></TablixCells></TablixRow>")
        corner_x = "<TablixCorner><TablixCornerRows><TablixCornerRow>" + "".join(
            f"<TablixCornerCell><CellContents>{c}</CellContents></TablixCornerCell>" for c in corner) \
            + "</TablixCornerRow></TablixCornerRows></TablixCorner>"
        colh = (f'<TablixColumnHierarchy><TablixMembers><TablixMember><Group Name="{col_group["name"]}">'
                f'<GroupExpressions><GroupExpression>{esc(col_group["expr"])}</GroupExpression></GroupExpressions></Group>'
                f'<SortExpressions><SortExpression><Value>{esc(col_group["sort"])}</Value></SortExpression></SortExpressions>'
                f'<TablixHeader><Size>0.6cm</Size><CellContents>{col_group["header"]}</CellContents></TablixHeader></TablixMember>'
                f'<TablixMember><TablixHeader><Size>0.6cm</Size><CellContents>'
                + self.tb(col_total_header, bold=True, bg=DARK, color="White", align="Center")
                + "</CellContents></TablixHeader></TablixMember></TablixMembers></TablixColumnHierarchy>")
        rowh = (f'<TablixRowHierarchy><TablixMembers><TablixMember><Group Name="{g1["name"]}">'
                f'<GroupExpressions><GroupExpression>{esc(g1["expr"])}</GroupExpression></GroupExpressions>'
                + (f"<DocumentMapLabel>{esc(g1['expr'])}</DocumentMapLabel>" if g1.get("docmap") else "") + "</Group>"
                f'<SortExpressions><SortExpression><Value>{esc(g1["sort"])}</Value></SortExpression></SortExpressions>'
                f'<TablixHeader><Size>{cm(g1["width"])}</Size><CellContents>{g1["header"]}</CellContents></TablixHeader>'
                f'<TablixMembers><TablixMember><Group Name="{g2["name"]}"><GroupExpressions><GroupExpression>{esc(g2["expr"])}'
                f'</GroupExpression></GroupExpressions></Group>'
                f'<SortExpressions><SortExpression><Value>{esc(g2["sort"])}</Value></SortExpression></SortExpressions>'
                f'<TablixHeader><Size>{cm(g2["width"])}</Size><CellContents>{g2["header"]}</CellContents></TablixHeader>'
                + (f"<Visibility><Hidden>false</Hidden><ToggleItem>{g1['toggle']}</ToggleItem></Visibility>" if g1.get("toggle") else "")
                + "</TablixMember></TablixMembers></TablixMember>"
                f'<TablixMember><TablixHeader><Size>{cm(g1["width"])}</Size><CellContents>'
                + self.tb(row_total_label, bold=True, bg=MID)
                + f'</CellContents></TablixHeader><TablixMembers><TablixMember><TablixHeader><Size>{cm(g2["width"])}</Size>'
                f'<CellContents>' + self.tb("", bg=MID) + "</CellContents></TablixHeader></TablixMember></TablixMembers>"
                "<KeepWithGroup>Before</KeepWithGroup></TablixMember></TablixMembers></TablixRowHierarchy>")
        top, left = pos
        x = (f'<Tablix Name="{name}">{corner_x}<TablixBody><TablixColumns>{cols}</TablixColumns><TablixRows>{rows}</TablixRows>'
             f"</TablixBody>{colh}{rowh}<RepeatColumnHeaders>true</RepeatColumnHeaders><RepeatRowHeaders>true</RepeatRowHeaders>"
             f"<DataSetName>{dataset}</DataSetName><NoRowsMessage>Немає даних за вибраними параметрами</NoRowsMessage>"
             f"<Top>{cm(top)}</Top><Left>{cm(left)}</Left><Height>1.8cm</Height>"
             f"<Width>{cm(g1['width'] + g2['width'] + 2 * cell_width)}</Width><Style><Border><Style>None</Style></Border></Style></Tablix>")
        return x, top + 1.8

    # ------------------------------------------------------------ діаграми
    def chart(self, name, dataset, ctype, category, series, title=None, pos=None, subtype="Plain", value_format="#,##0",
              legend=True, labels=False, category_sort=None, label_expr=None, sparkline=False, value_max=None,
              value_min=None, palette="BrightPastel", colors=None, label_format=None, label_text=None):
        """
        ctype: Column, Bar, Line, Shape (Pie); category: вираз групування категорій
        series: [(назва серії, вираз Y, тип або None, колір або None)]
        """
        cat = (f'<ChartCategoryHierarchy><ChartMembers><ChartMember><Group Name="{name}_Cat"><GroupExpressions>'
               f"<GroupExpression>{esc(category)}</GroupExpression></GroupExpressions></Group>"
               + (f"<SortExpressions><SortExpression><Value>{esc(category_sort[0])}</Value>"
                  + ("<Direction>Descending</Direction>" if category_sort[1] else "")
                  + "</SortExpression></SortExpressions>" if category_sort else "")
               + f"<Label>{esc(label_expr or category)}</Label></ChartMember></ChartMembers></ChartCategoryHierarchy>")
        ser_members = "".join(f"<ChartMember><Label>{esc(s[0])}</Label></ChartMember>" for s in series)
        ser_coll = ""
        for i, (sname, y, stype, color) in enumerate(series):
            t = stype or ctype
            st = subtype if stype is None else "Plain"
            pt_style = f"<Color>{color}</Color>" if color else ""
            if t == "Line":
                pt_style += f"<Border><Width>{'1.5pt' if sparkline else '2.25pt'}</Width>" \
                            + (f"<Color>{color}</Color>" if color else "") + "</Border>"
            lbl_fmt = f"<Format>{esc(label_format)}</Format>" if label_format else ""
            lbl_val = f"<Label>{esc(label_text)}</Label>" if label_text else "<UseValueAsLabel>true</UseValueAsLabel>"
            dl = (f"<ChartDataLabel><Style><FontSize>7pt</FontSize>{lbl_fmt}</Style>{lbl_val}"
                  f"<Visible>true</Visible></ChartDataLabel>") if labels else "<ChartDataLabel><Style /></ChartDataLabel>"
            marker = "<ChartMarker><Type>Circle</Type><Size>5pt</Size></ChartMarker>" if (t == "Line" and not sparkline) \
                else "<ChartMarker><Style /></ChartMarker>"
            ser_coll += (f'<ChartSeries Name="{name}_S{i}"><ChartDataPoints><ChartDataPoint><ChartDataPointValues>'
                         f"<Y>{esc(y)}</Y></ChartDataPointValues>{dl}<Style>{pt_style}</Style>{marker}"
                         f"<DataElementOutput>Output</DataElementOutput></ChartDataPoint></ChartDataPoints>"
                         f"<Type>{t}</Type><Subtype>{st}</Subtype><Style /><ChartEmptyPoints><Style /><ChartMarker><Style /></ChartMarker>"
                         f"<ChartDataLabel><Style /></ChartDataLabel></ChartEmptyPoints>"
                         f"<ValueAxisName>Primary</ValueAxisName><CategoryAxisName>Primary</CategoryAxisName>"
                         f"<ChartSmartLabel><CalloutLineColor>Black</CalloutLineColor><MinMovingDistance>0pt</MinMovingDistance></ChartSmartLabel>"
                         f"</ChartSeries>")
        hide_axes = sparkline or ctype == "Shape"
        axis_font = "<Style><FontSize>7pt</FontSize></Style>"

        def axis(kind):
            style = (f"<Style><FontSize>7pt</FontSize><Format>{esc(value_format)}</Format></Style>" if kind == "value"
                     else axis_font)
            x = f'<ChartAxis Name="Primary">{style}<ChartAxisTitle><Caption /><Style><FontSize>8pt</FontSize></Style></ChartAxisTitle>'
            if kind == "value":
                x += f"<ChartMajorGridLines><Style><Border><Color>Gainsboro</Color></Border></Style></ChartMajorGridLines>"
                x += f"<ChartMinorGridLines><Style><Border><Color>Gainsboro</Color><Style>Dotted</Style></Border></Style></ChartMinorGridLines>"
                if value_max is not None:
                    x += f"<Maximum>{value_max}</Maximum>"
                if value_min is not None:
                    x += f"<Minimum>{value_min}</Minimum>"
            else:
                x += "<ChartMajorGridLines><Enabled>False</Enabled><Style><Border><Color>Gainsboro</Color></Border></Style></ChartMajorGridLines>"
                x += "<ChartMinorGridLines><Style><Border><Color>Gainsboro</Color><Style>Dotted</Style></Border></Style></ChartMinorGridLines>"
                x += "<Interval>1</Interval><LabelsAutoFitDisabled>false</LabelsAutoFitDisabled>"
            x += ("<ChartMinorTickMarks><Length>0.5</Length></ChartMinorTickMarks><CrossAt>NaN</CrossAt>"
                  + ("<Visible>False</Visible>" if hide_axes else "")
                  + "<PreventFontShrink>false</PreventFontShrink></ChartAxis>")
            return x

        areas = (f'<ChartAreas><ChartArea Name="Default"><ChartCategoryAxes>{axis("cat")}</ChartCategoryAxes>'
                 f"<ChartValueAxes>{axis('value')}</ChartValueAxes><Style><BackgroundColor>#FFFFFF</BackgroundColor>"
                 f"<BackgroundGradientType>None</BackgroundGradientType></Style></ChartArea></ChartAreas>")
        leg = (f'<ChartLegends><ChartLegend Name="Default"><Style><FontSize>7pt</FontSize></Style>'
               f"<Position>{'RightCenter' if ctype == 'Shape' else 'BottomCenter'}</Position>"
               + ("" if legend else "<Hidden>true</Hidden>")
               + "<ChartLegendTitle><Caption /><Style><FontSize>8pt</FontSize></Style></ChartLegendTitle>"
               "<HeaderSeparatorColor>Black</HeaderSeparatorColor><ColumnSeparatorColor>Black</ColumnSeparatorColor></ChartLegend></ChartLegends>")
        ttl = (f'<ChartTitles><ChartTitle Name="{name}_T"><Caption>{esc(title)}</Caption><Style><FontSize>9pt</FontSize>'
               f"<FontWeight>Bold</FontWeight><Color>{DARK}</Color></Style></ChartTitle></ChartTitles>") if title else ""
        pal = f"<Palette>{palette}</Palette>"
        if colors:
            pal = "<Palette>Custom</Palette><ChartCustomPaletteColors>" + "".join(
                f"<ChartCustomPaletteColor>{c}</ChartCustomPaletteColor>" for c in colors) + "</ChartCustomPaletteColors>"
        x = (f'<Chart Name="{name}">{cat}<ChartSeriesHierarchy><ChartMembers>{ser_members}</ChartMembers></ChartSeriesHierarchy>'
             f"<ChartData><ChartSeriesCollection>{ser_coll}</ChartSeriesCollection></ChartData>{areas}{leg}{ttl}{pal}"
             "<ChartBorderSkin><Style><BackgroundColor>Gray</BackgroundColor><BackgroundGradientType>None</BackgroundGradientType>"
             "<Color>White</Color></Style></ChartBorderSkin><ChartNoDataMessage Name=\"NoDataMessage\"><Caption>Немає даних</Caption>"
             "<Style><BackgroundGradientType>None</BackgroundGradientType><TextAlign>General</TextAlign><VerticalAlign>Top</VerticalAlign></Style>"
             f"</ChartNoDataMessage><DataSetName>{dataset}</DataSetName>"
             + (self._pos(pos) if pos else "")
             + f"<Style><Border><Color>{GRID}</Color><Style>{'None' if sparkline else 'Solid'}</Style></Border>"
               "<BackgroundColor>White</BackgroundColor><BackgroundGradientType>None</BackgroundGradientType></Style></Chart>")
        return x

    # ------------------------------------------------------------ датчики
    def radial_gauge(self, name, dataset, value, pos, maximum=100, ranges=(), title=None, fmt="0"):
        rng = "".join(
            f'<ScaleRange Name="{name}_R{i}"><Style><Border><Style>None</Style></Border><BackgroundColor>{c}</BackgroundColor>'
            f"<BackgroundGradientType>None</BackgroundGradientType></Style><DistanceFromScale>-6</DistanceFromScale>"
            f"<StartValue><Value>{a}</Value></StartValue><EndValue><Value>{b}</Value></EndValue>"
            f"<StartWidth>12</StartWidth><EndWidth>12</EndWidth><BackgroundGradientType>None</BackgroundGradientType>"
            f"<Placement>Inside</Placement></ScaleRange>" for i, (a, b, c) in enumerate(ranges))
        lbl = (f'<GaugeLabels><GaugeLabel Name="{name}_L"><Text>{esc(title)}</Text><Style><FontSize>8pt</FontSize>'
               f"<FontWeight>Bold</FontWeight><Color>{DARK}</Color><TextAlign>Center</TextAlign></Style>"
               "<Top>78</Top><Left>5</Left><Height>14</Height><Width>90</Width></GaugeLabel>"
               f'<GaugeLabel Name="{name}_V"><Text>{esc(value)}</Text><Style><FontSize>10pt</FontSize><FontWeight>Bold</FontWeight>'
               f"<TextAlign>Center</TextAlign><Format>{esc(fmt)}</Format></Style><Top>62</Top><Left>30</Left><Height>14</Height><Width>40</Width>"
               "</GaugeLabel></GaugeLabels>") if title else ""
        return (f'<GaugePanel Name="{name}"><RadialGauges><RadialGauge Name="{name}_G"><PivotX>50</PivotX><PivotY>55</PivotY>'
                f'<GaugeScales><RadialScale Name="{name}_S"><Radius>38</Radius><StartAngle>60</StartAngle><SweepAngle>240</SweepAngle>'
                f'<GaugePointers><RadialPointer Name="{name}_P"><PointerCap><Style><BackgroundColor>#4D4D4D</BackgroundColor>'
                "<BackgroundGradientType>None</BackgroundGradientType></Style><OnTop>true</OnTop><CapStyle>RoundedDark</CapStyle>"
                f"<Width>18</Width></PointerCap><NeedleStyle>Tapered</NeedleStyle><Style><BackgroundColor>#C00000</BackgroundColor>"
                f"<BackgroundGradientType>None</BackgroundGradientType></Style><GaugeInputValue><Value>{esc(value)}</Value></GaugeInputValue>"
                "<Placement>Cross</Placement><Width>12</Width><MarkerLength>25</MarkerLength></RadialPointer></GaugePointers>"
                f"<ScaleRanges>{rng}</ScaleRanges><Style><Border><Style>None</Style></Border></Style>"
                "<GaugeMajorTickMarks><Style><BackgroundColor>#404040</BackgroundColor></Style><Placement>Inside</Placement>"
                "<Shape>Rectangle</Shape><Length>8</Length><Width>2</Width></GaugeMajorTickMarks>"
                "<GaugeMinorTickMarks><Style><BackgroundColor>#808080</BackgroundColor></Style><Placement>Inside</Placement>"
                "<Length>4</Length><Width>1</Width></GaugeMinorTickMarks>"
                f"<MaximumValue><Value>{maximum}</Value></MaximumValue><MinimumValue><Value>0</Value></MinimumValue>"
                "<ScaleLabels><Style><FontSize>7pt</FontSize></Style><DistanceFromScale>-8</DistanceFromScale><Placement>Inside</Placement>"
                "</ScaleLabels></RadialScale></GaugeScales>"
                "<BackFrame><Style><BackgroundColor>#F2F2F2</BackgroundColor><BackgroundGradientType>None</BackgroundGradientType>"
                "<Border><Color>#BFBFBF</Color><Style>Solid</Style></Border></Style><FrameStyle>Simple</FrameStyle>"
                "<FrameShape>Circular</FrameShape><FrameWidth>3</FrameWidth><FrameBackground><Style><BackgroundColor>#F2F2F2</BackgroundColor>"
                "</Style></FrameBackground></BackFrame><ClipContent>true</ClipContent><AspectRatio>1</AspectRatio>"
                "<Top>0</Top><Left>0</Left><Height>100</Height><Width>100</Width></RadialGauge></RadialGauges>"
                f"{lbl}<AntiAliasing>All</AntiAliasing><AutoLayout>true</AutoLayout><DataSetName>{dataset}</DataSetName>"
                + self._pos(pos) + "<Style><Border><Style>None</Style></Border></Style></GaugePanel>")

    def indicator(self, name, dataset, value, pos=None):
        """Трисигнальний індикатор стану KPI: -1 червоний, 0 жовтий, 1 зелений"""
        states = "".join(
            f'<IndicatorState Name="{n}"><StartValue><Value>{a}</Value></StartValue><EndValue><Value>{b}</Value></EndValue>'
            f"<Color>{c}</Color><ScaleFactor>1</ScaleFactor><IndicatorStyle>Circle</IndicatorStyle></IndicatorState>"
            for n, a, b, c in (("Погано", -1, -0.5, "#E04B4B"), ("Увага", -0.5, 0.5, "#F2C80F"), ("Добре", 0.5, 1, "#3BA55C")))
        return (f'<GaugePanel Name="{name}"><StateIndicators><StateIndicator Name="{name}_I">'
                f"<GaugeInputValue><Value>{esc(value)}</Value></GaugeInputValue><TransformationType>None</TransformationType>"
                f"<IndicatorStyle>Circle</IndicatorStyle><IndicatorStates>{states}</IndicatorStates>"
                "<MaximumValue><Value>1</Value></MaximumValue><MinimumValue><Value>-1</Value></MinimumValue>"
                "<Style><Border><Style>None</Style></Border></Style>"
                "<Top>0</Top><Left>0</Left><Height>100</Height><Width>100</Width></StateIndicator></StateIndicators>"
                f"<AutoLayout>true</AutoLayout><DataSetName>{dataset}</DataSetName>"
                + (self._pos(pos) if pos else "") + "<Style><Border><Style>None</Style></Border></Style></GaugePanel>")

    def subreport(self, name, report, params):
        p = "".join(f'<Parameter Name="{k}"><Value>{esc(v)}</Value></Parameter>' for k, v in params.items())
        return (f'<Subreport Name="{name}"><ReportName>{esc(report)}</ReportName><Parameters>{p}</Parameters>'
                "<KeepTogether>true</KeepTogether><Style><Border><Style>None</Style></Border></Style></Subreport>")

    def rectangle(self, name, items, pos, bg=None):
        return (f'<Rectangle Name="{name}"><ReportItems>{"".join(items)}</ReportItems><KeepTogether>true</KeepTogether>'
                + self._pos(pos) + f"<Style><Border><Color>{GRID}</Color><Style>Solid</Style></Border>"
                + (f"<BackgroundColor>{bg}</BackgroundColor>" if bg else "") + "</Style></Rectangle>")

    # ------------------------------------------------------------ збереження
    def to_xml(self):
        srcs = "".join(f'<DataSource Name="{s}"><DataSourceReference>{s}</DataSourceReference>'
                       f"<rd:SecurityType>None</rd:SecurityType><rd:DataSourceID>{guid()}</rd:DataSourceID></DataSource>"
                       for s in self.sources)
        hdr_items = self.tb('="Поліклініка · " & Globals!ReportName', size=7, color="#7F7F7F", border=False,
                            pos=(0, 0, self.body_w / 2, 0.5), padding=0)
        hdr_items += self.tb('="Сформовано: " & Format(Globals!ExecutionTime, "dd.MM.yyyy HH:mm")', size=7, color="#7F7F7F",
                             border=False, align="Right", pos=(0, self.body_w / 2, self.body_w / 2, 0.5), padding=0)
        ftr_items = self.tb('="Сторінка " & Globals!PageNumber & " з " & Globals!TotalPages', size=7, color="#7F7F7F",
                            border=False, align="Center", pos=(0, 0, self.body_w, 0.5), padding=0)
        page = (f"<PageHeader><Height>0.6cm</Height><PrintOnFirstPage>true</PrintOnFirstPage><PrintOnLastPage>true</PrintOnLastPage>"
                f"<ReportItems>{hdr_items}</ReportItems><Style><Border><Style>None</Style></Border></Style></PageHeader>"
                f"<PageFooter><Height>0.6cm</Height><PrintOnFirstPage>true</PrintOnFirstPage><PrintOnLastPage>true</PrintOnLastPage>"
                f"<ReportItems>{ftr_items}</ReportItems><Style><Border><Style>None</Style></Border></Style></PageFooter>"
                f"<PageHeight>{cm(self.page_h)}</PageHeight><PageWidth>{cm(self.page_w)}</PageWidth>"
                f"<InteractiveHeight>{cm(self.page_h)}</InteractiveHeight><InteractiveWidth>{cm(self.page_w)}</InteractiveWidth>"
                f"<LeftMargin>{cm(self.margin)}</LeftMargin><RightMargin>{cm(self.margin)}</RightMargin>"
                f"<TopMargin>{cm(self.margin)}</TopMargin><BottomMargin>{cm(self.margin)}</BottomMargin><Style /></Page>")
        body = (f"<Body><ReportItems>{''.join(self.items)}</ReportItems><Height>{cm(round(self.body_h + 0.2, 2))}</Height>"
                "<Style><Border><Style>None</Style></Border></Style></Body>")
        x = (f'<?xml version="1.0" encoding="utf-8"?>\n<Report {RDL_NS}>'
             "<df:DefaultFontFamily>Segoe UI</df:DefaultFontFamily><AutoRefresh>0</AutoRefresh>"
             f"<Description>{esc(self.description)}</Description>"
             f"<DataSources>{srcs}</DataSources><DataSets>{''.join(self.datasets)}</DataSets>"
             f"<ReportSections><ReportSection>{body}<Width>{cm(self.body_w)}</Width><Page>{page}</ReportSection></ReportSections>"
             + (f"<ReportParameters>{''.join(self.params)}</ReportParameters>" if self.params else "")
             + (f"<Code>{esc(self.code)}</Code>" if self.code else "")
             + f"<Language>uk-UA</Language><ConsumeContainerWhitespace>true</ConsumeContainerWhitespace>"
               f"<rd:ReportUnitType>Cm</rd:ReportUnitType><rd:ReportID>{guid()}</rd:ReportID></Report>")
        return x

    def save(self, folder):
        import os
        with open(os.path.join(folder, self.name + ".rdl"), "w", encoding="utf-8") as f:
            f.write(self.to_xml())
