#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
【脱敏版】原始脚本: drama_daily_report.py
- DB 凭证已改为从环境变量读取，移除明文 IP/密码
- 应用名 BingeFlow → 海外短剧App
- 表名/视图已泛化
- 输出路径改为脚本同目录

原始版本含公司内部信息（数据库密码、内部表名、产品名），请勿外传。
""".format(name="drama_daily_report.py")

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
海外短剧App 短剧广告日报 — 自动查库 → 生成图表 → 发飞书群
=================================================================
口径：
  - 数据源: app_events（event_time / install_time 已转北京时间 UTC+8）
  - 安装数: lf_register 事件, 全渠道, DATE(install_time)
  - 收入:   af_ad_view 事件, 全渠道, DATE(event_time)
  - ARPU:   收入 ÷ 安装数（当天）

用法：
  1. python drama_daily_report.py --no-upload  # 只生成图表不发飞书
  2. python drama_daily_report.py --dry-run    # 只在终端打印数据
=================================================================
"""
import sys
import os
import json
import io
import argparse
from datetime import datetime, timedelta, date

import mysql.connector
from mysql.connector import Error as MySQLError

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import matplotlib.font_manager as fm

import requests

# ============================================================
# 配置区
# ============================================================

# 数据库凭证请通过环境变量注入（避免硬编码）
DB_CONFIG = {
    "host":     os.environ["DB_HOST"],
    "port":     int(os.environ.get("DB_PORT", "3306")),
    "user":     os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
    "database": os.environ.get("DB_NAME", "app_analytics"),
    "charset":  "utf8mb4",
}

FEISHU_WEBHOOK_URL = os.environ.get(
    "FEISHU_WEBHOOK_URL",
    ""  # 已禁用，不再自动发飞书
)

LOOKBACK_DAYS = 7
CHART_OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sample_chart.png")"daily_report.png")

# ============================================================
# 中文字体
# ============================================================
_FONT_CANDIDATES = ["Microsoft YaHei", "Noto Sans SC", "SimHei", "STXihei", "Arial Unicode MS"]
_CN_FONT = None
for _fn in _FONT_CANDIDATES:
    _hits = [f for f in fm.fontManager.ttflist if f.name == _fn]
    if _hits:
        _CN_FONT = _hits[0].fname
        break
if _CN_FONT:
    _font_prop = fm.FontProperties(fname=_CN_FONT)
    plt.rcParams["font.family"] = _font_prop.get_name()
    print(f"[OK] 使用中文字体: {_font_prop.get_name()}")
else:
    print("[WARN] 未找到中文字体，图表中文可能显示为方框")

# ============================================================
# 数据库查询
# ============================================================


def get_connection():
    return mysql.connector.connect(**DB_CONFIG)


def query_daily_report(start_date: str, end_date: str) -> list[dict]:
    """
    口径：
      安装数 = lf_register 事件, DATE(install_time) 北京时间, 全渠道
      收入   = af_ad_view 事件, DATE(event_time) 北京时间, 全渠道
    """
    sql = f"""
    SELECT
        COALESCE(i.dt, r.dt) AS stat_date,
        COALESCE(i.installs, 0) AS new_installs,
        COALESCE(r.revenue, 0) AS total_revenue_usd,
        CASE WHEN COALESCE(i.installs, 0) > 0
             THEN ROUND(COALESCE(r.revenue, 0) / i.installs, 4)
             ELSE 0
        END AS arpu
    FROM (
        SELECT DATE(install_time) AS dt,
               COUNT(DISTINCT user_id) AS installs
        FROM drama.app_events
        WHERE event_name = 'lf_register'
          AND install_time IS NOT NULL
          AND install_time >= '{start_date}'
          AND install_time <  '{end_date}'
        GROUP BY dt
    ) i
    LEFT JOIN (
        SELECT DATE(event_time) AS dt,
               ROUND(SUM(CAST(JSON_EXTRACT(data, '$.event_revenue_usd') AS DECIMAL(10,6))), 4) AS revenue
        FROM drama.app_events
        WHERE event_name = 'af_ad_view'
          AND event_time >= '{start_date}'
          AND event_time <  '{end_date}'
        GROUP BY dt
    ) r ON i.dt = r.dt

    UNION

    SELECT
        COALESCE(i.dt, r.dt) AS stat_date,
        COALESCE(i.installs, 0) AS new_installs,
        COALESCE(r.revenue, 0) AS total_revenue_usd,
        CASE WHEN COALESCE(i.installs, 0) > 0
             THEN ROUND(COALESCE(r.revenue, 0) / i.installs, 4)
             ELSE 0
        END AS arpu
    FROM (
        SELECT DATE(install_time) AS dt,
               COUNT(DISTINCT user_id) AS installs
        FROM drama.app_events
        WHERE event_name = 'lf_register'
          AND install_time IS NOT NULL
          AND install_time >= '{start_date}'
          AND install_time <  '{end_date}'
        GROUP BY dt
    ) i
    RIGHT JOIN (
        SELECT DATE(event_time) AS dt,
               ROUND(SUM(CAST(JSON_EXTRACT(data, '$.event_revenue_usd') AS DECIMAL(10,6))), 4) AS revenue
        FROM drama.app_events
        WHERE event_name = 'af_ad_view'
          AND event_time >= '{start_date}'
          AND event_time <  '{end_date}'
        GROUP BY dt
    ) r ON i.dt = r.dt
    ORDER BY stat_date ASC
    """
    with get_connection() as conn:
        with conn.cursor(dictionary=True, buffered=True) as cur:
            cur.execute(sql)
            return cur.fetchall()


def query_country_breakdown(start_date: str, end_date: str) -> list[dict]:
    """按国家分组收入（af_ad_view, event_time 北京时间）"""
    sql = f"""
    SELECT
        COALESCE(JSON_UNQUOTE(JSON_EXTRACT(data, '$.country_code')), 'Unknown') AS country,
        COUNT(*) AS ad_events,
        ROUND(SUM(CAST(JSON_EXTRACT(data, '$.event_revenue_usd') AS DECIMAL(10,6))), 4) AS total_revenue_usd
    FROM drama.app_events
    WHERE event_name = 'af_ad_view'
      AND event_time >= '{start_date}'
      AND event_time <  '{end_date}'
    GROUP BY country
    HAVING total_revenue_usd > 0
    ORDER BY total_revenue_usd DESC
    """
    with get_connection() as conn:
        with conn.cursor(dictionary=True, buffered=True) as cur:
            cur.execute(sql)
            return cur.fetchall()


def query_daily_dau(start_date: str, end_date: str) -> list[dict]:
    """每日 DAU 和基础指标（辅助参考，按 create_time）"""
    sql = f"""
    SELECT
        DATE(create_time) AS stat_date,
        COUNT(DISTINCT user_id) AS dau,
        COUNT(DISTINCT IF(event_name = 'lf_register', user_id, NULL)) AS new_register,
        SUM(IF(event_name = 'af_ad_view', 1, 0)) AS impressions
    FROM drama.app_events
    WHERE create_time >= '{start_date}'
      AND create_time <  '{end_date}'
    GROUP BY stat_date
    ORDER BY stat_date ASC
    """
    with get_connection() as conn:
        with conn.cursor(dictionary=True, buffered=True) as cur:
            cur.execute(sql)
            return cur.fetchall()


def query_yesterday() -> dict | None:
    """昨日数据（北京时间）"""
    today = date.today()
    yesterday = today - timedelta(days=1)
    yt = yesterday.strftime("%Y-%m-%d")
    td = today.strftime("%Y-%m-%d")

    with get_connection() as conn:
        with conn.cursor(dictionary=True, buffered=True) as cur:
            # 昨日安装数
            cur.execute("""
            SELECT COUNT(DISTINCT user_id) AS installs
            FROM drama.app_events
            WHERE event_name = 'lf_register'
              AND install_time >= %s AND install_time < %s
            """, (yt, td))
            install_row = cur.fetchone()
            installs = install_row["installs"] if install_row else 0

            # 昨日收入
            cur.execute("""
            SELECT ROUND(SUM(CAST(JSON_EXTRACT(data, '$.event_revenue_usd') AS DECIMAL(10,6))), 4) AS rev
            FROM drama.app_events
            WHERE event_name = 'af_ad_view'
              AND event_time >= %s AND event_time < %s
            """, (yt, td))
            rev_row = cur.fetchone()
            rev = float(rev_row["rev"]) if rev_row and rev_row["rev"] else 0.0

            # 昨日 DAU
            cur.execute("""
            SELECT COUNT(DISTINCT user_id) AS dau
            FROM drama.app_events
            WHERE create_time >= %s AND create_time < %s
            """, (yt, td))
            dau_row = cur.fetchone()

    arpu = round(rev / installs, 4) if installs > 0 else 0
    return {
        "dau": dau_row["dau"] if dau_row else 0,
        "installs": installs,
        "total_revenue_usd": rev,
        "arpu": arpu,
    }


# ============================================================
# 图表生成
# ============================================================

C_BG = "#F8FAFC"
C_CARD = "#FFFFFF"
C_PRIMARY = "#0284C7"
C_ACCENT = "#D97706"
C_GREEN = "#059669"
C_RED = "#DC2626"
C_PURPLE = "#7C3AED"
C_TEXT = "#0F172A"
C_TEXT_SEC = "#64748B"
C_GRID = "#E2E8F0"


def create_dashboard(report_data, country_data, dau_data, yesterday):
    """生成日报仪表盘"""
    fig = plt.figure(figsize=(14, 9), facecolor=C_BG)
    gs = fig.add_gridspec(2, 1, hspace=0.28,
                          height_ratios=[2.5, 1.2],
                          left=0.06, right=0.96, top=0.93, bottom=0.06)

    yesterday_str = (date.today() - timedelta(days=1)).strftime("%m月%d日")

    total_installs = sum(int(r["new_installs"]) for r in report_data)
    total_rev = sum(float(r["total_revenue_usd"]) for r in report_data)
    avg_arpu = round(total_rev / total_installs, 2) if total_installs > 0 else 0

    # ==================================================================
    # 上半部分：主图（趋势图 + 右上角 KPI + 右下角饼图）
    # ==================================================================
    top = fig.add_subplot(gs[0], facecolor=C_BG)
    top.axis("off")

    # 标题
    top.text(0.02, 0.97, f"海外短剧App 广告日报 · {yesterday_str}",
             ha="left", va="top", fontsize=16, fontweight="bold",
             color=C_TEXT)

    # 趋势图（主体）
    ax_chart = fig.add_axes([0.07, 0.41, 0.68, 0.48], facecolor=C_CARD)

    dates_list = [r["stat_date"] for r in report_data]
    revenues = [float(r["total_revenue_usd"]) for r in report_data]
    installs = [int(r["new_installs"]) for r in report_data]
    arpus = [float(r["arpu"]) for r in report_data]

    bars = ax_chart.bar(dates_list, revenues, color=C_PRIMARY, alpha=0.85,
                        width=0.6, zorder=3, label="收入 (USD)")
    for bar, val in zip(bars, revenues):
        if val > 0:
            ax_chart.text(bar.get_x() + bar.get_width() / 2,
                          bar.get_height() + max(revenues) * 0.02,
                          f"${val:.1f}", ha="center", va="bottom", fontsize=9,
                          color=C_PRIMARY, fontweight="bold")
    for bar, val in zip(bars, installs):
        if val > 0:
            ax_chart.text(bar.get_x() + bar.get_width() / 2,
                          bar.get_height() / 2,
                          f"{val}人", ha="center", va="center", fontsize=8,
                          color="#FFFFFF", fontweight="bold")

    ax_twin = ax_chart.twinx()
    ax_twin.plot(dates_list, arpus, color=C_ACCENT, marker="o", linewidth=2,
                 markersize=6, zorder=4, label="ARPU (USD)")
    for d, a in zip(dates_list, arpus):
        if a > 0:
            ax_twin.annotate(f"${a:.2f}", (d, a),
                             textcoords="offset points", xytext=(0, 10),
                             fontsize=7, color=C_ACCENT, ha="center")

    ax_chart.set_facecolor(C_CARD)
    ax_chart.set_title("收入 & ARPU", fontsize=13, fontweight="bold", color=C_TEXT, pad=8)
    ax_chart.xaxis.set_major_formatter(mdates.DateFormatter("%m/%d"))
    ax_chart.xaxis.set_major_locator(mdates.DayLocator())
    ax_chart.tick_params(colors=C_TEXT_SEC, labelsize=9)
    ax_twin.tick_params(colors=C_TEXT_SEC, labelsize=9)
    ax_chart.set_ylabel("收入 (USD)", color=C_PRIMARY, fontsize=10)
    ax_twin.set_ylabel("ARPU (USD)", color=C_ACCENT, fontsize=10)
    ax_chart.grid(axis="y", color=C_GRID, linewidth=0.5, alpha=0.5)
    for spine in ax_chart.spines.values():
        spine.set_color(C_GRID)
    ax_twin.spines["right"].set_color(C_GRID)
    lines1, labels1 = ax_chart.get_legend_handles_labels()
    lines2, labels2 = ax_twin.get_legend_handles_labels()
    ax_chart.legend(lines1 + lines2, labels1 + labels2, loc="upper left",
                    fontsize=9, facecolor=C_CARD, edgecolor=C_GRID, labelcolor=C_TEXT)

    # 右上角：KPI 卡片
    kpi_box = fig.add_axes([0.81, 0.58, 0.16, 0.28], facecolor=C_CARD)
    kpi_box.set_xticks([])
    kpi_box.set_yticks([])
    for spine in kpi_box.spines.values():
        spine.set_color(C_GRID)
        spine.set_linewidth(0.5)
    kpi_box.text(0.5, 0.92, "周期总览", ha="center", va="top",
                 fontsize=10, fontweight="bold", color=C_TEXT_SEC)
    kpi_box.text(0.5, 0.70, f"${total_rev:.2f}", ha="center", va="center",
                 fontsize=22, fontweight="bold", color=C_PRIMARY)
    kpi_box.text(0.5, 0.50, "总收入 (USD)", ha="center", va="center",
                 fontsize=9, color=C_TEXT_SEC)
    kpi_box.text(0.5, 0.30, f"{total_installs} 人  ·  ARPU ${avg_arpu:.2f}",
                 ha="center", va="center", fontsize=10, color=C_TEXT)
    kpi_box.text(0.5, 0.10, f"昨日 ${yesterday.get('total_revenue_usd', 0):.2f}  ·  {yesterday.get('installs', 0)}人",
                 ha="center", va="center", fontsize=9, color=C_TEXT_SEC)

    # 右侧中间：国家收入饼图
    ax_pie = fig.add_axes([0.79, 0.28, 0.17, 0.30], facecolor=C_CARD)
    countries = [r["country"] for r in country_data]
    country_revs = [float(r["total_revenue_usd"]) for r in country_data]
    colors_pie = ["#0EA5E9", "#F97316", "#8B5CF6", "#10B981", "#F43F5E", "#EAB308"]
    total = sum(country_revs)

    wedges, texts = ax_pie.pie(
        country_revs,
        labels=None,
        autopct=None,
        colors=colors_pie[:len(countries)],
        startangle=90,
        wedgeprops={"edgecolor": "white", "linewidth": 2},
        radius=0.65,
    )

    # 图例放饼图下方
    legend_labels = [f"{ct}  ${rv:.2f}  ({rv/total*100:.1f}%)" for ct, rv in zip(countries, country_revs)]
    ax_pie.legend(wedges, legend_labels, loc="lower center",
                  bbox_to_anchor=(0.5, -0.12), fontsize=9,
                  frameon=False, labelcolor=C_TEXT, ncol=1)

    ax_pie.set_title("国家收入占比", fontsize=11, fontweight="bold", color=C_TEXT, pad=6)

    # ==================================================================
    # 下半部分：明细表格
    # ==================================================================
    ax3 = fig.add_subplot(gs[1], facecolor=C_CARD)
    ax3.axis("off")
    n_rows = len(report_data)
    ax3.set_xlim(0, 1)
    ax3.set_ylim(0, n_rows + 1.5)

    cols = ["日期", "新安装", "收入(USD)", "ARPU", "DAU", "展示"]
    col_widths = [0.10, 0.10, 0.18, 0.10, 0.10, 0.12]
    col_x = [0.08]
    for w in col_widths[:-1]:
        col_x.append(col_x[-1] + w)

    for i, (col_name, cx) in enumerate(zip(cols, col_x)):
        ax3.text(cx + col_widths[i] / 2, n_rows + 0.8, col_name,
                 ha="center", va="center", fontsize=10, fontweight="bold",
                 color=C_TEXT_SEC)
    ax3.axhline(y=n_rows + 0.5, xmin=0.04, xmax=0.93, color=C_GRID, linewidth=1)

    dau_map = {}
    for r in dau_data:
        d = r["stat_date"]
        k = d.strftime("%Y-%m-%d") if not isinstance(d, str) else d
        dau_map[k] = (r["dau"], r["impressions"])

    for row_idx, row in enumerate(reversed(report_data)):
        y = n_rows - row_idx - 0.5
        d = row["stat_date"]
        date_str = d.strftime("%m/%d") if not isinstance(d, str) else datetime.strptime(str(d), "%Y-%m-%d").strftime("%m/%d")
        date_key = d.strftime("%Y-%m-%d") if not isinstance(d, str) else str(d)
        dau_v, imp_v = dau_map.get(date_key, (0, 0))

        vals = [
            date_str,
            str(row["new_installs"]),
            f"${float(row['total_revenue_usd']):.2f}",
            f"${float(row['arpu']):.2f}",
            str(dau_v),
            f"{imp_v:,}",
        ]
        for i, (val, cx) in enumerate(zip(vals, col_x)):
            color = C_PRIMARY if i == 2 else (C_ACCENT if i == 3 else C_TEXT)
            ax3.text(cx + col_widths[i] / 2, y, val,
                     ha="center", va="center", fontsize=9, color=color)

        bg = C_BG if row_idx % 2 == 0 else C_CARD
        rect = plt.Rectangle((0.04, y - 0.28), 0.88, 0.55,
                             facecolor=bg, zorder=-1, transform=ax3.transData)
        ax3.add_patch(rect)

    ax3.set_title("日报明细", fontsize=13, fontweight="bold", color=C_TEXT, pad=8)

    fig.text(0.5, 0.005,
             f"Generated {datetime.now().strftime('%Y-%m-%d %H:%M')}  ·  数据源: app_events (北京时间)，全渠道",
             ha="center", va="bottom", fontsize=7, color=C_TEXT_SEC)

    return fig


# ============================================================
# 飞书 Webhook 发送
# ============================================================


def send_webhook_card(webhook_url: str, yesterday: dict, report_data: list[dict],
                      country_data: list[dict]) -> dict:
    """通过 Webhook 发送交互式卡片到群聊"""
    yesterday_str = (date.today() - timedelta(days=1)).strftime("%Y年%m月%d日")

    curr_rev = yesterday.get("total_revenue_usd", 0)
    curr_installs = yesterday.get("installs", 0)
    curr_arpu = yesterday.get("arpu", 0)

    # 环比
    prev_rev = float(report_data[-2]["total_revenue_usd"]) if len(report_data) >= 2 else 0.0
    if prev_rev and prev_rev > 0:
        change_pct = (curr_rev - prev_rev) / prev_rev * 100
        trend_icon = "🟢" if change_pct > 0 else "🔴" if change_pct < 0 else "➖"
        trend_text = f"{trend_icon} 环比 {change_pct:+.1f}%"
    else:
        trend_text = ""

    # 逐日趋势
    trend_lines = "\n".join(
        f"  {r['stat_date'].strftime('%m/%d') if not isinstance(r['stat_date'], str) else r['stat_date'][-5:]}: "
        f"安装 **{r['new_installs']}**人  "
        f"收入 **${float(r['total_revenue_usd']):.2f}**  "
        f"ARPU **${float(r['arpu']):.2f}**"
        for r in reversed(report_data)
    )

    # 国家分布 Top 3
    country_lines = "\n".join(
        f"  • **{r['country']}**: ${float(r['total_revenue_usd']):.2f}"
        for r in country_data[:3]
    )

    card = {
        "config": {"wide_screen_mode": True},
        "header": {
            "title": {"tag": "plain_text", "content": "📊 海外短剧App 广告日报"},
            "template": "blue"
        },
        "elements": [
            {
                "tag": "markdown",
                "content": (
                    f"**{yesterday_str}**\n"
                    f"🆕 新增安装：**{curr_installs}** 人\n"
                    f"💰 广告收入：**${curr_rev:.2f}** {trend_text}\n"
                    f"📊 ARPU：**${curr_arpu:.2f}**\n"
                    f"👥 DAU（参考）：**{yesterday.get('dau', 0)}**"
                )
            },
            {"tag": "hr"},
            {
                "tag": "markdown",
                "content": f"**📈 逐日趋势**\n{trend_lines}"
            },
            {"tag": "hr"},
            {
                "tag": "markdown",
                "content": f"**🌏 国家收入 Top 3**\n{country_lines}"
            },
            {"tag": "hr"},
            {
                "tag": "note",
                "elements": [
                    {"tag": "plain_text",
                     "content": f"口径: app_events (北京时间), 全渠道 · {datetime.now().strftime('%Y-%m-%d %H:%M')}"}
                ]
            }
        ]
    }

    body = {"msg_type": "interactive", "card": card}
    resp = requests.post(webhook_url, json=body, timeout=15)
    data = resp.json()
    if data.get("code") != 0:
        raise RuntimeError(f"发送卡片失败: {data}")
    return data


def send_webhook_chart(webhook_url: str, image_bytes: bytes,
                       filename: str = "daily_report.png") -> dict:
    """通过 Webhook 发送图表文件到群聊"""
    resp = requests.post(
        webhook_url,
        files={"file": (filename, io.BytesIO(image_bytes), "image/png")},
        data={"msg_type": "file"},
        timeout=30
    )
    data = resp.json()
    if data.get("code") != 0 and data.get("StatusCode") != 0:
        raise RuntimeError(f"发送文件失败: {data}")
    return data


# ============================================================
# 主流程
# ============================================================


def main():
    parser = argparse.ArgumentParser(description="海外短剧App 广告日报")
    parser.add_argument("--no-upload", action="store_true", help="只生成图表，不发飞书")
    parser.add_argument("--days", type=int, default=LOOKBACK_DAYS, help=f"查询天数（默认 {LOOKBACK_DAYS}）")
    parser.add_argument("--dry-run", action="store_true", help="只在终端打印数据，不画图不发飞书")
    args = parser.parse_args()

    today = date.today()

    # 查询范围（北京时间）
    query_start = (today - timedelta(days=args.days)).strftime("%Y-%m-%d")
    query_end = today.strftime("%Y-%m-%d")

    # DAU: create_time
    dau_start = (today - timedelta(days=args.days)).strftime("%Y-%m-%d")
    dau_end = today.strftime("%Y-%m-%d")

    print(f"\n[1/3] 查询数据库 ({query_start} ~ {query_end}) ...")
    try:
        report_data = query_daily_report(query_start, query_end)
        country_data = query_country_breakdown(query_start, query_end)
        dau_data = query_daily_dau(dau_start, dau_end)
        yesterday_data = query_yesterday()
    except MySQLError as e:
        print(f"[ERROR] 数据库查询失败: {e}")
        sys.exit(1)

    if not report_data:
        print("[WARN] 没有查询到数据")
        return

    if not yesterday_data:
        yesterday_data = {"dau": 0, "installs": 0, "total_revenue_usd": 0, "arpu": 0}

    print(f"  日报天数: {len(report_data)} 天")
    print(f"  国家数量: {len(country_data)}")
    print(f"  DAU 数据: {len(dau_data)} 天")

    if args.dry_run:
        print("\n=== 日报 ===")
        print(f"{'日期':>10s}  {'安装':>6s}  {'收入':>10s}  {'ARPU':>8s}")
        total_inst = 0
        total_rev = 0.0
        for r in report_data:
            d = r["stat_date"].strftime("%Y-%m-%d") if not isinstance(r["stat_date"], str) else str(r["stat_date"])
            rev = float(r["total_revenue_usd"])
            inst = int(r["new_installs"])
            total_inst += inst
            total_rev += rev
            print(f"  {d}  {inst:>6d}  ${rev:>8.2f}  ${float(r['arpu']):>7.2f}")
        if total_inst > 0:
            print(f"  {'合计':10s}  {total_inst:>6d}  ${total_rev:>8.2f}  ${total_rev/total_inst:.2f}")

        print(f"\n=== 国家分布 ===")
        for r in country_data:
            print(f"  {str(r['country']):>6s}  ${float(r['total_revenue_usd']):>8.2f}  ({int(r['ad_events'])}事件)")

        print(f"\n=== 昨日 ===")
        print(f"  新安装: {yesterday_data['installs']} 人")
        print(f"  收入: ${yesterday_data['total_revenue_usd']:.2f}")
        print(f"  ARPU: ${yesterday_data['arpu']:.2f}")
        return

    # ===== 生成图表 =====
    print("\n[2/3] 生成图表 ...")
    fig = create_dashboard(report_data, country_data, dau_data, yesterday_data)

    fig.savefig(CHART_OUTPUT, dpi=150, facecolor=C_BG, edgecolor="none",
                bbox_inches="tight")
    print(f"  图表已保存: {CHART_OUTPUT}")

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=150, facecolor=C_BG, edgecolor="none",
                bbox_inches="tight")
    buf.seek(0)
    plt.close(fig)

    if args.no_upload:
        print("\n[DONE] 图表已保存（跳过了飞书发送）")
        return

    # ===== 发送到飞书 =====
    webhook_url = FEISHU_WEBHOOK_URL.strip()
    if not webhook_url or "your_webhook" in webhook_url:
        print("\n[SKIP] FEISHU_WEBHOOK_URL 未配置")
        print("  图表已保存到本地")
        return

    print("\n[3/3] 发送到飞书 ...")
    try:
        send_webhook_card(webhook_url, yesterday_data, report_data, country_data)
        print("  卡片发送成功！")
    except Exception as e:
        print(f"[ERROR] 发送卡片失败: {e}")

    print("\n" + "=" * 50)
    print("  [OK] 日报已发送到飞书群聊！")
    print("=" * 50)


if __name__ == "__main__":
    main()
