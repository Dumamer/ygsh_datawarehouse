-- =====================================================================
-- 文件：sql/quality/data_quality_check.sql
-- 作用：对 ODS 层 6 张表做「完整性 / 唯一性 / 有效性 / 一致性 / 准确性」
--       五维度数据质量预评估，所有指标落表到 ydsh_dq 库，供导出 Excel
-- 执行：hive -f sql/quality/data_quality_check.sql
-- 产出：ydsh_dq.dq_check_result        五维度量化指标（长表）
--       ydsh_dq.dq_enum_distribution   枚举字段取值分布（明细）
-- 说明：
--   1. Hive 3 的 LazySimpleSerDe 默认 serialization.null.format='\N'，
--      CSV 里的空字段会读成空字符串 '' 而不是 NULL，
--      因此「缺失」统一用 (col IS NULL OR TRIM(col) = '') 判定，
--      这一条是很多同学统计空值率时数字对不上的根本原因。
--   2. 结果表用 DOUBLE 存指标值，行数类指标也是 DOUBLE，导出时再格式化。
--   3. 本脚本只做「诊断」，不做任何修改数据的动作，可反复执行。
-- =====================================================================

CREATE DATABASE IF NOT EXISTS ydsh_dq;

-- 本机以「本地模式（in-process）」运行 Hive，MapredLocalTask 在 Windows 下会起子进程
-- 执行小表广播 join 而失败，因此关闭 map join，改用普通 reduce join。
-- 若在 Docker/集群环境执行，可删掉这两行。
SET hive.auto.convert.join=false;
SET hive.auto.convert.join.noconditionaltask=false;

USE ydsh_dq;

DROP TABLE IF EXISTS ydsh_dq.dq_check_result;
CREATE TABLE ydsh_dq.dq_check_result (
  table_name   STRING COMMENT '被检表名',
  dimension    STRING COMMENT '维度：完整性/唯一性/有效性/一致性/准确性',
  column_name  STRING COMMENT '字段名或检查对象',
  metric       STRING COMMENT '指标名',
  metric_value DOUBLE COMMENT '指标值',
  sample       STRING COMMENT '样例值（异常示例）',
  check_time   STRING COMMENT '检查时间'
)
COMMENT '数据质量预评估结果（长表）'
STORED AS TEXTFILE;

DROP TABLE IF EXISTS ydsh_dq.dq_enum_distribution;
CREATE TABLE ydsh_dq.dq_enum_distribution (
  table_name  STRING,
  column_name STRING,
  value       STRING,
  cnt         BIGINT,
  is_legal    STRING
)
COMMENT '枚举字段取值分布与合法性标记'
STORED AS TEXTFILE;

-- =====================================================================
-- 一、完整性：全字段空值数 / 空值率
--     每张表用 explode(map(...)) 把「宽表聚合结果」转成「长表」，
--     避免为 51 个字段写 51 条 UNION ALL。
-- =====================================================================
INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_user', '完整性', t.col, 'null_cnt', CAST(t.n AS DOUBLE), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(user_id       IS NULL OR TRIM(user_id)       = '', 1, 0)) AS c1,
         SUM(IF(user_name     IS NULL OR TRIM(user_name)     = '', 1, 0)) AS c2,
         SUM(IF(gender        IS NULL OR TRIM(gender)        = '', 1, 0)) AS c3,
         SUM(IF(age           IS NULL OR TRIM(age)           = '', 1, 0)) AS c4,
         SUM(IF(city          IS NULL OR TRIM(city)          = '', 1, 0)) AS c5,
         SUM(IF(province      IS NULL OR TRIM(province)      = '', 1, 0)) AS c6,
         SUM(IF(register_date IS NULL OR TRIM(register_date) = '', 1, 0)) AS c7,
         SUM(IF(member_level  IS NULL OR TRIM(member_level)  = '', 1, 0)) AS c8,
         SUM(IF(phone         IS NULL OR TRIM(phone)         = '', 1, 0)) AS c9,
         SUM(IF(email         IS NULL OR TRIM(email)         = '', 1, 0)) AS c10
  FROM ydsh_ods.ods_user
) s
LATERAL VIEW explode(map('user_id', s.c1, 'user_name', s.c2, 'gender', s.c3, 'age', s.c4,
                         'city', s.c5, 'province', s.c6, 'register_date', s.c7,
                         'member_level', s.c8, 'phone', s.c9, 'email', s.c10)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_user', '完整性', t.col, 'null_rate', ROUND(CAST(t.n AS DOUBLE) / s.total, 6), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(user_id       IS NULL OR TRIM(user_id)       = '', 1, 0)) AS c1,
         SUM(IF(user_name     IS NULL OR TRIM(user_name)     = '', 1, 0)) AS c2,
         SUM(IF(gender        IS NULL OR TRIM(gender)        = '', 1, 0)) AS c3,
         SUM(IF(age           IS NULL OR TRIM(age)           = '', 1, 0)) AS c4,
         SUM(IF(city          IS NULL OR TRIM(city)          = '', 1, 0)) AS c5,
         SUM(IF(province      IS NULL OR TRIM(province)      = '', 1, 0)) AS c6,
         SUM(IF(register_date IS NULL OR TRIM(register_date) = '', 1, 0)) AS c7,
         SUM(IF(member_level  IS NULL OR TRIM(member_level)  = '', 1, 0)) AS c8,
         SUM(IF(phone         IS NULL OR TRIM(phone)         = '', 1, 0)) AS c9,
         SUM(IF(email         IS NULL OR TRIM(email)         = '', 1, 0)) AS c10
  FROM ydsh_ods.ods_user
) s
LATERAL VIEW explode(map('user_id', s.c1, 'user_name', s.c2, 'gender', s.c3, 'age', s.c4,
                         'city', s.c5, 'province', s.c6, 'register_date', s.c7,
                         'member_level', s.c8, 'phone', s.c9, 'email', s.c10)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_product', '完整性', t.col, 'null_cnt', CAST(t.n AS DOUBLE), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(product_id   IS NULL OR TRIM(product_id)   = '', 1, 0)) AS c1,
         SUM(IF(product_name IS NULL OR TRIM(product_name) = '', 1, 0)) AS c2,
         SUM(IF(category     IS NULL OR TRIM(category)     = '', 1, 0)) AS c3,
         SUM(IF(sub_category IS NULL OR TRIM(sub_category) = '', 1, 0)) AS c4,
         SUM(IF(brand        IS NULL OR TRIM(brand)        = '', 1, 0)) AS c5,
         SUM(IF(price        IS NULL OR TRIM(price)        = '', 1, 0)) AS c6,
         SUM(IF(cost         IS NULL OR TRIM(cost)         = '', 1, 0)) AS c7,
         SUM(IF(stock        IS NULL OR TRIM(stock)        = '', 1, 0)) AS c8,
         SUM(IF(status       IS NULL OR TRIM(status)       = '', 1, 0)) AS c9,
         SUM(IF(launch_date  IS NULL OR TRIM(launch_date)  = '', 1, 0)) AS c10
  FROM ydsh_ods.ods_product
) s
LATERAL VIEW explode(map('product_id', s.c1, 'product_name', s.c2, 'category', s.c3,
                         'sub_category', s.c4, 'brand', s.c5, 'price', s.c6, 'cost', s.c7,
                         'stock', s.c8, 'status', s.c9, 'launch_date', s.c10)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_product', '完整性', t.col, 'null_rate', ROUND(CAST(t.n AS DOUBLE) / s.total, 6), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(product_id   IS NULL OR TRIM(product_id)   = '', 1, 0)) AS c1,
         SUM(IF(product_name IS NULL OR TRIM(product_name) = '', 1, 0)) AS c2,
         SUM(IF(category     IS NULL OR TRIM(category)     = '', 1, 0)) AS c3,
         SUM(IF(sub_category IS NULL OR TRIM(sub_category) = '', 1, 0)) AS c4,
         SUM(IF(brand        IS NULL OR TRIM(brand)        = '', 1, 0)) AS c5,
         SUM(IF(price        IS NULL OR TRIM(price)        = '', 1, 0)) AS c6,
         SUM(IF(cost         IS NULL OR TRIM(cost)         = '', 1, 0)) AS c7,
         SUM(IF(stock        IS NULL OR TRIM(stock)        = '', 1, 0)) AS c8,
         SUM(IF(status       IS NULL OR TRIM(status)       = '', 1, 0)) AS c9,
         SUM(IF(launch_date  IS NULL OR TRIM(launch_date)  = '', 1, 0)) AS c10
  FROM ydsh_ods.ods_product
) s
LATERAL VIEW explode(map('product_id', s.c1, 'product_name', s.c2, 'category', s.c3,
                         'sub_category', s.c4, 'brand', s.c5, 'price', s.c6, 'cost', s.c7,
                         'stock', s.c8, 'status', s.c9, 'launch_date', s.c10)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_store', '完整性', t.col, 'null_cnt', CAST(t.n AS DOUBLE), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(store_id   IS NULL OR TRIM(store_id)   = '', 1, 0)) AS c1,
         SUM(IF(store_name IS NULL OR TRIM(store_name) = '', 1, 0)) AS c2,
         SUM(IF(province   IS NULL OR TRIM(province)   = '', 1, 0)) AS c3,
         SUM(IF(city       IS NULL OR TRIM(city)       = '', 1, 0)) AS c4,
         SUM(IF(district   IS NULL OR TRIM(district)   = '', 1, 0)) AS c5,
         SUM(IF(address    IS NULL OR TRIM(address)    = '', 1, 0)) AS c6,
         SUM(IF(open_date  IS NULL OR TRIM(open_date)  = '', 1, 0)) AS c7,
         SUM(IF(area       IS NULL OR TRIM(area)       = '', 1, 0)) AS c8,
         SUM(IF(manager    IS NULL OR TRIM(manager)    = '', 1, 0)) AS c9
  FROM ydsh_ods.ods_store
) s
LATERAL VIEW explode(map('store_id', s.c1, 'store_name', s.c2, 'province', s.c3, 'city', s.c4,
                         'district', s.c5, 'address', s.c6, 'open_date', s.c7,
                         'area', s.c8, 'manager', s.c9)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_store', '完整性', t.col, 'null_rate', ROUND(CAST(t.n AS DOUBLE) / s.total, 6), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(store_id   IS NULL OR TRIM(store_id)   = '', 1, 0)) AS c1,
         SUM(IF(store_name IS NULL OR TRIM(store_name) = '', 1, 0)) AS c2,
         SUM(IF(province   IS NULL OR TRIM(province)   = '', 1, 0)) AS c3,
         SUM(IF(city       IS NULL OR TRIM(city)       = '', 1, 0)) AS c4,
         SUM(IF(district   IS NULL OR TRIM(district)   = '', 1, 0)) AS c5,
         SUM(IF(address    IS NULL OR TRIM(address)    = '', 1, 0)) AS c6,
         SUM(IF(open_date  IS NULL OR TRIM(open_date)  = '', 1, 0)) AS c7,
         SUM(IF(area       IS NULL OR TRIM(area)       = '', 1, 0)) AS c8,
         SUM(IF(manager    IS NULL OR TRIM(manager)    = '', 1, 0)) AS c9
  FROM ydsh_ods.ods_store
) s
LATERAL VIEW explode(map('store_id', s.c1, 'store_name', s.c2, 'province', s.c3, 'city', s.c4,
                         'district', s.c5, 'address', s.c6, 'open_date', s.c7,
                         'area', s.c8, 'manager', s.c9)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_order', '完整性', t.col, 'null_cnt', CAST(t.n AS DOUBLE), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(order_id        IS NULL OR TRIM(order_id)        = '', 1, 0)) AS c1,
         SUM(IF(user_id         IS NULL OR TRIM(user_id)         = '', 1, 0)) AS c2,
         SUM(IF(store_id        IS NULL OR TRIM(store_id)        = '', 1, 0)) AS c3,
         SUM(IF(order_date      IS NULL OR TRIM(order_date)      = '', 1, 0)) AS c4,
         SUM(IF(order_time      IS NULL OR TRIM(order_time)      = '', 1, 0)) AS c5,
         SUM(IF(pay_amount      IS NULL OR TRIM(pay_amount)      = '', 1, 0)) AS c6,
         SUM(IF(discount_amount IS NULL OR TRIM(discount_amount) = '', 1, 0)) AS c7,
         SUM(IF(pay_type        IS NULL OR TRIM(pay_type)        = '', 1, 0)) AS c8,
         SUM(IF(order_status    IS NULL OR TRIM(order_status)    = '', 1, 0)) AS c9,
         SUM(IF(channel         IS NULL OR TRIM(channel)         = '', 1, 0)) AS c10
  FROM ydsh_ods.ods_order
) s
LATERAL VIEW explode(map('order_id', s.c1, 'user_id', s.c2, 'store_id', s.c3, 'order_date', s.c4,
                         'order_time', s.c5, 'pay_amount', s.c6, 'discount_amount', s.c7,
                         'pay_type', s.c8, 'order_status', s.c9, 'channel', s.c10)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_order', '完整性', t.col, 'null_rate', ROUND(CAST(t.n AS DOUBLE) / s.total, 6), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(order_id        IS NULL OR TRIM(order_id)        = '', 1, 0)) AS c1,
         SUM(IF(user_id         IS NULL OR TRIM(user_id)         = '', 1, 0)) AS c2,
         SUM(IF(store_id        IS NULL OR TRIM(store_id)        = '', 1, 0)) AS c3,
         SUM(IF(order_date      IS NULL OR TRIM(order_date)      = '', 1, 0)) AS c4,
         SUM(IF(order_time      IS NULL OR TRIM(order_time)      = '', 1, 0)) AS c5,
         SUM(IF(pay_amount      IS NULL OR TRIM(pay_amount)      = '', 1, 0)) AS c6,
         SUM(IF(discount_amount IS NULL OR TRIM(discount_amount) = '', 1, 0)) AS c7,
         SUM(IF(pay_type        IS NULL OR TRIM(pay_type)        = '', 1, 0)) AS c8,
         SUM(IF(order_status    IS NULL OR TRIM(order_status)    = '', 1, 0)) AS c9,
         SUM(IF(channel         IS NULL OR TRIM(channel)         = '', 1, 0)) AS c10
  FROM ydsh_ods.ods_order
) s
LATERAL VIEW explode(map('order_id', s.c1, 'user_id', s.c2, 'store_id', s.c3, 'order_date', s.c4,
                         'order_time', s.c5, 'pay_amount', s.c6, 'discount_amount', s.c7,
                         'pay_type', s.c8, 'order_status', s.c9, 'channel', s.c10)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_order_item', '完整性', t.col, 'null_cnt', CAST(t.n AS DOUBLE), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(item_id    IS NULL OR TRIM(item_id)    = '', 1, 0)) AS c1,
         SUM(IF(order_id   IS NULL OR TRIM(order_id)   = '', 1, 0)) AS c2,
         SUM(IF(product_id IS NULL OR TRIM(product_id) = '', 1, 0)) AS c3,
         SUM(IF(quantity   IS NULL OR TRIM(quantity)   = '', 1, 0)) AS c4,
         SUM(IF(unit_price IS NULL OR TRIM(unit_price) = '', 1, 0)) AS c5,
         SUM(IF(discount   IS NULL OR TRIM(discount)   = '', 1, 0)) AS c6
  FROM ydsh_ods.ods_order_item
) s
LATERAL VIEW explode(map('item_id', s.c1, 'order_id', s.c2, 'product_id', s.c3,
                         'quantity', s.c4, 'unit_price', s.c5, 'discount', s.c6)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_order_item', '完整性', t.col, 'null_rate', ROUND(CAST(t.n AS DOUBLE) / s.total, 6), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(item_id    IS NULL OR TRIM(item_id)    = '', 1, 0)) AS c1,
         SUM(IF(order_id   IS NULL OR TRIM(order_id)   = '', 1, 0)) AS c2,
         SUM(IF(product_id IS NULL OR TRIM(product_id) = '', 1, 0)) AS c3,
         SUM(IF(quantity   IS NULL OR TRIM(quantity)   = '', 1, 0)) AS c4,
         SUM(IF(unit_price IS NULL OR TRIM(unit_price) = '', 1, 0)) AS c5,
         SUM(IF(discount   IS NULL OR TRIM(discount)   = '', 1, 0)) AS c6
  FROM ydsh_ods.ods_order_item
) s
LATERAL VIEW explode(map('item_id', s.c1, 'order_id', s.c2, 'product_id', s.c3,
                         'quantity', s.c4, 'unit_price', s.c5, 'discount', s.c6)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_user_behavior', '完整性', t.col, 'null_cnt', CAST(t.n AS DOUBLE), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(behavior_id   IS NULL OR TRIM(behavior_id)   = '', 1, 0)) AS c1,
         SUM(IF(user_id       IS NULL OR TRIM(user_id)       = '', 1, 0)) AS c2,
         SUM(IF(product_id    IS NULL OR TRIM(product_id)    = '', 1, 0)) AS c3,
         SUM(IF(behavior_type IS NULL OR TRIM(behavior_type) = '', 1, 0)) AS c4,
         SUM(IF(behavior_time IS NULL OR TRIM(behavior_time) = '', 1, 0)) AS c5,
         SUM(IF(session_id    IS NULL OR TRIM(session_id)    = '', 1, 0)) AS c6
  FROM ydsh_ods.ods_user_behavior
) s
LATERAL VIEW explode(map('behavior_id', s.c1, 'user_id', s.c2, 'product_id', s.c3,
                         'behavior_type', s.c4, 'behavior_time', s.c5, 'session_id', s.c6)) t AS col, n;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_user_behavior', '完整性', t.col, 'null_rate', ROUND(CAST(t.n AS DOUBLE) / s.total, 6), NULL,
       from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS total,
         SUM(IF(behavior_id   IS NULL OR TRIM(behavior_id)   = '', 1, 0)) AS c1,
         SUM(IF(user_id       IS NULL OR TRIM(user_id)       = '', 1, 0)) AS c2,
         SUM(IF(product_id    IS NULL OR TRIM(product_id)    = '', 1, 0)) AS c3,
         SUM(IF(behavior_type IS NULL OR TRIM(behavior_type) = '', 1, 0)) AS c4,
         SUM(IF(behavior_time IS NULL OR TRIM(behavior_time) = '', 1, 0)) AS c5,
         SUM(IF(session_id    IS NULL OR TRIM(session_id)    = '', 1, 0)) AS c6
  FROM ydsh_ods.ods_user_behavior
) s
LATERAL VIEW explode(map('behavior_id', s.c1, 'user_id', s.c2, 'product_id', s.c3,
                         'behavior_type', s.c4, 'behavior_time', s.c5, 'session_id', s.c6)) t AS col, n;

-- =====================================================================
-- 二、唯一性：主键重复 + 整行完全重复
-- =====================================================================
INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_order', '唯一性', 'order_id', 'pk_dup_extra_rows', CAST(c.extra AS DOUBLE),
       CONCAT('重复主键个数=', CAST(c.dup_keys AS STRING)), from_unixtime(unix_timestamp())
FROM (
  SELECT SUM(cnt - 1) AS extra, COUNT(*) AS dup_keys
  FROM (SELECT order_id, COUNT(*) AS cnt FROM ydsh_ods.ods_order GROUP BY order_id HAVING COUNT(*) > 1) t
) c
UNION ALL
SELECT 'ods_order', '唯一性', 'order_id', 'pk_dup_rate',
       ROUND(CAST(c.extra AS DOUBLE) / tt.total, 6), NULL, from_unixtime(unix_timestamp())
FROM (SELECT SUM(cnt - 1) AS extra FROM (SELECT order_id, COUNT(*) cnt FROM ydsh_ods.ods_order GROUP BY order_id HAVING COUNT(*) > 1) t) c
CROSS JOIN (SELECT COUNT(*) AS total FROM ydsh_ods.ods_order) tt
UNION ALL
-- 整行完全重复：十个字段全部相同
SELECT 'ods_order', '唯一性', '整行', 'full_row_dup_extra_rows', CAST(SUM(cnt - 1) AS DOUBLE),
       '十个字段完全相同', from_unixtime(unix_timestamp())
FROM (
  SELECT COUNT(*) AS cnt FROM ydsh_ods.ods_order
  GROUP BY order_id, user_id, store_id, order_date, order_time, pay_amount,
           discount_amount, pay_type, order_status, channel
  HAVING COUNT(*) > 1
) t
UNION ALL
-- 主键重复但内容不同 = 主键重复多出行数 - 整行完全重复多出行数
SELECT 'ods_order', '唯一性', 'order_id', 'pk_dup_diff_content_extra_rows',
       CAST(
         (SELECT SUM(cnt - 1) FROM (SELECT order_id, COUNT(*) cnt FROM ydsh_ods.ods_order GROUP BY order_id HAVING COUNT(*) > 1) a)
         -
         (SELECT SUM(cnt - 1) FROM (SELECT COUNT(*) cnt FROM ydsh_ods.ods_order
            GROUP BY order_id, user_id, store_id, order_date, order_time, pay_amount,
                     discount_amount, pay_type, order_status, channel HAVING COUNT(*) > 1) b)
       AS DOUBLE),
       '主键相同但其余字段不同', from_unixtime(unix_timestamp())
UNION ALL
SELECT 'ods_user', '唯一性', 'user_id', 'pk_dup_extra_rows', CAST(COUNT(*) - COUNT(DISTINCT user_id) AS DOUBLE), NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_user
UNION ALL
SELECT 'ods_product', '唯一性', 'product_id', 'pk_dup_extra_rows', CAST(COUNT(*) - COUNT(DISTINCT product_id) AS DOUBLE), NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_product
UNION ALL
SELECT 'ods_store', '唯一性', 'store_id', 'pk_dup_extra_rows', CAST(COUNT(*) - COUNT(DISTINCT store_id) AS DOUBLE), NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_store
UNION ALL
SELECT 'ods_order_item', '唯一性', 'item_id', 'pk_dup_extra_rows', CAST(COUNT(*) - COUNT(DISTINCT item_id) AS DOUBLE), NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order_item
UNION ALL
SELECT 'ods_user_behavior', '唯一性', 'behavior_id', 'pk_dup_extra_rows', CAST(COUNT(*) - COUNT(DISTINCT behavior_id) AS DOUBLE), NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_user_behavior;

-- =====================================================================
-- 三、有效性：枚举字段取值分布 + 非法取值统计
-- =====================================================================
INSERT INTO TABLE ydsh_dq.dq_enum_distribution
SELECT 'ods_user', 'gender', gender, COUNT(*), IF(gender IN ('男', '女'), 'Y', 'N')
FROM ydsh_ods.ods_user GROUP BY gender
UNION ALL
SELECT 'ods_user', 'member_level', member_level, COUNT(*),
       IF(member_level IN ('普通会员', '银卡', '金卡', '钻石'), 'Y', 'N')
FROM ydsh_ods.ods_user GROUP BY member_level
UNION ALL
SELECT 'ods_product', 'status', status, COUNT(*), IF(status IN ('在售', '缺货', '下架'), 'Y', 'N')
FROM ydsh_ods.ods_product GROUP BY status
UNION ALL
SELECT 'ods_order', 'pay_type', pay_type, COUNT(*), IF(pay_type IN ('微信', '支付宝', '银行卡', '货到付款'), 'Y', 'N')
FROM ydsh_ods.ods_order GROUP BY pay_type
UNION ALL
SELECT 'ods_order', 'order_status', order_status, COUNT(*), IF(order_status IN ('已完成', '已取消', '待支付', '待发货', '退款中'), 'Y', 'N')
FROM ydsh_ods.ods_order GROUP BY order_status
UNION ALL
SELECT 'ods_order', 'channel', channel, COUNT(*), IF(channel IN ('APP', '小程序', '门店', 'PC'), 'Y', 'N')
FROM ydsh_ods.ods_order GROUP BY channel
UNION ALL
SELECT 'ods_user_behavior', 'behavior_type', behavior_type, COUNT(*), IF(behavior_type IN ('browse', '收藏', '加购', 'buy'), 'Y', 'N')
FROM ydsh_ods.ods_user_behavior GROUP BY behavior_type;

INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT table_name, '有效性', column_name, 'illegal_cnt', CAST(SUM(cnt) AS DOUBLE),
       CONCAT('非法取值种类=', CAST(COUNT(*) AS STRING)), from_unixtime(unix_timestamp())
FROM ydsh_dq.dq_enum_distribution WHERE is_legal = 'N'
GROUP BY table_name, column_name
UNION ALL
SELECT d.table_name, '有效性', d.column_name, 'illegal_rate',
       ROUND(CAST(SUM(d.cnt) AS DOUBLE) / s.total, 6), NULL, from_unixtime(unix_timestamp())
FROM ydsh_dq.dq_enum_distribution d
JOIN (
  SELECT 'ods_user' AS tn, COUNT(*) AS total FROM ydsh_ods.ods_user
  UNION ALL SELECT 'ods_product', COUNT(*) FROM ydsh_ods.ods_product
  UNION ALL SELECT 'ods_order', COUNT(*) FROM ydsh_ods.ods_order
  UNION ALL SELECT 'ods_user_behavior', COUNT(*) FROM ydsh_ods.ods_user_behavior
) s ON d.table_name = s.tn
WHERE d.is_legal = 'N'
GROUP BY d.table_name, d.column_name, s.total;

-- =====================================================================
-- 四、一致性：日期 / 手机号 / 复合主键格式是否统一
--     判定方式：只要不是标准格式就计入 bad_cnt
-- =====================================================================
INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_user', '一致性', 'register_date', 'bad_format_cnt',
       CAST(SUM(IF(NOT (register_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') AND register_date IS NOT NULL, 1, 0)) AS DOUBLE),
       '示例：2024/06/21、20230829', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_user
UNION ALL
SELECT 'ods_user', '一致性', 'phone', 'bad_format_cnt',
       CAST(SUM(IF(NOT (TRIM(phone) RLIKE '^1[3-9][0-9]{9}$') AND TRIM(phone) <> '', 1, 0)) AS DOUBLE),
       '示例：179-4507-0500', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_user
UNION ALL
SELECT 'ods_order', '一致性', 'order_date', 'bad_format_cnt',
       CAST(SUM(IF(NOT (order_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') AND order_date IS NOT NULL, 1, 0)) AS DOUBLE),
       '示例：2024/09/10', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order
UNION ALL
SELECT 'ods_order', '一致性', 'order_time', 'bad_format_cnt',
       CAST(SUM(IF(NOT (order_time RLIKE '^[0-9]{2}:[0-9]{2}:[0-9]{2}$') AND order_time IS NOT NULL, 1, 0)) AS DOUBLE),
       NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order
UNION ALL
SELECT 'ods_product', '一致性', 'launch_date', 'bad_format_cnt',
       CAST(SUM(IF(NOT (launch_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') AND TRIM(launch_date) <> '', 1, 0)) AS DOUBLE),
       NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_product
UNION ALL
SELECT 'ods_store', '一致性', 'open_date', 'bad_format_cnt',
       CAST(SUM(IF(NOT (open_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') AND TRIM(open_date) <> '', 1, 0)) AS DOUBLE),
       NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_store
UNION ALL
SELECT 'ods_user_behavior', '一致性', 'behavior_time', 'bad_format_cnt',
       CAST(SUM(IF(NOT (behavior_time RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AND TRIM(behavior_time) <> '', 1, 0)) AS DOUBLE),
       NULL, from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_user_behavior
UNION ALL
-- 引用完整性：订单表里的 user_id / store_id 是否能在外键表中找到
SELECT 'ods_order', '一致性', 'user_id', 'orphan_cnt', CAST(COUNT(*) AS DOUBLE),
       '订单 user_id 在 ods_user 中不存在', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order o
LEFT JOIN (SELECT DISTINCT user_id FROM ydsh_ods.ods_user) u ON o.user_id = u.user_id
WHERE u.user_id IS NULL
UNION ALL
SELECT 'ods_order', '一致性', 'store_id', 'orphan_cnt', CAST(COUNT(*) AS DOUBLE),
       '订单 store_id 在 ods_store 中不存在', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order o
LEFT JOIN (SELECT DISTINCT store_id FROM ydsh_ods.ods_store) s ON o.store_id = s.store_id
WHERE s.store_id IS NULL
UNION ALL
SELECT 'ods_order_item', '一致性', 'order_id', 'orphan_cnt', CAST(COUNT(*) AS DOUBLE),
       '明细 order_id 在 ods_order 中不存在', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order_item i
LEFT JOIN (SELECT DISTINCT order_id FROM ydsh_ods.ods_order) o ON i.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'ods_order_item', '一致性', 'product_id', 'orphan_cnt', CAST(COUNT(*) AS DOUBLE),
       '明细 product_id 在 ods_product 中不存在', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order_item i
LEFT JOIN (SELECT DISTINCT product_id FROM ydsh_ods.ods_product) p ON i.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'ods_user_behavior', '一致性', 'product_id', 'orphan_cnt', CAST(COUNT(*) AS DOUBLE),
       '行为 product_id 在 ods_product 中不存在', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_user_behavior b
LEFT JOIN (SELECT DISTINCT product_id FROM ydsh_ods.ods_product) p ON b.product_id = p.product_id
WHERE p.product_id IS NULL;

-- =====================================================================
-- 五、准确性：数值型字段是否落在业务合理区间
-- =====================================================================
INSERT INTO TABLE ydsh_dq.dq_check_result
SELECT 'ods_user', '准确性', 'age', 'out_of_range_cnt', CAST(COUNT(*) AS DOUBLE),
       '年龄不在 [1,120] 区间（含 0、150）', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_user
WHERE TRIM(age) <> '' AND (NOT (age RLIKE '^[0-9]+$') OR CAST(age AS DOUBLE) < 1 OR CAST(age AS DOUBLE) > 120)
UNION ALL
SELECT 'ods_product', '准确性', 'price', 'negative_cnt', CAST(COUNT(*) AS DOUBLE),
       '售价为负', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_product
WHERE TRIM(price) <> '' AND price RLIKE '^-'
UNION ALL
SELECT 'ods_product', '准确性', 'price', 'outlier_cnt', CAST(COUNT(*) AS DOUBLE),
       '售价 > 100000，疑似录入错误', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_product
WHERE TRIM(price) <> '' AND price RLIKE '^[0-9.]+$' AND CAST(price AS DOUBLE) > 100000
UNION ALL
SELECT 'ods_product', '准确性', 'cost', 'cost_gt_price_cnt', CAST(COUNT(*) AS DOUBLE),
       '成本价高于售价，业务不合理', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_product
WHERE TRIM(cost) <> '' AND TRIM(price) <> '' AND CAST(cost AS DOUBLE) > CAST(price AS DOUBLE)
  AND CAST(price AS DOUBLE) > 0
UNION ALL
SELECT 'ods_order', '准确性', 'pay_amount', 'negative_cnt', CAST(COUNT(*) AS DOUBLE),
       '实付金额为负', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order
WHERE TRIM(pay_amount) <> '' AND pay_amount RLIKE '^-' 
UNION ALL
SELECT 'ods_order', '准确性', 'pay_amount', 'outlier_cnt', CAST(COUNT(*) AS DOUBLE),
       '实付金额 > 100000，疑似录入错误', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order
WHERE TRIM(pay_amount) <> '' AND pay_amount RLIKE '^[0-9.]+$' AND CAST(pay_amount AS DOUBLE) > 100000
UNION ALL
SELECT 'ods_order', '准确性', 'discount_amount', 'negative_cnt', CAST(COUNT(*) AS DOUBLE),
       '优惠金额为负', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order
WHERE TRIM(discount_amount) <> '' AND discount_amount RLIKE '^-'
UNION ALL
SELECT 'ods_order_item', '准确性', 'quantity', 'non_positive_cnt', CAST(COUNT(*) AS DOUBLE),
       '购买数量 <= 0', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order_item
WHERE TRIM(quantity) <> '' AND CAST(quantity AS DOUBLE) <= 0
UNION ALL
SELECT 'ods_order_item', '准确性', 'unit_price', 'negative_cnt', CAST(COUNT(*) AS DOUBLE),
       '成交单价为负', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order_item
WHERE TRIM(unit_price) <> '' AND unit_price RLIKE '^-'
UNION ALL
SELECT 'ods_order_item', '准确性', 'discount', 'out_of_range_cnt', CAST(COUNT(*) AS DOUBLE),
       '折扣率不在 [0,1] 区间', from_unixtime(unix_timestamp())
FROM ydsh_ods.ods_order_item
WHERE TRIM(discount) <> '' AND (CAST(discount AS DOUBLE) < 0 OR CAST(discount AS DOUBLE) > 1);

-- =====================================================================
-- 六、汇总：每个维度的问题总数，直接用于答辩汇报
-- =====================================================================
SELECT dimension,
       COUNT(*) AS metric_cnt,
       CAST(SUM(metric_value) AS BIGINT) AS metric_sum
FROM ydsh_dq.dq_check_result
WHERE metric IN ('null_cnt', 'pk_dup_extra_rows', 'illegal_cnt', 'bad_format_cnt',
                 'orphan_cnt', 'out_of_range_cnt', 'negative_cnt', 'non_positive_cnt',
                 'outlier_cnt', 'cost_gt_price_cnt')
GROUP BY dimension
ORDER BY dimension;
