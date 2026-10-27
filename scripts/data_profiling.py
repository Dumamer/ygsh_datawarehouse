# -*- coding: utf-8 -*-
"""
data_profiling.py —— ODS 层数据质量预评估（五维度）辅助脚本

用途：
    在 Hive 环境不可用（或需要交叉验证）时，用纯 Python 对 ODS 层 6 张 CSV
    做与 sql/quality/data_quality_check.sql 等价的统计，输出 JSON + Markdown。
    结果用于生成 docs/数据质量预评估表.xlsx。

五维度定义：
    完整性 completeness —— 字段空值率
    唯一性 uniqueness     —— 主键重复率 / 整行重复
    有效性 validity       —— 枚举字段取值是否越界
    一致性 consistency    —— 关键格式是否统一（日期、手机号、省市）
    准确性 accuracy       —— 数值取值是否落在业务合理区间

运行：
    python scripts/data_profiling.py
    python scripts/data_profiling.py --data-dir "D:/cxdownload/模拟数据/模拟数据" --out docs
"""
import argparse
import csv
import io
import json
import os
import re
from collections import Counter, defaultdict
from datetime import datetime

TABLES = {
    "ods_user": {
        "pk": "user_id",
        "date_cols": ["register_date"],
        "enum_cols": {"gender": ["男", "女"],
                      "member_level": ["普通会员", "银卡", "金卡", "钻石"]},
        "num_cols": {"age": (1, 120)},
    },
    "ods_product": {
        "pk": "product_id",
        "date_cols": ["launch_date"],
        "enum_cols": {"status": ["在售", "缺货", "下架"]},
        "num_cols": {"price": (0, 100000), "cost": (0, 100000), "stock": (0, 100000)},
    },
    "ods_store": {
        "pk": "store_id",
        "date_cols": ["open_date"],
        "enum_cols": {},
        "num_cols": {"area": (0, 100000)},
    },
    "ods_order": {
        "pk": "order_id",
        "date_cols": ["order_date"],
        "enum_cols": {"pay_type": ["微信", "支付宝", "银行卡", "货到付款"],
                      "order_status": ["已完成", "已取消", "待支付", "待发货", "退款中"],
                      "channel": ["APP", "小程序", "门店", "PC"]},
        "num_cols": {"pay_amount": (0, 1e6), "discount_amount": (0, 1e6)},
    },
    "ods_order_item": {
        "pk": "item_id",
        "date_cols": [],
        "enum_cols": {},
        "num_cols": {"quantity": (1, 1000), "unit_price": (0, 1e6), "discount": (0, 1)},
    },
    "ods_user_behavior": {
        "pk": "behavior_id",
        "date_cols": [],
        "enum_cols": {"behavior_type": ["browse", "收藏", "加购", "buy"]},
        "num_cols": {},
    },
}

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
DATETIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
PHONE_RE = re.compile(r"^1[3-9]\d{9}$")


def read_csv(path):
    with io.open(path, encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        rows = [r for r in reader if any(x.strip() for x in r)]
    return header, rows


def is_null(v):
    return v is None or str(v).strip() == "" or str(v).strip().upper() in ("NULL", "\\N", "NAN")


def profile_table(name, cfg, path):
    header, rows = read_csv(path)
    idx = {c: i for i, c in enumerate(header)}
    total = len(rows)

    # ---- 完整性 ----
    completeness = []
    for col in header:
        i = idx[col]
        nulls = sum(1 for r in rows if is_null(r[i]))
        completeness.append({
            "column": col,
            "null_cnt": nulls,
            "null_rate": round(nulls / total, 6) if total else 0,
            "distinct": len({r[i] for r in rows if not is_null(r[i])}),
        })

    # ---- 唯一性 ----
    pk = cfg["pk"]
    pk_vals = [r[idx[pk]] for r in rows]
    pk_counter = Counter(pk_vals)
    dup_pk_rows = sum(c - 1 for c in pk_counter.values() if c > 1)
    dup_pk_values = sum(1 for c in pk_counter.values() if c > 1)
    full_row_counter = Counter(tuple(r) for r in rows)
    dup_full_rows = sum(c - 1 for c in full_row_counter.values() if c > 1)
    # 主键重复但内容不同
    pk_diff_content = 0
    seen = defaultdict(set)
    for r in rows:
        seen[r[idx[pk]]].add(tuple(r))
    for k, v in seen.items():
        if len(v) > 1:
            pk_diff_content += len(v) - 1
    uniqueness = {
        "pk": pk,
        "total_rows": total,
        "distinct_pk": len(pk_counter),
        "dup_pk_value_cnt": dup_pk_values,
        "dup_pk_extra_rows": dup_pk_rows,
        "dup_pk_rate": round(dup_pk_rows / total, 6) if total else 0,
        "dup_full_row_extra": dup_full_rows,
        "pk_dup_content_diff_extra": pk_diff_content,
    }

    # ---- 有效性 ----
    validity = []
    for col, legal in cfg["enum_cols"].items():
        c = Counter(r[idx[col]] for r in rows)
        illegal = {k: v for k, v in c.items() if k not in legal}
        validity.append({
            "column": col,
            "legal_values": legal,
            "distribution": dict(c.most_common()),
            "illegal_cnt": sum(illegal.values()),
            "illegal_values": illegal,
        })

    # ---- 一致性 ----
    consistency = []
    for col in cfg["date_cols"]:
        bad = Counter()
        for r in rows:
            v = r[idx[col]]
            if is_null(v):
                continue
            if not DATE_RE.match(v):
                bad[v] += 1
            else:
                try:
                    datetime.strptime(v, "%Y-%m-%d")
                except ValueError:
                    bad[v] += 1
        consistency.append({"column": col, "rule": "yyyy-MM-dd", "bad_cnt": sum(bad.values()),
                            "samples": dict(list(bad.items())[:5])})

    if "phone" in idx:
        bad = Counter()
        for r in rows:
            v = r[idx["phone"]]
            if is_null(v):
                continue
            if not PHONE_RE.match(v.strip()):
                bad[v] += 1
        consistency.append({"column": "phone", "rule": "11 位手机号 ^1[3-9]\\d{9}$",
                            "bad_cnt": sum(bad.values()), "samples": dict(list(bad.items())[:5])})

    if "province" in idx and "city" in idx:
        pairs = defaultdict(set)
        for r in rows:
            pairs[r[idx["province"]]].add(r[idx["city"]])
        multi = {p: sorted(c) for p, c in pairs.items() if len(c) > 1}
        consistency.append({"column": "province-city", "rule": "一省一城映射一致",
                            "bad_cnt": len(multi), "samples": dict(list(multi.items())[:5])})

    # ---- 准确性 ----
    accuracy = []
    for col, (lo, hi) in cfg["num_cols"].items():
        out_of_range = 0
        neg = 0
        nonnum = 0
        samples = []
        for r in rows:
            v = r[idx[col]]
            if is_null(v):
                continue
            try:
                f = float(v)
            except ValueError:
                nonnum += 1
                if len(samples) < 5:
                    samples.append(v)
                continue
            if f < 0:
                neg += 1
            if not (lo <= f <= hi):
                out_of_range += 1
                if len(samples) < 5:
                    samples.append(v)
        accuracy.append({"column": col, "range": [lo, hi], "out_of_range": out_of_range,
                         "negative": neg, "non_numeric": nonnum, "samples": samples})

    return {
        "table": name,
        "total_rows": total,
        "columns": header,
        "completeness": completeness,
        "uniqueness": uniqueness,
        "validity": validity,
        "consistency": consistency,
        "accuracy": accuracy,
    }


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--data-dir", default=os.path.join(here, "data"))
    ap.add_argument("--out", default=os.path.join(here, "docs"))
    args = ap.parse_args()

    result = {}
    for name, cfg in TABLES.items():
        path = os.path.join(args.data_dir, name + ".csv")
        if not os.path.exists(path):
            print("[skip] 未找到 %s" % path)
            continue
        result[name] = profile_table(name, cfg, path)
        print("[ok] %-18s rows=%d" % (name, result[name]["total_rows"]))

    os.makedirs(args.out, exist_ok=True)
    with io.open(os.path.join(args.out, "quality_profile.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
    print("已输出 ->", os.path.join(args.out, "quality_profile.json"))


if __name__ == "__main__":
    main()
