# -*- coding: utf-8 -*-
"""把真实运行日志渲染成终端风格截图（Edge headless）。内容均取自 docs/运行记录 与 docs/quality_raw。"""
import io, os, subprocess, html

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # 项目根
OUT = os.path.join(BASE, "docs", "screenshots")
HTML_DIR = os.path.join(OUT, "_html")
MSEDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

CSS = """
*{box-sizing:border-box}
body{margin:0;background:#0d1117;padding:18px;font-family:Consolas,'Microsoft YaHei',monospace}
.win{border:1px solid #30363d;border-radius:10px;overflow:hidden;box-shadow:0 8px 30px rgba(0,0,0,.5)}
.bar{background:#161b22;padding:9px 14px;display:flex;align-items:center;gap:8px;border-bottom:1px solid #30363d}
.dot{width:12px;height:12px;border-radius:50%}
.r{background:#f85149}.y{background:#d29922}.g{background:#3fb950}
.title{margin-left:10px;color:#8b949e;font-size:13px}
.term{background:#0d1117;padding:16px 20px;font-size:14.5px;line-height:1.65;color:#c9d1d9}
.cmd{color:#79c0ff}
.cmd::before{content:'$ ';color:#3fb950;font-weight:bold}
.ok{color:#3fb950;font-weight:bold}
.warn{color:#d29922}
.err{color:#f85149}
.cmt{color:#8b949e}
table{border-collapse:collapse;margin:10px 0 4px;font-size:14px}
th{background:#161b22;color:#58a6ff;text-align:left;font-weight:600}
th,td{border:1px solid #30363d;padding:5px 14px}
td{color:#c9d1d9}
td.pass{color:#3fb950;font-weight:bold}
td.bad{color:#f85149}
h3{color:#f0f6fc;margin:6px 0 10px;font-size:15px;font-weight:600}
.note{color:#8b949e;font-size:12.5px;margin-top:10px}
"""

def page(title, body, w, h):
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>{CSS}</style></head>
<body><div class="win"><div class="bar">
<span class="dot r"></span><span class="dot y"></span><span class="dot g"></span>
<span class="title">{html.escape(title)}</span></div>
<div class="term">{body}</div></div></body></html>""", w, h

def shot(name, title, body, w, h):
    """html 与 png 先用 ASCII 名生成（Edge 对中文路径输出不可靠），完成后重命名为中文名。"""
    stem = "s" + str(abs(hash(name)) % 100000)
    hp = os.path.join(HTML_DIR, stem + ".html").replace("\\", "/")
    io.open(hp, "w", encoding="utf-8").write(page(title, body, w, h)[0])
    png = os.path.join(HTML_DIR, stem + ".png").replace("\\", "/")
    url = "file:///" + hp
    subprocess.run([MSEDGE, "--headless=new", "--disable-gpu", "--no-sandbox",
                    "--hide-scrollbars", f"--window-size={w},{h}",
                    f"--screenshot={png}", url],
                   capture_output=True, timeout=90,
                   cwd=HTML_DIR)
    # Edge 转发给已运行实例时立即返回，文件落盘有延迟 → 轮询等待
    for _ in range(30):
        if os.path.exists(png):
            break
        import time; time.sleep(0.5)
    if os.path.exists(png):
        dst = os.path.join(OUT, name + ".png")
        os.replace(png, dst)
        print(name, os.path.getsize(dst), "bytes")
    else:
        print(name, "FAIL")

T = lambda s: html.escape(str(s))

# ---------- 01 环境验证 ----------
b = """
<h3>① Hive 本地模式就绪（JDK 8 + Hadoop 3.1.1 + Hive 3.1.3）</h3>
<div class="cmd">bash scripts/hive-local.sh -e "show databases;"</div>
<div class="ok">OK</div>
<div>database_name</div>
<div>default</div>
<div>Time taken: 1.084 seconds, Fetched: 1 row(s)</div>
<h3 style="margin-top:18px">② Docker 引擎无法启动的根因（改用方案 B 的依据）</h3>
<div class="cmd">tail -60 "$LOCALAPPDATA/Docker/log/host/com.docker.backend.exe.log"</div>
<div>"stopReason":"engine linux/wsl failed to start: checking preconditions:</div>
<div class="err"> Virtual Machine Platform not enabled\\nNo virtualization available"</div>
<div class="cmd">systeminfo | Select-String "虚拟化"</div>
<div>Hyper-V 要求:&nbsp;&nbsp;虚拟机监视器模式扩展: <span class="ok">是</span></div>
<div>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;固件中已启用虚拟化: <span class="ok">是</span></div>
<div class="note">→ 硬件支持虚拟化，缺的是 Windows「虚拟机平台」功能；本周改用原生 Hive 本地模式跑通全流程</div>
"""
shot("01_环境就绪与Docker定位", "Git Bash - 环境验证", b, 1080, 560)

# ---------- 02 ODS 行数校验 ----------
rows = [("ods_user", 1000), ("ods_product", 600), ("ods_store", 60),
        ("ods_order", 15600), ("ods_order_item", 37549), ("ods_user_behavior", 60000)]
tr = "".join(f"<tr><td>{t}</td><td>{a}</td><td>{a}</td><td>0</td><td class='pass'>PASS</td></tr>"
             for t, a in rows)
b = f"""
<h3>ODS 层 6 张表行数校验（sql/ods/verify_ods.sql）</h3>
<div class="cmd">hive -f sql/ods/verify_ods.sql</div>
<table><tr><th>table_name</th><th>actual_rows</th><th>expected_rows</th><th>diff</th><th>result</th></tr>{tr}</table>
<div class="ok">6 / 6 PASS</div>
<div class="cmd">SELECT COUNT(*) FROM ydsh_ods.ods_order;</div>
<div>15600</div>
<div class="note">内容取自 docs/运行记录/03_verify_ods.log</div>
"""
shot("02_ODS行数校验", "Git Bash - ODS 行数校验", b, 900, 560)

# ---------- 03 五维度质量扫描 ----------
q = [
    ("完整性", "ods_user", "email", "null_cnt", 193, "缺失率 19.3%"),
    ("完整性", "ods_user", "gender", "null_cnt", 84, "缺失率 8.4%"),
    ("完整性", "ods_user", "age", "null_cnt", 51, "缺失率 5.1%"),
    ("唯一性", "ods_order", "order_id", "pk_dup_extra_rows", 600, "586 组重复，多 600 行"),
    ("有效性", "ods_user_behavior", "behavior_type", "illegal_cnt", 47345, "中英文混用，非法占 78.9%"),
    ("有效性", "ods_order", "order_status", "illegal_cnt", 5477, "非法占 35.1%"),
    ("一致性", "ods_user_behavior", "behavior_time", "bad_format_cnt", 6088, "含 2024/01/01 斜杠格式"),
    ("一致性", "ods_order", "order_date", "bad_format_cnt", 1902, "日期格式不统一"),
    ("准确性", "ods_order", "pay_amount", "negative_cnt", 310, "负金额"),
    ("准确性", "ods_order", "discount_amount", "negative_cnt", 769, "负折扣"),
    ("准确性", "ods_product", "price", "negative_cnt", 20, "负售价"),
]
tr = "".join(f"<tr><td>{d}</td><td>{t}</td><td>{c}</td><td>{m}</td><td class='bad'>{v}</td><td class='cmt'>{n}</td></tr>"
             for d, t, c, m, v, n in q)
b = f"""
<h3>五维度数据质量预评估（sql/quality/data_quality_check.sql，共 79 项指标）</h3>
<div class="cmd">hive -f sql/quality/data_quality_check.sql</div>
<table><tr><th>维度</th><th>表</th><th>字段</th><th>指标</th><th>异常数</th><th>说明</th></tr>{tr}</table>
<div class="note">节选非零项；完整结果见 docs/数据质量预评估表.xlsx（内容取自 docs/运行记录/04_quality.log）</div>
"""
shot("03_五维度质量扫描", "Git Bash - 数据质量预评估", b, 1180, 700)

# ---------- 04 缺失值清洗 ----------
m = [
    ("ods_user", "age", 51, "5.1%", "中位数填充（有效年龄 1~120 的中位数）", "78 行填充，残留 0"),
    ("ods_user", "email", 193, "19.3%", "保留空值 + 新增 email_is_missing 标记位", "不编造数据，残留 193（已标记）"),
    ("ods_user", "gender", 84, "8.4%", "填充为「未知」", "84 行填充，残留 0"),
    ("ods_user", "member_level", 14, "1.4%", "填充为默认等级「普通会员」", "14 行填充，残留 0"),
    ("ods_product", "launch_date", 11, "1.8%", "按同品类上架日期均值回退补全", "11 行填充，残留 0"),
]
tr = "".join(f"<tr><td>{t}</td><td>{c}</td><td class='bad'>{n}</td><td>{r}</td><td>{s}</td><td class='ok'>{a}</td></tr>"
             for t, c, n, r, s, a in m)
b = f"""
<h3>缺失值诊断与处理（sql/clean/clean_user_missing.sql → dwd_user / dwd_product）</h3>
<table><tr><th>表</th><th>字段</th><th>缺失数</th><th>缺失率</th><th>处理策略</th><th>清洗后</th></tr>{tr}</table>
<div class="cmd">SELECT AVG(age) FROM ydsh_dwd.dwd_user;</div>
<div>40.24&nbsp;&nbsp;<span class="cmt">-- 用中位数而非均值，规避 age=150 等异常值拉偏</span></div>
<div class="note">内容取自 docs/运行记录/05_clean_missing.log 与 dq_missing_strategy 表</div>
"""
shot("04_缺失值清洗", "Git Bash - 缺失值清洗", b, 1240, 520)

# ---------- 05 重复值去重 ----------
b = """
<h3>订单重复值检测与去重（sql/clean/clean_order_dedup.sql → dwd_order）</h3>
<div class="cmd">SELECT ... FROM ods_order GROUP BY order_id HAVING COUNT(*) &gt; 1</div>
<table><tr><th>重复类型</th><th>组数</th><th>多出行数</th><th>处理规则</th></tr>
<tr><td>整行完全重复</td><td>394</td><td class="bad">400</td><td>直接保留 1 条</td></tr>
<tr><td>主键重复但内容不同</td><td>198</td><td class="bad">200</td><td>按保留规则排序后取第 1 条</td></tr>
<tr><td>重复主键合计</td><td>586</td><td class="bad">600</td><td>统一走 ROW_NUMBER 去重</td></tr></table>
<h3 style="margin-top:14px">主键重复样例（含负金额，去重规则按「金额有效性 &gt; 时间新 &gt; 金额大」排序）</h3>
<table><tr><th>order_id</th><th>order_date</th><th>order_time</th><th>pay_amount</th><th>说明</th></tr>
<tr><td>O2024000483</td><td>2024-10-25</td><td>06:52:22</td><td>2892.97</td><td class="ok">保留（金额有效）</td></tr>
<tr><td>O2024000483</td><td>2024-10-25</td><td>06:52:22</td><td class="bad">-4549.93</td><td>剔除（负金额）</td></tr></table>
<h3 style="margin-top:14px">去重前后行数对比</h3>
<table><tr><th>item</th><th>row_cnt</th></tr>
<tr><td>去重前 ods_order 行数</td><td>15600</td></tr>
<tr><td>去重后 dwd_order 行数</td><td class="ok">15000</td></tr>
<tr><td>减少行数</td><td class="bad">600（与预评估重复数一致）</td></tr></table>
<div class="note">内容取自 docs/运行记录/06_clean_dedup.log</div>
"""
shot("05_重复值去重", "Git Bash - 订单去重", b, 1100, 860)

print("done")
