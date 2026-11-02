-- =====================================================================
-- 第 2 周 · 数据导出：修复率明细 + 探索分析结果 → 本地 tsv（供 Excel 报告使用）
-- 说明：修复率口径复用 w2_repair_rate.sql，落表后导出，保证 Excel 数字可复现
-- 输出目录：docs/w2_raw/
-- =====================================================================
SET hive.auto.convert.join=false;

DROP TABLE IF EXISTS ydsh_dq.dq_w2_repair_rate;
CREATE TABLE ydsh_dq.dq_w2_repair_rate STORED AS ORC AS
SELECT '1-缺失值' AS dim_type, '用户年龄（缺失/越界/非正）' AS issue,
       SUM(IF(TRIM(age)='' OR CAST(age AS INT) NOT BETWEEN 1 AND 120, 1, 0)) AS before_cnt,
       0 AS after_cnt
FROM ydsh_ods.ods_user
UNION ALL
SELECT '1-缺失值', '用户年龄-清洗后残留（DWD）', 0,
       SUM(IF(NOT (age BETWEEN 1 AND 120), 1, 0)) FROM ydsh_dwd.dim_user
UNION ALL
SELECT '1-缺失值', '用户性别（空值）',
       SUM(IF(TRIM(gender)='' OR gender IS NULL, 1, 0)), 0 FROM ydsh_ods.ods_user
UNION ALL
SELECT '1-缺失值', '会员等级（空值）',
       SUM(IF(TRIM(member_level)='' OR member_level IS NULL, 1, 0)), 0 FROM ydsh_ods.ods_user
UNION ALL
SELECT '1-缺失值', '商品上架日期（空值）',
       SUM(IF(TRIM(launch_date)='' OR launch_date IS NULL, 1, 0)), 0 FROM ydsh_ods.ods_product
UNION ALL
SELECT '1-缺失值', '商品上架日期-清洗后残留（DWD）', 0,
       SUM(IF(TRIM(launch_date)='' OR launch_date IS NULL, 1, 0)) FROM ydsh_dwd.dim_product
UNION ALL
SELECT '1-缺失值', '用户邮箱（空值｜策略=保留+标记，不修复）',
       SUM(IF(TRIM(email)='' OR email IS NULL, 1, 0)), 0 FROM ydsh_ods.ods_user

-- ---------- 重复值 ----------
UNION ALL
SELECT '2-重复值', '订单主键重复多出行（15600-15000）',
       COUNT(*) - 15000, 0 FROM ydsh_ods.ods_order
UNION ALL
SELECT '2-重复值', '订单主键重复-清洗后残留（DWD）', 0,
       COUNT(*) - COUNT(DISTINCT order_id) FROM ydsh_dwd.dwd_order

-- ---------- 异常值 ----------
UNION ALL
SELECT '3-异常值', '订单金额异常（<=0 或 >10000，去重后口径）',
       SUM(IF(NOT (amt BETWEEN 0 AND 10000) OR amt IS NULL, 1, 0)), 0
FROM (SELECT order_id, MAX(CAST(pay_amount AS DOUBLE)) AS amt
      FROM ydsh_ods.ods_order GROUP BY order_id) d
UNION ALL
SELECT '3-异常值', '订单金额异常-清洗后残留（DWD）', 0,
       SUM(IF(NOT (pay_amount BETWEEN 0 AND 10000), 1, 0)) FROM ydsh_dwd.dwd_order
UNION ALL
SELECT '3-异常值', '订单优惠金额负值',
       SUM(IF(CAST(discount_amount AS DOUBLE) < 0, 1, 0)), 0 FROM ydsh_ods.ods_order
UNION ALL
SELECT '3-异常值', '订单优惠金额负值-清洗后残留（DWD）', 0,
       SUM(IF(discount_amount < 0, 1, 0)) FROM ydsh_dwd.dwd_order
UNION ALL
SELECT '3-异常值', '明细单价负值',
       SUM(IF(CAST(unit_price AS DOUBLE) < 0, 1, 0)), 0 FROM ydsh_ods.ods_order_item
UNION ALL
SELECT '3-异常值', '明细单价负值-清洗后残留（DWD）', 0,
       SUM(IF(unit_price < 0, 1, 0)) FROM ydsh_dwd.dwd_order_item
UNION ALL
SELECT '3-异常值', '明细数量非正（整行剔除）',
       SUM(IF(CAST(quantity AS INT) <= 0, 1, 0)), 0 FROM ydsh_ods.ods_order_item
UNION ALL
SELECT '3-异常值', '明细数量非正-清洗后残留（DWD）', 0,
       SUM(IF(quantity <= 0, 1, 0)) FROM ydsh_dwd.dwd_order_item

-- ---------- 枚举值 ----------
UNION ALL
SELECT '4-枚举值', '性别非规范（M/F/male/female/空）',
       SUM(IF(TRIM(gender) NOT IN ('男','女'), 1, 0)), 0 FROM ydsh_ods.ods_user
UNION ALL
SELECT '4-枚举值', '性别-清洗后残留（DWD）', 0,
       SUM(IF(gender NOT IN ('男','女','未知') OR gender IS NULL, 1, 0)) FROM ydsh_dwd.dim_user
UNION ALL
SELECT '4-枚举值', '会员等级非规范（简称/英文/空）',
       SUM(IF(TRIM(member_level) NOT IN ('普通会员','银卡会员','金卡会员','钻石会员'), 1, 0)), 0
FROM ydsh_ods.ods_user
UNION ALL
SELECT '4-枚举值', '会员等级-清洗后残留（DWD）', 0,
       SUM(IF(member_level NOT IN ('普通会员','银卡会员','金卡会员','钻石会员') OR member_level IS NULL, 1, 0))
FROM ydsh_dwd.dim_user
UNION ALL
SELECT '4-枚举值', '订单状态非规范（数字码/英文/同义词）',
       SUM(IF(TRIM(order_status) NOT IN ('已完成','已支付','待支付','已取消','退款中'), 1, 0)), 0
FROM ydsh_ods.ods_order
UNION ALL
SELECT '4-枚举值', '订单状态-清洗后残留（DWD）', 0,
       SUM(IF(order_status NOT IN ('已完成','已支付','待支付','已取消','退款中') OR order_status IS NULL, 1, 0))
FROM ydsh_dwd.dwd_order
UNION ALL
SELECT '4-枚举值', '支付方式非规范（wechat/alipay/微信）',
       SUM(IF(TRIM(pay_type) NOT IN ('支付宝','微信支付','货到付款','银行卡'), 1, 0)), 0
FROM ydsh_ods.ods_order
UNION ALL
SELECT '4-枚举值', '支付方式-清洗后残留（DWD）', 0,
       SUM(IF(pay_type NOT IN ('支付宝','微信支付','货到付款','银行卡') OR pay_type IS NULL, 1, 0))
FROM ydsh_dwd.dwd_order
UNION ALL
SELECT '4-枚举值', '下单渠道非规范（app/pc）',
       SUM(IF(TRIM(channel) NOT IN ('APP','小程序','门店','PC官网'), 1, 0)), 0
FROM ydsh_ods.ods_order
UNION ALL
SELECT '4-枚举值', '下单渠道-清洗后残留（DWD）', 0,
       SUM(IF(channel NOT IN ('APP','小程序','门店','PC官网') OR channel IS NULL, 1, 0))
FROM ydsh_dwd.dwd_order
UNION ALL
SELECT '4-枚举值', '行为类型非规范（中英混用/大小写）',
       SUM(IF(TRIM(behavior_type) NOT IN ('浏览','加购','收藏','购买'), 1, 0)), 0
FROM ydsh_ods.ods_user_behavior
UNION ALL
SELECT '4-枚举值', '行为类型-清洗后残留（DWD）', 0,
       SUM(IF(behavior_type NOT IN ('浏览','加购','收藏','购买') OR behavior_type IS NULL, 1, 0))
FROM ydsh_dwd.dwd_user_behavior

-- ---------- 格式 ----------
UNION ALL
SELECT '5-格式', '订单日期非 yyyy-MM-dd（斜杠）',
       SUM(IF(NOT order_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$', 1, 0)), 0
FROM ydsh_ods.ods_order
UNION ALL
SELECT '5-格式', '订单日期-清洗后残留（DWD）', 0,
       SUM(IF(NOT order_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$', 1, 0)) FROM ydsh_dwd.dwd_order
UNION ALL
SELECT '5-格式', '注册日期非 yyyy-MM-dd（斜杠/紧凑）',
       SUM(IF(NOT register_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$', 1, 0)), 0
FROM ydsh_ods.ods_user
UNION ALL
SELECT '5-格式', '注册日期-清洗后残留（DWD）', 0,
       SUM(IF(NOT register_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$', 1, 0)) FROM ydsh_dwd.dim_user
UNION ALL
SELECT '5-格式', '行为时间非 yyyy-MM-dd HH:mm:ss（斜杠/缺秒）',
       SUM(IF(NOT behavior_time RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$', 1, 0)), 0
FROM ydsh_ods.ods_user_behavior
UNION ALL
SELECT '5-格式', '行为时间-清洗后残留（DWD）', 0,
       SUM(IF(NOT behavior_time RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$', 1, 0))
FROM ydsh_dwd.dwd_user_behavior
UNION ALL
SELECT '5-格式', '手机号含分隔符/非数字字符',
       SUM(IF(phone RLIKE '[^0-9]', 1, 0)), 0
FROM ydsh_ods.ods_user
UNION ALL
SELECT '5-格式', '手机号-清洗后残留（DWD）', 0,
       SUM(IF(NOT phone RLIKE '^1[0-9]{10}$', 1, 0)) FROM ydsh_dwd.dim_user

ORDER BY dim_type, issue;

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
