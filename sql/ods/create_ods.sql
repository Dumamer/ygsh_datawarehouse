-- =====================================================================
-- 文件：sql/ods/create_ods.sql
-- 作用：创建 ODS 贴源层数据库，并为 6 张模拟数据表建表
-- 环境：Hive 3.1.3 / 数据库 ydsh_ods
-- 说明：
--   1. ODS（Operational Data Store）层遵循「贴源」原则：不做任何加工，
--      字段一律使用 STRING 承接，保证脏数据原样落地，便于后续质量评估。
--      若这里直接写 INT/DOUBLE，'150'、''、'abc' 会被 Hive 静默转成 NULL 或 0，
--      脏数据就被"洗掉"了，质量报告反而失真。
--   2. 6 张表均为 CSV、UTF-8、逗号分隔、首行为表头，
--      因此统一使用 ROW FORMAT DELIMITED + skip.header.line.count=1。
--   3. 类型转换与清洗统一放在 DWD 层（见 sql/clean/）完成。
-- 执行：hive -f sql/ods/create_ods.sql
-- =====================================================================

CREATE DATABASE IF NOT EXISTS ydsh_ods
  COMMENT '云购生活 ODS 贴源层：原始数据原样落地，不做清洗';

CREATE DATABASE IF NOT EXISTS ydsh_dwd
  COMMENT '云购生活 DWD 明细层：清洗后的明细数据';

CREATE DATABASE IF NOT EXISTS ydsh_dq
  COMMENT '云购生活 数据质量层：五维度评估结果';

USE ydsh_ods;

-- ---------------------------------------------------------------------
-- 1. 用户表 ods_user：1000 行
--    已知脏数据：gender/age/member_level/email 缺失；age 存在 0、150；
--                register_date 存在 2024/06/21、20230829 等格式；
--                phone 存在 179-4507-0500 等带分隔符格式
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ods.ods_user;
CREATE TABLE ydsh_ods.ods_user (
  user_id       STRING COMMENT '用户ID，主键',
  user_name     STRING COMMENT '用户名',
  gender        STRING COMMENT '性别：男/女，脏数据含 未知/male/female/M/F/空',
  age           STRING COMMENT '年龄，脏数据含空值、0、150',
  city          STRING COMMENT '城市',
  province      STRING COMMENT '省份',
  register_date STRING COMMENT '注册日期 yyyy-MM-dd，脏数据含 2024/06/21、20230829',
  member_level  STRING COMMENT '会员等级，脏数据含 银卡会员/金卡/normal/gold 等变体',
  phone         STRING COMMENT '手机号，脏数据含 179-4507-0500 等带分隔符格式',
  email         STRING COMMENT '邮箱，缺失率约 19%'
)
COMMENT '用户维度表（贴源层）'
ROW FORMAT DELIMITED
  FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count' = '1');

-- ---------------------------------------------------------------------
-- 2. 商品表 ods_product：600 行
--    已知脏数据：launch_date 缺失 11 条；price 存在负值与超限值
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ods.ods_product;
CREATE TABLE ydsh_ods.ods_product (
  product_id   STRING COMMENT '商品ID，主键',
  product_name STRING COMMENT '商品名称',
  category     STRING COMMENT '一级类目',
  sub_category STRING COMMENT '二级类目',
  brand        STRING COMMENT '品牌',
  price        STRING COMMENT '售价，脏数据含负值',
  cost         STRING COMMENT '成本价',
  stock        STRING COMMENT '库存',
  status       STRING COMMENT '状态：在售/缺货/下架',
  launch_date  STRING COMMENT '上架日期，存在缺失'
)
COMMENT '商品维度表（贴源层）'
ROW FORMAT DELIMITED
  FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count' = '1');

-- ---------------------------------------------------------------------
-- 3. 门店表 ods_store：60 行
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ods.ods_store;
CREATE TABLE ydsh_ods.ods_store (
  store_id   STRING COMMENT '门店ID，主键',
  store_name STRING COMMENT '门店名称',
  province   STRING COMMENT '省份',
  city       STRING COMMENT '城市',
  district   STRING COMMENT '区县',
  address    STRING COMMENT '详细地址',
  open_date  STRING COMMENT '开业日期',
  area       STRING COMMENT '营业面积（平方米）',
  manager    STRING COMMENT '店长'
)
COMMENT '门店维度表（贴源层）'
ROW FORMAT DELIMITED
  FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count' = '1');

-- ---------------------------------------------------------------------
-- 4. 订单表 ods_order：15600 行
--    已知脏数据：order_id 主键重复 586 个值、多出 600 行（其中 400 行为整行完全
--                重复、200 行为主键相同但 pay_amount 不同）；
--                order_date 存在 2024/09/10 等格式；pay_amount/discount_amount
--                存在负值；pay_type/order_status/channel 存在枚举变体
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ods.ods_order;
CREATE TABLE ydsh_ods.ods_order (
  order_id        STRING COMMENT '订单ID，主键（存在重复）',
  user_id         STRING COMMENT '用户ID',
  store_id        STRING COMMENT '门店ID',
  order_date      STRING COMMENT '下单日期 yyyy-MM-dd',
  order_time      STRING COMMENT '下单时间 HH:mm:ss',
  pay_amount      STRING COMMENT '实付金额，脏数据含负值与异常大额',
  discount_amount STRING COMMENT '优惠金额，脏数据含负值',
  pay_type        STRING COMMENT '支付方式，脏数据含 微信支付/alipay/wechat 等变体',
  order_status    STRING COMMENT '订单状态，脏数据含 已支付/1/2/3/4/cancelled 等变体',
  channel         STRING COMMENT '下单渠道，脏数据含 PC官网/app/pc 等变体'
)
COMMENT '订单事实表（贴源层）'
ROW FORMAT DELIMITED
  FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count' = '1');

-- ---------------------------------------------------------------------
-- 5. 订单明细表 ods_order_item：37549 行
--    已知脏数据：quantity 存在 0/负数；unit_price 存在负值
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ods.ods_order_item;
CREATE TABLE ydsh_ods.ods_order_item (
  item_id     STRING COMMENT '明细ID，主键',
  order_id    STRING COMMENT '订单ID',
  product_id  STRING COMMENT '商品ID',
  quantity    STRING COMMENT '购买数量，脏数据含 0 与负数',
  unit_price  STRING COMMENT '成交单价，脏数据含负值',
  discount    STRING COMMENT '折扣率（0~1）'
)
COMMENT '订单明细事实表（贴源层）'
ROW FORMAT DELIMITED
  FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count' = '1');

-- ---------------------------------------------------------------------
-- 6. 用户行为表 ods_user_behavior：60000 行
--    已知脏数据：behavior_type 中英文混用且有大小写变体（pv/PV/cart/Cart/
--                fav/购买/浏览），需第 2 周做标准化映射
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ods.ods_user_behavior;
CREATE TABLE ydsh_ods.ods_user_behavior (
  behavior_id   STRING COMMENT '行为ID，主键',
  user_id       STRING COMMENT '用户ID',
  product_id    STRING COMMENT '商品ID',
  behavior_type STRING COMMENT '行为类型，脏数据含 pv/PV/cart/fav/浏览/购买 等变体',
  behavior_time STRING COMMENT '行为时间 yyyy-MM-dd HH:mm:ss',
  session_id    STRING COMMENT '会话ID'
)
COMMENT '用户行为事实表（贴源层）'
ROW FORMAT DELIMITED
  FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count' = '1');

SHOW TABLES IN ydsh_ods;
