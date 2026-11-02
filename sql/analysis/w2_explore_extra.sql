-- =====================================================================
-- 第 2 周 · 子任务 7 补充：探索性分析（二）
--   任务书要求「品类 / 省份 / 门店 / 渠道」四维分布，首轮只覆盖了三类，
--   本脚本补上门店分布，并追加四个能体现维度表价值的探索方向：
--     会员等级价值分层（dim_user）、周末效应（dim_date）、复购分布、月度环比
--   口径与 w2_explore.sql 保持一致：pay_amount 非空 且 order_status <> '已取消'
-- 依赖：ydsh_dwd.* / ydsh_dws.dws_store_sales_d 已由 10~13 步加载完成
-- =====================================================================
SET hive.auto.convert.join=false;
SET hive.vectorized.execution.enabled=false;
SET hive.vectorized.execution.reduce.enabled=false;

-- ---------- 9. 门店销售排行（60 家门店，基于 DWS 门店-日汇总二次聚合） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_store_sales;
CREATE TABLE ydsh_ads.ads_store_sales STORED AS ORC AS
SELECT x.store_id,
       x.store_name,
       x.province,
       x.order_cnt,
       x.gmv,
       ROUND(x.gmv / x.total_gmv, 4) AS gmv_share,
       ROW_NUMBER() OVER (ORDER BY x.gmv DESC) AS rank_no
FROM (
  SELECT t.store_id, t.store_name, t.province, t.order_cnt, t.gmv,
         SUM(t.gmv) OVER () AS total_gmv
  FROM (
    SELECT d.store_id,
           d.store_name,
           s.province,
           SUM(d.order_cnt)            AS order_cnt,
           ROUND(SUM(d.gmv), 2)        AS gmv
    FROM ydsh_dws.dws_store_sales_d d
    JOIN ydsh_dwd.dim_store s ON d.store_id = s.store_id
    GROUP BY d.store_id, d.store_name, s.province
  ) t
) x;

-- ---------- 10. 会员等级价值分层（验证 dim_user 会员等级标准化的业务可用性） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_member_level_sales;
CREATE TABLE ydsh_ads.ads_member_level_sales STORED AS ORC AS
SELECT y.member_level,
       y.buyer_cnt,
       y.order_cnt,
       y.gmv,
       ROUND(y.gmv / y.order_cnt, 2)  AS aov,
       ROUND(y.gmv / y.buyer_cnt, 2)  AS arpu,
       ROUND(y.gmv / y.total_gmv, 4)  AS gmv_share
FROM (
  SELECT t.member_level, t.buyer_cnt, t.order_cnt, t.gmv,
         SUM(t.gmv) OVER () AS total_gmv
  FROM (
    SELECT u.member_level,
           COUNT(DISTINCT o.user_id)   AS buyer_cnt,
           COUNT(DISTINCT o.order_id)  AS order_cnt,
           SUM(o.pay_amount)           AS gmv
    FROM ydsh_dwd.dwd_order o
    JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
    WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
    GROUP BY u.member_level
  ) t
) y;

-- ---------- 11. 周末效应（唯一使用 dim_date 的两个衍生属性：is_weekend / day_of_week） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_weekend_sales;
CREATE TABLE ydsh_ads.ads_weekend_sales STORED AS ORC AS
SELECT dd.is_weekend,
       COUNT(DISTINCT o.order_id)                          AS order_cnt,
       COUNT(DISTINCT o.order_date)                        AS day_cnt,
       ROUND(SUM(o.pay_amount), 2)                         AS gmv,
       ROUND(SUM(o.pay_amount) / COUNT(DISTINCT o.order_date), 2) AS gmv_per_day,
       ROUND(SUM(o.pay_amount) / COUNT(DISTINCT o.order_id), 2)   AS aov
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_date dd ON o.order_date = dd.date_key
WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
GROUP BY dd.is_weekend;

-- ---------- 12. 下单次数分布（复购结构，用户级聚合后再分桶） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_repeat_purchase;
CREATE TABLE ydsh_ads.ads_repeat_purchase STORED AS ORC AS
SELECT f.bucket,
       COUNT(*)                        AS user_cnt,
       ROUND(SUM(f.amt), 2)            AS gmv,
       ROUND(AVG(f.amt), 2)            AS arpu,
       ROUND(SUM(f.amt) / SUM(SUM(f.amt)) OVER (), 4) AS gmv_share
FROM (
  SELECT o.user_id,
         COUNT(DISTINCT o.order_id) AS ord_cnt,
         SUM(o.pay_amount)          AS amt,
         CASE WHEN COUNT(DISTINCT o.order_id) = 1        THEN '1单'
              WHEN COUNT(DISTINCT o.order_id) <= 4       THEN '2-4单'
              WHEN COUNT(DISTINCT o.order_id) <= 9       THEN '5-9单'
              WHEN COUNT(DISTINCT o.order_id) <= 19      THEN '10-19单'
              ELSE '20单及以上' END  AS bucket
  FROM ydsh_dwd.dwd_order o
  WHERE o.pay_amount IS NOT NULL AND o.order_status <> '已取消'
  GROUP BY o.user_id
) f
GROUP BY f.bucket;

-- ---------- 13. 月度环比（窗口函数 LAG，衡量增长动能） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_month_mom;
CREATE TABLE ydsh_ads.ads_month_mom STORED AS ORC AS
SELECT m.stat_month,
       m.gmv,
       m.order_cnt,
       m.aov,
       LAG(m.gmv) OVER (ORDER BY m.stat_month)          AS prev_gmv,
       ROUND((m.gmv - LAG(m.gmv) OVER (ORDER BY m.stat_month))
             / LAG(m.gmv) OVER (ORDER BY m.stat_month) * 100, 2) AS mom_pct
FROM ydsh_dws.dws_sales_ym m;

-- ---------- 验证输出 ----------
SELECT '== 门店排行 TOP5 ==' AS sec, NULL, NULL, NULL, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_store_sales ORDER BY rank_no LIMIT 5;
SELECT '== 门店数量与合计 ==' AS sec, NULL, NULL, NULL, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT COUNT(*) AS store_cnt, ROUND(SUM(gmv), 2) AS total_gmv,
       ROUND(MAX(gmv) / MIN(gmv), 2) AS max_min_ratio
FROM ydsh_ads.ads_store_sales;
SELECT '== 会员等级分层 ==' AS sec, NULL, NULL, NULL, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_member_level_sales ORDER BY gmv DESC;
SELECT '== 周末效应 ==' AS sec, NULL, NULL, NULL, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_weekend_sales;
SELECT '== 复购分布 ==' AS sec, NULL, NULL, NULL, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_repeat_purchase ORDER BY gmv DESC;
SELECT '== 月度环比 ==' AS sec, NULL, NULL, NULL, NULL, NULL, NULL FROM ydsh_dwd.dwd_order LIMIT 0;
SELECT * FROM ydsh_ads.ads_month_mom ORDER BY stat_month;

-- ---------- 导出 tsv 供脚本排版 ----------
INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/store'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_store_sales ORDER BY rank_no;

INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/member'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_member_level_sales ORDER BY gmv DESC;

INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/weekend'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_weekend_sales;

INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/repeat'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_repeat_purchase ORDER BY gmv DESC;

INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/mom'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_month_mom ORDER BY stat_month;
