# -*- coding: utf-8 -*-
"""渲染第 2 周数仓分层架构图（Edge headless）。"""
import io, os, subprocess, time

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(BASE, "docs", "screenshots")
HTML_DIR = os.path.join(OUT, "_html")
MSEDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{background:#f5f7fa;font-family:'Microsoft YaHei',sans-serif;padding:24px}
.canvas{width:1350px;margin:0 auto}
h1{text-align:center;font-size:22px;color:#1a2b4c;margin-bottom:4px}
.sub{text-align:center;color:#7a8699;font-size:12.5px;margin-bottom:18px}
.layers{display:flex;flex-direction:column;gap:0}
.layer{display:flex;align-items:stretch;gap:14px;margin-bottom:0}
.tag{width:150px;border-radius:10px;color:#fff;display:flex;flex-direction:column;justify-content:center;align-items:center;padding:12px 8px;flex-shrink:0}
.tag .en{font-size:11px;opacity:.85;letter-spacing:1px}
.tag .cn{font-size:17px;font-weight:700;margin-top:2px}
.body{flex:1;background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:10px 14px;box-shadow:0 1px 4px rgba(20,40,80,.06)}
.body .desc{font-size:12px;color:#5a6577;margin-bottom:8px}
.tables{display:flex;flex-wrap:wrap;gap:6px}
.tb{font-size:11.5px;padding:3px 9px;border-radius:5px;font-family:Consolas,monospace}
.fact{background:#fdeee7;color:#c2510c;border:1px solid #f5c9ad}
.dim{background:#e8f1fd;color:#1d5db4;border:1px solid #b9d4f5}
.agg{background:#eaf7ef;color:#1a7f4e;border:1px solid #b5e2c8}
.src{background:#f1f2f6;color:#555f70;border:1px solid #d8dce5}
.arrowrow{display:flex;align-items:center;gap:14px;padding:2px 0 2px 0}
.arrow{width:150px;display:flex;justify-content:center;color:#94a3b8;font-size:15px;flex-shrink:0}
.arnote{font-size:11.5px;color:#8a94a6;background:#eef2f7;border-radius:6px;padding:3px 12px}
.legend{display:flex;justify-content:center;gap:16px;margin-top:14px;font-size:11.5px;color:#5a6577}
.legend span{display:inline-flex;align-items:center;gap:5px}
.dot{width:10px;height:10px;border-radius:3px;display:inline-block}
"""

def tag(color, en, cn):
    return f'<div class="tag" style="background:{color}"><div class="en">{en}</div><div class="cn">{cn}</div></div>'

def tb(cls, name):
    return f'<span class="tb {cls}">{name}</span>'

layers = f"""
<div class="layers">

<div class="layer">{tag('#8395a7','OPERATIONAL DATA STORE','ODS 贴源层')}
 <div class="body"><div class="desc">原样接入业务系统数据，全字段 STRING 贴源存储，保留全部脏数据不做加工 · 粒度：与源系统一致</div>
  <div class="tables">{tb('src','ods_user 1,000')}{tb('src','ods_product 600')}{tb('src','ods_store 60')}{tb('src','ods_order 15,600')}{tb('src','ods_order_item 37,549')}{tb('src','ods_user_behavior 60,000')}</div></div></div>

<div class="arrowrow"><div class="arrow">▼</div><div class="arnote">清洗四板斧：缺失值填充 · 去重 · 异常值修正 · 枚举/格式标准化（w2_01 ~ w2_03）</div></div>

<div class="layer">{tag('#3b82c4','DATA WAREHOUSE DETAIL','DWD 明细层')}
 <div class="body"><div class="desc">清洗、标准化、维度建模 —— 星型模型：事实表存度量与外键，维度表存描述属性 · 粒度：明细事实 / 维度成员 · ORC 列式存储 + 分区/分桶</div>
  <div class="tables">{tb('fact','dwd_order 15,000（按日期分区）')}{tb('fact','dwd_order_item 36,831（按 order_id 分 8 桶）')}{tb('fact','dwd_user_behavior 60,000（按日期分区）')}{tb('dim','dim_user 1,000')}{tb('dim','dim_product 600')}{tb('dim','dim_store 60')}{tb('dim','dim_date 731')}{tb('dim','dim_code_mapping 32')}</div></div></div>

<div class="arrowrow"><div class="arrow">▼</div><div class="arnote">按主题轻度汇总：按 月 / 门店-日 聚合，复用中间结果减少重复计算</div></div>

<div class="layer">{tag('#3fa46a','DATA WAREHOUSE SERVICE','DWS 汇总层')}
 <div class="body"><div class="desc">按分析主题做轻度聚合 · 粒度：月 / 门店-日 等汇总粒度</div>
  <div class="tables">{tb('agg','dws_sales_ym（月度销售）')}{tb('agg','dws_store_sales_d（门店日销售）')}</div></div></div>

<div class="arrowrow"><div class="arrow">▼</div><div class="arnote">面向报表与看板输出最终指标</div></div>

<div class="layer">{tag('#e08c2e','APPLICATION DATA SERVICE','ADS 应用层')}
 <div class="body"><div class="desc">直接支撑 KPI 看板、排行与可视化 · 粒度：指标级结果</div>
  <div class="tables">{tb('agg','ads_kpi_overview')}{tb('agg','ads_category_sales')}{tb('agg','ads_province_sales')}{tb('agg','ads_channel_sales')}{tb('agg','ads_user_top10')}{tb('agg','ads_user_cumsum_top')}</div></div></div>

</div>
<div class="legend">
 <span><i class="dot src"></i>源数据表</span>
 <span><i class="dot fact"></i>事实表（度量 + 外键）</span>
 <span><i class="dot dim"></i>维度表（描述属性）</span>
 <span><i class="dot agg"></i>汇总 / 指标表</span>
</div>
"""

html = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>{CSS}</style></head>
<body><div class="canvas">
<h1>云购生活数仓 · 四层架构设计图</h1>
<div class="sub">ODS → DWD → DWS → ADS ｜ 星型模型 ｜ 数据流向自上而下，清洗加工发生在 ODS → DWD</div>
{layers}
</div></body></html>"""

os.makedirs(HTML_DIR, exist_ok=True)
hp = os.path.join(HTML_DIR, "arch.html").replace("\\", "/")
io.open(hp, "w", encoding="utf-8").write(html)
png = os.path.join(HTML_DIR, "arch.png").replace("\\", "/")
subprocess.run([MSEDGE, "--headless=new", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
                "--window-size=1400,760", f"--screenshot={png}", "file:///" + hp],
               capture_output=True, timeout=90, cwd=HTML_DIR)
for _ in range(30):
    if os.path.exists(png): break
    time.sleep(0.5)
dst = os.path.join(OUT, "06_数仓四层架构图.png")
os.replace(png, dst)
print("done", os.path.getsize(dst), "bytes")
