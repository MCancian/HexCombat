#!/usr/bin/env python3
"""Fixture checks for tools/gd_metrics.py.

These are deliberately outside gd_metrics.py's inline self-test: the gate should prove the analyzer
still sees real .gd files, emits duplicate same-file/same-name function rows, and reports the current
repository's known parameter fixes. The production ceiling enforcement still lives in gd_metrics.py.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
METRICS = ROOT / "tools" / "gd_metrics.py"


def _run_metrics(root: Path, out_path: Path, *flags: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(METRICS), str(root), str(out_path), *flags],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def _assert(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def _functions_by_key(metrics: dict) -> dict:
    by_key = {}
    for fn in metrics["functions"]:
        by_key.setdefault(f"{fn['file']}::{fn['name']}", []).append(fn)
    return by_key


def _write_fixture(root: Path) -> None:
    (root / "fixture.gd").write_text(
        """
extends RefCounted

func single_line(a: int, b: int, c: int, d: int, e: int, f: int) -> void:
	pass

func wrapped(
	a: int,
	b: Array = [1, 2],
	c: Dictionary = {"x": 1, "y": 2},
	d: Callable[Array[int], Dictionary],
) -> void:
	if true:
		pass

class Inner:
	func duplicate_name(a: int, b: int, c: int, d: int, e: int, f: int) -> void:
		pass

func duplicate_name(a: int, b: int) -> void:
	pass
""".lstrip(),
        encoding="utf-8",
    )


def test_fixture_parameter_scan() -> None:
    with tempfile.TemporaryDirectory(prefix="gd_metrics_fixture_") as tmp:
        root = Path(tmp)
        _write_fixture(root)
        out = root / "metrics.json"
        result = _run_metrics(root, out)
        _assert(result.returncode == 0, result.stdout)
        metrics = json.loads(out.read_text(encoding="utf-8"))
        by_key = _functions_by_key(metrics)

        _assert(by_key["fixture.gd::single_line"][0]["params"] == 6, "single-line count drifted")
        _assert(by_key["fixture.gd::wrapped"][0]["params"] == 4, "wrapped/nested/default count drifted")
        _assert(by_key["fixture.gd::wrapped"][0]["cc"] == 2, "wrapped signature lines leaked into body CC")
        _assert(len(by_key["fixture.gd::duplicate_name"]) == 2, "duplicate function rows collapsed")
        params = sorted(fn["params"] for fn in by_key["fixture.gd::duplicate_name"])
        _assert(params == [2, 6], f"duplicate function param rows wrong: {params}")


def test_real_repo_metric_gate() -> None:
    with tempfile.TemporaryDirectory(prefix="gd_metrics_repo_") as tmp:
        out = Path(tmp) / "metrics.json"
        result = _run_metrics(ROOT, out, "--check-ceiling")
        _assert(result.returncode == 0, result.stdout)
        _assert("PASS: metric ceilings OK" in result.stdout, result.stdout)
        metrics = json.loads(out.read_text(encoding="utf-8"))
        by_key = _functions_by_key(metrics)
        # Path-keyed, so it moves when the file does: AntishipResolver became a calculator in plan 0050.
        params = by_key["scripts/calc/AntishipResolver.gd::resolve"][0]["params"]
        _assert(params == 3, f"AntishipResolver.resolve should stay paid down to 3 params, got {params}")


def main() -> int:
    try:
        test_fixture_parameter_scan()
        test_real_repo_metric_gate()
    except Exception as exc:  # noqa: BLE001 - simple validator script, print exact failure.
        print(f"FAIL: gd_metrics validation failed: {exc}")
        return 1
    print("PASS: gd_metrics validation succeeded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
