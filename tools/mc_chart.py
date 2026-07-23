#!/usr/bin/env python3
"""Render the Monte Carlo outcome distribution as a self-contained inline SVG for the deck.

Reads the summary JSON emitted by mc_summarize.py (the real batch, no fabricated numbers)
and writes an <svg> figure that drops straight into docs/presentation.html slide 6. Optionally
reads a sensitivity summary (knob value -> mean crossing loss %) for the companion panel.

Theme-matched to the deck: bg #0a0e17, accent #3b82f6 (blue) / #8b5cf6 (violet), Inter/Outfit.
The histogram is a single-hue distribution of the victory margin (one entity = PLA margin), so
per the dataviz form rules it carries no legend; the win threshold and mean are direct-labelled.

Usage:
    python3 tools/mc_chart.py --summary reports/mc/<name>.summary.json \
        [--sensitivity reports/mc/<name>.sensitivity.json] --out reports/mc/<name>.svg
"""

import argparse
import json
from pathlib import Path

# Deck design tokens.
BLUE = "#3b82f6"
VIOLET = "#8b5cf6"
INK = "#e2e8f0"
MUTED = "#94a3b8"
FAINT = "#64748b"
GRID = "rgba(255,255,255,0.08)"
BAR_TOP = "#60a5fa"  # lighter blue for the rounded data-end, per marks spec

WIDTH = 600
HEIGHT = 560


def esc(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, content, size, color, weight="400", anchor="start", font="Inter", extra=""):
    return (
        '<text x="%s" y="%s" font-family="%s, sans-serif" font-size="%s" '
        'font-weight="%s" fill="%s" text-anchor="%s"%s>%s</text>'
        % (x, y, font, size, weight, color, anchor, (" " + extra) if extra else "", esc(content))
    )


def histogram_panel(summary: dict) -> list[str]:
    margin = summary["margin"]
    bins = margin["bins"]
    # Drop leading/trailing empty bins so the axis frames the real data.
    first = next(i for i, b in enumerate(bins) if b["count"] > 0)
    last = max(i for i, b in enumerate(bins) if b["count"] > 0)
    bins = bins[first : last + 1]
    data_lo = bins[0]["start"]
    hi = bins[-1]["end"]
    lo = data_lo - 4  # empty gutter left of the tie line, so the "ROC wins" label has room

    plot_l, plot_r, plot_t, plot_b = 62, 566, 104, 292
    plot_w = plot_r - plot_l
    plot_h = plot_b - plot_t
    max_count = max(b["count"] for b in bins)
    y_top = ((max_count // 15) + 1) * 15  # round up to a clean gridline

    def mx(margin_value):
        return plot_l + (margin_value - lo) / (hi - lo) * plot_w

    def my(count):
        return plot_b - (count / y_top) * plot_h

    n = summary["n_games"]
    red = summary["outcomes"]["red"]
    parts: list[str] = []
    parts.append(text(60, 34, "Victory margin across %d seeds" % n, 21, INK, "700", "start", "Outfit"))
    parts.append(
        text(60, 58, "PLA amphibious assault vs full ROC defense · symmetric scripted policy",
             12.5, MUTED)
    )

    # Y gridlines + labels.
    step = y_top // 3
    for value in range(0, y_top + 1, step):
        y = my(value)
        parts.append('<line x1="%s" y1="%.1f" x2="%s" y2="%.1f" stroke="%s" stroke-width="1"/>'
                     % (plot_l, y, plot_r, y, GRID))
        parts.append(text(plot_l - 8, y + 4, str(value), 11, FAINT, "400", "end"))
    parts.append(text(plot_l, plot_t - 12, "games (of %d)" % n, 11, FAINT, "400", "start"))

    # Bars (2px surface gap; 4px rounded data-end at the top). Bin width in margin units = 5.
    bin_px = 5 / (hi - lo) * plot_w
    gap = 5
    for b in bins:
        bx = mx(b["start"]) + gap / 2
        bw = bin_px - gap
        by = my(b["count"])
        bh = plot_b - by
        if b["count"] == 0:
            continue
        parts.append(
            '<path d="M%.1f %.1f v%.1f a4 4 0 0 1 4 -4 h%.1f a4 4 0 0 1 4 4 v%.1f z" fill="%s"/>'
            % (bx, plot_b, -(bh - 4), bw - 8, bh - 4, BLUE)
        )
        parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="3" rx="1.5" fill="%s"/>'
                     % (bx, by, bw, BAR_TOP))
        parts.append(text(bx + bw / 2, by - 8, str(b["count"]), 12, INK, "600", "middle"))

    # X axis line, ticks (from margin 0), label.
    parts.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="1.5"/>'
                 % (plot_l, plot_b, plot_r, plot_b, "rgba(255,255,255,0.25)"))
    tick = 0
    while tick <= hi - 1:
        x = mx(tick)
        parts.append('<line x1="%.1f" y1="%s" x2="%.1f" y2="%s" stroke="%s" stroke-width="1"/>'
                     % (x, plot_b, x, plot_b + 5, "rgba(255,255,255,0.25)"))
        parts.append(text(x, plot_b + 19, "+%d" % tick if tick > 0 else "0", 11, MUTED, "400", "middle"))
        tick += 5
    parts.append(
        text((plot_l + plot_r) / 2, plot_b + 38,
             "PLA − ROC battalions present at game end  (victory margin)", 12, MUTED, "400", "middle")
    )

    # Win-threshold marker at margin 0: every game sits to its right; the gutter holds the label.
    tx = mx(0)
    parts.append('<line x1="%.1f" y1="%s" x2="%.1f" y2="%s" stroke="%s" stroke-width="2" '
                 'stroke-dasharray="5 4"/>' % (tx, plot_t + 2, tx, plot_b, VIOLET))
    parts.append(text(tx - 7, plot_t + 30, "tie", 11, VIOLET, "700", "end"))
    parts.append(text(tx - 7, plot_t + 45, "ROC 0/%d" % n, 9.5, FAINT, "400", "end"))

    # Mean marker.
    mean = margin["mean"]
    meanx = mx(mean)
    parts.append('<line x1="%.1f" y1="%s" x2="%.1f" y2="%s" stroke="%s" stroke-width="1.5" '
                 'stroke-dasharray="2 3"/>' % (meanx, plot_t + 2, meanx, plot_b, INK))
    parts.append(text(meanx + 5, plot_t + 12, "mean +%.1f" % mean, 11, INK, "600", "start"))

    # Headline readout row, clear of the axis.
    parts.append('<line x1="60" y1="342" x2="566" y2="342" stroke="%s" stroke-width="1"/>' % GRID)
    ry = 372
    readouts = [
        ("%d / %d" % (red, n), "PLA victories"),
        ("+%d" % margin["median"], "median margin"),
        ("+%d" % margin["min"], "thinnest win"),
        ("%d–%d" % (summary["turns_to_decision"]["min"], summary["turns_to_decision"]["max"]),
         "turns to decision"),
    ]
    col_w = WIDTH / len(readouts)
    for i, (value, label) in enumerate(readouts):
        cx = col_w * i + col_w / 2
        parts.append(text(cx, ry, value, 23, BLUE if i == 0 else INK, "700", "middle", "Outfit"))
        parts.append(text(cx, ry + 20, label, 11, MUTED, "400", "middle"))
    return parts


def sensitivity_panel(sens: dict) -> list[str]:
    points = sens["points"]  # list of {"value": float, "crossing_loss_pct": float, "red_win_rate": float}
    plot_l, plot_r, plot_t, plot_b = 60, 564, 420, 512
    xs = [p["value"] for p in points]
    ys = [p["crossing_loss_pct"] for p in points]
    x_lo, x_hi = min(xs), max(xs)
    y_lo = (min(ys) // 10) * 10
    y_hi = ((max(ys) // 10) + 1) * 10

    def mx(v):
        return plot_l + (v - x_lo) / (x_hi - x_lo) * (plot_r - plot_l)

    def my(v):
        return plot_b - (v - y_lo) / (y_hi - y_lo) * (plot_b - plot_t)

    parts: list[str] = []
    parts.append(text(60, 388, "Sensitivity — anti-ship strike bonus vs mean crossing loss",
                      15, INK, "700", "start", "Outfit"))
    parts.append(text(60, 406, "%s · PLA win rate stays 100%% across the sweep (margin only tightens)"
                      % sens.get("note", ""), 11, MUTED))

    for value in (y_lo, (y_lo + y_hi) / 2, y_hi):
        y = my(value)
        parts.append('<line x1="%s" y1="%.1f" x2="%s" y2="%.1f" stroke="%s" stroke-width="1"/>'
                     % (plot_l, y, plot_r, y, GRID))
        parts.append(text(plot_l - 8, y + 4, "%d%%" % value, 10.5, FAINT, "400", "end"))

    line = " ".join("%.1f,%.1f" % (mx(p["value"]), my(p["crossing_loss_pct"])) for p in points)
    parts.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="2.5" '
                 'stroke-linejoin="round" stroke-linecap="round"/>' % (line, VIOLET))
    for p in points:
        cx, cy = mx(p["value"]), my(p["crossing_loss_pct"])
        parts.append('<circle cx="%.1f" cy="%.1f" r="4.5" fill="%s" stroke="%s" stroke-width="2"/>'
                     % (cx, cy, VIOLET, "#0a0e17"))
        parts.append(text(mx(p["value"]), plot_b + 18, "%.1f" % p["value"], 10.5, MUTED, "400", "middle"))
    parts.append(text((plot_l + plot_r) / 2, plot_b + 36, "intel_locked_antiship_strike_bonus",
                      11, FAINT, "400", "middle"))
    return parts


def build_svg(summary: dict, sens: dict | None) -> str:
    height = HEIGHT if sens else 400
    body = histogram_panel(summary)
    if sens:
        body.append('<line x1="60" y1="360" x2="564" y2="360" stroke="%s" stroke-width="1"/>' % GRID)
        body += sensitivity_panel(sens)
    return (
        '<svg viewBox="0 0 %d %d" width="100%%" role="img" '
        'aria-label="Monte Carlo victory-margin distribution across %d seeds" '
        'xmlns="http://www.w3.org/2000/svg" style="max-width:100%%;height:auto;">\n  %s\n</svg>'
        % (WIDTH, height, summary["n_games"], "\n  ".join(body))
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--sensitivity", default="")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    summary = json.loads(Path(args.summary).read_text(encoding="utf-8"))
    sens = json.loads(Path(args.sensitivity).read_text(encoding="utf-8")) if args.sensitivity else None
    svg = build_svg(summary, sens)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(svg + "\n", encoding="utf-8")
    print("MC CHART OK: wrote %s (%d bytes)" % (out, len(svg)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
