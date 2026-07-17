#!/usr/bin/env python3
"""Stdlib validation for the cross-platform batch runner and mixed-seat replay logs."""

import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

import run_batch  # noqa: E402


class BatchRunnerTest(unittest.TestCase):
    def test_parse_matchup_accepts_bare_and_per_seat_ids(self) -> None:
        self.assertEqual(
            run_batch.parse_matchup("selfplay_default"),
            ("selfplay_default", "selfplay_default"),
        )
        self.assertEqual(
            run_batch.parse_matchup("llm_local:selfplay_default"),
            ("llm_local", "selfplay_default"),
        )
        with self.assertRaises(ValueError):
            run_batch.parse_matchup("red:green:extra")

    def test_read_valid_record_rejects_corrupt_and_unresolved_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            record_path = Path(directory) / "record.json"
            record_path.write_text("{", encoding="utf-8")
            self.assertIsNone(run_batch.read_valid_record(record_path))

            record_path.write_text(
                json.dumps({"all_resolved": False, "index_violations": []}),
                encoding="utf-8",
            )
            self.assertIsNone(run_batch.read_valid_record(record_path))

            record_path.write_text(
                json.dumps({"all_resolved": True, "index_violations": []}),
                encoding="utf-8",
            )
            self.assertIsNotNone(run_batch.read_valid_record(record_path))

    def test_make_jobs_stamps_per_seat_identity_in_filename_and_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            jobs = run_batch.make_jobs(
                ["roc_full_defense"],
                [("llm_local", "selfplay_default")],
                [20260624],
                30,
                "godot",
                Path(directory),
            )

        self.assertEqual(len(jobs), 1)
        job = jobs[0]
        self.assertEqual(
            job.record_path.name,
            "roc_full_defense__llm_local-vs-selfplay_default__seed20260624.json",
        )
        self.assertIn("--red-policy=llm_local", job.command)
        self.assertIn("--green-policy=selfplay_default", job.command)

    def test_live_llm_parallelism_emits_an_actionable_warning(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            run_batch.warn_live_llm_parallel(
                [("llm_local", "selfplay_default")], parallel=4
            )
        self.assertIn("--parallel 1", output.getvalue())

    def test_mixed_match_logs_both_seats(self) -> None:
        godot = os.environ.get("HEXCOMBAT_TEST_GODOT") or shutil.which("godot")
        if not godot:
            self.skipTest("Godot is unavailable for the mixed-seat replay test")
        reports_dir = REPO_ROOT / "reports"
        with tempfile.TemporaryDirectory(dir=reports_dir) as directory:
            entries = self._run_mixed_game(godot, Path(directory))

        self.assertEqual(len(entries), 4)
        self.assertEqual(
            sorted(entry["perspective"] for entry in entries),
            ["Green", "Green", "Red", "Red"],
        )

    def _run_mixed_game(self, godot: str, directory: Path) -> list[dict]:
        record_path = directory / "mixed.json"
        environment = os.environ.copy()
        environment["HEXCOMBAT_LLM_SIDECAR"] = "tools/llm_sidecar_stub.py"
        environment["HEXCOMBAT_STUB_MODE"] = "first_move"
        result = subprocess.run(
            [
                godot, "--headless", "--path", str(REPO_ROOT),
                "-s", "res://tools/run_selfplay_game.gd", "--",
                "--scenario=roc_full_defense", "--red-policy=llm_local",
                "--green-policy=selfplay_default", "--seed=20260624", "--turns=2",
                "--out=%s" % record_path,
            ],
            cwd=REPO_ROOT, env=environment, capture_output=True, text=True,
        )
        self.assertIn("GAME OK:", result.stdout + result.stderr)
        return [
            json.loads(line)
            for line in record_path.with_suffix(".jsonl").read_text(encoding="utf-8").splitlines()
            if line
        ]


if __name__ == "__main__":
    program = unittest.main(exit=False)
    if program.result.wasSuccessful():
        print("PASS: batch runner validation succeeded")
        sys.exit(0)
    print("FAIL: batch runner validation failed")
    sys.exit(1)
