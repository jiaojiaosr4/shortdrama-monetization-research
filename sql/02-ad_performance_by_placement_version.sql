-- 脱敏说明: 内部表名/JSON 字段已泛化为通用名；事件名保留以便对照原业务含义
-- 原始 SQL 在本地保留（包含内部 schema 信息，不公开上传）

-- ============================================================
-- Redash: 按日期 × 版本 × 广告位透视 — 展示数/收益/eCPM 合并在一个单元格
-- 数据源: app_events ('ad_view' 事件)
-- 变量: {{start_date}} {{end_date}} {{app_version}}
-- ============================================================
SELECT
    DATE(event_time) AS 日期,
    COALESCE(NULLIF(ver, ''), 'Unknown') AS 版本,

    -- ============ cold_start_app_open ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'cold_start_app_open' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'cold_start_app_open' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'cold_start_app_open' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'cold_start_app_open' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '冷启动(展示数/收益/eCPM)',

    -- ============ hot_start_app_open ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'hot_start_app_open' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'hot_start_app_open' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'hot_start_app_open' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'hot_start_app_open' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '热启动(展示数/收益/eCPM)',

    -- ============ play_interstitial ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'play_interstitial' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'play_interstitial' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'play_interstitial' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'play_interstitial' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '播放插屏(展示数/收益/eCPM)',

    -- ============ home_grid ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'home_grid' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'home_grid' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'home_grid' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'home_grid' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '首页列表(展示数/收益/eCPM)',

    -- ============ for_you_interstitial ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'for_you_interstitial' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'for_you_interstitial' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'for_you_interstitial' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'for_you_interstitial' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '推荐插屏(展示数/收益/eCPM)',

    -- ============ search_grid ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'search_grid' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'search_grid' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'search_grid' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'search_grid' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '搜索页(展示数/收益/eCPM)',

    -- ============ guide_page_1 ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'guide_page_1' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'guide_page_1' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'guide_page_1' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'guide_page_1' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '引导页1(展示数/收益/eCPM)',

    -- ============ guide_page_2 ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'guide_page_2' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'guide_page_2' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'guide_page_2' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'guide_page_2' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '引导页2(展示数/收益/eCPM)',

    -- ============ first_language_screen ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'first_language_screen' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'first_language_screen' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'first_language_screen' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'first_language_screen' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '语言选择(展示数/收益/eCPM)',

    -- ============ for_you_native_slide_page ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'for_you_native_slide_page' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'for_you_native_slide_page' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'for_you_native_slide_page' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'for_you_native_slide_page' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '推荐滑动(展示数/收益/eCPM)',

    -- ============ personal_center ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'personal_center' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'personal_center' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'personal_center' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'personal_center' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '个人中心(展示数/收益/eCPM)',

    -- ============ favorites ============
    CONCAT(
        SUM(CASE WHEN ad_pl = 'favorites' THEN 1 ELSE 0 END), ' / ',
        ROUND(SUM(CASE WHEN ad_pl = 'favorites' THEN rev ELSE 0 END), 4), ' / ',
        COALESCE(ROUND(SUM(CASE WHEN ad_pl = 'favorites' THEN rev ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ad_pl = 'favorites' THEN 1 ELSE 0 END), 0) * 1000, 4), 0)
    ) AS '收藏页(展示数/收益/eCPM)',

    -- ============ 汇总 ============
    CONCAT(
        COUNT(*), ' / ',
        ROUND(SUM(rev), 4), ' / ',
        COALESCE(ROUND(SUM(rev) / NULLIF(COUNT(*), 0) * 1000, 4), 0)
    ) AS '总计(展示数/收益/eCPM)'

FROM (
    SELECT
        event_time,
        version AS ver,
        COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.ad_placement'
        )), 'other') AS ad_pl,
        COALESCE(JSON_EXTRACT(data, '$.event_revenue_usd'), 0) AS rev
    FROM app_events
    WHERE event_name = ''ad_view''
      AND event_time >= '{{start_date}}'
      AND event_time <  '{{end_date}}'
      AND ('{{app_version}}' = 'ALL' OR version = '{{app_version}}')
) t
GROUP BY DATE(event_time), ver
ORDER BY 日期 ASC, 版本 ASC;
