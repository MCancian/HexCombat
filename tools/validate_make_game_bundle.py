#!/usr/bin/env python3
"""Stdlib validation for tools/make_game_bundle.py's ship_stats block (plan 0023 P2a).

make_game_bundle.py is not otherwise exercised by the gate, so this guards the one piece of
real derivation it does: folding each turn's antiship_summary into the canonical per-turn +
cumulative ship_stats home. Two fixtures:

  * a hermetic hand-authored >=2-turn record with known antiship numbers, so the running-sum and
    drift assertions check exact values with no dependency on a large report file; and
  * a smoke pass over reports/llm/game_20260710.json if present (real 30-turn shape).

The drift assertion is the load-bearing one: ship_stats.per_turn is a COPY of data that still
lives raw in turns[].digest.antiship_summary, and AGENTS.md makes single-source a hard rule, so
the two can silently diverge. Internal consistency (cumulative == sum(per_turn)) does not catch a
per-turn copy bug — this also asserts per_turn[n] == the n-th turn's digest fields.
"""
import json
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

import make_game_bundle as bundler  # noqa: E402


def _summary(destroyed, damaged, bns_lost, by_type, sent=None, beaches=None, wave=0):
    return {
        "resolved_turn": 0,
        "sent_by_type": sent or {},
        "unliftable_bn": 0,
        "systems_fired_count": 0,
        "destroyed_by_ship_type": by_type,
        "crossing_casualties": {"destroyed": destroyed, "damaged": damaged},
        "bns_lost_at_sea": bns_lost,
        "target_beaches": beaches or [],
        "target_tos": [],
        "mine_status": [],
        "wave_bns": wave,
    }


def _turns_fixture():
    """Three turns; turn 2 has no crossing (antiship_summary absent) to exercise the null row."""
    return [
        {"turn_number": 1, "digest": {"antiship_summary": _summary(
            10, 4, 3, {"FFG": 6, "DDG": 4}, sent={"FFG": 12}, beaches=[1, 2], wave=80)}},
        {"turn_number": 2, "digest": {}},  # no crossing this turn
        {"turn_number": 3, "digest": {"antiship_summary": _summary(
            5, 2, 1, {"FFG": 3, "LPD": 2}, sent={"LPD": 5}, beaches=[3], wave=40)}},
    ]


class ShipStatsTest(unittest.TestCase):
    def setUp(self):
        self.turns = _turns_fixture()
        self.stats = bundler.build_ship_stats(self.turns)

    def test_shape(self):
        self.assertIn("per_turn", self.stats)
        self.assertIn("cumulative", self.stats)
        self.assertEqual(len(self.stats["per_turn"]), len(self.turns))  # 1:1 with turns[]
        cum = self.stats["cumulative"]
        for key in ("destroyed", "damaged", "bns_lost_at_sea", "destroyed_by_ship_type", "series"):
            self.assertIn(key, cum)
        for row, turn in zip(self.stats["per_turn"], self.turns):
            self.assertEqual(row["turn_number"], turn["turn_number"])
            for field in bundler.SHIP_PER_TURN_FIELDS:
                self.assertIn(field, row)

    def test_cumulative_equals_running_sum(self):
        cum = self.stats["cumulative"]
        self.assertEqual(cum["destroyed"], 15)          # 10 + 0 + 5
        self.assertEqual(cum["damaged"], 6)             # 4 + 0 + 2
        self.assertEqual(cum["bns_lost_at_sea"], 4)     # 3 + 0 + 1
        self.assertEqual(cum["destroyed_by_ship_type"], {"FFG": 9, "DDG": 4, "LPD": 2})

    def test_series_is_running_cumulative(self):
        series = self.stats["cumulative"]["series"]
        self.assertEqual([s["destroyed"] for s in series], [10, 10, 15])
        self.assertEqual([s["damaged"] for s in series], [4, 4, 6])
        self.assertEqual([s["bns_lost_at_sea"] for s in series], [3, 3, 4])
        self.assertEqual([s["turn_number"] for s in series], [1, 2, 3])
        last = series[-1]
        cum = self.stats["cumulative"]
        self.assertEqual((last["destroyed"], last["damaged"], last["bns_lost_at_sea"]),
                         (cum["destroyed"], cum["damaged"], cum["bns_lost_at_sea"]))

    def test_per_turn_matches_source_digest(self):
        """Drift guard: each per_turn row must equal its source turns[n].digest.antiship_summary."""
        for row, turn in zip(self.stats["per_turn"], self.turns):
            summary = (turn["digest"] or {}).get("antiship_summary") or {}
            for field in bundler.SHIP_PER_TURN_FIELDS:
                self.assertEqual(row[field], summary.get(field),
                                 msg="per_turn.%s drifted from digest on turn %s"
                                     % (field, turn["turn_number"]))

    def test_null_row_for_turn_without_crossing(self):
        row = self.stats["per_turn"][1]  # turn 2, no antiship_summary
        for field in bundler.SHIP_PER_TURN_FIELDS:
            self.assertIsNone(row[field])

    def test_real_record_smoke(self):
        record_path = REPO_ROOT / "reports" / "llm" / "game_20260710.json"
        if not record_path.exists():
            self.skipTest("real fixture %s absent" % record_path)
        record = json.loads(record_path.read_text(encoding="utf-8"))
        turns = bundler.build_turns(record, {})
        self.assertGreaterEqual(len(turns), 2)
        stats = bundler.build_ship_stats(turns)
        self.assertEqual(len(stats["per_turn"]), len(turns))
        # Independently recompute the cumulative destroyed total and cross-check the stored one.
        expected = sum(((t["digest"] or {}).get("antiship_summary") or {})
                       .get("crossing_casualties", {}).get("destroyed", 0) or 0 for t in turns)
        self.assertEqual(stats["cumulative"]["destroyed"], expected)
        # And the drift guard on real data.
        for row, turn in zip(stats["per_turn"], turns):
            summary = (turn["digest"] or {}).get("antiship_summary") or {}
            for field in bundler.SHIP_PER_TURN_FIELDS:
                self.assertEqual(row[field], summary.get(field))


if __name__ == "__main__":
    program = unittest.main(exit=False)
    if program.result.wasSuccessful():
        print("PASS: make_game_bundle validation succeeded")
        sys.exit(0)
    print("FAIL: make_game_bundle validation failed")
    sys.exit(1)
