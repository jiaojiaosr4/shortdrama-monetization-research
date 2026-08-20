#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
【脱敏版】原始脚本: ad_funnel_report.py
- DB 凭证已改为从环境变量读取，移除明文 IP/密码
- 应用名 BingeFlow → 海外短剧App
- 表名/视图已泛化
- 输出路径改为脚本同目录

原始版本含公司内部信息（数据库密码、内部表名、产品名），请勿外传。
""".format(name="ad_funnel_report.py")

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
海外短剧App 广告加载失败分析 — 完整版
口径: 广告加载(ad_load) → 展示成功(ad_show) → 点击(ad_click)
注意: ad_show 事件仅上报成功，失败原因未入库，只能分析转化流失量
"""
import mysql.connector
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
from datetime import datetime
import numpy as np

# 数据库凭证请通过环境变量注入（避免硬编码）
DB_CONFIG = {
    "host":     os.environ["DB_HOST"],
    "port":     int(os.environ.get("DB_PORT", "3306")),
    "user":     os.environ["DB_USER"],
    "password": os.environ["DB_PASSWORD"],
    "database": os.environ.get("DB_NAME", "app_analytics"),
    "charset":  "utf8mb4",
}

# 中文字体
_FONT_CANDIDATES = ["Microsoft YaHei", "Noto Sans SC", "SimHei", "Arial Unicode MS"]
_CN_FONT = None
for _fn in _FONT_CANDIDATES:
    _hits = [f for f in fm.fontManager.ttflist if f.name == _fn]
    if _hits:
        _CN_FONT = _hits[0].fname
        break
if _CN_FONT:
    _font_prop = fm.FontProperties(fname=_CN_FONT)
    plt.rcParams["font.family"] = _font_prop.get_name()
    print(f"使用字体: {_font_prop.get_name()}")
else:
    print("未找到中文字体")

CHART_OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sample_chart.png")"output.png")

# ================================
# 日期范围 — 改这里切换时间窗口
# ================================
START_DATE = "2026-07-10"
END_DATE   = "2026-07-18"  # 左闭右开，到 7-17

# ================================
# 查库
# ================================
conn = mysql.connector.connect(**DB_CONFIG)
cur = conn.cursor(dictionary=True)

# 1) 基本漏斗: ad_load → ad_show → ad_click
cur.execute("""
SELECT event_name, COUNT(*) AS cnt
FROM ad_events
WHERE event_name IN ('ad_load','ad_show','ad_click')
  AND event_time >= %s AND event_time < %s
GROUP BY event_name
ORDER BY FIELD(event_name, 'ad_load','ad_show','ad_click')
""", (START_DATE, END_DATE))
funnel = {r["event_name"]: int(r["cnt"]) for r in cur.fetchall()}

# 2) 按渠道
cur.execute("""
SELECT
    COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(data, '$.af_channel')),''), 'Organic(自然量)') AS ch,
    SUM(event_name='ad_load') AS loads,
    SUM(event_name='ad_show') AS shows,
    SUM(event_name='ad_click') AS clicks
FROM ad_events
WHERE event_name IN ('ad_load','ad_show','ad_click')
  AND event_time >= %s AND event_time < %s
GROUP BY ch ORDER BY loads DESC
""", (START_DATE, END_DATE))
channels = cur.fetchall()

# 3) 每日趋势
cur.execute("""
SELECT
    DATE(event_time) AS dt,
    SUM(event_name='ad_load') AS loads,
    SUM(event_name='ad_show') AS shows,
    SUM(event_name='ad_click') AS clicks
FROM ad_events
WHERE event_name IN ('ad_load','ad_show','ad_click')
  AND event_time >= %s AND event_time < %s
GROUP BY dt ORDER BY dt ASC
""", (START_DATE, END_DATE))
daily = cur.fetchall()

cur.close()
conn.close()

# ================================
# 计算指标
# ================================
L = funnel.get("ad_load", 0)
S = funnel.get("ad_show", 0)
C = funnel.get("ad_click", 0)
loss_L2S = L - S
loss_S2C = S - C

# 渠道
ch_names = [c["ch"] for c in channels]
ch_loads = [int(c["loads"]) for c in channels]
ch_shows = [int(c["shows"]) for c in channels]
ch_clicks = [int(c["clicks"]) for c in channels]
ch_loss = [l - s for l, s in zip(ch_loads, ch_shows)]
ch_rates = [round(s/l*100, 1) if l > 0 else 0 for l, s in zip(ch_loads, ch_shows)]

# 每日
dts = [str(d["dt"])[-5:] for d in daily]
d_loads = [int(d["loads"]) for d in daily]
d_shows = [int(d["shows"]) for d in daily]
d_clicks = [int(d["clicks"]) for d in daily]
d_rates_l2s = [round(s/l*100, 1) if l > 0 else 0 for l, s in zip(d_loads, d_shows)]
d_rates_s2c = [round(c/s*100, 1) if s > 0 else 0 for s, c in zip(d_shows, d_clicks)]

# ================================
# 配色
# ================================
BG = "#0F172A"
CARD = "#1E293B"
CARD2 = "#263348"
PRIMARY = "#38BDF8"
GREEN = "#34D399"
ORANGE = "#FB923C"
RED = "#F87171"
YELLOW = "#FBBF24"
PURPLE = "#A78BFA"
TEXT = "#F1F5F9"
TEXT_SEC = "#94A3B8"
GRID = "#334155"
WHITE = "#FFFFFF"

# ================================
# 画布
# ================================
fig = plt.figure(figsize=(18, 11), facecolor=BG)

# ---- 标题 ----
fig.text(0.5, 0.975, "海外短剧App 广告加载失败分析",
         ha="center", va="top", fontsize=22, fontweight="bold", color=TEXT)
fig.text(0.5, 0.95, f"{START_DATE} ~ {END_DATE} | ad_events | {datetime.now().strftime('%Y-%m-%d %H:%M')}",
         ha="center", va="top", fontsize=9, color=TEXT_SEC)

# ================================================================
# [1] 顶部 KPI 行 — 4 个指标卡片
# ================================================================
kpi_data = [
    ("广告加载", f"{L:,}", "ad_load", PRIMARY),
    ("展示成功", f"{S:,}", "ad_show", GREEN),
    ("加载->展示率", f"{round(S/L*100,1)}%", f"流失 {loss_L2S:,} 次", RED),
    ("展示->点击率", f"{round(C/S*100,1)}%" if S > 0 else "N/A", f"点击 {C:,} 次", ORANGE),
]

for i, (label, value, sub, color) in enumerate(kpi_data):
    x0 = 0.05 + i * 0.235
    ax_card = fig.add_axes([x0, 0.882, 0.205, 0.06], facecolor=CARD)
    ax_card.set_xticks([])
    ax_card.set_yticks([])
    for spine in ax_card.spines.values():
        spine.set_color(GRID)
        spine.set_linewidth(0.5)
    ax_card.text(0.08, 0.72, label, ha="left", va="center", fontsize=9, color=TEXT_SEC)
    ax_card.text(0.08, 0.30, value, ha="left", va="center", fontsize=22, fontweight="bold", color=color)
    ax_card.text(0.90, 0.30, sub, ha="right", va="center", fontsize=8, color=TEXT_SEC)

# ================================================================
# [2] 左: 漏斗图 (横向柱状 + 流失标注)
# ================================================================
ax1 = fig.add_axes([0.04, 0.50, 0.30, 0.36], facecolor=CARD)

stage_names = ["1. 广告加载\n(ad_load)", "2. 展示成功\n(ad_show)", "3. 广告点击\n(ad_click)"]
stage_vals = [L, S, C]
stage_colors = [PRIMARY, GREEN, ORANGE]
stage_labels = [f"{L:,} 次", f"{S:,} 次   ({round(S/L*100,1)}%)", f"{C:,} 次   ({round(C/S*100,1) if S else 0}%)"]

# 横向柱状
bars = ax1.barh(stage_names, stage_vals, color=stage_colors, height=0.55,
                edgecolor=CARD, linewidth=2, zorder=3)
for bar, v, label in zip(bars, stage_vals, stage_labels):
    ax1.text(bar.get_width() + max(stage_vals)*0.015, bar.get_y() + bar.get_height()/2,
             label, va="center", fontsize=11, fontweight="bold", color=TEXT)

# 流失箭头标注: 在加载和展示之间画红色区域
arrow_y1 = 1.0  # ad_load bar center
arrow_y2 = 0.0  # ad_show bar center
arrow_y_mid = 0.5

ax1.annotate("",
    xy=(S, arrow_y2), xytext=(L, arrow_y1),
    arrowprops=dict(arrowstyle="->", color=RED, lw=2, connectionstyle="arc3,rad=-0.15"))
ax1.text(L*0.65, arrow_y_mid + 0.15,
         f"流失 {loss_L2S:,} 次 ({round(loss_L2S/L*100,1)}%)\n原因: 加载成功但未展示\n(客户端无失败上报)",
         ha="center", va="center", fontsize=9.5, color=RED,
         bbox=dict(boxstyle="round,pad=0.4", facecolor=CARD2, edgecolor=RED, alpha=0.9, linewidth=1))

ax1.set_xlim(0, max(stage_vals)*1.45)
ax1.set_facecolor(CARD)
ax1.set_title("广告漏斗: 加载 -> 展示 -> 点击", fontsize=14, fontweight="bold", color=TEXT, pad=12)
ax1.tick_params(colors=TEXT_SEC, labelsize=10)
for spine in ax1.spines.values():
    spine.set_visible(False)
ax1.xaxis.set_visible(False)

# ================================================================
# [3] 中: 按渠道转化率 + 流失构成
# ================================================================
ax2 = fig.add_axes([0.37, 0.50, 0.30, 0.36], facecolor=CARD)

x = np.arange(len(ch_names))
w = 0.30

# 堆叠柱状: 展示成功 (绿) + 流失量 (红) = 加载总量
bars_show = ax2.bar(x, ch_shows, w, color=GREEN, label="展示成功", zorder=3)
bars_loss = ax2.bar(x, ch_loss, w, bottom=ch_shows, color=RED, alpha=0.7, label="加载后流失", zorder=3)

# 标注
for i, (l, s, loss, r) in enumerate(zip(ch_loads, ch_shows, ch_loss, ch_rates)):
    # 总数
    ax2.text(i, l + max(ch_loads)*0.015, f"加载 {l:,}", ha="center", fontsize=8.5, color=TEXT_SEC)
    # 展示率
    ax2.text(i, s/2, f"展示率\n{r}%", ha="center", va="center", fontsize=9, fontweight="bold", color=WHITE)
    # 流失
    if loss > 0:
        ax2.text(i, s + loss*0.45, f"流失 {loss:,}", ha="center", va="center", fontsize=8.5, color=WHITE, alpha=0.9)

ax2.set_xticks(x)
ax2.set_xticklabels(ch_names, fontsize=10, color=TEXT)
ax2.set_facecolor(CARD)
ax2.set_title("按渠道: 展示成功 vs 加载流失 | 堆叠图", fontsize=14, fontweight="bold", color=TEXT, pad=12)
ax2.legend(fontsize=9, loc="upper right", facecolor=CARD2, edgecolor=GRID, labelcolor=TEXT)
ax2.tick_params(colors=TEXT_SEC, labelsize=9)
ax2.grid(axis="y", color=GRID, linewidth=0.5, alpha=0.3)
for spine in ax2.spines.values():
    spine.set_color(GRID)

# ================================================================
# [4] 右: 每日趋势
# ================================================================
ax3 = fig.add_axes([0.70, 0.50, 0.27, 0.36], facecolor=CARD)

ax3_twin = ax3.twinx()

# 堆叠面积: 展示成功 + 流失
ax3.fill_between(range(len(dts)), 0, d_shows, color=GREEN, alpha=0.35, label="展示成功")
ax3.fill_between(range(len(dts)), d_shows, d_loads, color=RED, alpha=0.25, label="加载后流失")
line_load, = ax3.plot(range(len(dts)), d_loads, "o-", color=PRIMARY, linewidth=2, markersize=5, label="加载次数")
line_show, = ax3.plot(range(len(dts)), d_shows, "s-", color=GREEN, linewidth=2, markersize=5, label="展示次数")
line_rate, = ax3_twin.plot(range(len(dts)), d_rates_l2s, "D--", color=RED,
                           linewidth=2.5, markersize=7, label="展示率 %")

# 每日标注展示率
for i, r in enumerate(d_rates_l2s):
    offset = (d_loads[i] - d_shows[i])*0.5 + d_shows[i]
    ax3.text(i, offset, f"{r}%", ha="center", va="center", fontsize=7.5, fontweight="bold", color=RED)

ax3.set_xticks(range(len(dts)))
ax3.set_xticklabels(dts, fontsize=8.5, color=TEXT_SEC)
ax3.set_facecolor(CARD)
ax3.set_title("每日广告加载/展示/展示率趋势", fontsize=14, fontweight="bold", color=TEXT, pad=12)
ax3.tick_params(colors=TEXT_SEC, labelsize=9)
ax3_twin.tick_params(colors=TEXT_SEC, labelsize=9)
ax3.grid(axis="y", color=GRID, linewidth=0.5, alpha=0.3)

lines = [line_load, line_show, line_rate]
labels = [l.get_label() for l in lines]
ax3.legend(lines, labels, loc="upper left", fontsize=8.5, facecolor=CARD2, edgecolor=GRID, labelcolor=TEXT)
for spine in ax3.spines.values():
    spine.set_color(GRID)

# ================================================================
# [5] 底部左: 渠道转化明细表
# ================================================================
ax4 = fig.add_axes([0.04, 0.08, 0.62, 0.38], facecolor=CARD)
ax4.axis("off")

# 表头
cols_hdr = ["渠道", "加载次数", "展示成功", "加载->展示率", "流失次数", "流失占比", "展示->点击", "点击率"]
col_xs = [0.02, 0.16, 0.29, 0.41, 0.515, 0.60, 0.70, 0.83]
for cx, hdr in zip(col_xs, cols_hdr):
    ax4.text(cx, 0.92, hdr, ha="left", va="center", fontsize=8.5, fontweight="bold", color=TEXT_SEC)

ax4.axhline(y=0.89, xmin=0.0, xmax=1.0, color=GRID, linewidth=1)

for row_i, c in enumerate(channels):
    l, s, clk = int(c["loads"]), int(c["shows"]), int(c["clicks"])
    loss = l - s
    rate_l2s = f"{round(s/l*100,1)}%" if l > 0 else "-"
    rate_s2c = f"{round(clk/s*100,1)}%" if s > 0 else "-"
    loss_pct = f"{round(loss/sum(ch_loss)*100,1)}%" if sum(ch_loss) > 0 else "-"
    y = 0.84 - row_i * 0.155

    # 斑马条纹
    if row_i % 2 == 0:
        rect = plt.Rectangle((0.01, y - 0.06), 0.98, 0.12, facecolor=CARD2, zorder=-1, transform=ax4.transAxes)
        ax4.add_patch(rect)

    vals = [c["ch"], f"{l:,}", f"{s:,}", rate_l2s, f"{loss:,}", loss_pct, f"{clk:,}", rate_s2c]
    vcolors = [TEXT, TEXT, GREEN, RED if l > 0 and s/l < 0.5 else GREEN, RED, RED,
               ORANGE, TEXT_SEC]
    for cx, val, vc in zip(col_xs, vals, vcolors):
        ax4.text(cx, y, val, ha="left", va="center", fontsize=8.5, color=vc, fontweight="bold" if vc != TEXT_SEC else "normal")

# 合计行
ax4.axhline(y=0.07, xmin=0.0, xmax=1.0, color=GRID, linewidth=1)
total_loss = sum(ch_loss)
ax4.text(col_xs[0], 0.03, "合计", ha="left", va="center", fontsize=9, fontweight="bold", color=TEXT)
ax4.text(col_xs[1], 0.03, f"{L:,}", ha="left", va="center", fontsize=9, fontweight="bold", color=TEXT)
ax4.text(col_xs[2], 0.03, f"{S:,}", ha="left", va="center", fontsize=9, fontweight="bold", color=GREEN)
ax4.text(col_xs[3], 0.03, f"{round(S/L*100,1)}%", ha="left", va="center", fontsize=9, fontweight="bold", color=RED)
ax4.text(col_xs[4], 0.03, f"{total_loss:,}", ha="left", va="center", fontsize=9, fontweight="bold", color=RED)
ax4.text(col_xs[5], 0.03, "100%", ha="left", va="center", fontsize=9, fontweight="bold", color=TEXT_SEC)
ax4.text(col_xs[6], 0.03, f"{C:,}", ha="left", va="center", fontsize=9, fontweight="bold", color=ORANGE)
ax4.text(col_xs[7], 0.03, f"{round(C/S*100,1)}%", ha="left", va="center", fontsize=9, fontweight="bold", color=TEXT_SEC)

ax4.set_title("渠道转化明细", fontsize=14, fontweight="bold", color=TEXT, pad=10)

# ================================================================
# [6] 底部右: 结论与建议
# ================================================================
ax5 = fig.add_axes([0.69, 0.08, 0.28, 0.38], facecolor=CARD)
ax5.set_xticks([])
ax5.set_yticks([])
for spine in ax5.spines.values():
    spine.set_color(GRID)
    spine.set_linewidth(0.5)

# 找出问题最大的渠道
worst_ch = min(channels, key=lambda c: float(c["shows"])/float(c["loads"]) if float(c["loads"]) > 0 else 999)
worst_name = worst_ch["ch"]
worst_rate = round(float(worst_ch["shows"])/float(worst_ch["loads"])*100, 1) if float(worst_ch["loads"]) > 0 else 0

ax5.text(0.5, 0.93, "结论与建议", ha="center", va="center", fontsize=14, fontweight="bold", color=TEXT)

conclusions = [
    ("问题1", f"加载->展示率仅 {round(S/L*100,1)}%，近一半({loss_L2S:,}次)广告加载后未展示，\n造成严重变现机会浪费", RED),
    ("问题2", f"最大问题渠道: {worst_name}，转化率仅 {worst_rate}%，\n该渠道流失 {ch_loss[0]:,} 次，占全部流失的 {round(ch_loss[0]/sum(ch_loss)*100,1)}%", RED),
    ("局限", "数据库只记录展示成功(ad_show)，未上报失败原因，\n需从客户端SDK日志或广告平台后台获取具体错误码", YELLOW),
    ("建议1", "排查自然量用户的网络环境与设备兼容性，\n确认广告SDK在弱网/低端设备上的初始化逻辑", PRIMARY),
    ("建议2", f"对比 TikTok({max(ch_rates)}%) 和有机量(24%) 的加载时机差异，\n优化广告预加载策略，减少无效加载", GREEN),
]

for i, (title, content, color) in enumerate(conclusions):
    y = 0.82 - i * 0.165
    ax5.text(0.06, y, f"[{title}]", ha="left", va="top", fontsize=9.5, fontweight="bold", color=color)
    ax5.text(0.11, y, content, ha="left", va="top", fontsize=8, color=TEXT_SEC, linespacing=1.3)

ax5.set_title("分析结论", fontsize=14, fontweight="bold", color=TEXT, pad=10)

# ---- 保存 ----
fig.savefig(CHART_OUTPUT, dpi=150, facecolor=BG, edgecolor="none", bbox_inches="tight")
print(f"\n预览图已保存: {CHART_OUTPUT}")
