-- =====================================================================
-- 文件：sql/ods/load_ods.sql
-- 作用：将 data/ 目录下 6 张 CSV 加载进 ODS 贴源层
-- 执行：hive --hiveconf data_dir=D:/path/to/data -f sql/ods/load_ods.sql
-- 说明：
--   1. 使用 LOAD DATA LOCAL INPATH，Hive 会把本地文件「移动/复制」到仓库目录下，
--      因此每张表重复执行前建议先 TRUNCATE，避免重复导入导致行数翻倍。
--   2. LOCAL 表示从客户端本地文件系统读取，不需要先把文件传到 HDFS，
--      这也是本机无 HDFS 集群时的标准做法。
--   3. 表头已在建表时用 tblproperties('skip.header.line.count'='1') 跳过，
--      文件首行的 UTF-8 BOM 也随之被跳过，不影响字段解析。
-- =====================================================================

USE ydsh_ods;

-- 幂等：重复执行前先清空，避免累加
TRUNCATE TABLE ydsh_ods.ods_user;
TRUNCATE TABLE ydsh_ods.ods_product;
TRUNCATE TABLE ydsh_ods.ods_store;
TRUNCATE TABLE ydsh_ods.ods_order;
TRUNCATE TABLE ydsh_ods.ods_order_item;
TRUNCATE TABLE ydsh_ods.ods_user_behavior;

LOAD DATA LOCAL INPATH '${hiveconf:data_dir}/ods_user.csv'           INTO TABLE ydsh_ods.ods_user;
LOAD DATA LOCAL INPATH '${hiveconf:data_dir}/ods_product.csv'        INTO TABLE ydsh_ods.ods_product;
LOAD DATA LOCAL INPATH '${hiveconf:data_dir}/ods_store.csv'          INTO TABLE ydsh_ods.ods_store;
LOAD DATA LOCAL INPATH '${hiveconf:data_dir}/ods_order.csv'          INTO TABLE ydsh_ods.ods_order;
LOAD DATA LOCAL INPATH '${hiveconf:data_dir}/ods_order_item.csv'     INTO TABLE ydsh_ods.ods_order_item;
LOAD DATA LOCAL INPATH '${hiveconf:data_dir}/ods_user_behavior.csv'  INTO TABLE ydsh_ods.ods_user_behavior;
