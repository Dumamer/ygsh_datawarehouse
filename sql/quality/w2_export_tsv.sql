-- =====================================================================
-- 第 2 周 · 数据导出：修复率明细 + 探索分析结果 → 本地 tsv（供 Excel 报告使用）
-- 说明：修复率明细由 w2_repair_rate.sql 落表后导出，保证 Excel 数字可复现
-- 输出目录：docs/w2_raw/
-- =====================================================================
SET hive.auto.convert.join=false;

-- 修复率明细已由 w2_repair_rate.sql 落表（ydsh_dq.dq_w2_repair_rate），
-- 此处只做导出，不再重复维护一份统计 SQL（单一来源，避免口径漂移）。

INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/repair_rate'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT dim_type, issue, before_cnt, after_cnt FROM ydsh_dq.dq_w2_repair_rate ORDER BY dim_type, issue;

INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/kpi'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_kpi_overview;
INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/category'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_category_sales;
INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/province'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_province_sales;
INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/channel'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_channel_sales;
INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/user_top10'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_ads.ads_user_top10;
INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/sales_ym'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT * FROM ydsh_dws.dws_sales_ym;
INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/order_stats'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT COUNT(*) AS orders, COUNT(DISTINCT user_id) AS users FROM ydsh_dwd.dwd_order;
-- DWD / DWS / ADS 各表行数（报告用）
INSERT OVERWRITE LOCAL DIRECTORY 'D:/cxdownload/ydsh-datawarehouse/docs/w2_raw/tbl_rows'
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
SELECT 'dim_user' AS t, COUNT(*) AS c FROM ydsh_dwd.dim_user
UNION ALL SELECT 'dim_product', COUNT(*) FROM ydsh_dwd.dim_product
UNION ALL SELECT 'dim_store', COUNT(*) FROM ydsh_dwd.dim_store
UNION ALL SELECT 'dim_date', COUNT(*) FROM ydsh_dwd.dim_date
UNION ALL SELECT 'dim_code_mapping', COUNT(*) FROM ydsh_dwd.dim_code_mapping
UNION ALL SELECT 'dwd_order', COUNT(*) FROM ydsh_dwd.dwd_order
UNION ALL SELECT 'dwd_order_item', COUNT(*) FROM ydsh_dwd.dwd_order_item
UNION ALL SELECT 'dwd_user_behavior', COUNT(*) FROM ydsh_dwd.dwd_user_behavior
UNION ALL SELECT 'dws_sales_ym', COUNT(*) FROM ydsh_dws.dws_sales_ym
UNION ALL SELECT 'dws_store_sales_d', COUNT(*) FROM ydsh_dws.dws_store_sales_d
UNION ALL SELECT 'ads_kpi_overview', COUNT(*) FROM ydsh_ads.ads_kpi_overview
UNION ALL SELECT 'ads_category_sales', COUNT(*) FROM ydsh_ads.ads_category_sales
UNION ALL SELECT 'ads_province_sales', COUNT(*) FROM ydsh_ads.ads_province_sales
UNION ALL SELECT 'ads_channel_sales', COUNT(*) FROM ydsh_ads.ads_channel_sales
UNION ALL SELECT 'ads_store_sales', COUNT(*) FROM ydsh_ads.ads_store_sales
UNION ALL SELECT 'ads_member_level_sales', COUNT(*) FROM ydsh_ads.ads_member_level_sales
UNION ALL SELECT 'ads_weekend_sales', COUNT(*) FROM ydsh_ads.ads_weekend_sales
UNION ALL SELECT 'ads_repeat_purchase', COUNT(*) FROM ydsh_ads.ads_repeat_purchase
UNION ALL SELECT 'ads_month_mom', COUNT(*) FROM ydsh_ads.ads_month_mom;
