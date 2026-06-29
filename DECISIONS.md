# DECISIONS.md — Port-fidelity questions for the user

Discrepancies surfaced by the TIV port audit that are **genuine design calls** — not obvious
bugs (those get fixed directly) and not intentional skips (those live in
`docs/plans/port_audit.md`). Each entry: what differs, why it might matter, and the options.

Status legend: 🔴 open · 🟡 leaning (recommendation noted) · ✅ resolved (with the call + date).

---

<!-- Append entries below. Template:

## <area> — <short title>  🔴
**HexCombat:** <current behavior + file:line>
**TIV:** <source behavior + file:line>
**Why it matters:** <gameplay/fidelity impact>
**Options:** (a) … (b) …
**Recommendation:** <if any>

-->

## Hex grid (Area 1) — HexMath treats offset (odd-r) coords as axial  ✅ RESOLVED 2026-06-29 (fixed + re-baselined, user call)

**Resolution:** user chose to fix immediately so the rest of the audit runs against correct
adjacency. `HexMath.neighbor_coords` → parity-aware odd-r; `HexMath.distance` → offset→cube. Scenario
beach-1 Green `BDE-66` moved `hex_43_17`→`hex_43_16`; fixtures + LLM example docs updated. Golden
invariant re-baselined `casualties=2, feba=0.76` → `casualties=3, feba=-0.55` (deterministic; reflects
correct adjacent-support aggregation). Full gate **ALL PHASES GREEN**. Details: `PLAN.md` → Decisions
(2026-06-29 hex adjacency). Original finding below for the record.

---


**HexCombat:** `data/taiwan_hex_grid.json` stores **offset odd-r** `row`/`col` (the TIV generator
shifts odd rows right by half a hex). `GameData.load_hex_grid` sets `hex.coord = Vector2i(row, col)`
(`scripts/GameData.gd:79`) with no offset→axial conversion, then `HexMath.neighbor_coords`
(`scripts/HexMath.gd:14`) applies **fixed axial directions** and `HexMath.distance`
(`scripts/HexMath.gd:21`) applies the **axial cube-distance formula** to those offset coords.

**TIV:** `src/core/hex_grid.py` `get_hex_neighbors` uses **parity-dependent odd-r offsets** (even
rows: `(-1,-1),(-1,0),(0,-1),(0,1),(1,-1),(1,0)`; odd rows: `(-1,0),(-1,1),(0,-1),(0,1),(1,0),(1,1)`).

**Evidence (haversine over the real grid, 308 interior hexes with 6 true ~10 km neighbors):**
odd-r neighbors ⊆ geographic-6 on **308/308**; HexCombat axial on **23/308**. HexCombat picks a
wrong neighbor (and misses a true one) on ~92% of interior hexes; the wrong pick flips with row
parity (e.g. `hex_5_10` gets `hex_6_9` instead of a real neighbor).

**Why it matters:** adjacency is the foundation of movement legality, commit/attack targeting,
combat force aggregation, FEBA, front-line distribution, and pathfinding/reachable ranges. Distance
(movement allowance, ranges) is likewise computed in the wrong coordinate space. The port is
**self-consistent** (its golden invariant `seed 20260624 → casualties=2, feba=0.76` was authored
against this adjacency) but **geographically wrong and divergent from the TIV oracle**.

**Options:**
- **(a) Fix to odd-r (recommended).** Make `neighbor_coords` parity-aware (read `coord.x` row
  parity) and convert offset→cube in `distance` (odd-r: `x = col - (row - (row&1))/2`, `z = row`,
  `y = -x-z`). `find_path`/`find_reachable` ride on `neighbor_lookup`, so they correct automatically.
  **Cost:** re-baselines the golden combat invariant and any distance-tuned values; needs a focused
  re-verify of the BOOTS golden + movement/FEBA tests. This is the faithful port.
- **(b) Keep axial, document as an intentional divergence.** Cheaper now, but every downstream
  phase validated "against TIV" inherits subtly wrong adjacency; not recommended.

**Recommendation:** (a). It's a genuine correctness bug vs. the oracle; the only reason it's here and
not auto-fixed is the golden re-baseline blast radius, which is your call to accept.
