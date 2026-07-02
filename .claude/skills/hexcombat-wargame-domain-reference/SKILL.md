---
name: hexcombat-wargame-domain-reference
description: The wargame-domain knowledge pack for HexCombat — WeGo turns, FEBA, OOB structure, DOS supply, the IJFS kill chain, anti-ship/mine warfare, odd-r hex geometry — as they apply HERE, plus the map from each mechanic to its Python source oracle. Use when a task requires understanding what a mechanic MEANS, not just where its code is.
---

# Wargame domain reference (as implemented here)

A mid-level engineer knows code; this is the wargaming theory they'd lack, bound to HexCombat's
implementation. Deeper per-system detail: `docs/systems/*.md`.

## The simulated question

Can a PLA (Red) amphibious invasion of Taiwan establish and expand a beachhead against ROC (Green)
defense? One turn = one day. Red must cross the strait (losing ships to missiles/mines), land over
beaches (throughput-limited), stay supplied, and win the ground fight; Green attrits the crossing,
strikes are exchanged via air/missile fires, and the battalion census decides victory.

## Core vocabulary

- **OOB (order of battle):** the force list. Brigades (atomic on-map unit) composed of battalions
  `{type, qty}`. `nato_type` drives symbology; battalion type drives strength (`UnitStats`),
  mechanization (supply), maneuver-vs-support classification.
- **WeGo:** both sides plan simultaneously, then one deterministic resolver applies everything
  (vs. IGO-UGO alternation). Why: no first-mover artifact; AI agents and humans use the same
  order buffers.
- **FEBA (forward edge of the battle area):** continuous combat per contested hex accumulates a
  km-scale front shift each round; past ±10 km (`FEBA_RETREAT_THRESHOLD_KM`) the losing side
  retreats to an adjacent owned hex. Hex ownership is by occupancy (both → contested; one → that
  side; empty → last owner).
- **Tactical vs administrative movement:** tactical = short (2 hexes mech/armor, 1 otherwise),
  may fight; admin = road-march (~20/10), may NOT fight that turn, costs more organization.
- **Organization:** per-brigade cohesion stat, spent by movement (admin −100, tactical −25) and
  combat; tracked from the start, inert in combat math until a later milestone.
- **DOS (days of supply):** Red's logistics pool in tons. Consumption per battalion-day =
  base (300 mech / 150 non-mech) minus a third if it didn't move, minus a third if it didn't
  fight; 150 tons = 1 DOS. Pool exhausted → Red fights at `red_out_of_supply_effectiveness`.
- **IJFS (integrated joint fires system):** Red's air/missile campaign. Kill chain:
  ISR detection → target priority → fires allocation (per-platform daily budget, greedy) →
  strike Pk → hit/miss. Multi-day pre-invasion **warmup** ramps effectiveness and applies
  "exquisite intel" (peacetime HUMINT/SIGINT that pre-locks a decaying count of anti-ship
  groups). IJFS suppresses/destroys Green anti-ship systems (feeding D3) and attrits Green
  maneuver battalions (detectability biased by mobility, hardness, and recent activity/posture).
- **Anti-ship & mine warfare (D3):** Green's counter-crossing. Surviving anti-ship systems build
  a firing plan vs the crossing fleet (launch attrition, finite magazines, suppression);
  damage → ship losses by type. Minefields use the **geometric model**: mines uniform in a field,
  a randomized approach path, only mines within `danger_radius` of the path are dangerous; the
  fleet transits decoys-first (a surviving decoy keeps sponging mines), then real ships by
  ascending value. Sunk ship → its embarked battalions are `lost_at_sea` (feeds offload + census).
- **Amphibious offload (D1):** beach throughput in tons/day; slots = floor(rate/2200). Maneuver
  battalions land first (brigade-slot limited); support battalions wait afloat. A brigade is
  "landed" when its first BN lands, but only landed BNs count in the victory census.
- **Front-line phase (D5):** Red redistributes maneuver battalions evenly along a drawn polyline
  (sampled at 2 km → hex sequence) — operational repositioning of the beachhead front.
- **Victory census:** end-of-cleanup count of battalions *present* on Taiwan. China loses at 0 PLA
  BNs (arming configurable); China wins when PLA BNs strictly exceed ROC BNs.

## Hex geometry (get this right — it was once wrong)

The grid is **odd-r offset** (`row`/`col`, odd rows shifted). Neighbor/distance math must be
parity-aware (offset→cube for distance). Treating stored coords as axial matched true geometry on
only 23/308 interior hexes vs 308/308 for odd-r — the project's biggest correctness bug. All
geometry goes through `HexMath`; never hand-roll adjacency.

## Source oracles (port lineage)

- **TIV** (`C:\Users\mdogg\TaiwanInvasionViewer` — the real source tree is **nested**:
  `TaiwanInvasionViewer\TaiwanInvasionViewer\src\…`; the outer dir looks empty of source):
  original Python/Flask sim; its `tests/python/` were the behavioral oracle for the port.
  Per-phase file map with line refs: `ROADMAP.md` D1–D5 sections.
- **TaiwanDefenseRefactor** (`C:\Users\mdogg\My Drive\Projects\TaiwanDefenseRefactor`): source of
  the geometric mine model (`mine_warfare.py`).
- **Fidelity policy (user call 2026-07-02):** HexCombat is now the **design of record**. TIV
  remains useful for understanding intent, but the user directs design changes; document every
  divergence in PLAN.md → Decisions. Known deliberate divergences are recorded per system in
  `docs/systems/*.md`.

## Research framing (primary use)

Outcomes are distributions, not anecdotes: a claim about the model means N seeded runs, win rates
+ casualty/duration distributions, and (for "what matters") knob sweeps. A single run is a
narrative, not a result. See `hexcombat-research-runs`.
