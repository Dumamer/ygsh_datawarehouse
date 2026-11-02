-- =====================================================================
-- 第 2 周 · 子任务 4：清洗前（ODS）vs 清洗后（DWD）五类脏数据修复率
-- 口径说明：
--   修复率 = (清洗前问题数 - 清洗后问题数) / 清洗前问题数
--   订单异常数按「去重后 15000 单」口径统计（与 DWD 可比）
--   邮箱缺失为「保留 + 标记」策略，非修复项，单列说明
-- =====================================================================
SET hive.auto.convert.join=false;
SET hive.vectorized.execution.enabled=false;
SET hive.vectorized.execution.reduce.enabled=false;

CREATE DATABASE IF NOT EXISTS ydsh_dq;

-- 说明：统计口径只写在这一处。结果先落表 ydsh_dq.dq_w2_repair_rate，
-- 再由 w2_export_tsv.sql 导出 tsv 给 Excel 报告用。
-- （早先导出脚本里另抄了一份同样的 SQL，改口径时两边漂移过一次，故改为单一来源。）
DROP TABLE IF EXISTS ydsh_dq.dq_w2_repair_rate;
CREATE TABLE ydsh_dq.dq_w2_repair_rate
COMMENT '第 2 周五类脏数据修复率明细（38 条记录：20 类问题 + 17 条残留校验 + 邮箱策略行）'
STORED AS ORC AS

-- ---------- 缺失值 ----------
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
-- 邮箱是「策略性保留」，清洗后依然是 193 条空值（只多了 email_is_missing 标记），
-- 因此这一行的残留数如实为 193、修复率 0%；报告脚本把它排除在修复分母之外并单列说明。
UNION ALL
SELECT '1-缺失值', '用户邮箱-清洗后残留（DWD，策略性保留）', 0,
       SUM(IF(TRIM(email)='' OR email IS NULL, 1, 0)) FROM ydsh_dwd.dim_user

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

;

-- 结果回读：运行记录里可直接看到 38 行，便于逐项核对
SELECT dim_type, issue, before_cnt, after_cnt
FROM ydsh_dq.dq_w2_repair_rate
ORDER BY dim_type, issue;
