# DECISIONS.md — Port-fidelity questions for the user

Discrepancies surfaced by the TIV port audit that are **genuine design calls** — not obvious
bugs (those get fixed directly) and not intentional skips (those live in
`docs/archive/port_audit.md`). Each entry: what differs, why it might matter, and the options.

Status legend: 🔴 open · 🟡 leaning (recommendation noted) · ✅ resolved (with the call + date).

---

## Ground combat (Area 2) — unit strength table differs from TIV for 12/17 types  ✅ RESOLVED 2026-06-29 (keep table; helicopters verified moot)

**Decision (user):** keep HexCombat's differentiated table; reconcile helicopters. **Resolution:**
helicopters (and all `rotary_wing`/`artillery` battalions) are routed to combat **support**, not
`maneuver_units` (`CombatForces.gd:14`), in **both** HexCombat and TIV (TIV pools `rotary_wing` as a
support resource; `is_adjacent_combat_eligible` = maneuver+artillery only). So the helicopter
maneuver-strength (0.5 vs TIV's 1.4) is **never used in combat** — no behavioral discrepancy. Kept 0.5
(aviation) and documented the routing in `UnitStats.gd`. The differentiated table is ratified as the
intended design (TIV's all-1.0 runtime is a latent mapping bug; HexCombat reflects the intent). Original
finding below.

---

## Ground combat (Area 2) — unit strength table (original finding)  🟡 (recommend: keep HexCombat's table; ratify)

**HexCombat:** `UnitStats.TYPE_DEFS` (`scripts/UnitStats.gd:6`) gives differentiated maneuver strengths
keyed by full battalion name — Armor/Tank 2.0, Combined Arms/Mech Inf 1.5, Amphibious 1.2, Air Assault
1.4, Recon 0.7, Air Defense 0.9, Support/Service Support 0.3, Reserve 0.5; helicopters 0.5.

**TIV (verified by calling `BOOTSCalculator`):** `_map_type_to_strength_key` only maps a handful of
lowercase short forms, so the full battalion-name `Type` strings the OOB actually carries fall through
to the `1.0` default. Net runtime values: **almost all maneuver units = 1.0**; only Field Artillery
0.8, Mech/Rocket Artillery 1.3, SOF 1.8, **Attack/Utility Helicopter 1.4** differ. **12 of 17 OOB
types resolve differently** from HexCombat.

**Why it matters:** unit strength drives the force ratio → loss rates, FEBA, and the result label.
HexCombat combat is materially different from TIV's actual output (e.g. an armored brigade is 2× a
support battalion in HexCombat but equal in TIV). TIV has **no pytest pinning strengths**, so this is
untested on the source side.

**Read:** TIV's flattening is near-certainly a latent bug — its `unit_combat_strength` table exists to
differentiate, but the type→key mapping never reaches it for real OOB names. HexCombat ported the
*intent*. The one place HexCombat also diverges from TIV's intent is **helicopters** (0.5 vs the
mapping's 1.4).

**Options:** (a) **Keep HexCombat's differentiated table** (recommended — it's the designed behavior;
matching TIV's all-1.0 bug would flatten the game). (b) Reconcile helicopters to 1.4 if they're meant
to fight as maneuver units (likely they shouldn't — they're aviation). (c) Match TIV literally
(all-1.0) — not recommended.

**Recommendation:** (a) + decide (b). Ratify so it's a recorded intentional divergence, not drift.

---

## Ground combat (Area 2) — feba_base_km 2.0 vs TIV 3.5  ✅ RESOLVED 2026-06-29 (made scenario-configurable, default 3.5)

**Decision (user):** make `feba_base_km` scenario-configurable, default to TIV's 3.5. **Resolution:**
added `feba_base_km` to scenario config (`GameData.feba_base_km`, default 3.5; `scenario_default.json`),
`GameState._resolve_combat_at` now passes it instead of the hardcoded 2.0. Golden re-baselined
`feba=-0.55` → `feba=-0.96` (×1.75); `combat_resolution_test` FEBA-delta assertion 1.0 → 1.75. Full
gate green. Original finding below.

---

## Ground combat (Area 2) — feba_base_km 2.0 (HexCombat) vs 3.5 (TIV config)  🟡 (original finding)

**HexCombat:** `GameState._resolve_combat_at` hardcodes `feba_base_km = 2.0` (`scripts/GameState.gd:1071`).
**TIV:** loads `3.5` from config (`_load_feba_base_km`; pinned by `tests/python/unit/test_boots_attack_mode.py:180`).

**Why it matters:** FEBA shift scales linearly with the base, so HexCombat's front advances/retreats
~57% as far per combat as TIV's — a balance-relevant divergence likely from the port not carrying the
config value.

**Options:** (a) set 3.5 to match TIV; (b) read it from the scenario/config (TIV-faithful + tunable);
(c) keep 2.0 as an intentional rebalance.

**Recommendation:** (b) — surface `feba_base_km` in scenario config defaulting to TIV's 3.5. Either
change re-baselines the golden FEBA value again, so it needs your sign-off.

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
