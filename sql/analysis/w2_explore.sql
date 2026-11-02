-- =====================================================================
-- 第 2 周 · 子任务 7：探索性数据分析（DWS 汇总层 + ADS 应用层）
--   DWS：轻度汇总（月度概览 / 门店日销售）
--   ADS：面向报表的指标结果 + 窗口函数分析
--   GMV 口径：pay_amount 非空且订单状态 <> '已取消'
-- =====================================================================
SET hive.auto.convert.join=false;
SET hive.vectorized.execution.enabled=false;

CREATE DATABASE IF NOT EXISTS ydsh_dws;
CREATE DATABASE IF NOT EXISTS ydsh_ads;

-- ========== DWS 汇总层 ==========

-- 1. 月度销售汇总（年-月粒度）
DROP TABLE IF EXISTS ydsh_dws.dws_sales_ym;
CREATE TABLE ydsh_dws.dws_sales_ym STORED AS ORC AS
SELECT dd.ym                                            AS stat_month,
       COUNT(DISTINCT o.order_id)                       AS order_cnt,
       COUNT(DISTINCT o.user_id)                        AS buyer_cnt,
       ROUND(SUM(o.pay_amount), 2)                      AS gmv,
       ROUND(SUM(o.pay_amount) / COUNT(DISTINCT o.order_id), 2) AS aov
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_date dd ON o.order_date = dd.date_key
WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
GROUP BY dd.ym;

-- 2. 门店日销售汇总（门店-日粒度，支撑后续可视化看板）
DROP TABLE IF EXISTS ydsh_dws.dws_store_sales_d;
CREATE TABLE ydsh_dws.dws_store_sales_d STORED AS ORC AS
SELECT o.store_id,
       s.store_name,
       o.order_date,
       COUNT(DISTINCT o.order_id)  AS order_cnt,
       ROUND(SUM(o.pay_amount), 2) AS gmv
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_store s ON o.store_id = s.store_id
WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
GROUP BY o.store_id, s.store_name, o.order_date;

-- ========== ADS 应用层 ==========

-- 3. 核心 KPI 总览
DROP TABLE IF EXISTS ydsh_ads.ads_kpi_overview;
CREATE TABLE ydsh_ads.ads_kpi_overview STORED AS ORC AS
SELECT COUNT(DISTINCT o.order_id)                                        AS total_orders,
       COUNT(DISTINCT o.user_id)                                         AS total_buyers,
       (SELECT COUNT(*) FROM ydsh_dwd.dim_user)                          AS total_users,
       ROUND(SUM(o.pay_amount), 2)                                       AS total_gmv,
       ROUND(SUM(o.pay_amount) / COUNT(DISTINCT o.order_id), 2)          AS aov,
       ROUND(SUM(o.discount_amount) / SUM(o.pay_amount + o.discount_amount), 4) AS discount_rate,
       ROUND(SUM(IF(o.order_status = '退款中', 1, 0)) / COUNT(*), 4)      AS refunding_rate
FROM ydsh_dwd.dwd_order o
WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消';

-- 4. 品类销售排行（明细事实表 join 商品维度，走外键关联）
DROP TABLE IF EXISTS ydsh_ads.ads_category_sales;
CREATE TABLE ydsh_ads.ads_category_sales STORED AS ORC AS
SELECT p.category,
       COUNT(DISTINCT i.order_id)                AS order_cnt,
       SUM(i.quantity)                           AS total_qty,
       ROUND(SUM(i.line_amount), 2)              AS sales_amount,
       ROW_NUMBER() OVER (ORDER BY SUM(i.line_amount) DESC) AS rank_no
FROM ydsh_dwd.dwd_order_item i
JOIN ydsh_dwd.dim_product p ON i.product_id = p.product_id
JOIN ydsh_dwd.dwd_order o   ON i.order_id = o.order_id
WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
GROUP BY p.category;

-- 5. 省份销售排行
DROP TABLE IF EXISTS ydsh_ads.ads_province_sales;
CREATE TABLE ydsh_ads.ads_province_sales STORED AS ORC AS
SELECT u.province,
       COUNT(DISTINCT o.order_id)   AS order_cnt,
       ROUND(SUM(o.pay_amount), 2)  AS gmv,
       ROW_NUMBER() OVER (ORDER BY SUM(o.pay_amount) DESC) AS rank_no
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
GROUP BY u.province;

-- 6. 渠道销售分布
DROP TABLE IF EXISTS ydsh_ads.ads_channel_sales;
CREATE TABLE ydsh_ads.ads_channel_sales STORED AS ORC AS
SELECT o.channel,
       COUNT(DISTINCT o.order_id)   AS order_cnt,
       ROUND(SUM(o.pay_amount), 2)  AS gmv
FROM ydsh_dwd.dwd_order o
WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
GROUP BY o.channel;

-- ========== 探索查询：窗口函数 ==========

-- 7. 用户累计消费走势（sum over：每位用户按时间累计消费金额，取累计 top5 示意）
DROP TABLE IF EXISTS ydsh_ads.ads_user_cumsum_top;
CREATE TABLE ydsh_ads.ads_user_cumsum_top STORED AS ORC AS
SELECT * FROM (
  SELECT t.user_id, t.order_date, t.pay_amount,
         ROUND(SUM(t.pay_amount) OVER (PARTITION BY t.user_id ORDER BY t.order_date
                                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS cum_amount,
         ROW_NUMBER() OVER (PARTITION BY t.user_id ORDER BY t.order_date)      AS seq_no
  FROM (
    SELECT user_id, order_date, pay_amount
    FROM ydsh_dwd.dwd_order
    WHERE pay_amount IS NOT NULL AND order_status <> '已取消'
  ) t
) s
WHERE s.seq_no <= 5;

-- 8. 全站消费 TOP10 用户（row_number）
DROP TABLE IF EXISTS ydsh_ads.ads_user_top10;
CREATE TABLE ydsh_ads.ads_user_top10 STORED AS ORC AS
SELECT user_id, user_name, member_level, ROUND(total_amount, 2) AS total_amount, rank_no
FROM (
  SELECT u.user_id, u.user_name, u.member_level,
         SUM(o.pay_amount) AS total_amount,
         ROW_NUMBER() OVER (ORDER BY SUM(o.pay_amount) DESC) AS rank_no
  FROM ydsh_dwd.dwd_order o
  JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
  WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
  GROUP BY u.user_id, u.user_name, u.member_level
) t
WHERE rank_no <= 10;

-- ========== 输出探索结果 ==========
SELECT '== KPI 总览 ==' AS sec, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_kpi_overview;
SELECT '== 月度销售 ==' AS sec, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_dws.dws_sales_ym ORDER BY stat_month;
SELECT '== 品类排行 ==' AS sec, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_category_sales ORDER BY rank_no;
SELECT '== 省份排行 TOP8 ==' AS sec, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_province_sales ORDER BY rank_no LIMIT 8;
SELECT '== 渠道分布 ==' AS sec, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_channel_sales ORDER BY gmv DESC;
SELECT '== 消费 TOP10 用户 ==' AS sec, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_user_top10 ORDER BY rank_no;
SELECT '== 用户累计消费样例(U000001) ==' AS sec, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_user_cumsum_top WHERE user_id = 'U000001' ORDER BY seq_no;
