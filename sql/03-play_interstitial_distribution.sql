-- 脱敏说明: 内部表名/JSON 字段已泛化为通用名；事件名保留以便对照原业务含义
-- 原始 SQL 在本地保留（包含内部 schema 信息，不公开上传）

-- ============================================================
-- 播放插屏展示次数用户分布 — 按有无引导页分组
-- 用于验证插屏广告人均展示差异是否来自少数极端用户
-- 数据源: app_events ('ad_view' 事件)
-- 变量: {{start_date}} {{end_date}} {{country}} {{media_source}}
-- ============================================================

SELECT
    grp AS 分组,
    CASE
        WHEN play_cnt = 0 THEN '0次'
        WHEN play_cnt <= 3 THEN '1-3次'
        WHEN play_cnt <= 6 THEN '4-6次'
        WHEN play_cnt <= 10 THEN '7-10次'
        ELSE '10次以上'
    END AS 插屏频次,
    COUNT(*) AS 用户数,
    ROUND(AVG(play_cnt), 2) AS 人均展示
FROM (
    SELECT
        raw.afid,
        CASE WHEN g.afid IS NOT NULL THEN '有引导页' ELSE '无引导页' END AS grp,
        SUM(CASE WHEN ad_pl = 'play_interstitial' THEN 1 ELSE 0 END) AS play_cnt
    FROM (
        SELECT
            JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_id')) AS afid,
            COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
                CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.ad_placement'
            )), 'other') AS ad_pl
        FROM app_events
        WHERE event_name = ''ad_view''
          AND event_time >= '{{start_date}}'
          AND event_time <  '{{end_date}}'
          AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
          AND ('{{media_source}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.media_source')) = '{{media_source}}')
    ) raw
    LEFT JOIN (
        SELECT DISTINCT JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_id')) AS afid
        FROM app_events
        WHERE event_name = 'o_config'
          AND event_time >= '2026-07-25'
          AND event_time <  '{{end_date}}'
          AND JSON_UNQUOTE(JSON_EXTRACT(
              CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.guide_screen_1'
          )) = 'true'
    ) g ON raw.afid = g.afid
    GROUP BY raw.afid, g.afid
) user_agg
GROUP BY grp,
    CASE
        WHEN play_cnt = 0 THEN '0次'
        WHEN play_cnt <= 3 THEN '1-3次'
        WHEN play_cnt <= 6 THEN '4-6次'
        WHEN play_cnt <= 10 THEN '7-10次'
        ELSE '10次以上'
    END
ORDER BY 1, 2
