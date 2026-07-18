"""Metric extractors for sweep cells (plan 0012).

Each registry function takes a cell dict ({"overrides": ..., "samples": [...]}) whose samples are
standard run_selfplay_game.gd records, and returns RAW numbers — a float or a flat dict of floats.
All formatting (±, %, decimals) lives in make_sweep_report.py; keeping numbers raw here lets
callers sort/threshold and spares every new extractor from duplicating format code.

Extraction is fail-loud: a missing key is a typo or a contract break, never a default.
"""

import math


def mean(samples):
    if not samples:
        return 0.0
    return sum(samples) / len(samples)


def stdev(samples, m):
    if len(samples) < 2:
        return 0.0
    variance = sum((x - m) ** 2 for x in samples) / (len(samples) - 1)
    return math.sqrt(variance)


def _first_wave_antiship(record):
    """The D3 antiship digest of the first crossing turn (turn 1 in every canned sweep)."""
    digest = record["turn_digests"][0]
    summary = digest["antiship_summary"]
    if not summary:
        raise KeyError(
            "record %s turn 1 has an empty antiship_summary (no crossing wave resolved)"
            % record.get("base_seed"))
    return summary


def _maneuver_counts(digest):
    counts = digest["ijfs_summary"]["target_counts_by_category_status"]["Maneuver Units"]
    return float(counts["total"]), float(counts["destroyed"])


def crossing_loss_pct(cell_data):
    """First-wave BN crossing loss (%): bns_lost_at_sea / wave_bns from the turn-1 D3 digest."""
    losses = []
    for record in cell_data["samples"]:
        summary = _first_wave_antiship(record)
        wave = float(summary["wave_bns"])
        lost = float(summary["bns_lost_at_sea"])
        losses.append(100.0 * lost / wave if wave > 0 else 0.0)
    m = mean(losses)
    return {"mean": m, "sd": stdev(losses, m)}


def maneuver_attrition_pct(cell_data):
    """IJFS maneuver-pool attrition over the whole game, from the D4 digests' target census."""
    pools = []
    killeds = []
    warmups = []
    taiwans = []
    for record in cell_data["samples"]:
        digests = record["turn_digests"]
        pool, warmup_killed = _maneuver_counts(digests[0])
        _, killed = _maneuver_counts(digests[-1])
        pools.append(pool)
        killeds.append(killed)
        warmups.append(warmup_killed)
        taiwans.append(float(record["census"]["green"]))
    m_killed = mean(killeds)
    m_pool = mean(pools)
    return {
        "pool": m_pool,
        "killed_mean": m_killed,
        "killed_sd": stdev(killeds, m_killed),
        "pct_pool": 100.0 * m_killed / m_pool if m_pool > 0 else 0.0,
        "warmup_killed_mean": mean(warmups),
        "taiwan_mean": mean(taiwans),
    }


def red_win_rate(cell_data):
    """Share of decided games the record marks as a Red win (winner is lowercase in records)."""
    wins = 0
    total = 0
    for record in cell_data["samples"]:
        if "winner" in record:
            total += 1
            if str(record["winner"]).lower() == "red":
                wins += 1
    if total == 0:
        return 0.0
    return 100.0 * wins / total


REGISTRY = {
    "crossing_loss_pct": crossing_loss_pct,
    "maneuver_attrition_pct": maneuver_attrition_pct,
    "red_win_rate": red_win_rate,
}
