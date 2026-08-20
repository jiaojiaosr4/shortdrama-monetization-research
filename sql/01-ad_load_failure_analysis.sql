-- 脱敏说明: 内部表名/JSON 字段已泛化为通用名；事件名保留以便对照原业务含义
-- 原始 SQL 在本地保留（包含内部 schema 信息，不公开上传）

-- ============================================================
-- Redash: 广告展示失败分析
-- 变量: {{start_date}} {{end_date}} {{country}}
-- 分析维度:
--   【查询1】整体漏斗: ad_load → 加载成功/失败 → 展示成功/失败
--   【查询2】ad_load 加载失败原因 + 占比
--   【查询3】ad_show 展示失败原因 + 占比
--   【查询4】按渠道看加载→展示转化
--   【查询5】每日趋势
-- ============================================================


-- ============================================================
-- 【查询1】整体漏斗 — 从加载到展示的完整转化
-- ============================================================
WITH load_total AS (
    SELECT COUNT(*) AS n FROM app_analytics.ad_events
    WHERE event_name = 'ad_load'
      AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
        AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
),
load_success AS (
    SELECT COUNT(*) AS n FROM app_analytics.ad_events
    WHERE event_name = 'ad_load'
      AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
        AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
      AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%'
),
load_failed AS (
    SELECT COUNT(*) AS n FROM app_analytics.ad_events
    WHERE event_name = 'ad_load'
      AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
        AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
      AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
),
show_total AS (
    SELECT COUNT(*) AS n FROM app_analytics.ad_events
    WHERE event_name = 'ad_show'
      AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
        AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
),
show_success AS (
    SELECT COUNT(*) AS n FROM app_analytics.ad_events
    WHERE event_name = 'ad_show'
      AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
        AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
      AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%'
),
show_failed AS (
    SELECT COUNT(*) AS n FROM app_analytics.ad_events
    WHERE event_name = 'ad_show'
      AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
        AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
      AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
)
SELECT '加载请求(ad_load总量)' AS 阶段, (SELECT n FROM load_total) AS 次数,
       ROUND((SELECT n FROM load_total) * 100.0 / (SELECT n FROM load_total), 2) AS 占加载总量_pct
UNION ALL
SELECT '├ 加载成功' AS 阶段, (SELECT n FROM load_success),
       ROUND((SELECT n FROM load_success) * 100.0 / (SELECT n FROM load_total), 2)
UNION ALL
SELECT '├ 加载失败' AS 阶段, (SELECT n FROM load_failed),
       ROUND((SELECT n FROM load_failed) * 100.0 / (SELECT n FROM load_total), 2)
UNION ALL
SELECT '│  ├ 展示成功(变现)' AS 阶段, (SELECT n FROM show_success),
       ROUND((SELECT n FROM show_success) * 100.0 / (SELECT n FROM load_total), 2)
UNION ALL
SELECT '│  ├ 展示失败(ad_show failed)' AS 阶段, (SELECT n FROM show_failed),
       ROUND((SELECT n FROM show_failed) * 100.0 / (SELECT n FROM load_total), 2)
UNION ALL
SELECT '│  └ 加载成功但未展示(浪费)' AS 阶段,
       (SELECT n FROM load_success) - (SELECT n FROM show_total),
       ROUND(((SELECT n FROM load_success) - (SELECT n FROM show_total)) * 100.0 / (SELECT n FROM load_total), 2);


-- ============================================================
-- 【查询2】ad_load 加载失败原因 + 占比
-- 失败信息在 event_value JSON: error_reason 字段
-- ============================================================
SELECT
    CASE
        -- JavascriptEngine
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%JavascriptEngine%'
          OR JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%Javascript%'
        THEN 'JS引擎不可用'
        -- DNS解析失败
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%Unable to resolve host%'
        THEN 'DNS解析失败(Google域名)'
        -- SSL/连接异常
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%SSL%'
          OR JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%Connection reset%'
          OR JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%end of stream%'
        THEN 'SSL/连接被重置'
        -- No fill
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%No fill%'
           OR JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%eCPM floor%'
        THEN '无广告填充(No Fill)'
        -- Network error
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%Network error%'
        THEN '网络错误'
        -- Internal error
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%Internal error%'
        THEN 'SDK内部错误'
        -- native ad response
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%native ad response%'
        THEN '原生广告响应失败'
        -- 请求频率限制
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%Too many%'
        THEN '请求频率限制'
        -- HTTP错误
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )) LIKE '%HTTP response code%'
        THEN 'HTTP错误'
        ELSE COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason'
        )), '其他')
    END AS 失败原因,
    COUNT(*) AS 次数,
    ROUND(COUNT(*) * 100.0 / (
        SELECT COUNT(*) FROM app_analytics.ad_events
        WHERE event_name = 'ad_load'
          AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
            AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
          AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
    ), 2) AS 占加载失败_pct,
    ROUND(COUNT(*) * 100.0 / (
        SELECT COUNT(*) FROM app_analytics.ad_events
        WHERE event_name = 'ad_load'
          AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
            AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
    ), 2) AS 占全部加载_pct
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}'
  AND event_time <  '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
GROUP BY 失败原因
ORDER BY 次数 DESC;


-- ============================================================
-- 【查询3】ad_show 展示失败原因 + 占比
-- 失败信息在 event_value JSON: error_msg 字段
-- ============================================================
SELECT
    CASE
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_msg'
        )) LIKE '%foreground%'
          OR JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_msg'
        )) LIKE '%前台%'
        THEN 'App不在前台'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_msg'
        )) LIKE '%Timeout%'
          OR JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_msg'
        )) LIKE '%超时%'
        THEN '展示超时'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_msg'
        )) LIKE '%load is failed%'
          OR JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_msg'
        )) LIKE '%加载失败%'
        THEN '广告加载失败导致'
        ELSE COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_msg'
        )), '其他')
    END AS 失败原因,
    COUNT(*) AS 次数,
    ROUND(COUNT(*) * 100.0 / (
        SELECT COUNT(*) FROM app_analytics.ad_events
        WHERE event_name = 'ad_show'
          AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
            AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
          AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
    ), 2) AS 占展示失败_pct,
    ROUND(COUNT(*) * 100.0 / (
        SELECT COUNT(*) FROM app_analytics.ad_events
        WHERE event_name = 'ad_show'
          AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
            AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
    ), 2) AS 占全部展示_pct
FROM app_analytics.ad_events
WHERE event_name = 'ad_show'
  AND event_time >= '{{start_date}}'
  AND event_time <  '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
GROUP BY 失败原因
ORDER BY 次数 DESC;


-- ============================================================
-- 【查询4】按渠道看加载→展示转化（饼图/柱状图用）
-- ============================================================
SELECT
    COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data, '$.media_source')), ''), 'Organic') AS 渠道,
    SUM(CASE WHEN event_name = 'ad_load' THEN 1 ELSE 0 END) AS 加载次数,
    SUM(CASE WHEN event_name = 'ad_show' THEN 1 ELSE 0 END) AS 展示次数,
    SUM(CASE WHEN event_name = 'ad_load' THEN 1 ELSE 0 END)
      - SUM(CASE WHEN event_name = 'ad_show' THEN 1 ELSE 0 END) AS 未展示,
    ROUND(
        (SUM(CASE WHEN event_name = 'ad_load' THEN 1 ELSE 0 END)
       - SUM(CASE WHEN event_name = 'ad_show' THEN 1 ELSE 0 END))
        * 100.0 / NULLIF(SUM(CASE WHEN event_name = 'ad_load' THEN 1 ELSE 0 END), 0),
    2) AS 未展示率_pct
FROM app_analytics.ad_events
WHERE event_name IN ('ad_load', 'ad_show')
  AND event_time >= '{{start_date}}'
  AND event_time <  '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
GROUP BY 渠道
ORDER BY 未展示 DESC;


-- ============================================================
-- 【查询5】每日趋势（折线图用）
-- ============================================================
SELECT
    dt AS 日期,
    loads AS 加载总量,
    load_success AS 加载成功,
    load_failed AS 加载失败,
    ROUND(load_failed * 100.0 / NULLIF(loads, 0), 2) AS 加载失败率_pct,
    shows AS 展示总量,
    loads - shows AS 总缺口,
    ROUND((loads - shows) * 100.0 / NULLIF(loads, 0), 2) AS 总缺口率_pct
FROM (
    SELECT
        DATE(event_time) AS dt,
        SUM(CASE WHEN event_name = 'ad_load' THEN 1 ELSE 0 END) AS loads,
        SUM(CASE WHEN event_name = 'ad_load'
                  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%'
             THEN 1 ELSE 0 END) AS load_success,
        SUM(CASE WHEN event_name = 'ad_load'
                  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
             THEN 1 ELSE 0 END) AS load_failed,
        SUM(CASE WHEN event_name = 'ad_show' THEN 1 ELSE 0 END) AS shows
    FROM app_analytics.ad_events
    WHERE event_name IN ('ad_load', 'ad_show')
      AND event_time >= '{{start_date}}'
      AND event_time <  '{{end_date}}'
        AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
    GROUP BY dt
) t
ORDER BY 日期 ASC;


-- ============================================================
-- 【查询6】合并：单维度失败率分析
--   维度 = 设备型号 / 系统版本 / 网络类型 / 运营商 / App版本 / SDK版本
--   图表：用「分析维度」做筛选器或分组柱状图
-- ============================================================
SELECT '设备型号' AS 分析维度,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_model')) AS 维度值,
    COUNT(*) AS 加载总量,
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%' THEN 1 ELSE 0 END) AS 加载成功,
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) AS 加载失败,
    ROUND(SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS 失败率_pct
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
GROUP BY 维度值
HAVING COUNT(*) >= 50

UNION ALL

SELECT '系统版本' AS 分析维度,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.os_version')) AS 维度值,
    COUNT(*), SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
GROUP BY 维度值

UNION ALL

SELECT '网络类型' AS 分析维度,
    CASE WHEN JSON_EXTRACT(data, '$.wifi') = true THEN 'WiFi' ELSE '蜂窝网络' END AS 维度值,
    COUNT(*), SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
GROUP BY 维度值

UNION ALL

SELECT '运营商' AS 分析维度,
    COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data, '$.carrier')), ''), 'Unknown') AS 维度值,
    COUNT(*), SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
GROUP BY 维度值
HAVING COUNT(*) >= 50

UNION ALL

SELECT 'App版本' AS 分析维度,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.app_version')) AS 维度值,
    COUNT(*), SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
GROUP BY 维度值

UNION ALL

SELECT 'SDK版本' AS 分析维度,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.sdk_version')) AS 维度值,
    COUNT(*), SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
GROUP BY 维度值

ORDER BY 分析维度, 失败率_pct DESC;


-- ============================================================
-- 【查询7】合并：维度 × 错误原因 交叉分析
--   交叉维度 = 设备型号 / 系统版本
--   图表：用「分析维度」筛选后做堆叠柱状图
-- ============================================================
SELECT '设备型号' AS 分析维度,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_model')) AS 维度值,
    CASE
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%JavascriptEngine%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Javascript%'
        THEN 'JS引擎不可用'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Unable to resolve host%'
        THEN 'DNS解析失败'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%SSL%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Connection reset%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%end of stream%'
        THEN 'SSL/连接被重置'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%No fill%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%eCPM floor%'
        THEN '无广告填充'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Network error%'
        THEN '网络错误'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Internal error%'
        THEN 'SDK内部错误'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%native ad response%'
        THEN '原生广告响应失败'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Too many%'
        THEN '请求频率限制'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%HTTP response code%'
        THEN 'HTTP错误'
        ELSE COALESCE(JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')), '其他')
    END AS 错误原因,
    COUNT(*) AS 次数
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
GROUP BY 维度值, 错误原因
HAVING 次数 >= 10

UNION ALL

SELECT '系统版本' AS 分析维度,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.os_version')) AS 维度值,
    CASE
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%JavascriptEngine%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Javascript%'
        THEN 'JS引擎不可用'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Unable to resolve host%'
        THEN 'DNS解析失败'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%SSL%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Connection reset%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%end of stream%'
        THEN 'SSL/连接被重置'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%No fill%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%eCPM floor%'
        THEN '无广告填充'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Network error%'
        THEN '网络错误'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Internal error%'
        THEN 'SDK内部错误'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%native ad response%'
        THEN '原生广告响应失败'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Too many%'
        THEN '请求频率限制'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%HTTP response code%'
        THEN 'HTTP错误'
        ELSE COALESCE(JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')), '其他')
    END AS 错误原因,
    COUNT(*) AS 次数
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
GROUP BY 维度值, 错误原因
ORDER BY 分析维度, 次数 DESC;


-- ============================================================
-- 【查询8】深度定位：JavascriptEngine 不可用 — 按机型+系统+App版本
--   （这类问题通常是手机 WebView 组件缺失/被阉割，可定位到具体机型）
-- ============================================================
SELECT
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_model')) AS 设备型号,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.os_version')) AS 系统版本,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.app_version')) AS App版本,
    COUNT(*) AS JS引擎失败次数
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
  AND (JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%JavascriptEngine%'
    OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Javascript%')
GROUP BY 设备型号, 系统版本, App版本
ORDER BY JS引擎失败次数 DESC
LIMIT 30;


-- ============================================================
-- 【查询9】深度定位：DNS/连接类问题 — 按运营商+网络类型+错误子类
--   （这类问题通常是运营商 DNS 污染或网络拦截，可定位到具体运营商）
-- ============================================================
SELECT
    COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data, '$.carrier')), ''), 'Unknown') AS 运营商,
    CASE WHEN JSON_EXTRACT(data, '$.wifi') = true THEN 'WiFi' ELSE '蜂窝网络' END AS 网络类型,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) AS 国家,
    CASE
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Unable to resolve host%'
        THEN 'DNS解析失败'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%SSL%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Connection reset%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%end of stream%'
        THEN 'SSL/连接被重置'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Network error%'
        THEN '网络错误'
        ELSE '其他连接问题'
    END AS 错误类型,
    COUNT(*) AS 次数
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
  AND (JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Unable to resolve host%'
    OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%SSL%'
    OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Connection reset%'
    OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%end of stream%'
    OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Network error%')
GROUP BY 运营商, 网络类型, 国家, 错误类型
ORDER BY 次数 DESC
LIMIT 30;


-- ============================================================
-- 【查询10】用户重复失败分析 — 失败次数分布
--   看失败是集中在少数用户（持续失败）还是分散在多数用户（偶发）
-- ============================================================
SELECT
    CASE
        WHEN cnt = 1 THEN '1次(偶发)'
        WHEN cnt BETWEEN 2 AND 5 THEN '2-5次'
        WHEN cnt BETWEEN 6 AND 10 THEN '6-10次'
        WHEN cnt BETWEEN 11 AND 20 THEN '11-20次'
        WHEN cnt BETWEEN 21 AND 50 THEN '21-50次'
        ELSE '50次以上(持续失败)'
    END AS 失败频次,
    CASE
        WHEN cnt = 1 THEN 1
        WHEN cnt BETWEEN 2 AND 5 THEN 2
        WHEN cnt BETWEEN 6 AND 10 THEN 3
        WHEN cnt BETWEEN 11 AND 20 THEN 4
        WHEN cnt BETWEEN 21 AND 50 THEN 5
        ELSE 6
    END AS 排序序号,
    COUNT(*) AS 用户数,
    SUM(cnt) AS 失败总次数,
    ROUND(SUM(cnt) * 100.0 / (
        SELECT COUNT(*) FROM app_analytics.ad_events
        WHERE event_name = 'ad_load'
          AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
            AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
          AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
    ), 2) AS 占全部失败_pct
FROM (
    SELECT
        JSON_UNQUOTE(JSON_EXTRACT(data, '$.user_id')) AS uid,
        COUNT(*) AS cnt
    FROM app_analytics.ad_events
    WHERE event_name = 'ad_load'
      AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
        AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
      AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
    GROUP BY uid
) t
GROUP BY 失败频次, 排序序号
ORDER BY 排序序号 ASC;


-- ============================================================
-- 【查询11】重复失败 Top 用户详情 — 高频失败用户长什么样
--   列出失败最多的用户及其设备信息，定位是否特定用户/设备
-- ============================================================
SELECT
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.user_id')) AS 用户ID,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_model')) AS 设备型号,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.os_version')) AS 系统版本,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.app_version')) AS App版本,
    COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data, '$.carrier')), ''), 'Unknown') AS 运营商,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) AS 国家,
    COUNT(*) AS 失败次数,
    COUNT(DISTINCT DATE(event_time)) AS 失败跨越天数,
    GROUP_CONCAT(DISTINCT
        CASE
            WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%JavascriptEngine%'
              OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Javascript%'
            THEN 'JS引擎'
            WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Unable to resolve host%'
            THEN 'DNS'
            WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%No fill%'
              OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%eCPM floor%'
            THEN 'NoFill'
            WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Network error%'
            THEN '网络错误'
            WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%SSL%'
              OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Connection reset%'
            THEN 'SSL/连接'
            ELSE '其他'
        END
        ORDER BY 1 SEPARATOR ', '
    ) AS 错误类型列表
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
GROUP BY 用户ID, 设备型号, 系统版本, App版本, 运营商, 国家
ORDER BY 失败次数 DESC
LIMIT 50;


-- ============================================================
-- 【查询12A】各广告位失败率对比
--   图表: Bar, X=广告位, Y=失败率_pct
-- ============================================================
SELECT
    COALESCE(JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')), '未知') AS 广告位,
    COUNT(*) AS 加载总量,
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) LIKE '%"result":"success"%' THEN 1 ELSE 0 END) AS 加载成功,
    SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) AS 加载失败,
    ROUND(SUM(CASE WHEN JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS 失败率_pct
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
GROUP BY 广告位
ORDER BY 失败率_pct DESC;


-- ============================================================
-- 【查询12B】广告位 × 错误原因交叉
--   图表: Bar(Stacked), X=广告位, Y=次数, 分组=错误原因
-- ============================================================
SELECT
    COALESCE(JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')), '未知') AS 广告位,
    CASE
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%JavascriptEngine%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Javascript%'
        THEN 'JS引擎不可用'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Unable to resolve host%'
        THEN 'DNS解析失败'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%SSL%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Connection reset%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%end of stream%'
        THEN 'SSL/连接被重置'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%No fill%'
          OR JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%eCPM floor%'
        THEN '无广告填充'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Network error%'
        THEN '网络错误'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Internal error%'
        THEN 'SDK内部错误'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')) LIKE '%Too many%'
        THEN '请求频率限制'
        ELSE COALESCE(JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')), '其他')
    END AS 错误原因,
    COUNT(*) AS 次数
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
GROUP BY 广告位, 错误原因
ORDER BY 次数 DESC;


-- ============================================================
-- 【查询12C】广告位 × 错误原因 — 用户数（去重）
--   看每个广告位的失败影响了多少个不同用户，而不是次数
--   图表: Bar(Stacked), X=广告位, Y=用户数, 分组=错误原因
-- ============================================================
SELECT
    CASE
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'cold_start_app_open' THEN '冷启动'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'hot_start_app_open' THEN '热加载'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'play_interstitial' THEN '播放插屏'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'home_grid' THEN '首页列表'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'for_you_interstitial' THEN '推荐页插屏'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'search_grid' THEN '搜索页'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'guide_page_1' THEN '引导页 - 1'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'guide_page_2' THEN '引导页 - 2'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'first_language_screen' THEN '引导页 - 语言'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'for_you_native_slide_page' THEN '推荐原生滑动'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'personal_center' THEN '个人中心'
        WHEN JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')) = 'favorites' THEN '收藏页'
        ELSE COALESCE(JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.placement')), '未知')
    END AS 广告位,
    CASE
        WHEN data LIKE '%JavascriptEngine%' OR data LIKE '%Javascript%' THEN 'JS引擎不可用'
        WHEN data LIKE '%Unable to resolve host%' THEN 'DNS解析失败'
        WHEN data LIKE '%SSL%' OR data LIKE '%Connection reset%' OR data LIKE '%end of stream%' THEN 'SSL/连接被重置'
        WHEN data LIKE '%No fill%' OR data LIKE '%eCPM floor%' THEN '无广告填充'
        WHEN data LIKE '%Network error%' THEN '网络错误'
        WHEN data LIKE '%Internal error%' THEN 'SDK内部错误'
        WHEN data LIKE '%Too many%' THEN '请求频率限制'
        ELSE COALESCE(JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')), '其他')
    END AS 错误原因,
    COUNT(DISTINCT JSON_UNQUOTE(JSON_EXTRACT(data, '$.user_id'))) AS 用户数
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
GROUP BY 广告位, 错误原因
ORDER BY 用户数 DESC;


-- ============================================================
-- 【查询13】失败机型+系统版本清单 — 用于广告投放屏蔽决策
--   按机型+系统版本+错误原因，列出失败用户数
--   直接导出 Top 机型清单，在广告 SDK 初始化时跳过这些设备
-- ============================================================
SELECT
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_model')) AS 设备型号,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.os_version')) AS 系统版本,
    CASE
        WHEN data LIKE '%JavascriptEngine%' OR data LIKE '%Javascript%' THEN 'JS引擎不可用'
        WHEN data LIKE '%Unable to resolve host%' THEN 'DNS解析失败'
        WHEN data LIKE '%SSL%' OR data LIKE '%Connection reset%' OR data LIKE '%end of stream%' THEN 'SSL/连接被重置'
        WHEN data LIKE '%No fill%' OR data LIKE '%eCPM floor%' THEN '无广告填充'
        WHEN data LIKE '%Network error%' THEN '网络错误'
        WHEN data LIKE '%Internal error%' THEN 'SDK内部错误'
        WHEN data LIKE '%Too many%' THEN '请求频率限制'
        ELSE COALESCE(JSON_UNQUOTE(JSON_EXTRACT(CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.error_reason')), '其他')
    END AS 错误原因,
    COUNT(*) AS 失败次数,
    COUNT(DISTINCT JSON_UNQUOTE(JSON_EXTRACT(data, '$.user_id'))) AS 失败用户数,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT JSON_UNQUOTE(JSON_EXTRACT(data, '$.user_id'))), 1) AS 人均失败次数
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
GROUP BY 设备型号, 系统版本, 错误原因
HAVING 失败用户数 >= 1
ORDER BY 失败用户数 DESC, 失败次数 DESC
LIMIT 100;


-- ============================================================
-- 【查询14】建议屏蔽的设备清单 — 只列出JS引擎/SSL等不可修复的错误
--   排除 No Fill（广告平台问题）和网络错误（偶发）
--   这些机型用户投放广告也无法加载，建议屏蔽避免浪费
-- ============================================================
SELECT
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_model')) AS 建议屏蔽机型,
    JSON_UNQUOTE(JSON_EXTRACT(data, '$.os_version')) AS 系统版本,
    COUNT(*) AS 失败次数,
    COUNT(DISTINCT JSON_UNQUOTE(JSON_EXTRACT(data, '$.user_id'))) AS 受影响用户数,
    GROUP_CONCAT(DISTINCT
        CASE
            WHEN data LIKE '%JavascriptEngine%' OR data LIKE '%Javascript%' THEN 'JS引擎'
            WHEN data LIKE '%Unable to resolve host%' THEN 'DNS'
            WHEN data LIKE '%SSL%' OR data LIKE '%Connection reset%' THEN 'SSL/连接'
            ELSE 'Other'
        END
        ORDER BY 1 SEPARATOR ', '
    ) AS 错误类型
FROM app_analytics.ad_events
WHERE event_name = 'ad_load'
  AND event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
    AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
  AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) NOT LIKE '%"result":"success"%'
  AND (data LIKE '%JavascriptEngine%' OR data LIKE '%Javascript%'
    OR data LIKE '%Unable to resolve host%'
    OR data LIKE '%SSL%' OR data LIKE '%Connection reset%')
  AND data NOT LIKE '%No fill%'
  AND data NOT LIKE '%eCPM floor%'
GROUP BY 建议屏蔽机型, 系统版本
ORDER BY 失败次数 DESC
LIMIT 50;


-- ============================================================
-- 【查询15】用户留存天数分布
-- 留存天数 = 用户实际活跃了多少个不同日期
-- ============================================================
SELECT
    留存天数段,
    用户数 AS 留存人数,
    ROUND(用户数 * 100.0 / SUM(用户数) OVER(), 2) AS 留存率_pct
FROM (
    SELECT
        CASE
            WHEN days = 1 THEN '1天'
            WHEN days BETWEEN 2 AND 14 THEN CONCAT(days, '天')
            ELSE '15天及以上'
        END AS 留存天数段,
        days AS 排序,
        COUNT(*) AS 用户数
    FROM (
        SELECT
            JSON_UNQUOTE(JSON_EXTRACT(data, '$.user_id')) AS uid,
            COUNT(DISTINCT DATE(event_time)) AS days
        FROM app_analytics.ad_events
        WHERE event_time >= '{{start_date}}' AND event_time < '{{end_date}}'
          AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
        GROUP BY JSON_UNQUOTE(JSON_EXTRACT(data, '$.user_id'))
    ) t
    GROUP BY days
) t2
ORDER BY 排序;
