-- =====================================================================
-- 第 2 周 · 子任务 6（上）：DWD 层维度建模 DDL —— 星型模型
--   事实表：dwd_order（按 order_date 分区 / ORC）、dwd_order_item（按 order_id 分 8 桶 / ORC）、
--           dwd_user_behavior（按 behavior_date 分区 / ORC）
--   维度表：dim_user / dim_product / dim_store / dim_date / 编码映射 dim_code_mapping
--   事实表通过外键（user_id / store_id / product_id / date_key）关联维度表主键
-- =====================================================================
SET hive.auto.convert.join=false;
SET hive.vectorized.execution.enabled=false;

-- 第 1 周的旧清洗表已被第 2 周完整清洗链替代，重建
DROP TABLE IF EXISTS ydsh_dwd.dwd_order;
DROP TABLE IF EXISTS ydsh_dwd.dwd_user;
DROP TABLE IF EXISTS ydsh_dwd.dwd_product;

-- ---------- 维度表 ----------
-- 用户维度
CREATE TABLE IF NOT EXISTS ydsh_dwd.dim_user (
  user_id         string COMMENT '主键',
  user_name       string,
  gender          string COMMENT '男/女/未知',
  age             int,
  city            string,
  province        string,
  region          string COMMENT 'province+city 合并',
  member_level    string COMMENT '普通/银卡/金卡/钻石会员',
  register_date   string,
  phone           string COMMENT '11 位纯数字',
  email           string,
  age_is_filled   int    COMMENT '1=年龄由中位数填充',
  email_is_missing int   COMMENT '1=邮箱缺失保留空值'
) STORED AS ORC;

-- 商品维度
CREATE TABLE IF NOT EXISTS ydsh_dwd.dim_product (
  product_id      string COMMENT '主键',
  product_name    string,
  category        string,
  sub_category    string,
  brand           string,
  launch_date     string,
  price           double,
  cost            double,
  stock           int,
  status          string
) STORED AS ORC;

-- 门店维度
CREATE TABLE IF NOT EXISTS ydsh_dwd.dim_store (
  store_id        string COMMENT '主键',
  store_name      string,
  province        string,
  city            string,
  district        string,
  address         string,
  open_date       string,
  area            double,
  manager         string
) STORED AS ORC;

-- 时间维度（2023-01-01 ~ 2024-12-31 由 posexplode 生成，不依赖业务表）
CREATE TABLE IF NOT EXISTS ydsh_dwd.dim_date (
  date_key        string COMMENT '主键 yyyy-MM-dd',
  year            int,
  month           int,
  day             int,
  ym              string COMMENT 'yyyy-MM，用于月度聚合',
  quarter         int,
  day_of_week     int    COMMENT '1=周一 ... 7=周日',
  is_weekend      int    COMMENT '1=周末'
) STORED AS ORC;

-- ---------- 事实表 ----------
-- 订单事实表：按 order_date 分区（查询带分区条件可裁剪到具体日期）
CREATE TABLE IF NOT EXISTS ydsh_dwd.dwd_order (
  order_id            string COMMENT '主键（已去重）',
  user_id             string COMMENT '外键 → dim_user',
  store_id            string COMMENT '外键 → dim_store',
  order_timestamp     string COMMENT 'yyyy-MM-dd HH:mm:ss',
  pay_amount          double COMMENT '度量：实付金额（异常已回填修正）',
  pay_amount_is_repaired int COMMENT '0=原始有效 1=明细回填 2=无法修复置空',
  discount_amount     double COMMENT '度量：优惠金额',
  pay_type            string COMMENT '微信支付/支付宝/货到付款/银行卡',
  order_status        string COMMENT '已完成/已支付/待支付/已取消/退款中',
  channel             string COMMENT 'APP/小程序/门店/PC官网'
) PARTITIONED BY (order_date string COMMENT 'yyyy-MM-dd')
  STORED AS ORC;

-- 订单明细事实表：按 order_id 分 8 桶（与订单表 join 时可做 bucket map join）
CREATE TABLE IF NOT EXISTS ydsh_dwd.dwd_order_item (
  item_id         string COMMENT '主键',
  order_id        string COMMENT '外键 → dwd_order（分桶键）',
  product_id      string COMMENT '外键 → dim_product',
  quantity        int,
  unit_price      double,
  discount        double COMMENT '折扣率',
  line_amount     double COMMENT '度量：quantity*unit_price*(1-discount)'
) CLUSTERED BY (order_id) SORTED BY (order_id) INTO 8 BUCKETS
  STORED AS ORC;

-- 用户行为事实表：按 behavior_date 分区
CREATE TABLE IF NOT EXISTS ydsh_dwd.dwd_user_behavior (
  user_id         string COMMENT '外键 → dim_user',
  product_id      string COMMENT '外键 → dim_product',
  behavior_type   string COMMENT '浏览/加购/收藏/购买',
  behavior_time   string
) PARTITIONED BY (behavior_date string COMMENT 'yyyy-MM-dd')
  STORED AS ORC;
