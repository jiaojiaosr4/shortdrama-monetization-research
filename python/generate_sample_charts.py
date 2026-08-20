#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
可视化样图生成器（脱敏版）—— 用模拟数据展示原脚本的输出风格

原脚本使用真实业务数据生成深色主题的运营仪表盘（漏斗图、堆叠柱状、
折线趋势、KPI 卡片、维度明细表）。本脚本用纯模拟数据重现相同风格，
可在不暴露真实业务数据的前提下展示可视化能力。

输出:
  docs/assets/sample-ad-funnel.png        —— 广告加载漏斗
  docs/assets/sample-daily-dashboard.png  —— 7日运营日报
"""
import os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
from datetime import datetime, timedelta

# 中文字体
for _fn in ["Microsoft YaHei", "Noto Sans SC", "SimHei", "Arial Unicode MS"]:
    _hits = [f for f in fm.fontManager.ttflist if f.name == _fn]
    if _hits:
        _fp = fm.FontProperties(fname=_hits[0].fname)
        plt.rcParams["font.family"] = _fp.get_name()
        break
plt.rcParams["axes.unicode_minus"] = False

# 深色配色（与原版一致）
BG = "#0F172A"; CARD = "#1E293B"; CARD2 = "#263348"
PRIMARY = "#38BDF8"; GREEN = "#34D399"; ORANGE = "#FB923C"
RED = "#F87171"; YELLOW = "#FBBF24"; PURPLE = "#A78BFA"
TEXT = "#F1F5F9"; TEXT_SEC = "#94A3B8"; GRID = "#334155"; WHITE = "#FFFFFF"

ASSETS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "assets")
os.makedirs(ASSETS_DIR, exist_ok=True)


# =============================================================
# 样图 1：广告加载漏斗（funnel + 堆叠 + 折线）
# =============================================================
def make_funnel():
    np.random.seed(42)
    L, S, C = 11863, 6021, 1641     # 模拟：加载/展示/点击
    loss_L2S = L - S

    channels = [
        ("TikTok",          9856, 5266, 1531, 0.534),
        ("Organic(自然量)",  1072,  257,   14, 0.240),
        ("Pangle",            915,  484,   92, 0.529),
        ("PineDrama",          13,   11,    1, 0.846),
        ("Global App Bundle",   7,    3,    1, 0.429),
    ]
    ch_names  = [c[0] for c in channels]
    ch_loads  = [c[1] for c in channels]
    ch_shows  = [c[2] for c in channels]
    ch_clicks = [c[3] for c in channels]
    ch_loss   = [l - s for l, s in zip(ch_loads, ch_shows)]
    ch_rates  = [round(s/l*100, 1) for l, s in zip(ch_loads, ch_shows)]

    days = 11
    base = np.linspace(800, 1200, days)
    d_loads = (base + np.random.randint(-200, 300, days)).clip(min=400).astype(int)
    d_shows = (d_loads * np.random.uniform(0.42, 0.62, days)).astype(int)
    d_clicks = (d_shows * np.random.uniform(0.25, 0.33, days)).astype(int)
    d_rates = [round(s/l*100, 1) for l, s in zip(d_loads, d_shows)]
    dts = [(datetime(2026, 7, 7) + timedelta(days=i)).strftime("%m-%d") for i in range(days)]

    fig = plt.figure(figsize=(18, 11), facecolor=BG)
    fig.text(0.5, 0.975, "海外短剧App 广告加载失败分析（样图）",
             ha="center", va="top", fontsize=22, fontweight="bold", color=TEXT)
    fig.text(0.5, 0.948, "模拟数据展示 | 仅作可视化能力示例，不含真实业务信息",
             ha="center", va="top", fontsize=10, color=TEXT_SEC)

    # KPI 卡片
    kpis = [
        ("广告加载", f"{L:,}", "ad_load", PRIMARY),
        ("展示成功", f"{S:,}", "ad_show", GREEN),
        ("加载->展示率", f"{round(S/L*100,1)}%", f"流失 {loss_L2S:,} 次", RED),
        ("展示->点击率", f"{round(C/S*100,1)}%", f"点击 {C:,} 次", ORANGE),
    ]
    for i, (lbl, val, sub, color) in enumerate(kpis):
        x0 = 0.05 + i * 0.235
        ax = fig.add_axes([x0, 0.882, 0.205, 0.06], facecolor=CARD)
        ax.set_xticks([]); ax.set_yticks([])
        for sp in ax.spines.values(): sp.set_color(GRID); sp.set_linewidth(0.5)
        ax.text(0.08, 0.72, lbl, ha="left", va="center", fontsize=9, color=TEXT_SEC)
        ax.text(0.08, 0.30, val, ha="left", va="center", fontsize=22, fontweight="bold", color=color)
        ax.text(0.90, 0.30, sub, ha="right", va="center", fontsize=8, color=TEXT_SEC)

    # 左：漏斗
    ax1 = fig.add_axes([0.04, 0.50, 0.30, 0.36], facecolor=CARD)
    stage_names = ["1. 广告加载\n(ad_load)", "2. 展示成功\n(ad_show)", "3. 广告点击\n(ad_click)"]
    stage_vals  = [L, S, C]
    bars = ax1.barh(stage_names, stage_vals, color=[PRIMARY, GREEN, ORANGE],
                    height=0.55, edgecolor=CARD, linewidth=2, zorder=3)
    for bar, v in zip(bars, stage_vals):
        ax1.text(bar.get_width() + max(stage_vals)*0.015,
                 bar.get_y() + bar.get_height()/2,
                 f"{v:,}", va="center", fontsize=11, fontweight="bold", color=TEXT)
    ax1.annotate("", xy=(S, 0), xytext=(L, 1),
                 arrowprops=dict(arrowstyle="->", color=RED, lw=2, connectionstyle="arc3,rad=-0.15"))
    ax1.text(L*0.65, 0.55, f"流失 {loss_L2S:,} 次 ({round(loss_L2S/L*100,1)}%)\n加载成功但未展示",
             ha="center", va="center", fontsize=9.5, color=RED,
             bbox=dict(boxstyle="round,pad=0.4", facecolor=CARD2, edgecolor=RED, alpha=0.9))
    ax1.set_xlim(0, max(stage_vals)*1.45)
    ax1.set_facecolor(CARD)
    ax1.set_title("广告漏斗: 加载 → 展示 → 点击", fontsize=14, fontweight="bold", color=TEXT, pad=12)
    ax1.tick_params(colors=TEXT_SEC, labelsize=10)
    for sp in ax1.spines.values(): sp.set_visible(False)
    ax1.xaxis.set_visible(False)

    # 中：渠道堆叠
    ax2 = fig.add_axes([0.37, 0.50, 0.30, 0.36], facecolor=CARD)
    x = np.arange(len(ch_names)); w = 0.5
    ax2.bar(x, ch_shows, w, color=GREEN, label="展示成功", zorder=3)
    ax2.bar(x, ch_loss, w, bottom=ch_shows, color=RED, alpha=0.7, label="加载后流失", zorder=3)
    for i, (l, s, r) in enumerate(zip(ch_loads, ch_shows, ch_rates)):
        ax2.text(i, l + max(ch_loads)*0.02, f"加载 {l:,}", ha="center", fontsize=8.5, color=TEXT_SEC)
        ax2.text(i, s/2, f"展示率\n{r}%", ha="center", va="center", fontsize=9, fontweight="bold", color=WHITE)
    ax2.set_xticks(x); ax2.set_xticklabels(ch_names, fontsize=10, color=TEXT)
    ax2.set_title("按渠道: 展示成功 vs 加载流失", fontsize=14, fontweight="bold", color=TEXT, pad=12)
    ax2.legend(fontsize=9, loc="upper right", facecolor=CARD2, edgecolor=GRID, labelcolor=TEXT)
    ax2.tick_params(colors=TEXT_SEC, labelsize=9)
    ax2.grid(axis="y", color=GRID, linewidth=0.5, alpha=0.3)
    for sp in ax2.spines.values(): sp.set_color(GRID)

    # 右：每日趋势
    ax3 = fig.add_axes([0.70, 0.50, 0.27, 0.36], facecolor=CARD)
    ax3_twin = ax3.twinx()
    ax3.fill_between(range(days), 0, d_shows, color=GREEN, alpha=0.35)
    ax3.fill_between(range(days), d_shows, d_loads, color=RED, alpha=0.25)
    ax3.plot(range(days), d_loads, "o-", color=PRIMARY, linewidth=2, markersize=5, label="加载次数")
    ax3.plot(range(days), d_shows, "s-", color=GREEN, linewidth=2, markersize=5, label="展示次数")
    ax3_twin.plot(range(days), d_rates, "D--", color=RED, linewidth=2.5, markersize=7, label="展示率 %")
    for i, r in enumerate(d_rates):
        ax3.text(i, (d_loads[i] - d_shows[i])*0.5 + d_shows[i], f"{r}%",
                 ha="center", va="center", fontsize=7.5, fontweight="bold", color=RED)
    ax3.set_xticks(range(days)); ax3.set_xticklabels(dts, fontsize=8.5, color=TEXT_SEC)
    ax3.set_title("每日广告加载/展示/展示率趋势", fontsize=14, fontweight="bold", color=TEXT, pad=12)
    ax3.tick_params(colors=TEXT_SEC, labelsize=9)
    ax3_twin.tick_params(colors=TEXT_SEC, labelsize=9)
    ax3.grid(axis="y", color=GRID, linewidth=0.5, alpha=0.3)

    # 左下：明细表
    ax4 = fig.add_axes([0.04, 0.08, 0.62, 0.38], facecolor=CARD)
    ax4.axis("off")
    cols = ["渠道", "加载", "展示成功", "展示率", "流失", "流失占比", "点击", "点击率"]
    xs = [0.02, 0.18, 0.30, 0.42, 0.52, 0.62, 0.72, 0.85]
    for cx, h in zip(xs, cols):
        ax4.text(cx, 0.92, h, ha="left", va="center", fontsize=9, fontweight="bold", color=TEXT_SEC)
    ax4.axhline(y=0.89, xmin=0, xmax=1, color=GRID, linewidth=1)
    for i, (name, l, s, clk, r) in enumerate(channels):
        loss = l - s
        loss_pct = round(loss / sum(ch_loss) * 100, 1)
        s2c = round(clk/s*100, 1)
        rate_str = f"{r*100:.1f}%"
        y = 0.84 - i * 0.13
        if i % 2 == 0:
            ax4.add_patch(plt.Rectangle((0.01, y - 0.05), 0.98, 0.10,
                                        facecolor=CARD2, zorder=-1, transform=ax4.transAxes))
        vals = [name, f"{l:,}", f"{s:,}", rate_str, f"{loss:,}", f"{loss_pct}%", f"{clk:,}", f"{s2c}%"]
        colors = [TEXT, TEXT, GREEN, RED if r*100 < 50 else GREEN, RED, RED, ORANGE, TEXT_SEC]
        for cx, v, c in zip(xs, vals, colors):
            ax4.text(cx, y, v, ha="left", va="center", fontsize=9, color=c,
                     fontweight="bold" if c in (RED, GREEN, ORANGE) else "normal")
    ax4.text(0.01, 0.94, "渠道转化明细", ha="left", va="center", fontsize=14, fontweight="bold", color=TEXT)

    # 右下：结论
    ax5 = fig.add_axes([0.69, 0.08, 0.28, 0.38], facecolor=CARD)
    ax5.set_xticks([]); ax5.set_yticks([])
    for sp in ax5.spines.values(): sp.set_color(GRID); sp.set_linewidth(0.5)
    ax5.text(0.5, 0.94, "分析结论", ha="center", va="center", fontsize=14, fontweight="bold", color=TEXT)
    cons = [
        ("问题1", f"加载→展示率仅 {round(S/L*100,1)}%，近一半({loss_L2S:,}次)广告加载后未展示", RED),
        ("问题2", f"最大问题渠道: 自然量，转化率 24.0%，\n该渠道流失 {ch_loss[1]:,} 次", RED),
        ("局限", "数据库只记录展示成功，未上报失败原因", YELLOW),
        ("建议1", "排查弱网/低端设备的广告 SDK 初始化逻辑", PRIMARY),
        ("建议2", "对比 TikTok 与自然量的加载时机差异，\n优化广告预加载策略", GREEN),
    ]
    for i, (t, c, color) in enumerate(cons):
        y = 0.78 - i * 0.16
        ax5.text(0.06, y, f"[{t}]", ha="left", va="top", fontsize=9.5, fontweight="bold", color=color)
        ax5.text(0.11, y, c, ha="left", va="top", fontsize=8, color=TEXT_SEC, linespacing=1.3)

    out = os.path.join(ASSETS_DIR, "sample-ad-funnel.png")
    fig.savefig(out, dpi=130, facecolor=BG, edgecolor="none", bbox_inches="tight")
    plt.close(fig)
    print("  ->", out)


# =============================================================
# 样图 2：7日运营日报（收入+ARPU+KPI卡片+国家占比）
# =============================================================
def make_daily():
    np.random.seed(7)
    days = 7
    base = datetime(2026, 7, 16)
    revs    = [21.29, 22.66, 24.05, 16.97, 17.00, 9.87, 15.21]
    arpu    = [0.17, 0.22, 0.27, 0.20, 0.22, 0.17, 0.10]
    install = [122, 104, 90, 83, 77, 59, 154]
    dau     = [165, 161, 138, 140, 138, 98, 206]
    shows   = [664, 479, 516, 604, 745, 403, 733]
    dates   = [(base + timedelta(days=i)).strftime("%m/%d") for i in range(days)]

    countries = [("JP", 113.19, 0.891), ("ID", 13.80, 0.109), ("BR", 0.03, 0.0),
                 ("SG", 0.02, 0.0), ("RO", 0.01, 0.0), ("US", 0.0, 0.0)]

    fig = plt.figure(figsize=(14, 9), facecolor="white")
    fig.text(0.5, 0.965, "海外短剧App 广告日报 · 07/22（样图）",
             ha="center", va="top", fontsize=20, fontweight="bold", color="#1a1a1a")
    fig.text(0.5, 0.935, "Revenue & ARPU  |  模拟数据展示 | 仅作可视化能力示例",
             ha="center", va="top", fontsize=10, color="#888")

    # 主图：收入 + ARPU 双轴
    ax = fig.add_axes([0.05, 0.45, 0.62, 0.43])
    bars = ax.bar(dates, revs, color="#2E86AB", width=0.55, label="收入 (USD)")
    for b, v in zip(bars, revs):
        ax.text(b.get_x() + b.get_width()/2, v + 0.4, f"${v:.1f}",
                ha="center", fontsize=9, color="#2E86AB", fontweight="bold")
    ax2 = ax.twinx()
    ax2.plot(dates, arpu, "o-", color="#E76F51", linewidth=2, markersize=8, label="ARPU (USD)")
    for x, y in zip(dates, arpu):
        ax2.text(x, y + 0.01, f"${y:.2f}", ha="center", fontsize=8, color="#E76F51")
    ax.set_ylabel("收入 (USD)", color="#1a1a1a", fontsize=11)
    ax2.set_ylabel("ARPU (USD)", color="#E76F51", fontsize=11)
    ax.set_title("收入 & ARPU", fontsize=14, fontweight="bold", color="#1a1a1a", pad=10)
    ax.tick_params(colors="#1a1a1a")
    ax2.tick_params(colors="#E76F51")
    ax.set_ylim(0, max(revs) * 1.15)
    ax2.set_ylim(0, max(arpu) * 1.2)
    ax.grid(axis="y", color="#eee", linewidth=0.5)
    ax.set_axisbelow(True)
    for sp in ax.spines.values(): sp.set_color("#ddd")

    # 右上：KPI 卡片
    ax_k = fig.add_axes([0.71, 0.62, 0.25, 0.26], facecolor="#F7F8FA")
    ax_k.set_xticks([]); ax_k.set_yticks([])
    for sp in ax_k.spines.values(): sp.set_color("#e4e6eb")
    ax_k.text(0.5, 0.88, "周期总览", ha="center", fontsize=11, color="#888")
    ax_k.text(0.5, 0.65, "$127.05", ha="center", fontsize=30, fontweight="bold", color="#2E86AB")
    ax_k.text(0.5, 0.45, "总 收入 (USD)", ha="center", fontsize=10, color="#555")
    ax_k.text(0.5, 0.25, "689 人  ·  ARPU $0.18", ha="center", fontsize=10, color="#555")
    ax_k.text(0.5, 0.10, "昨日 $15.21 · 154人", ha="center", fontsize=9, color="#888")

    # 右下：国家占比饼
    ax_p = fig.add_axes([0.71, 0.10, 0.25, 0.45])
    sizes = [c[2] for c in countries if c[2] > 0]
    labels = [f"{c[0]} ${c[1]:.2f} ({c[2]*100:.1f}%)" for c in countries if c[2] > 0]
    colors = ["#2E86AB", "#E76F51", "#F4A261", "#264653", "#E9C46A", "#2A9D8F"][:len(sizes)]
    wedges, texts = ax_p.pie(sizes, labels=labels, colors=colors, startangle=90,
                             textprops={"fontsize": 8.5, "color": "#1a1a1a"})
    ax_p.set_title("国家收入占比", fontsize=12, fontweight="bold", color="#1a1a1a", pad=10)

    # 底部明细表
    ax_t = fig.add_axes([0.05, 0.05, 0.62, 0.32])
    ax_t.axis("off")
    headers = ["日期", "新安装", "收入(USD)", "ARPU", "DAU", "展示"]
    xs = [0.05, 0.25, 0.42, 0.55, 0.70, 0.85]
    for cx, h in zip(xs, headers):
        ax_t.text(cx, 0.92, h, ha="left", fontsize=10, fontweight="bold", color="#555")
    ax_t.axhline(0.88, xmin=0, xmax=1, color="#e4e6eb", linewidth=1)
    for i, (d, ins, rv, ap, du, sh) in enumerate(zip(dates, install, revs, arpu, dau, shows)):
        y = 0.78 - i * 0.11
        if i % 2 == 0:
            ax_t.add_patch(plt.Rectangle((0.02, y - 0.045), 0.96, 0.09,
                                         facecolor="#f7f8fa", zorder=-1, transform=ax_t.transAxes))
        for cx, v, c in zip(xs, [d, ins, f"${rv:.2f}", f"${ap:.2f}", du, sh],
                            ["#1a1a1a"]*6):
            ax_t.text(cx, y, str(v), ha="left", va="center", fontsize=10, color=c)
    ax_t.set_title("日报明细", fontsize=12, fontweight="bold", color="#1a1a1a", pad=10)

    fig.text(0.5, 0.01, f"Generated {datetime.now().strftime('%Y-%m-%d %H:%M')}  |  模拟数据，与真实业务无关",
             ha="center", fontsize=8, color="#aaa")

    out = os.path.join(ASSETS_DIR, "sample-daily-dashboard.png")
    fig.savefig(out, dpi=130, facecolor="white", edgecolor="none", bbox_inches="tight")
    plt.close(fig)
    print("  ->", out)


if __name__ == "__main__":
    print("Generating sample charts...")
    make_funnel()
    make_daily()
    print("DONE")
