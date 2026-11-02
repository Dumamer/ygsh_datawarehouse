-- =====================================================================
-- 第 2 周 · 子任务 1：枚举字段标准化
-- 策略：
--   gender / member_level —— 取值形态少且无数字编码，直接 CASE WHEN 映射为中文标准值
--   order_status / pay_type / channel / behavior_type —— 存在数字码与英文码，
--       先做 TRIM + 大小写归一并保留「编码原值」，到 w2_03 用编码映射表统一转换
--   category / brand —— TRIM 去首尾空格、统一大小写
-- 输入: ydsh_ods.*    输出: ydsh_tmp.t_*_std
-- =====================================================================
SET hive.auto.convert.join=false;

DROP DATABASE IF EXISTS ydsh_tmp CASCADE;
CREATE DATABASE ydsh_tmp;

-- ---------- 1. 用户表 ----------
-- gender 规范值域：男 / 女 / 未知
-- member_level 规范值域：普通会员 / 银卡会员 / 金卡会员 / 钻石会员
CREATE TABLE ydsh_tmp.t_user_std AS
SELECT user_id,
       TRIM(user_name)                      AS user_name,
       CASE WHEN TRIM(gender) IN ('男','M','male','Male')        THEN '男'
            WHEN TRIM(gender) IN ('女','F','female','Female')    THEN '女'
            ELSE '未知' END                                      AS gender,
       CASE WHEN TRIM(member_level) IN ('普通会员','普通','normal','Normal') THEN '普通会员'
            WHEN TRIM(member_level) IN ('银卡会员','银卡','silver','Silver')     THEN '银卡会员'
            WHEN TRIM(member_level) IN ('金卡会员','金卡','gold','Gold')         THEN '金卡会员'
            WHEN TRIM(member_level) IN ('钻石会员','钻石','diamond','Diamond')   THEN '钻石会员'
            ELSE '普通会员' END                                   AS member_level,
       age,
       TRIM(city)       AS city,
       TRIM(province)   AS province,
       register_date,
       phone,
       email
FROM ydsh_ods.ods_user;

-- ---------- 2. 商品表：category / brand 清理 ----------
CREATE TABLE ydsh_tmp.t_product_std AS
SELECT product_id,
       TRIM(product_name)            AS product_name,
       TRIM(category)                AS category,
       TRIM(sub_category)            AS sub_category,
       TRIM(brand)                   AS brand,
       launch_date,
       price,
       cost,
       stock,
       TRIM(status)                  AS status
FROM ydsh_ods.ods_product;

-- ---------- 3. 订单表：编码字段归一为「标准编码」，中文转换留给编码映射表 ----------
CREATE TABLE ydsh_tmp.t_order_code AS
SELECT order_id, user_id, store_id,
       order_date, order_time,
       pay_amount, discount_amount,
       LOWER(TRIM(pay_type))        AS pay_type_code,      -- wechat/alipay/微信支付/... → 统一小写
       LOWER(TRIM(order_status))    AS order_status_code,  -- 1/2/3/4/cancelled/已完成/... → 统一小写
       UPPER(TRIM(channel))         AS channel_code        -- app/pc/APP/... → 统一大写
FROM ydsh_ods.ods_order;

-- ---------- 4. 订单明细表 ----------
CREATE TABLE ydsh_tmp.t_item_code AS
SELECT item_id, order_id, product_id, quantity, unit_price, discount
FROM ydsh_ods.ods_order_item;

-- ---------- 5. 行为表：behavior_type 归一编码 ----------
CREATE TABLE ydsh_tmp.t_behavior_code AS
SELECT user_id, product_id,
       LOWER(TRIM(behavior_type))   AS behavior_type_code, -- pv/buy/cart/fav/浏览/... → 统一小写
       behavior_time
FROM ydsh_ods.ods_user_behavior;

-- ---------- 6. 验证：枚举收敛情况 ----------
SELECT 't_user.gender'          AS chk, gender        AS val, COUNT(*) AS c FROM ydsh_tmp.t_user_std GROUP BY gender
UNION ALL
SELECT 't_user.member_level',   member_level, COUNT(*) FROM ydsh_tmp.t_user_std GROUP BY member_level
UNION ALL
SELECT 't_order.pay_type_code', pay_type_code, COUNT(*) FROM ydsh_tmp.t_order_code GROUP BY pay_type_code
UNION ALL
SELECT 't_order.order_status_code', order_status_code, COUNT(*) FROM ydsh_tmp.t_order_code GROUP BY order_status_code
UNION ALL
SELECT 't_order.channel_code', channel_code, COUNT(*) FROM ydsh_tmp.t_order_code GROUP BY channel_code
UNION ALL
SELECT 't_behavior.behavior_type_code', behavior_type_code, COUNT(*) FROM ydsh_tmp.t_behavior_code GROUP BY behavior_type_code
ORDER BY chk, c DESC;
