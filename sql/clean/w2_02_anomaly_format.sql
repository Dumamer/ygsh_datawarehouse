-- =====================================================================
-- 第 2 周 · 子任务 2：异常值处理 与 格式标准化
-- 1) 数值异常：
--    - 订单 pay_amount <=0 或 >10000 视为异常（正常金额 P98≈5000，1万~10万区间零样本，
--      手册建议的 P99 阈值被 2% 超大脏值污染[P99=551万]，故改用分布断档边界 1 万）
--      → 优先用订单明细回填 SUM(quantity*unit_price*(1-discount))，无法修复置 NULL 并标记
--    - discount_amount < 0 取绝对值（录入符号错误）
--    - 用户 age <=0 或 >120 或缺失 → 有效值(1~120)中位数填充 + 标记位
--    - 明细 quantity <=0 的行剔除、unit_price <0 取绝对值
-- 2) 格式标准化：
--    - 日期三种形态 2024-07-26 / 2024/07/26 / 20240726 → yyyy-MM-dd
--    - behavior_time 斜杠日期 → yyyy-MM-dd HH:mm:ss
--    - 手机号去除分隔符统一 11 位纯数字
-- 3) 订单去重（沿用第 1 周四级保留规则：金额有效性 > 时间新 > 金额大 > 兜底）
-- 输入: ydsh_tmp.t_*_std / ydsh_ods.ods_order   输出: ydsh_tmp.t_*_clean
-- =====================================================================
SET hive.auto.convert.join=false;
-- 踩坑：Hive 3 本地模式下 CASE WHEN + RLIKE 走向量化执行会 MapRedTask 失败（无堆栈），
-- 关闭向量化后正常，60000 行全量写入成功
SET hive.vectorized.execution.enabled=false;
SET hive.vectorized.execution.reduce.enabled=false;

-- ---------- 1. 用户：年龄修复 + 日期/手机号格式标准化 ----------
DROP TABLE IF EXISTS ydsh_tmp.t_user_clean;
CREATE TABLE ydsh_tmp.t_user_clean AS
SELECT u.user_id, u.user_name, u.gender, u.member_level, u.city, u.province, u.email,
       ROUND(CASE WHEN u.age_ok = 1 THEN u.age_num
            ELSE u.age_median END)                             AS age,
       CASE WHEN u.age_ok = 1 THEN 0 ELSE 1 END            AS age_is_filled,
       u.register_date_std                                 AS register_date,
       regexp_replace(u.phone, '[^0-9]', '')               AS phone,
       LENGTH(regexp_replace(u.phone, '[^0-9]', ''))       AS phone_len
FROM (
  SELECT s.*,
         CAST(s.age AS INT)                                                      AS age_num,
         IF(CAST(s.age AS INT) BETWEEN 1 AND 120, 1, 0)                          AS age_ok,
         PERCENTILE_APPROX(CAST(s.age AS DOUBLE), 0.5)
           OVER ()                                                               AS age_median,
         CASE WHEN s.register_date RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
                   THEN regexp_replace(s.register_date, '/', '-')
              WHEN s.register_date RLIKE '^[0-9]{8}$'
                   THEN concat_ws('-', substr(s.register_date,1,4),
                                              substr(s.register_date,5,2),
                                              substr(s.register_date,7,2))
              ELSE s.register_date END                                          AS register_date_std
  FROM ydsh_tmp.t_user_std s
) u;

-- ---------- 2. 订单：先去重，再修正异常金额 ----------
-- 2.1 按 order_id 去重（15000 个真实订单）
DROP TABLE IF EXISTS ydsh_tmp.t_order_dedup;
CREATE TABLE ydsh_tmp.t_order_dedup AS
SELECT t.*
FROM (
  SELECT o.*,
         ROW_NUMBER() OVER (
           PARTITION BY o.order_id
           ORDER BY CASE WHEN CAST(o.pay_amount AS DOUBLE) BETWEEN 0 AND 10000 THEN 1 ELSE 0 END DESC,
                    o.order_time DESC,
                    CAST(o.pay_amount AS DOUBLE) DESC
         ) AS rn
  FROM ydsh_tmp.t_order_code o
) t
WHERE t.rn = 1;

-- 2.2 明细可信金额聚合（用于回填异常订单金额）
DROP TABLE IF EXISTS ydsh_tmp.t_item_amount;
CREATE TABLE ydsh_tmp.t_item_amount AS
SELECT order_id,
       ROUND(SUM(CAST(quantity AS INT) * CAST(unit_price AS DOUBLE)
                 * (1 - COALESCE(CAST(discount AS DOUBLE), 0))), 2) AS item_amount
FROM ydsh_tmp.t_item_code
WHERE CAST(quantity AS INT) > 0 AND CAST(unit_price AS DOUBLE) > 0
GROUP BY order_id;

-- 2.3 金额修正 + 标记位
--     pay_amount_is_repaired: 0=原始有效  1=明细回填修正  2=无法修复置空
DROP TABLE IF EXISTS ydsh_tmp.t_order_clean;
CREATE TABLE ydsh_tmp.t_order_clean AS
SELECT d.order_id, d.user_id, d.store_id, d.order_date_std AS order_date, d.order_time,
       CASE WHEN d.amt_ok = 1 THEN d.pay_amt
            WHEN i.item_amount BETWEEN 0 AND 10000 THEN i.item_amount
            ELSE NULL END                                              AS pay_amount,
       CASE WHEN d.amt_ok = 1 THEN 0
            WHEN i.item_amount BETWEEN 0 AND 10000 THEN 1
            ELSE 2 END                                                 AS pay_amount_is_repaired,
       CASE WHEN CAST(d.discount_amount AS DOUBLE) < 0
            THEN ROUND(ABS(CAST(d.discount_amount AS DOUBLE)), 2)
            ELSE CAST(d.discount_amount AS DOUBLE) END                 AS discount_amount,
       d.pay_type_code, d.order_status_code, d.channel_code
FROM (
  SELECT t.*,
         CAST(t.pay_amount AS DOUBLE)                                        AS pay_amt,
         IF(CAST(t.pay_amount AS DOUBLE) > 0
            AND CAST(t.pay_amount AS DOUBLE) <= 10000, 1, 0)                 AS amt_ok,
         CASE WHEN t.order_date RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
                   THEN regexp_replace(t.order_date, '/', '-')
              WHEN t.order_date RLIKE '^[0-9]{8}$'
                   THEN concat_ws('-', substr(t.order_date,1,4),
                                              substr(t.order_date,5,2),
                                              substr(t.order_date,7,2))
              ELSE t.order_date END                                          AS order_date_std
  FROM ydsh_tmp.t_order_dedup t
) d
LEFT JOIN ydsh_tmp.t_item_amount i ON d.order_id = i.order_id;

-- ---------- 3. 明细：unit_price 修正、无效行剔除 ----------
DROP TABLE IF EXISTS ydsh_tmp.t_item_clean;
CREATE TABLE ydsh_tmp.t_item_clean AS
SELECT item_id, order_id, product_id, quantity,
       ROUND(ABS(CAST(unit_price AS DOUBLE)), 2)                            AS unit_price,
       CAST(discount AS DOUBLE)                                             AS discount,
       ROUND(CAST(quantity AS INT) * ABS(CAST(unit_price AS DOUBLE))
             * (1 - COALESCE(CAST(discount AS DOUBLE), 0)), 2)              AS line_amount
FROM ydsh_tmp.t_item_code
WHERE CAST(quantity AS INT) > 0;

-- ---------- 4. 行为：时间格式标准化 ----------
DROP TABLE IF EXISTS ydsh_tmp.t_behavior_clean;
CREATE TABLE ydsh_tmp.t_behavior_clean AS
SELECT user_id, product_id, behavior_type_code,
       CASE WHEN behavior_time RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'
                 THEN behavior_time
                 ELSE concat(regexp_replace(behavior_time, '/', '-'), ':00') END  AS behavior_time,
       substr(concat(regexp_replace(behavior_time, '/', '-'), ':00'), 1, 10)      AS behavior_date
FROM ydsh_tmp.t_behavior_code;

-- ---------- 5. 修复效果验证 ----------
SELECT '用户年龄-填充后残留越界/空' AS chk, COUNT(*) AS v FROM ydsh_tmp.t_user_clean
 WHERE NOT (age BETWEEN 1 AND 120)
UNION ALL
SELECT '用户手机号-非11位', COUNT(*) FROM ydsh_tmp.t_user_clean WHERE phone_len <> 11
UNION ALL
SELECT '用户注册日期-非标准格式', COUNT(*) FROM ydsh_tmp.t_user_clean WHERE NOT register_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
UNION ALL
SELECT '订单日期-非标准格式', COUNT(*) FROM ydsh_tmp.t_order_clean WHERE NOT order_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
UNION ALL
SELECT '订单-去重后行数', COUNT(*) FROM ydsh_tmp.t_order_clean
UNION ALL
SELECT '订单-金额仍异常行数', COUNT(*) FROM ydsh_tmp.t_order_clean WHERE NOT (pay_amount BETWEEN 0 AND 10000)
UNION ALL
SELECT '订单-负折扣残留', COUNT(*) FROM ydsh_tmp.t_order_clean WHERE discount_amount < 0
UNION ALL
SELECT '明细-数量非正残留', COUNT(*) FROM ydsh_tmp.t_item_clean WHERE quantity <= 0
UNION ALL
SELECT '明细-负单价残留', COUNT(*) FROM ydsh_tmp.t_item_clean WHERE unit_price < 0
UNION ALL
SELECT '行为-时间非标准格式', COUNT(*) FROM ydsh_tmp.t_behavior_clean WHERE NOT behavior_time RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$';
