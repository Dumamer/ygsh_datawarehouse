-- =====================================================================
-- 第 2 周 · 子任务 6（下）：DWD 层数据加载
--   维度表一次性全量加载；事实表动态分区加载 + 分桶加载
-- =====================================================================
SET hive.auto.convert.join=false;
SET hive.vectorized.execution.enabled=false;
SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
-- 踩坑：默认 hive.exec.max.dynamic.partitions.pernode=100，dwd_order 有 366 个日分区，
-- 本地模式下不报原因直接 MapRedTask return code 2（对比：92 分区的行为表可正常写入）
SET hive.exec.max.dynamic.partitions.pernode=1000;
SET hive.exec.max.dynamic.partitions=1000;

-- ---------- 1. 维度表加载 ----------
-- 编码映射表（CTAS 自 tmp 层，含映射依据备注）
DROP TABLE IF EXISTS ydsh_dwd.dim_code_mapping;
CREATE TABLE ydsh_dwd.dim_code_mapping STORED AS ORC AS
SELECT code_type, code_value, std_name, remark
FROM ydsh_tmp.dim_code_mapping;

INSERT OVERWRITE TABLE ydsh_dwd.dim_user
SELECT user_id, user_name, gender, age, city, province, region, member_level,
       register_date, phone, email,
       age_is_filled,
       IF(TRIM(email) = '', 1, 0)
FROM ydsh_tmp.t_user_final;

-- launch_date 缺失沿用第 1 周策略：按同品类上架日期均值回退，品类无样本用全局均值兜底
INSERT OVERWRITE TABLE ydsh_dwd.dim_product
SELECT p.product_id, p.product_name, p.category, p.sub_category, p.brand,
       IF(TRIM(p.launch_date) = '',
          date_sub('2024-12-31', CAST(ROUND(COALESCE(c.metric_value, g.metric_value)) AS INT)),
          p.launch_date)          AS launch_date,
       p.price, p.cost, p.stock, p.status
FROM ydsh_tmp.t_product_std p
LEFT JOIN (SELECT * FROM ydsh_dq.dq_fill_baseline WHERE metric_name LIKE 'launch_days_%' AND metric_name <> 'launch_days_ALL') c
       ON c.metric_name = CONCAT('launch_days_', p.category)
LEFT JOIN (SELECT * FROM ydsh_dq.dq_fill_baseline WHERE metric_name = 'launch_days_ALL') g
       ON TRIM(p.launch_date) = '';

INSERT OVERWRITE TABLE ydsh_dwd.dim_store
SELECT store_id, store_name, province, city, district, address,
       open_date, area, manager
FROM ydsh_ods.ods_store;

-- 时间维度：posexplode 生成 2023-01-01 起 731 天
INSERT OVERWRITE TABLE ydsh_dwd.dim_date
SELECT d                                                            AS date_key,
       CAST(substr(d, 1, 4) AS INT)                                 AS year,
       CAST(substr(d, 6, 2) AS INT)                                 AS month,
       CAST(substr(d, 9, 2) AS INT)                                 AS day,
       substr(d, 1, 7)                                              AS ym,
       CAST(ceil(CAST(substr(d, 6, 2) AS INT) / 3.0) AS INT)        AS quarter,
       CAST(date_format(d, 'u') AS INT)                             AS day_of_week,
       IF(date_format(d, 'u') IN ('6', '7'), 1, 0)                  AS is_weekend
FROM (
  SELECT date_add('2023-01-01', pos) AS d
  FROM (SELECT posexplode(split(space(730), ' ')) AS (pos, x)) t
) g;

-- ---------- 2. 事实表加载（动态分区） ----------
INSERT OVERWRITE TABLE ydsh_dwd.dwd_order PARTITION (order_date)
SELECT order_id, user_id, store_id, order_timestamp,
       pay_amount, pay_amount_is_repaired, discount_amount,
       pay_type, order_status, channel,
       order_date
FROM ydsh_tmp.t_order_final;

INSERT OVERWRITE TABLE ydsh_dwd.dwd_order_item
SELECT item_id, order_id, product_id, quantity, unit_price, discount, line_amount
FROM ydsh_tmp.t_item_clean;

INSERT OVERWRITE TABLE ydsh_dwd.dwd_user_behavior PARTITION (behavior_date)
SELECT user_id, product_id, behavior_type, behavior_time,
       behavior_date
FROM ydsh_tmp.t_behavior_final;

-- ---------- 3. 加载验证 ----------
SELECT 'dwd_order 行数'      AS chk, CAST(COUNT(*) AS STRING) AS v FROM ydsh_dwd.dwd_order
UNION ALL SELECT 'dwd_order 分区数', CAST(COUNT(DISTINCT order_date) AS STRING) FROM ydsh_dwd.dwd_order
UNION ALL SELECT 'dwd_order_item 行数', CAST(COUNT(*) AS STRING) FROM ydsh_dwd.dwd_order_item
UNION ALL SELECT 'dwd_user_behavior 行数', CAST(COUNT(*) AS STRING) FROM ydsh_dwd.dwd_user_behavior
UNION ALL SELECT 'dim_user 行数', CAST(COUNT(*) AS STRING) FROM ydsh_dwd.dim_user
UNION ALL SELECT 'dim_product 行数', CAST(COUNT(*) AS STRING) FROM ydsh_dwd.dim_product
UNION ALL SELECT 'dim_store 行数', CAST(COUNT(*) AS STRING) FROM ydsh_dwd.dim_store
UNION ALL SELECT 'dim_date 行数', CAST(COUNT(*) AS STRING) FROM ydsh_dwd.dim_date
UNION ALL SELECT 'dim_code_mapping 行数', CAST(COUNT(*) AS STRING) FROM ydsh_dwd.dim_code_mapping;

SHOW PARTITIONS ydsh_dwd.dwd_order;
