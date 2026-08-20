-- 脱敏说明: 内部表名/JSON 字段已泛化为通用名；事件名保留以便对照原业务含义
-- 原始 SQL 在本地保留（包含内部 schema 信息，不公开上传）

-- ============================================================
-- 引导页 A/B 对比: 有 vs 无 — 总收入 & 各广告位收入
-- 数据源: app_events
-- 关联: data.device_id
-- 变量: {{start_date}} {{end_date}} {{media_source}} {{country}}
-- ============================================================

WITH guide_users AS (
    SELECT DISTINCT
        JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_id')) AS afid
    FROM app_events
    WHERE event_name = 'o_config'
      AND event_time >= '2026-07-25'
      AND event_time <  '{{end_date}}'
      AND JSON_UNQUOTE(JSON_EXTRACT(
          CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON),
          '$.guide_screen_1'
      )) = 'true'
),
revenue_raw AS (
    SELECT
        JSON_UNQUOTE(JSON_EXTRACT(data, '$.device_id')) AS afid,
        COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.ad_placement'
        )), 'other') AS ad_pl,
        COALESCE(JSON_EXTRACT(data, '$.event_revenue_usd'), 0) AS rev
    FROM app_events
    WHERE event_name = ''ad_view''
      AND event_time >= '{{start_date}}'
      AND event_time <  '{{end_date}}'
      AND ('{{media_source}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.media_source')) = '{{media_source}}')
      AND ('{{country}}' = 'ALL' OR JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')) = '{{country}}')
)
SELECT
    CASE WHEN g.afid IS NOT NULL THEN '有引导页' ELSE '无引导页' END AS 分组,
    COUNT(DISTINCT r.afid) AS 用户数,
    ROUND(SUM(r.rev), 4) AS 总收益,
    ROUND(SUM(r.rev) / NULLIF(COUNT(DISTINCT r.afid), 0), 4) AS 人均收益,
    ROUND(SUM(CASE WHEN ad_pl = 'cold_start_app_open'        THEN rev ELSE 0 END), 4) AS 冷启动,
    ROUND(SUM(CASE WHEN ad_pl = 'hot_start_app_open'         THEN rev ELSE 0 END), 4) AS 热启动,
    ROUND(SUM(CASE WHEN ad_pl = 'play_interstitial'          THEN rev ELSE 0 END), 4) AS 播放插屏,
    ROUND(SUM(CASE WHEN ad_pl = 'home_grid'                  THEN rev ELSE 0 END), 4) AS 首页列表,
    ROUND(SUM(CASE WHEN ad_pl = 'for_you_interstitial'       THEN rev ELSE 0 END), 4) AS 推荐插屏,
    ROUND(SUM(CASE WHEN ad_pl = 'search_grid'                THEN rev ELSE 0 END), 4) AS 搜索页,
    ROUND(SUM(CASE WHEN ad_pl = 'guide_page_1'               THEN rev ELSE 0 END), 4) AS 引导页1,
    ROUND(SUM(CASE WHEN ad_pl = 'guide_page_2'               THEN rev ELSE 0 END), 4) AS 引导页2,
    ROUND(SUM(CASE WHEN ad_pl = 'first_language_screen'      THEN rev ELSE 0 END), 4) AS 语言选择,
    ROUND(SUM(CASE WHEN ad_pl = 'for_you_native_slide_page'  THEN rev ELSE 0 END), 4) AS 推荐滑动,
    ROUND(SUM(CASE WHEN ad_pl = 'personal_center'            THEN rev ELSE 0 END), 4) AS 个人中心,
    ROUND(SUM(CASE WHEN ad_pl = 'favorites'                  THEN rev ELSE 0 END), 4) AS 收藏页
FROM revenue_raw r
LEFT JOIN guide_users g ON r.afid = g.afid
GROUP BY 1
ORDER BY 分组;
