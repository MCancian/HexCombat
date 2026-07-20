#!/usr/bin/env python3
"""Cross-sweep knob ledger + sensitivity ranking (plan 0018).

Every game record written by run_selfplay_game.gd carries record["knobs"] — the full resolved
value of every registry knob (data/knobs/registry.json). Because the vector is COMPLETE, any two
records from any sweep sit in a common knob-space, which is what makes these two views possible:

  ledger       one row per distinct knob-vector explored: game count, sources, outcome summary.
               "What parameter space have we run?"
  sensitivity  for each knob that VARIES across a record set, the spread it induces in an outcome
               metric, ranked. "Which knobs move outcomes the most?"

Pure functions (record dicts in -> numbers/rows out) so they unit-test without touching Godot;
the CLI just does discovery + Markdown rendering. Metrics operate over ALL games in a group
(win rate = wins / total games, undecided included in the denominator).

Usage:
  research_knobs.py ledger      --records reports/ [--out reports/research_ledger.md]
  research_knobs.py sensitivity --records reports/ [--metric red_win_rate|census_margin]
"""

import argparse
import glob
import json
import os
import sys

# --------------------------------------------------------------------------------------------
# Record loading
# --------------------------------------------------------------------------------------------


def is_record(obj):
    """A game record we can place in knob-space: has a knobs vector and an outcome."""
    return isinstance(obj, dict) and "knobs" in obj and "winner" in obj


def load_records(paths):
    """Load every *.json record under the given files/dirs/globs (recursive for dirs). Silently
    skips non-record JSON (sweep specs, manifests, reports) so a whole reports/ tree can be passed."""
    records = []
    for path in _expand(paths):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                obj = json.load(handle)
        except (json.JSONDecodeError, OSError):
            continue
        if is_record(obj):
            obj.setdefault("_source", path)
            records.append(obj)
    return records


def _expand(paths):
    for path in paths:
        if os.path.isdir(path):
            yield from sorted(glob.glob(os.path.join(path, "**", "*.json"), recursive=True))
        elif any(ch in path for ch in "*?["):
            yield from sorted(glob.glob(path, recursive=True))
        else:
            yield path


# --------------------------------------------------------------------------------------------
# Knob-vector helpers
# --------------------------------------------------------------------------------------------


def _canonical(value):
    """Hashable, order-stable rendering of a knob value (lists/dicts -> compact JSON)."""
    if isinstance(value, (list, dict)):
        return json.dumps(value, sort_keys=True, separators=(",", ":"))
    return value


def knob_vector(record):
    """{knob_id -> canonical value} for one record."""
    return {k: _canonical(v) for k, v in record.get("knobs", {}).items()}


def varying_knobs(records):
    """Knob ids whose canonical value is not identical across every record (sorted)."""
    if not records:
        return []
    vectors = [knob_vector(r) for r in records]
    all_ids = set().union(*(v.keys() for v in vectors))
    varying = [kid for kid in all_ids if len({v.get(kid) for v in vectors}) > 1]
    return sorted(varying)


# --------------------------------------------------------------------------------------------
# Outcome metrics
# --------------------------------------------------------------------------------------------


def red_win_rate(records):
    if not records:
        return 0.0
    return sum(1 for r in records if r.get("winner") == "red") / len(records)


def green_win_rate(records):
    if not records:
        return 0.0
    return sum(1 for r in records if r.get("winner") == "green") / len(records)


def undecided_rate(records):
    if not records:
        return 0.0
    decided = sum(1 for r in records if r.get("winner") in ("red", "green"))
    return (len(records) - decided) / len(records)


def census_margin(records):
    """Mean (red - green) terminal battalions on Taiwan."""
    if not records:
        return 0.0
    total = 0.0
    for r in records:
        census = r.get("census", {})
        total += float(census.get("red", 0)) - float(census.get("green", 0))
    return total / len(records)


METRICS = {
    "red_win_rate": red_win_rate,
    "census_margin": census_margin,
}


# --------------------------------------------------------------------------------------------
# Ledger
# --------------------------------------------------------------------------------------------


def build_ledger(records):
    """Group records by full knob-vector. Returns a list of group dicts, most-games first."""
    groups = {}
    for record in records:
        vector = knob_vector(record)
        key = json.dumps(vector, sort_keys=True)
        group = groups.setdefault(key, {"vector": vector, "records": []})
        group["records"].append(record)
    rows = []
    for group in groups.values():
        recs = group["records"]
        rows.append({
            "vector": group["vector"],
            "n": len(recs),
            "red_win_rate": red_win_rate(recs),
            "green_win_rate": green_win_rate(recs),
            "undecided_rate": undecided_rate(recs),
            "census_margin": census_margin(recs),
            "sources": sorted({os.path.dirname(r.get("_source", "")) for r in recs}),
        })
    rows.sort(key=lambda row: row["n"], reverse=True)
    return rows


def render_ledger_md(records):
    if not records:
        return "# Research knob ledger\n\n_No records found._\n"
    rows = build_ledger(records)
    varying = varying_knobs(records)
    constant = {k: v for k, v in knob_vector(records[0]).items() if k not in varying}
    lines = ["# Research knob ledger", ""]
    lines.append("%d record(s), %d distinct knob-vector(s), %d knob(s) varying." % (
        len(records), len(rows), len(varying)))
    lines.append("")
    if constant:
        lines.append("**Held constant across all records:** " + ", ".join(
            "`%s`=%s" % (k, constant[k]) for k in sorted(constant)))
        lines.append("")
    header = ["N"] + ["`%s`" % k for k in varying] + ["Red win%", "Green win%", "Undecided%", "Census margin"]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join(["---"] * len(header)) + "|")
    for row in rows:
        cells = [str(row["n"])]
        cells += [str(row["vector"].get(k, "")) for k in varying]
        cells += [
            "%.0f%%" % (100 * row["red_win_rate"]),
            "%.0f%%" % (100 * row["green_win_rate"]),
            "%.0f%%" % (100 * row["undecided_rate"]),
            "%+.1f" % row["census_margin"],
        ]
        lines.append("| " + " | ".join(cells) + " |")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------------------------
# Sensitivity
# --------------------------------------------------------------------------------------------


def knob_sensitivity(records, metric="red_win_rate"):
    """For each varying knob, the outcome metric grouped by that knob's value, and the spread
    (range of per-value means). Ranked by spread desc. Confounding caveat when >1 knob varies."""
    metric_fn = METRICS[metric]
    results = []
    for knob_id in varying_knobs(records):
        by_value = {}
        for record in records:
            value = knob_vector(record).get(knob_id)
            by_value.setdefault(value, []).append(record)
        per_value = {value: metric_fn(recs) for value, recs in by_value.items()}
        spread = max(per_value.values()) - min(per_value.values()) if per_value else 0.0
        results.append({
            "knob": knob_id,
            "metric": metric,
            "per_value": per_value,
            "spread": spread,
            "n_values": len(per_value),
        })
    results.sort(key=lambda row: row["spread"], reverse=True)
    return results


def render_sensitivity_md(records, metric="red_win_rate"):
    ranked = knob_sensitivity(records, metric)
    varying = varying_knobs(records)
    lines = ["# Knob sensitivity — %s" % metric, ""]
    if not ranked:
        lines.append("_No knob varies across these records — nothing to rank._")
        lines.append("")
        return "\n".join(lines)
    lines.append("%d record(s); ranking %d varying knob(s) by the spread each induces in `%s`." % (
        len(records), len(ranked), metric))
    if len(varying) > 1:
        lines.append("")
        lines.append("> **Caveat:** more than one knob varies across this set, so spreads may be "
                     "confounded (co-varying knobs). Cleanest read is a set where one knob varies "
                     "at a time — e.g. a single sweep grid.")
    lines.append("")
    lines.append("| Rank | Knob | Values | `%s` by value | Spread |" % metric)
    lines.append("|---|---|---|---|---|")
    for i, row in enumerate(ranked, 1):
        by_value = ", ".join("%s→%.3g" % (v, m) for v, m in sorted(row["per_value"].items(),
                                                                    key=lambda kv: str(kv[0])))
        lines.append("| %d | `%s` | %d | %s | %.3g |" % (
            i, row["knob"], row["n_values"], by_value, row["spread"]))
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(description="Research knob ledger + sensitivity (plan 0018).")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("ledger", "sensitivity"):
        p = sub.add_parser(name)
        p.add_argument("--records", nargs="+", required=True, help="record files/dirs/globs")
        p.add_argument("--out", default="", help="write Markdown here (default: stdout)")
        if name == "sensitivity":
            p.add_argument("--metric", default="red_win_rate", choices=sorted(METRICS))
    args = parser.parse_args(argv)

    records = load_records(args.records)
    if args.command == "ledger":
        text = render_ledger_md(records)
    else:
        text = render_sensitivity_md(records, args.metric)

    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text)
        print("Wrote %s (%d record(s))" % (args.out, len(records)))
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
