-- 脱敏说明: 内部表名/JSON 字段已泛化为通用名；事件名保留以便对照原业务含义
-- 原始 SQL 在本地保留（包含内部 schema 信息，不公开上传）

-- ============================================================
-- 每个用户最后一次选择的语言
-- 数据源: app_events (o_language_switch 事件)
-- event_value 包含: user_id, to_language, from_language
-- ============================================================
SELECT
    user_id,
    语言,
    最后切换时间
FROM (
    SELECT
        JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.user_id'
        )) AS user_id,
        JSON_UNQUOTE(JSON_EXTRACT(
            CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.to_language'
        )) AS 语言,
        event_time AS 最后切换时间,
        ROW_NUMBER() OVER (
            PARTITION BY JSON_UNQUOTE(JSON_EXTRACT(
                CAST(JSON_UNQUOTE(JSON_EXTRACT(data, '$.event_value')) AS JSON), '$.user_id'
            ))
            ORDER BY event_time DESC
        ) AS rn
    FROM app_events
    WHERE event_name = 'o_language_switch'
) t
WHERE rn = 1
  AND user_id IS NOT NULL
ORDER BY user_id;
