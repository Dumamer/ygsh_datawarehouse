#!/usr/bin/env bash
# =====================================================================
# run_all.sh —— 第 1 周一键执行脚本
#
# 依次执行：建库建表 -> 导入 ODS -> 行数校验 -> 五维度质量评估 -> 缺失值处理 -> 去重
# 每一步的输出同时打印到屏幕并写入 docs/运行记录/*.log，作为交付证据。
#
# 用法：
#   bash scripts/run_all.sh                      # Docker/集群环境（默认调用 hive）
#   HIVE_BIN="bash scripts/hive-local.sh" bash scripts/run_all.sh   # Windows 本地模式
#
# 环境变量：
#   HIVE_BIN   Hive 客户端命令（默认 hive）
#   DATA_DIR   原始 CSV 所在目录（默认 <repo>/data；Docker 容器内为 /data）
# =====================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HIVE_BIN="${HIVE_BIN:-hive}"
DATA_DIR="${DATA_DIR:-$ROOT/data}"
LOGDIR="$ROOT/docs/运行记录"
mkdir -p "$LOGDIR"

FAIL=0

run_step() {
  local name="$1"; shift
  local log="$LOGDIR/$name.log"
  local raw="$LOGDIR/.$name.raw"
  echo ""
  echo "============================================================"
  echo "▶ $name"
  echo "============================================================"
  # shellcheck disable=SC2086
  if $HIVE_BIN "$@" > "$raw" 2>&1; then
    filter_log "$raw" "$log"
    rm -f "$raw"
    echo "✔ $name 完成（日志：docs/运行记录/$name.log）"
  else
    filter_log "$raw" "$log"
    rm -f "$raw"
    echo "✘ $name 失败，请查看 docs/运行记录/$name.log"
    FAIL=1
  fi
}

# 去掉 Hive 的日志噪音（时间戳 / MapReduce 进度 / 连接信息），只留可读的执行结果
filter_log() {
  grep -vE '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:,]+ ' "$1" \
    | grep -vE '^(SLF4J|Logging initialized|Hive Session ID|Query ID|Total jobs|Number of reduce|Ended Job|Job running|MapReduce Jobs|Total MapReduce|In order to)' \
    | grep -vE '^Launching Job|is filtered out by|is selected by|^Stage-Stage|^No Stats for|^Warning: Shuffle Join' \
    | grep -vE '^\s+set (mapreduce|hive)\.' \
    | grep -vE 'preemption|Speculative execution|Committed|Completed executing|INFO' \
    | sed -E 's/\b_u[0-9]+\.//g' \
    | grep -vE '^$' > "$2" || true
}

run_step "01_create_ods"  -f "$ROOT/sql/ods/create_ods.sql"
run_step "02_load_ods"    --hiveconf "data_dir=$DATA_DIR" -f "$ROOT/sql/ods/load_ods.sql"
run_step "03_verify_ods"  -f "$ROOT/sql/ods/verify_ods.sql"
run_step "04_quality"     -f "$ROOT/sql/quality/data_quality_check.sql"
run_step "05_clean_missing" -f "$ROOT/sql/clean/clean_user_missing.sql"
run_step "06_clean_dedup" -f "$ROOT/sql/clean/clean_order_dedup.sql"

echo ""
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  echo "全部步骤执行完成。下一步："
  echo "  1) 导出质量指标：见 docs/运行记录/04_quality.log"
  echo "  2) 生成 Excel：python scripts/build_quality_report.py"
else
  echo "存在失败步骤，请按日志逐个排查。"
fi
echo "============================================================"
exit "$FAIL"
