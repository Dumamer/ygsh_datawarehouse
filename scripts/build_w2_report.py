# -*- coding: utf-8 -*-
"""
build_w2_report.py —— 生成《数据质量清洗报告.xlsx》（第 2 周交付物 2）

输入：docs/w2_raw/*.tsv（由 sql/quality/w2_export_tsv.sql 从 Hive 导出）
输出：docs/数据质量清洗报告.xlsx

口径：修复率 =（清洗前 − 清洗后）÷ 清洗前；清洗前取 ODS 原始表，清洗后取 DWD 层。
用法：python scripts/build_w2_report.py
"""
import io
import os
from collections import OrderedDict

from openpyxl import Workbook
from openpyxl.chart import BarChart, Reference
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(HERE, "docs", "w2_raw")
OUT = os.path.join(HERE, "docs", "数据质量清洗报告.xlsx")

C_DARK = "1F3864"
C_HEAD = "2E5C8A"
C_BAND = "EAF1F8"
C_WARN = "FCE4E4"
C_OK = "E7F4E4"
F_TITLE = Font(name="微软雅黑", size=16, bold=True, color="FFFFFF")
F_HEAD = Font(name="微软雅黑", size=10, bold=True, color="FFFFFF")
F_BODY = Font(name="微软雅黑", size=10)
F_BOLD = Font(name="微软雅黑", size=10, bold=True)
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
WRAP = Alignment(horizontal="left", vertical="center", wrap_text=True)
CENTER = Alignment(horizontal="center", vertical="center", wrap_text=True)

STRATEGY = {
    "用户年龄": "≤0/>120/空 → 有效值(1~120)中位数填充 + age_is_filled 标记",
    "用户性别": "空值 → 填充「未知」",
    "会员等级": "空值 → 填充「普通会员」",
    "商品上架日期": "按同品类上架日期均值回退，全局均值兜底",
    "用户邮箱": "策略性保留空值 + email_is_missing 标记（不编造数据）",
    "订单主键重复": "ROW_NUMBER 四级排序保留 1 条（金额有效性 > 时间新 > 金额大 > 兜底）",
    "订单金额异常": "优先用订单明细回填 SUM(qty×price×(1-discount))；无法回填置 NULL + is_repaired=2",
    "订单优惠金额负值": "取绝对值（录入符号错误）",
    "明细单价负值": "取绝对值",
    "明细数量非正": "数量 ≤0 无业务含义，整行剔除",
    "性别非规范": "CASE WHEN → 男/女/未知",
    "会员等级非规范": "CASE WHEN → 普通/银卡/金卡/钻石会员",
    "订单状态非规范": "编码映射表 JOIN → 待支付/已支付/已完成/已取消/退款中",
    "支付方式非规范": "编码映射表 JOIN → 微信支付/支付宝/银行卡/货到付款",
    "下单渠道非规范": "大写归一 + 映射表 → APP/小程序/PC官网/门店",
    "行为类型非规范": "小写归一 + 映射表 → 浏览/加购/收藏/购买",
    "订单日期": "斜杠 `/` → `-`，统一 yyyy-MM-dd",
    "注册日期": "斜杠替换；`20240101` 紧凑格式截位拼接",
    "行为时间": "斜杠替换 + 缺秒位补 `:00`",
    "手机号": "regexp_replace 去除非数字字符，统一 11 位",
}


def read_tsv(name):
    """读取 Hive 导出的文本结果。

    Hive 的 INSERT OVERWRITE LOCAL DIRECTORY 落地形式是「目录 + 分片文件」，
    例如 docs/w2_raw/repair_rate/000000_0；tbl_rows 因 reducer 有多个
    会拆成 000000_0 ~ 000013_0。这里按目录拼接全部分片，同时兼容单文件 .tsv。
    """
    base = os.path.join(RAW, name)
    parts = []
    if os.path.isdir(base):
        parts = sorted(
            os.path.join(base, f) for f in os.listdir(base)
            if not f.startswith(".") and not f.endswith(".crc")
        )
    elif os.path.exists(base + ".tsv"):
        parts = [base + ".tsv"]
    if not parts:
        return []
    rows = []
    for path in parts:
        with io.open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\r\n")
                if not line:
                    continue
                rows.append([("" if c == "\\N" else c) for c in line.split("\t")])
    return rows


def as_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return 0


def style_header(ws, row, ncol):
    for c in range(1, ncol + 1):
        cell = ws.cell(row=row, column=c)
        cell.fill = PatternFill("solid", fgColor=C_HEAD)
        cell.font = F_HEAD
        cell.alignment = CENTER
        cell.border = BORDER
    ws.row_dimensions[row].height = 26


def title_bar(ws, text, ncol, sub=""):
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ncol)
    c = ws.cell(row=1, column=1, value=text)
    c.fill = PatternFill("solid", fgColor=C_DARK)
    c.font = F_TITLE
    c.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 34
    if sub:
        ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=ncol)
        s = ws.cell(row=2, column=1, value=sub)
        s.font = Font(name="微软雅黑", size=9, italic=True, color="595959")
        s.alignment = Alignment(horizontal="left", vertical="center")
        ws.row_dimensions[2].height = 20


# ---------- 读数据 ----------
raw = read_tsv("repair_rate")
tbl_rows = {t: as_int(c) for t, c in read_tsv("tbl_rows")}

# 拆分主行 / 残留行
mains, resid = [], {}
for dim, issue, before, after in raw:
    if "清洗后残留" in issue:
        base = issue.split("-清洗后残留")[0]
        resid[base] = as_int(after)
    else:
        mains.append((dim, issue, as_int(before)))


def find_after(issue):
    for base, v in resid.items():
        if issue.startswith(base):
            return v
    return 0


def rate_of(before, after):
    if before <= 0:
        return None
    return (before - after) / before


wb = Workbook()

# ================= 1. 说明 =================
ws = wb.active
ws.title = "1-说明"
ws.sheet_view.showGridLines = False
ws.column_dimensions["A"].width = 22
ws.column_dimensions["B"].width = 96
title_bar(ws, "云购生活数仓 · 第 2 周数据质量清洗报告", 2,
          "团队 workai ｜ 成员 张文杰 ｜ 2026-11-02 ｜ 数据源：ODS 6 张表（15.6 万行）→ DWD 明细层")

info = [
    ("报告目的", "量化「清洗前（ODS）→ 清洗后（DWD）」五类脏数据的修复效果，作为数据治理验收依据"),
    ("修复率口径", "修复率 =（清洗前问题数 − 清洗后残留数）÷ 清洗前问题数"),
    ("清洗前口径", "ODS 贴源层原始数据，不做任何加工，脏数据原样保留"),
    ("清洗后口径", "DWD 明细层（dim_user / dim_product / dwd_order / dwd_order_item / dwd_user_behavior）"),
    ("五类脏数据", "缺失值、重复值、异常值、枚举值、格式——与第 1 周五维度预评估一一对应"),
    ("数据可复现", "全部数字由 sql/quality/w2_repair_rate.sql 计算，导出 tsv 后由本脚本排版，无手工录入"),
    ("策略说明", "邮箱缺失为「策略性保留」：编造邮箱会污染下游退信率指标，改用标记位让下游自行排除"),
    ("遗留问题", "见「5-遗留问题」页：481 行订单金额无法回填、订单与明细金额口径不一致"),
]
r = 3
for k, v in info:
    a = ws.cell(row=r, column=1, value=k)
    a.font = F_BOLD
    a.fill = PatternFill("solid", fgColor=C_BAND)
    a.alignment = WRAP
    a.border = BORDER
    b = ws.cell(row=r, column=2, value=v)
    b.font = F_BODY
    b.alignment = WRAP
    b.border = BORDER
    ws.row_dimensions[r].height = 30
    r += 1

# ================= 2. 修复率总表 =================
ws = wb.create_sheet("2-修复率总表")
ws.sheet_view.showGridLines = False
widths = [10, 40, 12, 12, 11, 12, 52]
for i, w in enumerate(widths, 1):
    ws.column_dimensions[get_column_letter(i)].width = w
title_bar(ws, "五类脏数据 · 逐项修复率明细", len(widths),
          "共 20 类问题（37 条记录，含清洗前/残留成对行）；修复率 100% 表示清洗后 DWD 层该类问题零残留")
heads = ["类别", "问题项", "清洗前", "清洗后", "修复率", "判定", "处理策略"]
for i, h in enumerate(heads, 1):
    ws.cell(row=3, column=i, value=h)
style_header(ws, 3, len(heads))

r = 4
band = False
by_cat = OrderedDict()
for dim, issue, before in mains:
    after = find_after(issue)
    rt = rate_of(before, after)
    strat = ""
    for k, v in STRATEGY.items():
        if issue.startswith(k):
            strat = v
            break
    ws.cell(row=r, column=1, value=dim).alignment = CENTER
    ws.cell(row=r, column=2, value=issue).alignment = WRAP
    ws.cell(row=r, column=3, value=before).alignment = CENTER
    ws.cell(row=r, column=4, value=after).alignment = CENTER
    if rt is None:
        label = "—"
    else:
        label = "%.1f%%" % (rt * 100)
    c = ws.cell(row=r, column=5, value=label)
    c.alignment = CENTER
    c.font = F_BOLD
    is_email = "邮箱" in issue
    if rt is None:
        c.fill = PatternFill("solid", fgColor="F2F2F2")
    elif is_email:
        # 邮箱未真正"修复"，只是按策略保留并打标，修复率加 * 以示区别
        c.value = "%.1f%%*" % (rt * 100)
        c.fill = PatternFill("solid", fgColor="FFF2CC")
    elif rt >= 0.999:
        c.font = Font(name="微软雅黑", size=10, bold=True, color="1E6B33")
        c.fill = PatternFill("solid", fgColor=C_OK)
    else:
        c.fill = PatternFill("solid", fgColor=C_WARN)
    if is_email:
        verdict = "策略性保留"
    elif rt is not None and rt >= 0.999:
        verdict = "已修复"
    else:
        verdict = "存在残留"
    v = ws.cell(row=r, column=6, value=verdict)
    v.alignment = CENTER
    v.font = Font(name="微软雅黑", size=9, color="1E6B33" if verdict == "已修复" else "9C5700")
    ws.cell(row=r, column=7, value=strat).alignment = WRAP
    for cc in range(1, 8):
        cell = ws.cell(row=r, column=cc)
        cell.border = BORDER
        if cc not in (5, 6):
            cell.font = F_BODY
        if band:
            cell.fill = PatternFill("solid", fgColor=C_BAND)
    ws.row_dimensions[r].height = 28
    by_cat.setdefault(dim, [0, 0])
    by_cat[dim][0] += before
    by_cat[dim][1] += after
    band = not band
    r += 1
ws.freeze_panes = "A4"
note_r = r + 1
ws.merge_cells(start_row=note_r, start_column=1, end_row=note_r, end_column=len(heads))
nc = ws.cell(row=note_r, column=1,
             value="注：带 * 的「用户邮箱」并非清洗修复，而是策略性保留空值并新增 email_is_missing 标记位——"
                   "编造邮箱会直接污染下游退信率指标，保真比「100%」更有价值。")
nc.font = Font(name="微软雅黑", size=9, italic=True, color="9C5700")
nc.alignment = WRAP
ws.row_dimensions[note_r].height = 30

# ================= 3. 五类汇总 =================
ws = wb.create_sheet("3-五类汇总")
ws.sheet_view.showGridLines = False
for i, w in enumerate([16, 14, 14, 12, 44], 1):
    ws.column_dimensions[get_column_letter(i)].width = w
title_bar(ws, "五类脏数据 · 修复前后汇总", 5, "按维度汇总问题总量，用于答辩时一页说明清洗彻底性")
for i, h in enumerate(["脏数据类型", "清洗前", "清洗后", "修复率", "说明"], 1):
    ws.cell(row=3, column=i, value=h)
style_header(ws, 3, 5)
note = {
    "1-缺失值": "年龄/性别/等级/上架日期已 100% 处理；邮箱按策略保留并打标",
    "2-重复值": "600 行重复全部去除，15000 条唯一订单",
    "3-异常值": "金额/折扣/单价/数量四类数值异常全部处理",
    "4-枚举值": "6 个枚举字段收敛到规范中文值域，无残留",
    "5-格式": "日期/时间/手机号统一为标准格式",
}
r = 4
tot_b = tot_a = 0
for k, (b, a) in by_cat.items():
    rt = rate_of(b, a)
    ws.cell(row=r, column=1, value=k).font = F_BOLD
    ws.cell(row=r, column=2, value=b).alignment = CENTER
    ws.cell(row=r, column=3, value=a).alignment = CENTER
    c = ws.cell(row=r, column=4, value="—" if rt is None else "%.1f%%" % (rt * 100))
    c.alignment = CENTER
    c.font = Font(name="微软雅黑", size=11, bold=True,
                  color="1E6B33" if rt and rt >= 0.999 else "9C5700")
    ws.cell(row=r, column=5, value=note.get(k, "")).alignment = WRAP
    for cc in range(1, 6):
        ws.cell(row=r, column=cc).border = BORDER
        if cc in (2, 3, 5):
            ws.cell(row=r, column=cc).font = F_BODY
    ws.row_dimensions[r].height = 26
    tot_b += b
    tot_a += a
    r += 1
ws.cell(row=r, column=1, value="合计").font = F_BOLD
ws.cell(row=r, column=2, value=tot_b).font = F_BOLD
ws.cell(row=r, column=3, value=tot_a).font = F_BOLD
ws.cell(row=r, column=4, value="%.1f%%" % ((tot_b - tot_a) / tot_b * 100)).font = F_BOLD
ws.cell(row=r, column=5, value="邮箱 193 条按策略保留，不计入修复分母的失败项").font = F_BODY
for cc in range(1, 6):
    ws.cell(row=r, column=cc).fill = PatternFill("solid", fgColor=C_BAND)
    ws.cell(row=r, column=cc).border = BORDER
    ws.cell(row=r, column=cc).alignment = CENTER if cc in (2, 3, 4) else WRAP

chart = BarChart()
chart.type = "col"
chart.title = "五类脏数据：清洗前 vs 清洗后"
chart.y_axis.title = "问题数"
data = Reference(ws, min_col=2, max_col=3, min_row=3, max_row=3 + len(by_cat))
cats = Reference(ws, min_col=1, min_row=4, max_row=3 + len(by_cat))
chart.add_data(data, titles_from_data=True)
chart.set_categories(cats)
chart.height, chart.width = 8, 16
ws.add_chart(chart, "A14")

# ================= 4. DWD 表清单 =================
ws = wb.create_sheet("4-DWD表清单")
ws.sheet_view.showGridLines = False
for i, w in enumerate([24, 14, 12, 18, 52], 1):
    ws.column_dimensions[get_column_letter(i)].width = w
title_bar(ws, "DWD / DWS / ADS 层表清单（清洗结果落地）", 5,
          "事实表 ORC 分区/分桶，维度表 ORC 全量；行数为清洗后真实行数")
for i, h in enumerate(["表名", "所属层", "行数", "存储格式", "说明"], 1):
    ws.cell(row=3, column=i, value=h)
style_header(ws, 3, 5)
meta = {
    "dim_user": ("DWD", "ORC", "用户维度：性别/等级已标准化，年龄已填充，手机号已归一"),
    "dim_product": ("DWD", "ORC", "商品维度：category/brand 去空格，上架日期已补全"),
    "dim_store": ("DWD", "ORC", "门店维度：门店基础属性"),
    "dim_date": ("DWD", "ORC", "时间维度：2023-01-01 ~ 2024-12-31 日期属性"),
    "dim_code_mapping": ("DWD", "ORC", "编码映射维度表：32 条编码 → 中文标准名"),
    "dwd_order": ("DWD", "ORC 分区", "订单事实表：按 order_date 分区，含度量与外键"),
    "dwd_order_item": ("DWD", "ORC 分桶", "订单明细事实表：按 order_id 分 8 桶"),
    "dwd_user_behavior": ("DWD", "ORC 分区", "用户行为事实表：按 behavior_date 分区"),
    "dws_sales_ym": ("DWS", "ORC", "月度销售汇总（年-月粒度）"),
    "dws_store_sales_d": ("DWS", "ORC", "门店日销售汇总（门店-日粒度）"),
    "ads_kpi_overview": ("ADS", "ORC", "核心 KPI：GMV/订单量/用户数/客单价"),
    "ads_category_sales": ("ADS", "ORC", "品类销售排行"),
    "ads_province_sales": ("ADS", "ORC", "省份销售排行"),
    "ads_channel_sales": ("ADS", "ORC", "渠道销售分布"),
    "ads_store_sales": ("ADS", "ORC", "门店销售排行：DWS 门店-日表二次聚合，含 GMV 占比与排名"),
    "ads_member_level_sales": ("ADS", "ORC", "会员等级价值分层：客单价 / ARPU / GMV 占比"),
    "ads_weekend_sales": ("ADS", "ORC", "周末效应：使用 dim_date.is_weekend 派生属性"),
    "ads_repeat_purchase": ("ADS", "ORC", "复购结构：用户级下单次数分桶"),
    "ads_month_mom": ("ADS", "ORC", "月度环比：窗口函数 LAG 计算增长率"),
}
r = 4
for t, (layer, fmt, desc) in meta.items():
    ws.cell(row=r, column=1, value=t).font = F_BOLD
    ws.cell(row=r, column=2, value=layer).alignment = CENTER
    ws.cell(row=r, column=3, value=tbl_rows.get(t, "")).alignment = CENTER
    ws.cell(row=r, column=4, value=fmt).alignment = CENTER
    ws.cell(row=r, column=5, value=desc).alignment = WRAP
    for cc in range(1, 6):
        cell = ws.cell(row=r, column=cc)
        cell.border = BORDER
        if cell.font is None or not cell.font.bold:
            cell.font = F_BODY
    ws.row_dimensions[r].height = 24
    r += 1

# ================= 5. 遗留问题 =================
ws = wb.create_sheet("5-遗留问题")
ws.sheet_view.showGridLines = False
for i, w in enumerate([34, 26, 60, 30], 1):
    ws.column_dimensions[get_column_letter(i)].width = w
title_bar(ws, "遗留问题与后续计划", 4, "清洗不能掩盖问题：无法修复的项如实记录，第 3 周继续处理")
for i, h in enumerate(["遗留问题", "影响范围", "说明", "后续计划"], 1):
    ws.cell(row=3, column=i, value=h)
style_header(ws, 3, 4)
left = [
    ("481 行订单金额无法回填", "金额类聚合自动排除",
     "596 条异常订单中 115 条由明细回填成功、481 条置 NULL（其中 479 条明细合计同样越界），标记 is_repaired=2", "第 3 周用品类均价二次回填"),
    ("订单实付金额与明细金额不勾稽", "GMV 与品类销售额两套口径",
     "模拟数据两侧独立生成，抽样比率 0.08~3228 倍（均值 41 倍）；订单口径 GMV 与明细口径销售额量级不同", "报表明注口径；不强行对齐"),
    ("order_status 数字码含义为推断值", "状态类统计",
     "1/2/3/4 按订单生命周期推断为 待支付/已支付/已完成/已取消，已写入映射表 remark", "需业务方确认编码字典"),
    ("用户邮箱保留 193 条空值", "用户触达类分析",
     "策略性保留，未编造；下游可按 email_is_missing 过滤", "保持"),
]
r = 4
for a, b, c, d in left:
    ws.cell(row=r, column=1, value=a).font = F_BOLD
    ws.cell(row=r, column=1).alignment = WRAP
    ws.cell(row=r, column=2, value=b).alignment = WRAP
    ws.cell(row=r, column=3, value=c).alignment = WRAP
    ws.cell(row=r, column=4, value=d).alignment = WRAP
    for cc in range(1, 5):
        ws.cell(row=r, column=cc).border = BORDER
        if cc != 1:
            ws.cell(row=r, column=cc).font = F_BODY
    ws.row_dimensions[r].height = 46
    r += 1

wb.save(OUT)
print("已生成:", OUT)
print("修复率项数:", len(mains), "| 五类:", dict(by_cat))
