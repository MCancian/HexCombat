#!/usr/bin/env python3
"""Stdlib validation for the research knob ledger + sensitivity (plan 0018)."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import research_knobs as rk  # noqa: E402


def _record(winner, knobs, census=None):
    return {
        "record_version": 2,
        "winner": winner,
        "game_over": winner in ("red", "green"),
        "census": census or {"red": 0, "green": 0},
        "knobs": knobs,
    }


class LoadRecordsTest(unittest.TestCase):
    def test_skips_non_records_and_bad_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "rec.json").write_text(
                json.dumps(_record("red", {"a": 1})), encoding="utf-8")
            (Path(directory) / "spec.json").write_text(
                json.dumps({"sweep_name": "x"}), encoding="utf-8")  # not a record
            (Path(directory) / "broken.json").write_text("{", encoding="utf-8")
            records = rk.load_records([directory])
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0]["winner"], "red")


class VaryingKnobsTest(unittest.TestCase):
    def test_only_changing_knobs_reported(self) -> None:
        records = [
            _record("red", {"held": 1, "moved": 4}),
            _record("green", {"held": 1, "moved": 8}),
        ]
        self.assertEqual(rk.varying_knobs(records), ["moved"])

    def test_list_knob_values_compared_canonically(self) -> None:
        # Same list content -> not varying; different -> varying.
        same = [_record("red", {"caps": [2, 4]}), _record("red", {"caps": [2, 4]})]
        self.assertEqual(rk.varying_knobs(same), [])
        diff = [_record("red", {"caps": [2, 4]}), _record("red", {"caps": [2, 2]})]
        self.assertEqual(rk.varying_knobs(diff), ["caps"])


class MetricsTest(unittest.TestCase):
    def test_win_rates_and_margin(self) -> None:
        records = [
            _record("red", {}, {"red": 10, "green": 4}),
            _record("red", {}, {"red": 8, "green": 6}),
            _record("green", {}, {"red": 0, "green": 20}),
            _record("", {}, {"red": 5, "green": 5}),
        ]
        self.assertAlmostEqual(rk.red_win_rate(records), 0.5)
        self.assertAlmostEqual(rk.green_win_rate(records), 0.25)
        self.assertAlmostEqual(rk.undecided_rate(records), 0.25)
        # margins: 6, 2, -20, 0 -> mean -3
        self.assertAlmostEqual(rk.census_margin(records), -3.0)


class LedgerTest(unittest.TestCase):
    def test_groups_by_vector_and_orders_by_count(self) -> None:
        records = [
            _record("red", {"warmup": 3}),
            _record("green", {"warmup": 3}),
            _record("red", {"warmup": 7}),
        ]
        rows = rk.build_ledger(records)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["n"], 2)  # warmup=3 group first (more games)
        self.assertEqual(rows[0]["vector"]["warmup"], 3)
        self.assertAlmostEqual(rows[0]["red_win_rate"], 0.5)

    def test_render_lists_constant_and_varying(self) -> None:
        records = [
            _record("red", {"held": 1, "warmup": 3}),
            _record("green", {"held": 1, "warmup": 7}),
        ]
        md = rk.render_ledger_md(records)
        self.assertIn("Held constant", md)
        self.assertIn("`held`", md)
        self.assertIn("warmup", md)


class SensitivityTest(unittest.TestCase):
    def test_ranks_bigger_spread_first(self) -> None:
        # knob "big" flips outcome entirely; knob "small" barely moves it.
        records = [
            _record("red", {"big": 0, "small": 0}),
            _record("red", {"big": 0, "small": 1}),
            _record("green", {"big": 1, "small": 0}),
            _record("green", {"big": 1, "small": 1}),
        ]
        ranked = rk.knob_sensitivity(records, "red_win_rate")
        self.assertEqual(ranked[0]["knob"], "big")
        self.assertAlmostEqual(ranked[0]["spread"], 1.0)   # big=0 -> 1.0 red, big=1 -> 0.0 red
        self.assertAlmostEqual(
            next(r for r in ranked if r["knob"] == "small")["spread"], 0.0)

    def test_confounding_caveat_when_multiple_vary(self) -> None:
        records = [
            _record("red", {"a": 0, "b": 0}),
            _record("green", {"a": 1, "b": 1}),
        ]
        md = rk.render_sensitivity_md(records, "red_win_rate")
        self.assertIn("Caveat", md)

    def test_reports_per_bin_sample_counts(self) -> None:
        records = [
            _record("red", {"k": 0}), _record("green", {"k": 0}),  # value 0: n=2
            _record("red", {"k": 1}),                              # value 1: n=1
        ]
        ranked = rk.knob_sensitivity(records, "red_win_rate")
        row = ranked[0]
        self.assertEqual(row["counts"][0], 2)
        self.assertEqual(row["counts"][1], 1)
        self.assertEqual(row["min_bin_n"], 1)
        md = rk.render_sensitivity_md(records, "red_win_rate")
        self.assertIn("n=2", md)
        self.assertIn("n=1", md)

    def test_thin_bin_warning_when_a_value_has_few_games(self) -> None:
        # value 1 backed by a single game -> should be flagged, not silently trusted.
        records = [
            _record("red", {"k": 0}), _record("red", {"k": 0}), _record("red", {"k": 0}),
            _record("green", {"k": 1}),
        ]
        md = rk.render_sensitivity_md(records, "red_win_rate")
        self.assertIn("Thin bins", md)


if __name__ == "__main__":
    result = unittest.main(argv=[sys.argv[0], "-v"], exit=False).result
    if result.wasSuccessful():
        print("PASS: research knobs validation succeeded")
        sys.exit(0)
    print("FAIL: research knobs validation failed")
    sys.exit(1)
