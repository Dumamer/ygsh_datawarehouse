-- =====================================================================
-- 文件：sql/clean/clean_order_dedup.sql
-- 作用：数据清洗（一）—— 重复值检测与去重，产出 DWD 订单表
-- 执行：hive -f sql/clean/clean_order_dedup.sql
-- 产出：ydsh_dq.dq_order_dup_analysis  重复形态分析（整行重复 / 主键重复内容不同）
--       ydsh_dwd.dwd_order             去重后的订单明细表
--       ydsh_dq.dq_dedup_stat          去重前后行数对比
--
-- 【为什么必须区分两类重复】
--   ① 整行完全重复：10 个字段一模一样，属于采集/导入时重复投递，直接留 1 条即可；
--   ② 主键重复但内容不同：order_id 相同、pay_amount 不同，属于同一订单被多次改写
--      （例如支付回调重复、金额二次修改）。这类不能"随便留一条"，
--      必须按业务规则排序后取一条，否则会把真实成交金额丢掉。
--   本数据：586 个 order_id 重复，多出 600 行 = 400 行整行重复 + 200 行内容不同。
--
-- 【保留规则】（ORDER BY 优先级从高到低）
--   1. 金额有效性：pay_amount 为「可解析且 > 0 且 <= 100000」的记录优先，
--      避免保留负金额或七位数的脏记录；
--   2. 时间新鲜度：order_time 倒序，保留最后一次写入的记录（幂等重放的通常更靠后）；
--   3. 金额大小：同样有效时取金额较大的一条，倾向保留含完整优惠计算的记录；
--   4. 兜底确定性：以上都相同时按整行内容排序，保证多次执行结果稳定可复现。
-- =====================================================================

SET hive.auto.convert.join=false;

-- ---------------------------------------------------------------------
-- 第 1 步：重复值检测（group by + having count(*) > 1）
-- ---------------------------------------------------------------------
-- 1.1 主键重复概览
SELECT COUNT(*) AS dup_order_id_cnt,
       SUM(cnt - 1) AS extra_rows,
       ROUND(SUM(cnt - 1) / 15600, 4) AS dup_rate
FROM (
  SELECT order_id, COUNT(*) AS cnt
  FROM ydsh_ods.ods_order
  GROUP BY order_id
  HAVING COUNT(*) > 1
) t;

-- 1.2 整行完全重复（10 个字段全同）
SELECT COUNT(*) AS dup_groups, SUM(cnt - 1) AS extra_rows
FROM (
  SELECT COUNT(*) AS cnt
  FROM ydsh_ods.ods_order
  GROUP BY order_id, user_id, store_id, order_date, order_time, pay_amount,
           discount_amount, pay_type, order_status, channel
  HAVING COUNT(*) > 1
) t;

-- 1.3 主键重复但内容不同的样例（答辩时用来讲"两类重复"最有说服力）
-- 技巧：先把「订单ID + 整行内容指纹」去重，再按订单ID计数，>1 即内容有差异。
-- （Hive 不允许在 COUNT(DISTINCT expr) 里引用未参与 GROUP BY 的列）
SELECT o.order_id, o.user_id, o.order_date, o.order_time, o.pay_amount, o.pay_type, o.channel
FROM ydsh_ods.ods_order o
JOIN (
  SELECT order_id
  FROM (
    SELECT DISTINCT order_id,
           CONCAT_WS('|', user_id, store_id, order_date, order_time,
                     pay_amount, discount_amount, pay_type, order_status, channel) AS sig
    FROM ydsh_ods.ods_order
  ) d0
  GROUP BY order_id
  HAVING COUNT(*) > 1
) d ON o.order_id = d.order_id
ORDER BY o.order_id, o.order_time
LIMIT 10;

-- 1.4 重复形态落表，供质量报告引用
DROP TABLE IF EXISTS ydsh_dq.dq_order_dup_analysis;
CREATE TABLE ydsh_dq.dq_order_dup_analysis (
  category      STRING COMMENT '重复类型',
  groups_cnt    BIGINT COMMENT '重复组数',
  extra_rows    BIGINT COMMENT '多出的行数',
  handle_rule   STRING COMMENT '处理方式'
) STORED AS TEXTFILE;

INSERT INTO TABLE ydsh_dq.dq_order_dup_analysis
SELECT '整行完全重复', COUNT(*), SUM(cnt - 1), '直接保留 1 条'
FROM (
  SELECT COUNT(*) AS cnt FROM ydsh_ods.ods_order
  GROUP BY order_id, user_id, store_id, order_date, order_time, pay_amount,
           discount_amount, pay_type, order_status, channel
  HAVING COUNT(*) > 1
) a
UNION ALL
SELECT '主键重复但内容不同', COUNT(*), SUM(cnt - 1), '按保留规则排序后取第 1 条'
FROM (
  SELECT order_id, COUNT(*) AS cnt
  FROM (
    SELECT DISTINCT order_id,
           CONCAT_WS('|', user_id, store_id, order_date, order_time,
                     pay_amount, discount_amount, pay_type, order_status, channel) AS sig
    FROM ydsh_ods.ods_order
  ) b0
  GROUP BY order_id
  HAVING COUNT(*) > 1
) b
UNION ALL
SELECT '重复主键合计', COUNT(*), SUM(cnt - 1), '统一走 ROW_NUMBER 去重'
FROM (
  SELECT order_id, COUNT(*) AS cnt FROM ydsh_ods.ods_order
  GROUP BY order_id HAVING COUNT(*) > 1
) c;

-- ---------------------------------------------------------------------
-- 第 2 步：去重，输出 dwd_order
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dwd_order;
CREATE TABLE ydsh_dwd.dwd_order (
  order_id        STRING COMMENT '订单ID（已唯一）',
  user_id         STRING,
  store_id        STRING,
  order_date      STRING COMMENT '下单日期（格式标准化见第 2 周）',
  order_time      STRING COMMENT '下单时间',
  pay_amount      DOUBLE COMMENT '实付金额（异常值清理见第 2 周）',
  discount_amount DOUBLE COMMENT '优惠金额',
  pay_type        STRING,
  order_status    STRING,
  channel         STRING,
  pay_amount_valid INT   COMMENT '金额是否落在合理区间 [0,100000]：1=有效 0=异常'
)
COMMENT '订单明细表（DWD）：已完成重复值去重'
STORED AS TEXTFILE;

INSERT INTO TABLE ydsh_dwd.dwd_order
SELECT
  order_id, user_id, store_id, order_date, order_time,
  CAST(pay_amount AS DOUBLE)      AS pay_amount,
  CAST(discount_amount AS DOUBLE) AS discount_amount,
  pay_type, order_status, channel,
  CASE WHEN TRIM(pay_amount) RLIKE '^[0-9.]+$'
        AND CAST(pay_amount AS DOUBLE) > 0
        AND CAST(pay_amount AS DOUBLE) <= 100000
       THEN 1 ELSE 0 END          AS pay_amount_valid
FROM (
  SELECT o.*,
         ROW_NUMBER() OVER (
           PARTITION BY order_id
           ORDER BY
             -- 规则 1：金额有效优先
             CASE WHEN TRIM(pay_amount) RLIKE '^[0-9.]+$'
                   AND CAST(pay_amount AS DOUBLE) > 0
                   AND CAST(pay_amount AS DOUBLE) <= 100000 THEN 0 ELSE 1 END,
             -- 规则 2：时间越新越优先
             order_time DESC,
             -- 规则 3：金额越大越优先
             CAST(pay_amount AS DOUBLE) DESC,
             -- 规则 4：兜底，保证结果确定性
             CONCAT_WS('|', user_id, store_id, order_date, pay_amount,
                       discount_amount, pay_type, order_status, channel) ASC
         ) AS rn
  FROM ydsh_ods.ods_order o
) t
WHERE rn = 1;

-- ---------------------------------------------------------------------
-- 第 3 步：去重前后行数对比（必须落表，验收标准要求"差异已统计并记录"）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dq.dq_dedup_stat;
CREATE TABLE ydsh_dq.dq_dedup_stat (
  item        STRING,
  row_cnt     BIGINT
) STORED AS TEXTFILE;

INSERT INTO TABLE ydsh_dq.dq_dedup_stat
SELECT '去重前 ods_order 行数', COUNT(*) FROM ydsh_ods.ods_order;

INSERT INTO TABLE ydsh_dq.dq_dedup_stat
SELECT '去重后 dwd_order 行数', COUNT(*) FROM ydsh_dwd.dwd_order;

INSERT INTO TABLE ydsh_dq.dq_dedup_stat
SELECT '减少行数', a.cnt - b.cnt
FROM (SELECT COUNT(*) AS cnt FROM ydsh_ods.ods_order) a
CROSS JOIN (SELECT COUNT(*) AS cnt FROM ydsh_dwd.dwd_order) b;

SELECT * FROM ydsh_dq.dq_dedup_stat;

-- ---------------------------------------------------------------------
-- 第 4 步：验收
-- ---------------------------------------------------------------------
-- 4.1 order_id 必须唯一：期望 dup_cnt 行为 0 条
SELECT COUNT(*) AS remaining_dup_keys
FROM (
  SELECT order_id, COUNT(*) AS cnt FROM ydsh_dwd.dwd_order GROUP BY order_id HAVING COUNT(*) > 1
) t;

-- 4.2 减少的行数应等于预评估阶段发现的重复多出行数（600）
SELECT s.row_cnt AS removed_rows, a.extra_rows AS expected_removed,
       IF(s.row_cnt = a.extra_rows, 'PASS', 'FAIL') AS result
FROM (SELECT row_cnt FROM ydsh_dq.dq_dedup_stat WHERE item = '减少行数') s
CROSS JOIN (SELECT SUM(extra_rows) AS extra_rows FROM ydsh_dq.dq_order_dup_analysis WHERE category = '重复主键合计') a;

-- 4.3 抽样：确认保留的是"金额有效 + 时间最新"的那条
SELECT * FROM ydsh_dwd.dwd_order WHERE order_id IN ('O2024004513', 'O2024001324', 'O2024008316');
