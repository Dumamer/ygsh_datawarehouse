-- =====================================================================
-- 第 2 周 · 子任务 3：字段拆分合并 与 编码映射
-- 1) 建立编码映射维度表 dim_code_mapping（code_type / code_value / std_name），
--    演示企业级「编码 → 中文名称」的标准做法：DWD 加工时通过 JOIN 完成转换
--    * order_status 数字码含义按订单生命周期推断：1 待支付 / 2 已支付 / 3 已完成 / 4 已取消
-- 2) order_date + order_time 合并为 order_timestamp（yyyy-MM-dd HH:mm:ss）
-- 3) province + city 合并为 region
-- 输入: ydsh_tmp.t_*_clean   输出: ydsh_tmp.t_*_final
-- =====================================================================
SET hive.auto.convert.join=false;
SET hive.vectorized.execution.enabled=false;

-- ---------- 1. 编码映射维度表 ----------
DROP TABLE IF EXISTS ydsh_tmp.dim_code_mapping;
CREATE TABLE ydsh_tmp.dim_code_mapping (
  code_type   string COMMENT '编码类型：order_status/pay_type/channel/behavior_type',
  code_value  string COMMENT '原始编码（清洗后保留的小写/大写标准编码）',
  std_name    string COMMENT '中文标准名称',
  remark      string COMMENT '映射依据'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE;

INSERT INTO ydsh_tmp.dim_code_mapping VALUES
  ('order_status', '已完成',   '已完成', '中文标准值'),
  ('order_status', '已支付',   '已支付', '中文标准值'),
  ('order_status', '待支付',   '待支付', '中文标准值'),
  ('order_status', '已取消',   '已取消', '中文标准值'),
  ('order_status', '退款中',   '退款中', '中文标准值'),
  ('order_status', '已付款',   '已支付', '同义归一：已付款=已支付'),
  ('order_status', '完成',     '已完成', '同义归一：完成=已完成'),
  ('order_status', 'cancelled','已取消', '英文编码翻译'),
  ('order_status', '1',        '待支付', '数字码按订单生命周期推断'),
  ('order_status', '2',        '已支付', '数字码按订单生命周期推断'),
  ('order_status', '3',        '已完成', '数字码按订单生命周期推断'),
  ('order_status', '4',        '已取消', '数字码按订单生命周期推断'),
  ('pay_type',     '支付宝',    '支付宝',   '中文标准值'),
  ('pay_type',     '微信支付',  '微信支付', '中文标准值'),
  ('pay_type',     '货到付款',  '货到付款', '中文标准值'),
  ('pay_type',     '银行卡',    '银行卡',   '中文标准值'),
  ('pay_type',     'wechat',   '微信支付', '英文编码翻译'),
  ('pay_type',     'alipay',   '支付宝',   '英文编码翻译'),
  ('pay_type',     '微信',      '微信支付', '简称补全'),
  ('channel',      'APP',      'APP',     '中文标准值'),
  ('channel',      '门店',      '门店',     '中文标准值'),
  ('channel',      '小程序',    '小程序',   '中文标准值'),
  ('channel',      'PC官网',   'PC官网',  '中文标准值'),
  ('channel',      'PC',       'PC官网',  '简称补全'),
  ('behavior_type','pv',       '浏览', '英文编码翻译'),
  ('behavior_type','buy',      '购买', '英文编码翻译'),
  ('behavior_type','cart',     '加购', '英文编码翻译'),
  ('behavior_type','fav',      '收藏', '英文编码翻译'),
  ('behavior_type','浏览',      '浏览', '中文标准值'),
  ('behavior_type','购买',      '购买', '中文标准值'),
  ('behavior_type','加购',      '加购', '中文标准值'),
  ('behavior_type','收藏',      '收藏', '中文标准值');

-- ---------- 2. 订单：JOIN 编码映射 + 合并 order_timestamp ----------
DROP TABLE IF EXISTS ydsh_tmp.t_order_final;
CREATE TABLE ydsh_tmp.t_order_final AS
SELECT o.order_id, o.user_id, o.store_id,
       concat(substr(o.order_date, 1, 10), ' ', o.order_time) AS order_timestamp,
       substr(o.order_date, 1, 10)                            AS order_date,
       o.pay_amount, o.pay_amount_is_repaired, o.discount_amount,
       ps.std_name                                            AS pay_type,
       os.std_name                                            AS order_status,
       cs.std_name                                            AS channel
FROM ydsh_tmp.t_order_clean o
LEFT JOIN ydsh_tmp.dim_code_mapping ps
       ON ps.code_type = 'pay_type'      AND ps.code_value = o.pay_type_code
LEFT JOIN ydsh_tmp.dim_code_mapping os
       ON os.code_type = 'order_status'  AND os.code_value = o.order_status_code
LEFT JOIN ydsh_tmp.dim_code_mapping cs
       ON cs.code_type = 'channel'       AND cs.code_value = o.channel_code;

-- ---------- 3. 用户：合并 region ----------
DROP TABLE IF EXISTS ydsh_tmp.t_user_final;
CREATE TABLE ydsh_tmp.t_user_final AS
SELECT user_id, user_name, gender, member_level,
       CONCAT_WS('', province, city) AS region,
       province, city, age, age_is_filled,
       register_date, phone, email
FROM ydsh_tmp.t_user_clean;

-- ---------- 4. 行为：JOIN 编码映射 ----------
DROP TABLE IF EXISTS ydsh_tmp.t_behavior_final;
CREATE TABLE ydsh_tmp.t_behavior_final AS
SELECT b.user_id, b.product_id,
       COALESCE(bs.std_name, b.behavior_type_code) AS behavior_type,
       b.behavior_time, b.behavior_date
FROM ydsh_tmp.t_behavior_clean b
LEFT JOIN ydsh_tmp.dim_code_mapping bs
       ON bs.code_type = 'behavior_type' AND bs.code_value = b.behavior_type_code;

-- ---------- 5. 验证：映射后枚举收敛到规范值域 ----------
SELECT '订单支付方式'   AS chk, pay_type,     COUNT(*) AS c FROM ydsh_tmp.t_order_final GROUP BY pay_type
UNION ALL SELECT '订单状态',   order_status,  COUNT(*) FROM ydsh_tmp.t_order_final GROUP BY order_status
UNION ALL SELECT '订单渠道',   channel,       COUNT(*) FROM ydsh_tmp.t_order_final GROUP BY channel
UNION ALL SELECT '行为类型',   behavior_type, COUNT(*) FROM ydsh_tmp.t_behavior_final GROUP BY behavior_type
ORDER BY chk, c DESC;

SELECT '时间戳非标准残留' AS chk, COUNT(*) AS c
FROM ydsh_tmp.t_order_final
WHERE NOT order_timestamp RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$';
