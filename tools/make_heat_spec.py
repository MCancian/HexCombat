#!/usr/bin/env python3
"""Turn a 3-knob sweep (x-axis × y-axis × a two-value condition) into a heat-spec JSON for
`mc_chart.py --heat`. Reads the sweep's cell rollups and the manifest's knob/grid order:
knob[0] = x-axis, knob[1] = y-axis, knob[2] = the condition that splits the two panels.

The cell metric is `red_win_rate` (PLA victories / all games; undecided games count as non-wins),
reused from sweep_metrics so the heatmap and the sweep report agree by construction.

Usage:
    python3 tools/make_heat_spec.py --sweep-dir reports/sweeps/off_island_offload_heat \
        --title "..." --xlabel "..." --ylabel "..." \
        --panel-true "Taipei port intact" --panel-false "port neutralized" \
        --out docs/reports/assets/<name>.heat.json
"""

import argparse
import glob
import json
import os

from sweep_metrics import red_win_rate


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sweep-dir", required=True)
    p.add_argument("--title", default="")
    p.add_argument("--subtitle", default="")
    p.add_argument("--xlabel", default="")
    p.add_argument("--ylabel", default="")
    p.add_argument("--footnote", default="")
    p.add_argument("--panel-true", default="condition on")
    p.add_argument("--panel-false", default="condition off")
    p.add_argument("--out", required=True)
    args = p.parse_args()

    with open(os.path.join(args.sweep_dir, "sweep.json")) as f:
        manifest = json.load(f)
    x_knob, y_knob, cond_knob = manifest["knobs"]
    xs, ys, conds = manifest["grid"]
    if sorted(conds) != [False, True]:
        raise SystemExit("condition knob must be exactly [true, false]; got %r" % conds)

    # (x, y, cond) -> win%.
    table: dict = {}
    grid_knobs = (x_knob, y_knob, cond_knob)
    for cell_file in glob.glob(os.path.join(args.sweep_dir, "cells", "*.json")):
        with open(cell_file) as f:
            cell = json.load(f)
        ov = cell["overrides"]
        if any(k not in ov for k in grid_knobs):
            continue  # an out-of-band cell (e.g. a mines-only floor cell) — not part of this grid
        table[(ov[x_knob], ov[y_knob], ov[cond_knob])] = red_win_rate(cell)

    missing = [(x, y, c) for c in conds for y in ys for x in xs if (x, y, c) not in table]
    if missing:
        raise SystemExit("sweep incomplete — %d cells missing, e.g. %r" % (len(missing), missing[0]))

    def matrix(cond):  # rows indexed by y (grid order), cols by x
        return [[round(table[(x, y, cond)], 1) for x in xs] for y in ys]

    spec = {
        "title": args.title,
        "subtitle": args.subtitle,
        "xlabel": args.xlabel,
        "ylabel": args.ylabel,
        "footnote": args.footnote,
        "x": xs,
        "y": ys,
        "panels": [
            {"label": args.panel_true, "cells": matrix(True)},
            {"label": args.panel_false, "cells": matrix(False)},
        ],
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(spec, f, indent=2)
        f.write("\n")
    print("HEAT SPEC OK: wrote %s (%d×%d grid, 2 panels)" % (args.out, len(xs), len(ys)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
