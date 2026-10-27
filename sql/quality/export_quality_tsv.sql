-- =====================================================================
-- 文件：sql/quality/export_quality_tsv.sql
-- 作用：把质量评估结果从 Hive 导出为本地 TSV，供 scripts/build_quality_report.py 生成 Excel
-- 执行：hive -f sql/quality/export_quality_tsv.sql
-- 说明：
--   1. 用 INSERT OVERWRITE LOCAL DIRECTORY 导出，Hive 会写到 local 文件系统，
--      目录下会生成 000000_0 文件（Hive 的固定命名），重命名后交给 Python。
--   2. 执行前需先跑过 sql/quality/data_quality_check.sql 与 sql/clean/ 两个脚本，
--      否则 dq_missing_strategy / dq_dedup_stat 还不存在。
-- =====================================================================
SET hive.auto.convert.join=false;

INSERT OVERWRITE LOCAL DIRECTORY '/tmp/ydsh_export/check'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT table_name, dimension, column_name, metric, metric_value, sample
FROM ydsh_dq.dq_check_result;

INSERT OVERWRITE LOCAL DIRECTORY '/tmp/ydsh_export/enum'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT table_name, column_name, value, cnt, is_legal
FROM ydsh_dq.dq_enum_distribution;

INSERT OVERWRITE LOCAL DIRECTORY '/tmp/ydsh_export/missing'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT table_name, column_name, missing_cnt, missing_rate, strategy, filled_cnt, null_after_cnt
FROM ydsh_dq.dq_missing_strategy;

INSERT OVERWRITE LOCAL DIRECTORY '/tmp/ydsh_export/dup'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT category, groups_cnt, extra_rows, handle_rule
FROM ydsh_dq.dq_order_dup_analysis;

INSERT OVERWRITE LOCAL DIRECTORY '/tmp/ydsh_export/dedup'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT item, row_cnt
FROM ydsh_dq.dq_dedup_stat;
