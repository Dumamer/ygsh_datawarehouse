-- =====================================================================
-- 文件：sql/clean/clean_user_missing.sql
-- 作用：数据清洗（一）—— 缺失值诊断与处理，产出 DWD 明细层表
-- 执行：hive -f sql/clean/clean_user_missing.sql
-- 产出：ydsh_dwd.dwd_user            清洗后的用户明细表
--       ydsh_dwd.dwd_product         清洗后的商品明细表（上架日期补全）
--       ydsh_dq.dq_missing_strategy  缺失值处理策略留痕表
--
-- 【策略总表】先定策略、再写 SQL，这是数据治理的基本顺序
-- ┌───────────────────────┬──────┬────────────────────────────────────────┐
-- │ 字段                   │ 缺失 │ 处理策略与业务理由                      │
-- ├───────────────────────┼──────┼────────────────────────────────────────┤
-- │ ods_user.age          │  51  │ 用「有效年龄(1~120)」中位数填充。          │
-- │                       │      │ 理由：年龄分布右偏且有 150 这类异常值，   │
-- │                       │      │ 均值会被拉高，中位数更稳健；不删行，      │
-- │                       │      │ 因为用户维度表删行会连带丢失其它有效字段。│
-- │ ods_user.email        │ 193  │ 保留空值，新增 email_is_missing 标记位。  │
-- │                       │      │ 理由：邮箱是有则更好的营销字段，无法合理  │
-- │                       │      │ 推断，编造会污染后续触达分析。            │
-- │ ods_user.gender       │  84  │ 填充为「未知」。                          │
-- │                       │      │ 理由：性别不可推断，但下游 group by 需要  │
-- │                       │      │ 显式分支，避免 NULL 被静默丢弃。          │
-- │ ods_user.member_level │  14  │ 填充为业务默认最小等级「普通会员」。      │
-- │ ods_product.launch_date│ 11  │ 用同品类上架日期均值回退补全；品类内无     │
-- │                       │      │ 有效值时回退到全局均值。                  │
-- └───────────────────────┴──────┴────────────────────────────────────────┘
--
-- 说明：本脚本只处理「缺失值」。枚举变体（male/female/M/F、银卡会员/normal、
--       pv/cart/fav）属于「有效性/一致性」问题，按教学进度放在第 2 周
--       清洗（二）处理，这里刻意不做，避免不同性质的脏数据混在一起。
-- =====================================================================

CREATE DATABASE IF NOT EXISTS ydsh_dwd;
CREATE DATABASE IF NOT EXISTS ydsh_dq;

-- Windows 本地模式下关闭 map join（见 sql/quality 里的同类说明）
SET hive.auto.convert.join=false;

-- ---------------------------------------------------------------------
-- 第 0 步：计算填充基线并落表（中位数/均值必须落表，才能被跨行引用）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dq.dq_fill_baseline;
CREATE TABLE ydsh_dq.dq_fill_baseline (
  metric_name  STRING,
  metric_value DOUBLE,
  remark       STRING
) STORED AS TEXTFILE;

-- 有效年龄中位数
INSERT INTO TABLE ydsh_dq.dq_fill_baseline
SELECT 'age_median', percentile_approx(CAST(age AS DOUBLE), 0.5), '有效年龄(1~120)中位数'
FROM ydsh_ods.ods_user
WHERE TRIM(age) <> '' AND age RLIKE '^[0-9]+$'
  AND CAST(age AS DOUBLE) BETWEEN 1 AND 120;

-- 分品类上架日期基线：存「上架日期距 2024-12-31 的天数均值」，补全时反向推算
-- 注意：源数据 category 存在尾部空格（如'图书文娱 '），必须先 TRIM，否则会拆成两组
INSERT INTO TABLE ydsh_dq.dq_fill_baseline
SELECT CONCAT('launch_days_', TRIM(category)),
       AVG(CAST(datediff(TO_DATE(launch_date), TO_DATE('2024-12-31')) AS DOUBLE)),
       '品类上架日期基线（距 2024-12-31 的天数均值）'
FROM ydsh_ods.ods_product
WHERE TRIM(launch_date) <> ''
GROUP BY TRIM(category);

-- 全局兜底基线
INSERT INTO TABLE ydsh_dq.dq_fill_baseline
SELECT 'launch_days_ALL',
       AVG(CAST(datediff(TO_DATE(launch_date), TO_DATE('2024-12-31')) AS DOUBLE)),
       '全局上架日期基线（品类内无样本时兜底）'
FROM ydsh_ods.ods_product
WHERE TRIM(launch_date) <> '';

SELECT * FROM ydsh_dq.dq_fill_baseline ORDER BY metric_name;

-- ---------------------------------------------------------------------
-- 第 1 步：诊断——清洗前每类缺失值的数量与占比
-- ---------------------------------------------------------------------
SELECT 'ods_user.age'          AS target, COUNT(*) AS missing_cnt,
       ROUND(COUNT(*) / 1000, 4) AS missing_rate, 'median_fill'        AS strategy
FROM ydsh_ods.ods_user WHERE age IS NULL OR TRIM(age) = ''
UNION ALL
SELECT 'ods_user.email', COUNT(*), ROUND(COUNT(*) / 1000, 4), 'keep_null_and_flag'
FROM ydsh_ods.ods_user WHERE email IS NULL OR TRIM(email) = ''
UNION ALL
SELECT 'ods_user.gender', COUNT(*), ROUND(COUNT(*) / 1000, 4), 'fill_unknown'
FROM ydsh_ods.ods_user WHERE gender IS NULL OR TRIM(gender) = ''
UNION ALL
SELECT 'ods_user.member_level', COUNT(*), ROUND(COUNT(*) / 1000, 4), 'fill_default_level'
FROM ydsh_ods.ods_user WHERE member_level IS NULL OR TRIM(member_level) = ''
UNION ALL
SELECT 'ods_product.launch_date', COUNT(*), ROUND(COUNT(*) / 600, 4), 'category_mean_fill'
FROM ydsh_ods.ods_product WHERE launch_date IS NULL OR TRIM(launch_date) = '';

-- ---------------------------------------------------------------------
-- 第 2 步：清洗——输出 dwd_user
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dwd_user;
CREATE TABLE ydsh_dwd.dwd_user (
  user_id          STRING COMMENT '用户ID',
  user_name        STRING COMMENT '用户名',
  gender           STRING COMMENT '性别：男/女/未知（缺失已填充为未知）',
  age              INT    COMMENT '年龄：合法值原样保留，缺失/异常用中位数填充',
  city             STRING COMMENT '城市',
  province         STRING COMMENT '省份',
  register_date    STRING COMMENT '注册日期（格式标准化见第 2 周）',
  member_level     STRING COMMENT '会员等级（缺失已填充为普通会员）',
  phone            STRING COMMENT '手机号（格式标准化见第 2 周）',
  email            STRING COMMENT '邮箱，保留空值',
  age_is_filled    INT    COMMENT '年龄是否被填充：1=填充 0=原始有效值',
  email_is_missing INT    COMMENT '邮箱是否缺失：1=缺失 0=有值'
)
COMMENT '用户明细表（DWD）：已完成缺失值处理'
STORED AS TEXTFILE;

INSERT INTO TABLE ydsh_dwd.dwd_user
SELECT
  u.user_id,
  u.user_name,
  IF(u.gender IS NULL OR TRIM(u.gender) = '', '未知', u.gender)                      AS gender,
  CASE WHEN TRIM(u.age) RLIKE '^[0-9]+$' AND CAST(u.age AS DOUBLE) BETWEEN 1 AND 120
       THEN CAST(u.age AS INT)
       ELSE CAST(b.metric_value AS INT)
  END                                                                               AS age,
  u.city,
  u.province,
  u.register_date,
  IF(u.member_level IS NULL OR TRIM(u.member_level) = '', '普通会员', u.member_level)  AS member_level,
  u.phone,
  NULLIF(TRIM(u.email), '')                                                         AS email,
  CASE WHEN TRIM(u.age) RLIKE '^[0-9]+$' AND CAST(u.age AS DOUBLE) BETWEEN 1 AND 120
       THEN 0 ELSE 1 END                                                            AS age_is_filled,
  CASE WHEN TRIM(u.email) = '' THEN 1 ELSE 0 END                                     AS email_is_missing
FROM ydsh_ods.ods_user u
CROSS JOIN (SELECT metric_value FROM ydsh_dq.dq_fill_baseline WHERE metric_name = 'age_median') b;

-- ---------------------------------------------------------------------
-- 第 3 步：商品上架日期缺失补全（同品类均值 -> 全局均值兜底）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dwd_product;
CREATE TABLE ydsh_dwd.dwd_product (
  product_id   STRING,
  product_name STRING,
  category     STRING,
  sub_category STRING,
  brand        STRING,
  price        DOUBLE,
  cost         DOUBLE,
  stock        INT,
  status       STRING,
  launch_date  STRING COMMENT '上架日期：缺失已按同品类均值补全',
  launch_date_is_filled INT COMMENT '1=补全 0=原始值'
)
COMMENT '商品明细表（DWD）：已完成缺失值处理'
STORED AS TEXTFILE;

INSERT INTO TABLE ydsh_dwd.dwd_product
SELECT
  p.product_id,
  p.product_name,
  p.category,
  p.sub_category,
  p.brand,
  CAST(p.price AS DOUBLE),
  CAST(p.cost  AS DOUBLE),
  CAST(p.stock AS INT),
  p.status,
  CASE WHEN TRIM(p.launch_date) <> '' THEN TO_DATE(p.launch_date)
       ELSE DATE_ADD(TO_DATE('2024-12-31'),
                     CAST(COALESCE(c.metric_value, g.metric_value) AS INT))
  END                                                                               AS launch_date,
  CASE WHEN TRIM(p.launch_date) = '' THEN 1 ELSE 0 END                               AS launch_date_is_filled
FROM ydsh_ods.ods_product p
LEFT JOIN ydsh_dq.dq_fill_baseline c
       ON c.metric_name = CONCAT('launch_days_', TRIM(p.category))
LEFT JOIN ydsh_dq.dq_fill_baseline g
       ON g.metric_name = 'launch_days_ALL';

-- ---------------------------------------------------------------------
-- 第 4 步：清洗统计落表（供策略留痕表与质量报告使用）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dq.dq_clean_stat;
CREATE TABLE ydsh_dq.dq_clean_stat (
  k STRING,
  v BIGINT
) STORED AS TEXTFILE;

INSERT INTO TABLE ydsh_dq.dq_clean_stat
SELECT 'user_total',              COUNT(*) FROM ydsh_ods.ods_user
UNION ALL SELECT 'user_age_null_before',       COUNT(*) FROM ydsh_ods.ods_user WHERE age IS NULL OR TRIM(age) = ''
UNION ALL SELECT 'user_age_invalid_before',    COUNT(*) FROM ydsh_ods.ods_user WHERE TRIM(age) <> '' AND (NOT (age RLIKE '^[0-9]+$') OR CAST(age AS DOUBLE) NOT BETWEEN 1 AND 120)
UNION ALL SELECT 'user_email_null_before',     COUNT(*) FROM ydsh_ods.ods_user WHERE email IS NULL OR TRIM(email) = ''
UNION ALL SELECT 'user_gender_null_before',    COUNT(*) FROM ydsh_ods.ods_user WHERE gender IS NULL OR TRIM(gender) = ''
UNION ALL SELECT 'user_level_null_before',     COUNT(*) FROM ydsh_ods.ods_user WHERE member_level IS NULL OR TRIM(member_level) = ''
UNION ALL SELECT 'dwd_user_age_filled',        SUM(age_is_filled) FROM ydsh_dwd.dwd_user
UNION ALL SELECT 'dwd_user_age_null_after',    COUNT(*) FROM ydsh_dwd.dwd_user WHERE age IS NULL
UNION ALL SELECT 'dwd_user_age_oor_after',     COUNT(*) FROM ydsh_dwd.dwd_user WHERE age NOT BETWEEN 1 AND 120
UNION ALL SELECT 'dwd_user_email_null_after',  COUNT(*) FROM ydsh_dwd.dwd_user WHERE email IS NULL
UNION ALL SELECT 'dwd_user_gender_null_after', COUNT(*) FROM ydsh_dwd.dwd_user WHERE gender IS NULL
UNION ALL SELECT 'dwd_user_level_null_after',  COUNT(*) FROM ydsh_dwd.dwd_user WHERE member_level IS NULL
UNION ALL SELECT 'product_date_null_before',   COUNT(*) FROM ydsh_ods.ods_product WHERE launch_date IS NULL OR TRIM(launch_date) = ''
UNION ALL SELECT 'dwd_product_date_filled',    SUM(launch_date_is_filled) FROM ydsh_dwd.dwd_product
UNION ALL SELECT 'dwd_product_date_null_after',COUNT(*) FROM ydsh_dwd.dwd_product WHERE launch_date IS NULL;

-- ---------------------------------------------------------------------
-- 第 5 步：策略留痕表（写进质量报告，答辩时直接用）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dq.dq_missing_strategy;
CREATE TABLE ydsh_dq.dq_missing_strategy (
  table_name     STRING,
  column_name    STRING,
  missing_cnt    BIGINT COMMENT '清洗前缺失数',
  missing_rate   DOUBLE COMMENT '清洗前缺失率',
  strategy       STRING COMMENT '处理策略',
  filled_cnt     BIGINT COMMENT '被填充/处理的记录数',
  null_after_cnt BIGINT COMMENT '清洗后仍为空的数量'
) STORED AS TEXTFILE;

-- 为什么拆成 5 条 INSERT 而不是一条 UNION ALL：
-- Hive 的 UNION 会把各分支的子查询合并解析，多个分支都叫 s 且列名相同会报
-- "Ambiguous column reference"，拆开写更稳妥也更好读。
INSERT INTO TABLE ydsh_dq.dq_missing_strategy
SELECT 'ods_user', 'age', s.age_null, ROUND(s.age_null / s.total, 4),
       '中位数填充（有效年龄 1~120 的中位数）', s.age_filled, s.age_null_after
FROM (
  SELECT MAX(IF(k = 'user_total', v, 0))                   AS total,
         MAX(IF(k = 'user_age_null_before', v, 0))         AS age_null,
         MAX(IF(k = 'dwd_user_age_filled', v, 0))          AS age_filled,
         MAX(IF(k = 'dwd_user_age_null_after', v, 0))      AS age_null_after
  FROM ydsh_dq.dq_clean_stat
) s;

INSERT INTO TABLE ydsh_dq.dq_missing_strategy
SELECT 'ods_user', 'email', s.email_null, ROUND(s.email_null / s.total, 4),
       '保留空值 + 新增 email_is_missing 标记位', 0, s.email_null_after
FROM (
  SELECT MAX(IF(k = 'user_total', v, 0))                   AS total,
         MAX(IF(k = 'user_email_null_before', v, 0))       AS email_null,
         MAX(IF(k = 'dwd_user_email_null_after', v, 0))    AS email_null_after
  FROM ydsh_dq.dq_clean_stat
) s;

INSERT INTO TABLE ydsh_dq.dq_missing_strategy
SELECT 'ods_user', 'gender', s.gender_null, ROUND(s.gender_null / s.total, 4),
       '填充为「未知」', s.gender_null, s.gender_null_after
FROM (
  SELECT MAX(IF(k = 'user_total', v, 0))                   AS total,
         MAX(IF(k = 'user_gender_null_before', v, 0))      AS gender_null,
         MAX(IF(k = 'dwd_user_gender_null_after', v, 0))   AS gender_null_after
  FROM ydsh_dq.dq_clean_stat
) s;

INSERT INTO TABLE ydsh_dq.dq_missing_strategy
SELECT 'ods_user', 'member_level', s.level_null, ROUND(s.level_null / s.total, 4),
       '填充为默认等级「普通会员」', s.level_null, s.level_null_after
FROM (
  SELECT MAX(IF(k = 'user_total', v, 0))                   AS total,
         MAX(IF(k = 'user_level_null_before', v, 0))       AS level_null,
         MAX(IF(k = 'dwd_user_level_null_after', v, 0))    AS level_null_after
  FROM ydsh_dq.dq_clean_stat
) s;

INSERT INTO TABLE ydsh_dq.dq_missing_strategy
SELECT 'ods_product', 'launch_date', s.pdate_null, ROUND(s.pdate_null / 600, 4),
       '按同品类上架日期均值回退补全', s.pdate_filled, s.pdate_null_after
FROM (
  SELECT MAX(IF(k = 'product_date_null_before', v, 0))     AS pdate_null,
         MAX(IF(k = 'dwd_product_date_filled', v, 0))      AS pdate_filled,
         MAX(IF(k = 'dwd_product_date_null_after', v, 0))  AS pdate_null_after
  FROM ydsh_dq.dq_clean_stat
) s;

SELECT * FROM ydsh_dq.dq_missing_strategy;

-- ---------------------------------------------------------------------
-- 第 6 步：清洗效果验收
-- ---------------------------------------------------------------------
SELECT 'ods_user'     AS table_name, COUNT(*) AS rows_cnt FROM ydsh_ods.ods_user
UNION ALL SELECT 'dwd_user',    COUNT(*) FROM ydsh_dwd.dwd_user
UNION ALL SELECT 'ods_product', COUNT(*) FROM ydsh_ods.ods_product
UNION ALL SELECT 'dwd_product', COUNT(*) FROM ydsh_dwd.dwd_product;

-- 期望：gender_null=0 age_null=0 age_out_of_range=0 level_null=0，email_null=193（按策略保留）
SELECT
  SUM(IF(gender       IS NULL, 1, 0))       AS gender_null,
  SUM(IF(age          IS NULL, 1, 0))       AS age_null,
  SUM(IF(age NOT BETWEEN 1 AND 120, 1, 0))  AS age_out_of_range,
  SUM(IF(member_level IS NULL, 1, 0))       AS level_null,
  SUM(IF(email        IS NULL, 1, 0))       AS email_null_expected_193
FROM ydsh_dwd.dwd_user;

SELECT * FROM ydsh_dwd.dwd_user LIMIT 5;
SELECT * FROM ydsh_dwd.dwd_product WHERE launch_date_is_filled = 1 LIMIT 5;
