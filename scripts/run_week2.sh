#!/usr/bin/env bash
# =====================================================================
# run_week2.sh —— 第 2 周一键执行脚本
#
# 依次执行：枚举标准化 -> 异常值/格式标准化 -> 字段合并与编码映射
#           -> DWD 建模 DDL -> DWD 数据加载 -> 修复率统计
# 每步输出写入 docs/运行记录/07~12 号日志，作为交付证据。
#
# 用法：
#   bash scripts/run_week2.sh                                          # 集群/Docker 环境
#   HIVE_BIN="bash scripts/hive-local.sh" bash scripts/run_week2.sh     # Windows 本地模式
# =====================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HIVE_BIN="${HIVE_BIN:-hive}"
LOGDIR="$ROOT/docs/运行记录"
mkdir -p "$LOGDIR"

FAIL=0

filter_log() {
  grep -vE '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:,]+ ' "$1" \
    | grep -vE '^(SLF4J|Logging initialized|Hive Session ID|Query ID|Total jobs|Number of reduce|Ended Job|Job running|MapReduce Jobs|Total MapReduce|In order to)' \
    | grep -vE '^Launching Job|is filtered out by|is selected by|^Stage-Stage|^No Stats for|^Warning: Shuffle Join' \
    | grep -vE '^\s+set (mapreduce|hive)\.' \
    | grep -vE 'preemption|Speculative execution|Committed|Completed executing|INFO' \
    | sed -E 's/\b_u[0-9]+\.//g' \
    | grep -vE '^$' > "$2" || true
}

run_step() {
  local name="$1"; shift
  local log="$LOGDIR/$name.log"
  local raw="$LOGDIR/.$name.raw"
  echo ""
  echo "============================================================"
  echo "▶ $name"
  echo "============================================================"
  if $HIVE_BIN "$@" > "$raw" 2>&1; then
    filter_log "$raw" "$log"; rm -f "$raw"
    echo "✔ $name 完成"
  else
    filter_log "$raw" "$log"; rm -f "$raw"
    echo "✘ $name 失败，查看 docs/运行记录/$name.log"
    FAIL=1
  fi
}

run_step "07_w2_enum"        -f "$ROOT/sql/clean/w2_01_enum_normalize.sql"
run_step "08_w2_anomaly"     -f "$ROOT/sql/clean/w2_02_anomaly_format.sql"
run_step "09_w2_merge"       -f "$ROOT/sql/clean/w2_03_merge_encode.sql"
run_step "10_create_dwd"     -f "$ROOT/sql/dwd/create_dwd.sql"
run_step "11_load_dwd"       -f "$ROOT/sql/dwd/load_dwd.sql"
run_step "12_w2_repair_rate" -f "$ROOT/sql/quality/w2_repair_rate.sql"
run_step "13_w2_explore"     -f "$ROOT/sql/analysis/w2_explore.sql"
run_step "15_w2_explore_extra" -f "$ROOT/sql/analysis/w2_explore_extra.sql"

echo ""
echo "============================================================"
[ "$FAIL" -eq 0 ] && echo "第 2 周全部步骤执行完成" || echo "存在失败步骤，请按日志排查"
echo "============================================================"
exit "$FAIL"
