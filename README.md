# 云购生活数据仓库项目 · workai

> 企业级数据仓库与经营分析可视化系统 —— 从 6 张原始 CSV 到可支撑经营决策的分析体系

![week](https://img.shields.io/badge/进度-第2周-brightgreen) ![hive](https://img.shields.io/badge/Hive-3.1.3-blue) ![license](https://img.shields.io/badge/用途-课程实训-lightgrey)

---

## 一、团队信息

| 项目 | 内容 |
|---|---|
| 队名 | **workai** |
| 成员 | 张文杰 |
| 口号 | 让每一行脏数据都有归宿 |
| 仓库 | https://github.com/Dumamer/ygsh_datawarehouse |

## 二、角色分工

本项目按课程要求的四个岗位划分，当前由 1 人承担多岗，后续成员加入后按此表交接：

| 角色 | 负责人 | 主要职责 | 本周产出 |
|---|---|---|---|
| 项目经理 | 张文杰 | 需求拆解、进度把控、Git 规范制定、答辩汇报 | README、阶段计划、提交规范 |
| 数据工程师 | 张文杰 | 环境搭建、ODS 建表导入、数据清洗 SQL 开发 | `docker/`、`sql/ods/`、`sql/clean/` |
| 数据分析师 | 张文杰 | 五维度数据质量评估、问题定级与处理策略 | `sql/quality/`、数据质量预评估表 |
| 可视化工程师 | 张文杰 | 质量结果可视化呈现、报告排版 | 质量预评估表 Excel、质量报告图表 |

## 三、项目目标

1. **工程目标**：搭起一套可复现的本地数仓环境（Hive + MySQL Metastore），所有脚本一键可跑。
2. **数据目标**：把 6 张业务 CSV 原样落进 ODS 贴源层，行数与数据字典完全一致。
3. **质量目标**：用「完整性 / 唯一性 / 有效性 / 一致性 / 准确性」五维度量化评估数据质量，问题可定位、可量化、可追踪。
4. **治理目标**：完成清洗第一阶段（缺失值处理 + 重复值去重），产出可被下游直接使用的 DWD 明细表。
5. **协作目标**：建立规范的 Git 工作流（Conventional Commits + `.gitignore`），让每一步操作可追溯。

## 四、阶段计划

| 周次 | 主题 | 关键产出 |
|---|---|---|
| 第 1 周 | 项目启动 / 环境搭建 / Git 基础 / 数据导入与清洗（一） | ODS 6 张表、质量预评估表、`dwd_user`/`dwd_order` |
| 第 2 周 | 清洗进阶 / 数仓建模 / 探索分析 | 枚举标准化、日期归一、维表建模、EDA 报告 |
| 第 3 周 | 分析 / 预测 / AI 协同 | 指标体系、RFM、销量预测、AI 协同日志（二） |
| 第 4 周 | 可视化 / 部署 | Superset 看板、部署上线 |
| 第 5 周 | 整合 / 文档 / 答辩 | 项目文档、答辩 PPT、最终交付 |

## 五、技术栈

| 层次 | 选型 | 说明 |
|---|---|---|
| 运行环境 | Docker Desktop / Docker Compose | 课程标准方案，`docker/` 下一键编排 |
| 数仓引擎 | Apache Hive 3.1.3 | ODS/DWD 层 SQL 开发 |
| 元数据 | MySQL 8.0（课程方案）/ Derby（本机回退方案） | Metastore |
| 开发语言 | Hive SQL、Bash、Python 3.13 | 数据加工 + 报告生成 |
| 版本管理 | Git + GitHub（HTTPS + PAT） | Conventional Commits |
| 可视化（后续） | Superset / ECharts | 第 4 周 |

## 六、仓库结构

```
ydsh-datawarehouse/
├─ README.md                          # 本文件
├─ .gitignore                         # 忽略数据/日志/密钥
├─ docker/
│  ├─ docker-compose.yml              # Hive + MySQL 编排（课程标准方案）
│  └─ README.md                       # 环境启动说明
├─ sql/
│  ├─ ods/
│  │  ├─ create_ods.sql               # 建库 + 6 张表建表语句
│  │  ├─ load_ods.sql                 # 6 张 CSV 导入
│  │  └─ verify_ods.sql               # 行数校验（对比数据字典）
│  ├─ quality/
│  │  ├─ data_quality_check.sql       # 第 1 周五维度质量扫描
│  │  ├─ w2_repair_rate.sql           # 第 2 周：清洗前后修复率（37 条记录 / 20 类问题）
│  │  └─ w2_export_tsv.sql            # 第 2 周：指标结果导出 tsv（供报告排版）
│  ├─ clean/
│  │  ├─ clean_user_missing.sql       # 第 1 周：缺失值诊断与处理
│  │  ├─ clean_order_dedup.sql        # 第 1 周：重复值检测与去重
│  │  ├─ w2_01_enum_normalize.sql     # 第 2 周：6 个枚举字段标准化 + 去空格
│  │  ├─ w2_02_anomaly_format.sql     # 第 2 周：异常值修正 + 日期/时间/手机号格式归一 + 去重
│  │  └─ w2_03_merge_encode.sql       # 第 2 周：32 条编码映射表 + order_timestamp / region 合并
│  ├─ dwd/
│  │  ├─ create_dwd.sql               # 第 2 周：星型模型 DDL（3 事实 + 5 维度，ORC/分区/分桶）
│  │  └─ load_dwd.sql                 # 第 2 周：维度全量加载 + 事实表动态分区加载
│  └─ analysis/
│     ├─ w2_explore.sql               # 第 2 周：DWS 汇总 + ADS 指标 + 窗口函数
│     └─ w2_explore_extra.sql         # 第 2 周：门店/会员/周末/复购/环比五个补充分析
├─ scripts/
│  ├─ run_all.sh                      # 第 1 周：一键跑通 ODS→质量→清洗
│  ├─ run_week2.sh                    # 第 2 周：一键跑通 07~15 全部步骤
│  ├─ hive-local.sh                   # Windows 无 Docker 时的本地模式启动器
│  ├─ data_profiling.py               # 质量数据交叉校验（Python 版）
│  ├─ build_quality_report.py         # 生成《数据质量预评估表.xlsx》
│  ├─ build_w2_report.py              # 生成《数据质量清洗报告.xlsx》
│  ├─ make_arch_diagram.py            # 渲染四层架构图 PNG
│  └─ make_screenshots.py             # 从真实日志渲染关键截图
├─ docs/
│  ├─ 环境搭建笔记.md                  # 踩坑记录与解决方案
│  ├─ 数据质量预评估表.xlsx            # 第 1 周五维度扫描结果
│  ├─ 数据质量预评估说明.md            # 结论解读
│  ├─ 数据质量清洗报告.xlsx / .md      # 第 2 周：修复率对比报告
│  ├─ 数仓架构设计文档.md              # 第 2 周：四层架构 + 命名规范 + 分区分桶策略
│  ├─ 第2周_探索性分析简报.md          # 第 2 周：核心指标与分布分析
│  ├─ 模拟数据字典.md                  # 6 张表字段与脏数据分布
│  ├─ 答辩提纲.md                      # 5~8 分钟汇报提纲 + 预设追问
│  ├─ workai_第1周_AI协同日志.md       # 第 1 周 AI 协同日志
│  ├─ workai_第2周_AI协同日志.md       # 第 2 周 AI 协同日志
│  ├─ screenshots/                     # 关键执行截图（PNG）
│  ├─ 运行记录/                        # 各脚本真实执行输出 01~15（证据留存）
│  ├─ quality_raw/                     # 第 1 周质量指标原始导出
│  └─ w2_raw/                          # 第 2 周指标结果原始导出（tsv）
└─ data/                               # 原始 CSV（已 gitignore，不入库）
```

## 七、快速开始

### 方案 A：Docker（课程标准方案）

```bash
cd docker
docker compose up -d          # 启动 mysql / hive-metastore / hive-server
docker ps                     # 三个容器均为 Up 即成功
bash ../scripts/run_all.sh    # 一键执行建表 -> 导入 -> 校验 -> 质量 -> 清洗
```

### 方案 B：Windows 本地模式（无 Docker 时）

```bash
# 依赖：JDK 8 + Hadoop 3.1.1(winutils) + Hive 3.1.3，配置见 docs/环境搭建笔记.md
export HIVE_BIN="bash $(pwd)/scripts/hive-local.sh"
bash scripts/run_all.sh          # 第 1 周：ODS 建表 → 导入 → 校验 → 质量 → 清洗
bash scripts/run_week2.sh        # 第 2 周：枚举标准化 → 异常/格式 → 编码映射 → DWD → 修复率 → 探索分析
```

> 第 2 周脚本依次执行 07~15 共 9 步，每步的完整输出落在 `docs/运行记录/`，
> 报告与简报中的每个数字都能在该目录找到出处。

## 八、第 1 周完成情况

| # | 交付物 | 状态 | 位置 |
|---|---|---|---|
| 1 | README.md | ✅ | 本文件 |
| 2 | 环境搭建笔记 | ✅ | `docs/环境搭建笔记.md` |
| 3 | Git 仓库（.gitignore + 规范提交） | ✅ | 本仓库提交历史 |
| 4 | ODS 建表与导入脚本 | ✅ | `sql/ods/` |
| 5 | 数据质量预评估表 | ✅ | `docs/数据质量预评估表.xlsx` |
| 6 | 缺失值 / 重复值清洗脚本 | ✅ | `sql/clean/` |
| 7 | AI 协同日志 | ✅ | `docs/workai_第1周_AI协同日志.md` |

### ODS 导入校验结果

| 表名 | 实际行数 | 预期行数 | 结果 |
|---|---:|---:|---|
| ods_user | 1,000 | 1,000 | PASS |
| ods_product | 600 | 600 | PASS |
| ods_store | 60 | 60 | PASS |
| ods_order | 15,600 | 15,600 | PASS |
| ods_order_item | 37,549 | 37,549 | PASS |
| ods_user_behavior | 60,000 | 60,000 | PASS |

### 数据质量结论（一句话版）

> 6 张表中 4 张干净、2 张脏：**订单表重复率 3.85%（多出 600 行）**，**用户表空值 342 个（邮箱缺失 19.3%）**，
> 枚举字段中英文混用导致 `order_status` 非法占比 35.11%、`behavior_type` 非法 78.9%。
> 本周已处理缺失值与重复值，枚举标准化与日期归一放在第 2 周。

### 清洗成果

| 指标 | 清洗前 | 清洗后 |
|---|---:|---:|
| `dwd_user` 年龄空值 / 越界 | 51 / 27 | 0 / 0 |
| `dwd_user` 性别、等级空值 | 84 / 14 | 0 / 0 |
| `dwd_product` 上架日期空值 | 11 | 0 |
| `dwd_order` 行数（重复） | 15,600（600 行重复） | 15,000（0 重复） |

## 九、第 2 周完成情况

### 9.1 交付物清单（任务书 §五）

| # | 交付物 | 状态 | 位置 |
|:---:|---|:---:|---|
| 1 | 枚举标准化 / 异常值 / 格式清洗脚本 | ✅ | `sql/clean/w2_01~03` |
| 2 | 数据质量对比报告 | ✅ | `docs/数据质量清洗报告.xlsx` + `.md` |
| 3 | 数仓架构设计文档 | ✅ | `docs/数仓架构设计文档.md`、`docs/screenshots/06_数仓四层架构图.png` |
| 4 | DWD 层建模与 ETL 脚本 | ✅ | `sql/dwd/create_dwd.sql`、`load_dwd.sql` |
| 5 | 探索性分析简报 | ✅ | `docs/第2周_探索性分析简报.md` |
| 6 | Git 提交记录 | ✅ | 按子任务拆分，见提交历史 |
| 7 | AI 协同日志（二） | ✅ | `docs/workai_第2周_AI协同日志.md` |

### 9.2 清洗成果：五类脏数据全部收敛

| 脏数据类型 | 清洗前 | 清洗后残留 | 修复率 | 关键策略 |
|---|---:|---:|---:|---|
| 缺失值 | 187 | 0 | 100% | 年龄中位数填充 + 标记位、性别/等级填默认值、上架日期按品类均值回退（**邮箱 193 条策略性保留，不计入分母**） |
| 重复值 | 600 | 0 | 100% | `ROW_NUMBER` 四级排序（金额有效性 > 时间新 > 金额大 > 兜底） |
| 异常值 | 2,886 | 0 | 100% | 金额明细回填 / 置 NULL 打标；折扣与单价取绝对值；数量 ≤0 整行剔除 |
| 枚举值 | 60,601 | 0 | 100% | 性别/等级走 `CASE WHEN`，状态/支付/渠道/行为走 32 条编码映射表 JOIN |
| 格式 | 8,217 | 0 | 100% | 日期斜杠与紧凑格式归一、行为时间补秒位、手机号去分隔符 |
| **合计** | **72,491** | **0** | **100%** | 20 类问题逐项可查，见报告「2-修复率总表」；分母不含邮箱 193 条 |

### 9.3 DWD 层建模结果

| 层 | 表 | 行数 | 存储 |
|---|---|---:|---|
| DWD 维度 | dim_user / dim_product / dim_store / dim_date / dim_code_mapping | 1,000 / 600 / 60 / 731 / 32 | ORC |
| DWD 事实 | dwd_order | 15,000 | ORC + 366 个日分区 |
| DWD 事实 | dwd_order_item | 36,831 | ORC + 按 order_id 分 8 桶 |
| DWD 事实 | dwd_user_behavior | 60,000 | ORC + 92 个日分区 |

> 踩坑记录：本地模式默认 `hive.exec.max.dynamic.partitions.pernode=100`，
> 而 `dwd_order` 需要 366 个日分区，超出上限时**不报错、只静默失败**（`MapRedTask return code 2`）。
> 调到 1000 后一次写出全部分区，详见 `docs/运行记录/11_load_dwd.log` 与第 2 周 AI 日志。

### 9.4 探索性分析核心数字

| 指标 | 值 | 指标 | 值 |
|---|---:|---|---:|
| 有效订单量 | 12,505 | 总 GMV | ¥31,845,527.95 |
| 购买用户数 | 1,000 | 客单价 AOV | ¥2,546.62 |
| 人均下单 | 12.51 单 | 折扣率 / 退款中占比 | 12.80% / 6.31% |
| 品类 CR3 | 42.66% | 省份 CR3 / 门店 TOP1 占比 | 22.29% / 2.03% |

**一致性自检**：12 个月 GMV 相加 = `ads_kpi_overview.total_gmv`，差额 **0.00 元**，四层口径传递无损耗。

### 9.5 结论一句话版

> 清洗侧：五类脏数据 72,491 个问题点全部收敛到 0（另有邮箱 193 条按策略保留、不编造），20 类问题逐项可查、可复现。
> 建模侧：星型模型 + 日分区 + 分桶落成，月度汇总与总 GMV 严格对齐。
> 分析侧：指标链路已闭环，但**渠道四等分、会员等级无差异、周末零效应、复购高度集中**四项
> 证明模拟数据为独立随机生成——简报已把这些划为「数据局限」，而不是包装成经营结论。

## 十、Git 提交规范（Conventional Commits）

| 前缀 | 用途 | 示例 |
|---|---|---|
| `feat` | 新增功能/脚本/表 | `feat(ods): 新增 6 张表建表脚本` |
| `fix` | 修复错误 | `fix(clean): 修正去重排序键` |
| `docs` | 文档变更 | `docs: 补充环境搭建笔记` |
| `refactor` | 重构（不改行为） | `refactor(quality): 用 explode(map) 简化空值统计` |
| `chore` | 杂项（配置、依赖） | `chore: 更新 .gitignore` |
| `data` | 数据/结果文件 | `data: 导出质量预评估表` |

**提交粒度**：一个子任务一到两次提交，提交信息说清「做了什么、为什么」。

## 十一、参考资料

- [GitHub Docs](https://docs.github.com/) · [Git Reference](https://git-scm.com/doc)
- [Apache Hive 官方文档](https://hive.apache.org/) · [Docker Docs](https://docs.docker.com/)

---

<div align="center">workai · 第 2 周交付 · 2026-11</div>
