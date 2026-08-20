-- 脱敏说明: 内部表名/JSON 字段已泛化为通用名；事件名保留以便对照原业务含义
-- 原始 SQL 在本地保留（包含内部 schema 信息，不公开上传）

-- ============================================================
-- 各广告位平均展示次数（人均）
-- 数据源: app_events ('ad_view' 事件)
-- 变量: {{start_date}} {{end_date}} {{country}} {{media_source}}
-- ============================================================

SELECT
    COUNT(DISTINCT afid) AS 用户数,
    COUNT(*) AS 总展示次数,
    ROUND(COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 人均展示,

    ROUND(SUM(CASE WHEN ad_pl = 'cold_start_app_open'        THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 冷启动,
    ROUND(SUM(CASE WHEN ad_pl = 'hot_start_app_open'         THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 热启动,
    ROUND(SUM(CASE WHEN ad_pl = 'play_interstitial'          THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 播放插屏,
    ROUND(SUM(CASE WHEN ad_pl = 'home_grid'                  THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 首页列表,
    ROUND(SUM(CASE WHEN ad_pl = 'for_you_interstitial'       THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 推荐插屏,
    ROUND(SUM(CASE WHEN ad_pl = 'search_grid'                THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 搜索页,
    ROUND(SUM(CASE WHEN ad_pl = 'guide_page_1'               THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 引导页1,
    ROUND(SUM(CASE WHEN ad_pl = 'guide_page_2'               THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 引导页2,
    ROUND(SUM(CASE WHEN ad_pl = 'first_language_screen'      THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 语言选择,
    ROUND(SUM(CASE WHEN ad_pl = 'for_you_native_slide_page'  THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 推荐滑动,
    ROUND(SUM(CASE WHEN ad_pl = 'personal_center'            THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 个人中心,
    ROUND(SUM(CASE WHEN ad_pl = 'favorites'                  THEN 1 ELSE 0 END) * 1.0 / NULLIF(COUNT(DISTINCT afid), 0), 2) AS 收藏页

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
) t
