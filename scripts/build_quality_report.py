# -*- coding: utf-8 -*-
"""
build_quality_report.py —— 生成《数据质量预评估表.xlsx》

输入：docs/quality_raw/*.tsv（由 Hive 的 INSERT OVERWRITE LOCAL DIRECTORY 导出）
输出：docs/数据质量预评估表.xlsx

为什么分两步（Hive 出数 -> Python 排版）：
    Hive 负责「算准」，Python 负责「排好看」。把 SQL 计算结果先落成 tsv，
    既能被 Excel 直接验证，也便于换环境重跑，不依赖某个 BI 工具的连接配置。

用法：
    python scripts/build_quality_report.py
"""
import io
import os
from collections import defaultdict, OrderedDict

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(HERE, "docs", "quality_raw")
OUT = os.path.join(HERE, "docs", "数据质量预评估表.xlsx")

# ---------- 样式 ----------
C_DARK = "1F3864"
C_HEAD = "2E5C8A"
C_BAND = "EAF1F8"
C_WARN = "FCE4E4"
C_OK = "E7F4E4"
C_TITLE_FONT = Font(name="微软雅黑", size=16, bold=True, color="FFFFFF")
C_HEAD_FONT = Font(name="微软雅黑", size=10, bold=True, color="FFFFFF")
C_BODY = Font(name="微软雅黑", size=10)
C_BODY_B = Font(name="微软雅黑", size=10, bold=True)
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
WRAP = Alignment(horizontal="left", vertical="center", wrap_text=True)
CENTER = Alignment(horizontal="center", vertical="center", wrap_text=True)


def read_tsv(name):
    path = os.path.join(RAW, name + ".tsv")
    if not os.path.exists(path):
        return []
    rows = []
    with io.open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n").rstrip("\r")
            if not line:
                continue
            rows.append([("" if c == "\\N" else c) for c in line.split("\t")])
    return rows


def num(v):
    try:
        f = float(v)
        return int(f) if f == int(f) else round(f, 4)
    except (TypeError, ValueError):
        return v


# ---------- 数据准备 ----------
check = read_tsv("check")          # table, dim, col, metric, value, sample
enum = read_tsv("enum")            # table, col, value, cnt, is_legal
missing = read_tsv("missing")      # table, col, missing_cnt, missing_rate, strategy, filled, null_after
dup = read_tsv("dup")              # category, groups, extra, rule
dedup = read_tsv("dedup")          # item, cnt

by_key = defaultdict(dict)
for t, d, c, m, v, s in check:
    by_key[(d, t, c)][m] = num(v)
    if s and s != "":
        by_key[(d, t, c)][m + "_sample"] = s

TABLES = ["ods_user", "ods_product", "ods_store", "ods_order", "ods_order_item", "ods_user_behavior"]
TABLE_CN = {
    "ods_user": "用户表", "ods_product": "商品表", "ods_store": "门店表",
    "ods_order": "订单表", "ods_order_item": "订单明细表", "ods_user_behavior": "用户行为表",
}
ROW_CNT = {"ods_user": 1000, "ods_product": 600, "ods_store": 60,
           "ods_order": 15600, "ods_order_item": 37549, "ods_user_behavior": 60000}

wb = Workbook()


def style_header(ws, row_idx, ncol):
    for c in range(1, ncol + 1):
        cell = ws.cell(row=row_idx, column=c)
        cell.font = C_HEAD_FONT
        cell.fill = PatternFill("solid", fgColor=C_HEAD)
        cell.alignment = CENTER
        cell.border = BORDER


def style_body(ws, r1, r2, ncol, zebra=True):
    for r in range(r1, r2 + 1):
        for c in range(1, ncol + 1):
            cell = ws.cell(row=r, column=c)
            cell.font = C_BODY
            cell.border = BORDER
            cell.alignment = WRAP if c <= 3 else CENTER
            if zebra and (r - r1) % 2 == 1:
                cell.fill = PatternFill("solid", fgColor=C_BAND)


def set_widths(ws, widths):
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w


# ---------- Sheet 1：报告说明 ----------
ws = wb.active
ws.title = "报告说明"
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:D1")
ws["A1"] = "云购生活新零售 · 第 1 周 数据质量预评估表"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER

meta = [
    ("项目名称", "云购生活新零售企业——企业级数据仓库与经营分析可视化系统"),
    ("团队 / 成员", "workai / 张文杰"),
    ("评估对象", "ODS 贴源层 6 张表，合计 104,809 行"),
    ("评估维度", "完整性 / 唯一性 / 有效性 / 一致性 / 准确性"),
    ("评估方式", "Hive 3.1.3 + Hive SQL（sql/quality/data_quality_check.sql），结果导出后成表"),
    ("评估结论", "六张表中 4 张质量良好，2 张（用户表、订单表）存在明显脏数据；"
               "订单表重复率 3.85%，枚举字段非法取值占比高，需按计划在清洗（一）（二）中处理"),
]
r = 3
for k, v in meta:
    ws.cell(row=r, column=1, value=k).font = C_BODY_B
    ws.cell(row=r, column=1).fill = PatternFill("solid", fgColor=C_BAND)
    ws.cell(row=r, column=1).border = BORDER
    ws.cell(row=r, column=1).alignment = CENTER
    ws.merge_cells(start_row=r, start_column=2, end_row=r, end_column=4)
    cell = ws.cell(row=r, column=2, value=v)
    cell.font = C_BODY
    cell.alignment = WRAP
    cell.border = BORDER
    ws.row_dimensions[r].height = 34 if len(v) > 30 else 22
    r += 1

r += 1
ws.cell(row=r, column=1, value="五维度定义与判定口径").font = Font(name="微软雅黑", size=11, bold=True, color=C_DARK)
r += 1
defs = [
    ("维度", "含义", "本次判定口径", "问题记录方式"),
    ("完整性", "字段是否缺失", "col IS NULL OR TRIM(col)='' 记为缺失", "记录空值数与空值率"),
    ("唯一性", "主键是否唯一", "主键重复 = 同一 PK 出现>1 次；整行重复 = 全部字段相同", "记录重复组数与多出行数"),
    ("有效性", "枚举取值是否合法", "对照业务允许取值集合（见附录）", "记录非法取值及出现次数"),
    ("一致性", "格式/引用是否统一", "日期 yyyy-MM-dd、手机号 11 位、外键能否关联", "记录格式不符数与孤儿记录数"),
    ("准确性", "数值是否业务合理", "年龄 1~120、金额>0、折扣 0~1、成本<=售价", "记录越界记录数"),
]
for i, row in enumerate(defs):
    for j, v in enumerate(row, start=1):
        cell = ws.cell(row=r, column=j, value=v)
        cell.border = BORDER
        cell.alignment = WRAP
        cell.font = C_HEAD_FONT if i == 0 else C_BODY
        if i == 0:
            cell.fill = PatternFill("solid", fgColor=C_HEAD)
        elif i % 2 == 0:
            cell.fill = PatternFill("solid", fgColor=C_BAND)
    r += 1
set_widths(ws, [16, 30, 52, 30])

# ---------- Sheet 2：完整性 ----------
ws = wb.create_sheet("1-完整性")
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:G1")
ws["A1"] = "维度一：完整性 —— 全字段空值统计（51 个字段）"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER
headers = ["表名", "表中文名", "字段", "空值数", "空值率", "是否需处理", "说明"]
for j, h in enumerate(headers, start=1):
    ws.cell(row=2, column=j, value=h)
style_header(ws, 2, len(headers))

r = 3
for t in TABLES:
    for c in sorted([k[2] for k in by_key if k[0] == "完整性" and k[1] == t],
                    key=lambda x: [x2[2] for x2 in by_key if x2[0] == "完整性" and x2[1] == t].index(x)):
        d = by_key[("完整性", t, c)]
        cnt = d.get("null_cnt", 0)
        rate = d.get("null_rate", 0)
        need = "是" if cnt > 0 else "否"
        note = ""
        if cnt > 0:
            note = "缺失率 %.2f%%，需在清洗（一）中处理" % (rate * 100)
        vals = [t, TABLE_CN[t], c, cnt, "%.2f%%" % (rate * 100), need, note]
        for j, v in enumerate(vals, start=1):
            ws.cell(row=r, column=j, value=v)
        if cnt > 0:
            for j in range(1, len(headers) + 1):
                ws.cell(row=r, column=j).fill = PatternFill("solid", fgColor=C_WARN)
        r += 1
style_body(ws, 3, r - 1, len(headers), zebra=False)
set_widths(ws, [18, 12, 18, 10, 10, 12, 40])
ws.freeze_panes = "A3"

# ---------- Sheet 3：唯一性 ----------
ws = wb.create_sheet("2-唯一性")
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:F1")
ws["A1"] = "维度二：唯一性 —— 主键重复与整行重复"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER

headers = ["表名", "主键", "总行数", "重复主键数", "多出行数", "重复率", "结论"]
for j, h in enumerate(headers, start=1):
    ws.cell(row=2, column=j, value=h)
style_header(ws, 2, len(headers))
r = 3
for t in TABLES:
    d = by_key.get(("唯一性", t, "order_id" if t == "ods_order" else
                    {"ods_user": "user_id", "ods_product": "product_id", "ods_store": "store_id",
                     "ods_order_item": "item_id", "ods_user_behavior": "behavior_id"}[t]), {})
    pk = {"ods_user": "user_id", "ods_product": "product_id", "ods_store": "store_id",
          "ods_order": "order_id", "ods_order_item": "item_id", "ods_user_behavior": "behavior_id"}[t]
    extra = d.get("pk_dup_extra_rows", 0)
    rate = d.get("pk_dup_rate", 0) if t == "ods_order" else (extra / ROW_CNT[t] if ROW_CNT[t] else 0)
    conc = "存在重复，需去重" if extra else "主键唯一，无需处理"
    sample = d.get("pk_dup_extra_rows_sample", "")
    vals = [t, pk, ROW_CNT[t], (sample.replace("重复主键个数=", "") if sample else (extra and "-") or 0),
            extra, "%.2f%%" % (rate * 100), conc]
    for j, v in enumerate(vals, start=1):
        ws.cell(row=r, column=j, value=v)
    if extra:
        for j in range(1, len(headers) + 1):
            ws.cell(row=r, column=j).fill = PatternFill("solid", fgColor=C_WARN)
    r += 1
style_body(ws, 3, r - 1, len(headers), zebra=False)

r += 1
ws.cell(row=r, column=1, value="订单表重复形态拆解").font = Font(name="微软雅黑", size=11, bold=True, color=C_DARK)
r += 1
sub = ["重复类型", "重复组数", "多出行数", "处理方式"]
for j, h in enumerate(sub, start=1):
    ws.cell(row=r, column=j, value=h)
style_header(ws, r, len(sub))
r += 1
for row in sorted(dup, key=lambda x: {"整行完全重复": 0, "主键重复但内容不同": 1, "重复主键合计": 2}.get(x[0], 9)):
    for j, v in enumerate([row[0], num(row[1]), num(row[2]), row[3]], start=1):
        ws.cell(row=r, column=j, value=v)
    r += 1
style_body(ws, r - len(dup), r - 1, len(sub))
set_widths(ws, [18, 14, 12, 14, 12, 10, 26])
ws.freeze_panes = "A3"

# ---------- Sheet 4：有效性 ----------
ws = wb.create_sheet("3-有效性")
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:F1")
ws["A1"] = "维度三：有效性 —— 枚举字段取值合法性"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER
headers = ["表名", "字段", "非法取值数", "非法占比", "非法取值明细（值×条数）", "结论"]
for j, h in enumerate(headers, start=1):
    ws.cell(row=2, column=j, value=h)
style_header(ws, 2, len(headers))

enum_map = defaultdict(list)
for t, c, v, cnt, legal in enum:
    if legal == "N":
        enum_map[(t, c)].append((("(空)" if v == "" else v), num(cnt)))

r = 3
for t, c, k in sorted([(k[1], k[2], k) for k in by_key if k[0] == "有效性"]):
    d = by_key[k]
    cnt = d.get("illegal_cnt", 0)
    rate = d.get("illegal_rate", 0)
    detail = "、".join("%s×%s" % (v, n) for v, n in sorted(enum_map.get((t, c), []), key=lambda x: -x[1])[:8])
    vals = [t, c, cnt, "%.2f%%" % (rate * 100), detail, "需标准化映射" if cnt else "取值规范"]
    for j, v in enumerate(vals, start=1):
        ws.cell(row=r, column=j, value=v)
    if cnt:
        for j in range(1, len(headers) + 1):
            ws.cell(row=r, column=j).fill = PatternFill("solid", fgColor=C_WARN)
    r += 1
style_body(ws, 3, r - 1, len(headers), zebra=False)
set_widths(ws, [18, 18, 12, 10, 62, 16])
ws.freeze_panes = "A3"

# ---------- Sheet 5：一致性 ----------
ws = wb.create_sheet("4-一致性")
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:F1")
ws["A1"] = "维度四：一致性 —— 格式统一性与引用完整性"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER
headers = ["表名", "检查对象", "指标", "异常数量", "样例 / 说明", "结论"]
for j, h in enumerate(headers, start=1):
    ws.cell(row=2, column=j, value=h)
style_header(ws, 2, len(headers))
r = 3
items = [k for k in by_key if k[0] == "一致性"]
items.sort(key=lambda k: (TABLES.index(k[1]),
                          "orphan_cnt" in by_key[k],
                          k[2]))
for k in items:
    t, c = k[1], k[2]
    for metric, val in sorted(by_key[k].items()):
        if metric.endswith("_sample"):
            continue
        sample = by_key[k].get(metric + "_sample", "")
        label = "格式不符数" if metric == "bad_format_cnt" else "孤儿记录数"
        conc = "需标准化" if val else "通过"
        vals = [t, c, label, val, sample if sample else "", conc]
        for j, v in enumerate(vals, start=1):
            ws.cell(row=r, column=j, value=v)
        if val:
            for j in range(1, len(headers) + 1):
                ws.cell(row=r, column=j).fill = PatternFill("solid", fgColor=C_WARN)
        r += 1
        break
style_body(ws, 3, r - 1, len(headers), zebra=False)
set_widths(ws, [20, 20, 12, 10, 42, 14])
ws.freeze_panes = "A3"

# ---------- Sheet 6：准确性 ----------
ws = wb.create_sheet("5-准确性")
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:F1")
ws["A1"] = "维度五：准确性 —— 数值取值合理性"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER
headers = ["表名", "字段", "检查项", "异常数量", "说明", "结论"]
for j, h in enumerate(headers, start=1):
    ws.cell(row=2, column=j, value=h)
style_header(ws, 2, len(headers))
METRIC_CN = {
    "out_of_range_cnt": "超出合理区间",
    "negative_cnt": "出现负值",
    "outlier_cnt": "异常大额",
    "non_positive_cnt": "非正数",
    "cost_gt_price_cnt": "成本高于售价",
}
r = 3
acc = [k for k in by_key if k[0] == "准确性"]
acc.sort(key=lambda k: (TABLES.index(k[1]), k[2]))
for k in acc:
    for metric, val in sorted(by_key[k].items()):
        if metric.endswith("_sample"):
            continue
        desc = by_key[k].get(metric + "_sample", "")
        vals = [k[1], k[2], METRIC_CN.get(metric, metric), val, desc,
                "需清洗" if val else "通过"]
        for j, v in enumerate(vals, start=1):
            ws.cell(row=r, column=j, value=v)
        if val:
            for j in range(1, len(headers) + 1):
                ws.cell(row=r, column=j).fill = PatternFill("solid", fgColor=C_WARN)
        r += 1
style_body(ws, 3, r - 1, len(headers), zebra=False)
set_widths(ws, [18, 16, 14, 10, 44, 12])
ws.freeze_panes = "A3"

# ---------- Sheet 7：清洗效果 ----------
ws = wb.create_sheet("6-清洗效果验证")
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:G1")
ws["A1"] = "清洗（一）效果验证 —— 缺失值处理策略与重复值去重结果"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER
headers = ["表名", "字段", "清洗前缺失数", "缺失率", "处理策略", "被填充数", "清洗后仍为空"]
for j, h in enumerate(headers, start=1):
    ws.cell(row=2, column=j, value=h)
style_header(ws, 2, len(headers))
r = 3
for row in missing:
    vals = [row[0], row[1], num(row[2]), "%.2f%%" % (float(row[3]) * 100), row[4], num(row[5]), num(row[6])]
    for j, v in enumerate(vals, start=1):
        ws.cell(row=r, column=j, value=v)
    r += 1
style_body(ws, 3, r - 1, len(headers))

r += 1
ws.cell(row=r, column=1, value="重复值去重结果").font = Font(name="微软雅黑", size=11, bold=True, color=C_DARK)
r += 1
sub = ["项目", "行数"]
for j, h in enumerate(sub, start=1):
    ws.cell(row=r, column=j, value=h)
style_header(ws, r, len(sub))
r += 1
for row in dedup:
    for j, v in enumerate([row[0], num(row[1])], start=1):
        ws.cell(row=r, column=j, value=v)
    r += 1
style_body(ws, r - len(dedup), r - 1, len(sub))
set_widths(ws, [18, 20, 14, 10, 44, 12, 14])

# ---------- Sheet 8：问题清单 ----------
ws = wb.create_sheet("7-问题清单")
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:E1")
ws["A1"] = "问题清单与处理计划（按严重程度排序）"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER
headers = ["序号", "严重度", "问题描述", "影响", "处理计划"]
for j, h in enumerate(headers, start=1):
    ws.cell(row=2, column=j, value=h)
style_header(ws, 2, len(headers))
issues = [
    ("高", "ods_order 主键重复：586 个 order_id 重复，多出 600 行（400 行整行重复 + 200 行金额不同）",
     "订单数与 GMV 虚高 3.85%，去重规则不当会丢真实成交金额", "第 1 周 清洗（一）：ROW_NUMBER 按业务规则去重（已完成）"),
    ("高", "ods_user 性别/会员等级/年龄/邮箱缺失，合计 342 个空值（邮箱缺失率 19.3%）",
     "用户画像分组会漏人，留存/复购分析失真", "第 1 周 清洗（一）：中位数填充 + 默认值 + 标记位（已完成）"),
    ("高", "枚举字段中英文混用：order_status 有 8 类非法取值共 5477 行；behavior_type 非法 47345 行",
     "状态漏斗与转化率统计口径错乱", "第 2 周 清洗（二）：建立映射字典统一为标准值"),
    ("中", "日期格式不统一：order_date 1902 行、register_date 125 行、behavior_time 6088 行为 yyyy/MM/dd",
     "按日期分区/聚合时大量记录无法归入正确日期", "第 2 周 清洗（二）：正则归一 + TO_DATE"),
    ("中", "金额异常：订单实付负值 310 行、异常大额 312 行，优惠金额负值 769 行；商品售价负值 20 行",
     "GMV、客单价、毛利率指标被严重拉偏", "第 2 周 清洗（二）：置空 + 按业务规则重算"),
    ("中", "明细表数量异常：quantity<=0 共 718 行，unit_price 负值 798 行",
     "销量、销售额统计失真", "第 2 周 清洗（二）"),
    ("低", "手机号格式：102 个带分隔符（179-4507-0500）",
     "影响用户触达与去重", "第 2 周 清洗（二）：去除非数字字符"),
    ("低", "商品上架日期缺失 11 条", "商品生命周期分析样本缺失", "第 1 周 清洗（一）：同品类均值补全（已完成）"),
    ("低", "ods_product.category 存在尾部空格（如'图书文娱 '）导致品类被拆成 9 组",
     "按品类聚合时出现重复分组", "第 2 周 清洗（二）：TRIM 统一"),
]
r = 3
for i, row in enumerate(issues, start=1):
    vals = [i] + list(row)
    for j, v in enumerate(vals, start=1):
        ws.cell(row=r, column=j, value=v)
    if row[0] == "高":
        for j in range(1, len(headers) + 1):
            ws.cell(row=r, column=j).fill = PatternFill("solid", fgColor=C_WARN)
    ws.row_dimensions[r].height = 40
    r += 1
style_body(ws, 3, r - 1, len(headers), zebra=False)
set_widths(ws, [6, 8, 62, 36, 40])
ws.freeze_panes = "A3"

# ---------- Sheet 9：附录 ----------
ws = wb.create_sheet("附录-枚举分布")
ws.sheet_view.showGridLines = False
ws.merge_cells("A1:E1")
ws["A1"] = "附录：枚举字段实际取值分布（用于说明「为什么算非法」）"
ws["A1"].font = C_TITLE_FONT
ws["A1"].fill = PatternFill("solid", fgColor=C_DARK)
ws["A1"].alignment = CENTER
headers = ["表名", "字段", "取值", "条数", "是否合法"]
for j, h in enumerate(headers, start=1):
    ws.cell(row=2, column=j, value=h)
style_header(ws, 2, len(headers))
r = 3
for t, c, v, cnt, legal in sorted(enum, key=lambda x: (x[0], x[1], x[4], -float(x[3] or 0))):
    for j, val in enumerate([t, c, ("(空字符串)" if v == "" else v), num(cnt),
                             "合法" if legal == "Y" else "非法"], start=1):
        ws.cell(row=r, column=j, value=val)
    if legal == "N":
        for j in range(1, len(headers) + 1):
            ws.cell(row=r, column=j).fill = PatternFill("solid", fgColor=C_WARN)
    r += 1
style_body(ws, 3, r - 1, len(headers), zebra=False)
set_widths(ws, [18, 18, 22, 10, 10])
ws.freeze_panes = "A3"

wb.save(OUT)
print("已生成 ->", OUT)
