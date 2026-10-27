# 云购生活数据仓库项目 · workai

> 企业级数据仓库与经营分析可视化系统 —— 从 6 张原始 CSV 到可支撑经营决策的分析体系

![week](https://img.shields.io/badge/进度-第1周-brightgreen) ![hive](https://img.shields.io/badge/Hive-3.1.3-blue) ![license](https://img.shields.io/badge/用途-课程实训-lightgrey)

---

## 一、团队信息

| 项目 | 内容 |
|---|---|
| 队名 | **workai** |
| 成员 | 张文杰 |
| 口号 | 让每一行脏数据都有归宿 |
| 仓库 | 云购生活数仓实训仓库（ODS → DWD → DWS → ADS + 可视化） |

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
│  │  └─ data_quality_check.sql       # 五维度质量扫描
│  └─ clean/
│     ├─ clean_user_missing.sql       # 缺失值诊断与处理
│     └─ clean_order_dedup.sql        # 重复值检测与去重
├─ scripts/
│  ├─ run_all.sh                      # 一键跑通本周全部 SQL
│  ├─ hive-local.sh                   # Windows 无 Docker 时的本地模式启动器
│  ├─ data_profiling.py               # 质量数据交叉校验（Python 版）
│  └─ build_quality_report.py         # 生成《数据质量预评估表.xlsx》
├─ docs/
│  ├─ 环境搭建笔记.md                  # 踩坑记录与解决方案
│  ├─ 数据质量预评估表.xlsx            # 五维度扫描结果（交付物 5）
│  ├─ 数据质量预评估说明.md            # 结论解读
│  ├─ 模拟数据字典.md                  # 6 张表字段与脏数据分布
│  ├─ workai_第1周_AI协同日志.md       # AI 协同日志（交付物 7）
│  ├─ 运行记录/                        # 各脚本真实执行输出（证据留存）
│  └─ quality_raw/                     # 质量指标原始导出（tsv，可复现）
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
bash scripts/run_all.sh
```

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

## 九、Git 提交规范（Conventional Commits）

| 前缀 | 用途 | 示例 |
|---|---|---|
| `feat` | 新增功能/脚本/表 | `feat(ods): 新增 6 张表建表脚本` |
| `fix` | 修复错误 | `fix(clean): 修正去重排序键` |
| `docs` | 文档变更 | `docs: 补充环境搭建笔记` |
| `refactor` | 重构（不改行为） | `refactor(quality): 用 explode(map) 简化空值统计` |
| `chore` | 杂项（配置、依赖） | `chore: 更新 .gitignore` |
| `data` | 数据/结果文件 | `data: 导出质量预评估表` |

**提交粒度**：一个子任务一到两次提交，提交信息说清「做了什么、为什么」。

## 十、参考资料

- [GitHub Docs](https://docs.github.com/) · [Git Reference](https://git-scm.com/doc)
- [Apache Hive 官方文档](https://hive.apache.org/) · [Docker Docs](https://docs.docker.com/)

---

<div align="center">workai · 第 1 周交付 · 2026-10</div>
