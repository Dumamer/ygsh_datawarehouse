-- =====================================================================
-- 文件：sql/ods/verify_ods.sql
-- 作用：ODS 层导入结果校验——行数是否与数据字典预期一致
-- 执行：hive -f sql/ods/verify_ods.sql
-- 预期行数来源：《第 1 周部署操作手册》步骤 6 数据字典
-- =====================================================================

USE ydsh_ods;

SELECT 'ods_user' AS table_name, COUNT(*) AS actual_rows, 1000 AS expected_rows,
       COUNT(*) - 1000 AS diff, IF(COUNT(*) = 1000, 'PASS', 'FAIL') AS result
FROM ydsh_ods.ods_user
UNION ALL
SELECT 'ods_product', COUNT(*), 600, COUNT(*) - 600, IF(COUNT(*) = 600, 'PASS', 'FAIL')
FROM ydsh_ods.ods_product
UNION ALL
SELECT 'ods_store', COUNT(*), 60, COUNT(*) - 60, IF(COUNT(*) = 60, 'PASS', 'FAIL')
FROM ydsh_ods.ods_store
UNION ALL
SELECT 'ods_order', COUNT(*), 15600, COUNT(*) - 15600, IF(COUNT(*) = 15600, 'PASS', 'FAIL')
FROM ydsh_ods.ods_order
UNION ALL
SELECT 'ods_order_item', COUNT(*), 37549, COUNT(*) - 37549, IF(COUNT(*) = 37549, 'PASS', 'FAIL')
FROM ydsh_ods.ods_order_item
UNION ALL
SELECT 'ods_user_behavior', COUNT(*), 60000, COUNT(*) - 60000, IF(COUNT(*) = 60000, 'PASS', 'FAIL')
FROM ydsh_ods.ods_user_behavior;

-- 抽样核对：确认字段没有整体错位、中文没有乱码
SELECT * FROM ydsh_ods.ods_user LIMIT 3;
SELECT * FROM ydsh_ods.ods_order LIMIT 3;
