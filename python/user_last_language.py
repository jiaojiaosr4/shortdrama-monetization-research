#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
【脱敏版】原始脚本: user_last_language.py
- DB 凭证已改为从环境变量读取，移除明文 IP/密码
- 应用名 BingeFlow → 海外短剧App
- 表名/视图已泛化
- 输出路径改为脚本同目录

原始版本含公司内部信息（数据库密码、内部表名、产品名），请勿外传。
""".format(name="user_last_language.py")

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
导出每个用户最后一次选择的语言（明细，按日期排序）。
数据源: app_events.o_language_switch
输出: 用户语言_明细.csv
"""

import os
import sys
import csv
import pymysql

# 数据库凭证请通过环境变量注入（避免硬编码）
DB_CONFIG = {
    "host":     os.environ["DB_HOST"],
    "port":     int(os.environ.get("DB_PORT", "3306")),
    "user":     os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
    "database": os.environ.get("DB_NAME", "app_analytics"),
    "charset":  "utf8mb4",
}

USER_LAST_LANGUAGE_SQL = """
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
ORDER BY 最后切换时间 ASC
"""

OUT_DIR = os.path.dirname(os.path.abspath(__file__))


def main():
    conn = None
    try:
        conn = pymysql.connect(**DB_CONFIG)
        cursor = conn.cursor()
        cursor.execute(USER_LAST_LANGUAGE_SQL)

        path = os.path.join(OUT_DIR, "用户语言_明细.csv")
        with open(path, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f)
            w.writerow(["user_id", "语言", "最后切换时间"])
            count = 0
            for row in cursor:
                w.writerow(row)
                count += 1

        print(f"导出完成: {path}，共 {count} 条记录")

    except pymysql.Error as e:
        print(f"数据库错误: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if conn:
            conn.close()


if __name__ == "__main__":
    main()
