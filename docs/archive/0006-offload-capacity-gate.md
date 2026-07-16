# 0006 — Offload capacity gate (beaches + ports)

**Status:** DONE — shipped 2026-07-15 on `feat/0006-offload-gate` (9 commits, golden byte-stable
throughout via default-off knobs; no re-baseline). Facts: `docs/systems/amphibious-offload.md` §9;
knobs: `hexcombat-config-and-knobs`; decisions: `docs/DECISIONS.md` 2026-07-15; incident:
`hexcombat-failure-archaeology` → "Sealift livelock" (found + fixed by the C8 research runs).

> This plan is a **work order**. It has two parts: (A) study the TIV offload model against what
> HexCombat already ports, then (B) implement an infrastructure-throughput gate so the amount of Red
> force that comes ashore is limited by **held/operational offload nodes (beaches + ports + maybe
> airbridges)**, not only by ship lift. Read the whole plan, then start with Part A.

## Goal

Make **shore offload capacity** a real, held-infrastructure-driven constraint on the invasion.
Today the only cross-turn throttle on Red buildup is amphibious ship lift (plan 0004). The USER
design call (2026-07-12): *"The primary limitation on the amount of Red forces that come over will
be (1) the carrying capacity of surviving [amphibious] ships, and (2) the offload capacity of
beaches and ports on Taiwan."* Item (1) shipped in 0004; **this plan is item (2)** — the second gate,
scaling with how many beaches and ports Red holds and their operational state.

## Why now — session context (2026-07-12)

While closing 0004 we deep-pooled `scenario_default` (auto-seed every non-first-wave RED brigade as
follow-on) and fixed a fractional-hull lift bug. With real sustained lift and **no offload cap**, an
empty-orders golden self-play now has Red **overrun to a turn-17 `china_majority`** (was: a hard
plateau at 91 ashore). Root cause of the old plateau was instructive and is exactly what this plan
must model properly:

- **Beachhead saturation.** Under empty orders, landed brigades never move inland, so they occupy
  the beach's Day-1 brigade slots; the beach offload sink fills and new arrivals can't land.
- **No ports / airbridges.** Red can never expand offload capacity by seizing a port, so the only
  sink is the handful of assault beaches.

So the offload gate is the missing balancer. It also closes the sealift feedback loop: when offload
backs up, cohorts don't drain, hulls aren't freed, and embark self-throttles — the intended tempo.

## MUST READ before designing (source of truth)

**TIV source docs (the model to port — read first, cite in Part A):**
- `/var/home/qyfs/Projects/TaiwanInvasionViewer/docs/PRD/Offload.md` — the product model:
  throughput formula (beaches + ports×5.0/deg 1.0 + airbridges×1.0/deg 0.5 + piers/barges), Day-1
  assault rule, maneuver-first loading, destination locks (`Locked_Destination` = `port:id` /
  `airfield:id`), counter-offload damage, DOS. See esp. "Infrastructure Throughput" (throughput
  formula), "Day 1 Initial Assault Rule", "Battalion Allocation Algorithm".
- `/var/home/qyfs/Projects/TaiwanInvasionViewer/docs/technical/calculator_offload.md` — the
  algorithm: 8-step pipeline, per-TO port/airbridge throughput, throughput **cost multipliers**
  (BN-type × ship-category: amphibious-inf on mil-amphib = 0.5×, civilian-non-amphib = 2.0× at
  beach), beach offload queue (`build_offload_queue`, 10-turn timeline), fractional-BN flow.
- Onboarding to those repos: `TaiwanInvasionViewer/docs/technical/ssot_map.md` →
  `codebase_map.md`. Python oracles: `src/services/offload/beach_throughput.py`,
  `.../infrastructure_throughput.py`, `src/services/manifest_allocator.py`.

**HexCombat canonical homes (reconcile against these — do NOT re-port what was intentionally
skipped):**
- `docs/systems/amphibious-offload.md` — current offload + sealift behavior (the durable doc; §on
  offload throughput). Update at closeout.
- `docs/archive/port_audit.md` — authoritative list of what was ported vs intentionally skipped from
  TIV offload. **Read the "Parked / Intentionally skipped" section first.**
- Skills: `hexcombat-add-phase-resolver` (this likely extends an existing resolver, not a new
  phase), `hexcombat-wargame-domain-reference` (offload semantics + oracle map),
  `hexcombat-config-and-knobs` (adding beach/port/rate knobs + scenario params),
  `hexcombat-change-control` (digest shape changes → golden re-baseline required + allowed).

## Part A — what HexCombat already has vs. the gap (verified 2026-07-12)

### Existing offload code (file:line)

- **`scripts/OffloadRates.gd`** — throughput rate constants ported from TIV
  `defaults/offload_rates.json`, in short tons/day. `TONS_PER_BN = 2200`. Beach `BEACH_BASE 4400`,
  `FLOATING_PIER 2200`, `JACKUP_BARGE 4400`. **`OPERATIONAL_PORT 11000`, `DEGRADED_PORT 2200`,
  `SEIZED_PORT 0`, `OPERATIONAL_AIRBRIDGE 2200`, `DEGRADED_AIRBRIDGE 1100`, `SEIZED_AIRBRIDGE 0` are
  defined but NOTHING references them** — ports/airbridges are ported as rates only, never wired.
- **`scripts/OffloadCalculator.gd`** — pure lib. `beach_capacity_bns()` (`:32`) sums **beach**
  throughput only: `(offload_rate + floating_piers*pier_rate + jackup_barge*barge_rate)/TONS_PER_BN`
  → BN-slots/day. `resolve_offload_day(current_day, …)` (`:76`) branches:
  - `_resolve_day1` (`:126`): brigade-slot assault — `beach_slots = floor(beach_capacity)`, one
    brigade per slot (locked-beach first, then priority); **maneuver BNs land, support BNs defer**
    (`day1_support_waiting`); unassigned brigades defer (`day1_no_beach_slot`). `is_maneuver_bn` uses
    `MANEUVER_BN_TYPES` (`:15`).
  - `_resolve_day_n` (`:199`): tons-based greedy — each BN costs a **flat** `TONS_PER_BN` from the
    beach's `remaining_tons`; over-capacity BNs defer (`throughput_limited`). **No BN-type/ship-
    category cost multiplier** (TIV's 0.5×/1.0×/2.0×).
- **`scripts/resolvers/OffloadResolver.gd`** — `resolve(turn_number, ship_reserve, beaches,
  brigades)` (`:36`). Builds `active_beach_ids` from each reserve entry's `locked_beach`; calls
  `beach_capacity_bns` then `resolve_offload_day(turn_number, …)`. **Passes the GLOBAL `turn_number`
  as `current_day`** → a brigade that first crosses on turn 8 is offloaded under "Day 8" throughput
  rules, never the Day-1 assault bypass. This is a real limitation for follow-on echelons (they never
  get an assault landing). Mutates reserve entries' `bns` in place; returns landings + first-landing
  brigade ids.
- **`scripts/model/BeachDef.gd`** — `offload_rate`, `capacity_battalions` (loaded but unused by the
  calculator), `floating_piers`, `jackup_barge`, `to_number`, `advance_direction`, `hex_id`, `lat/lng`.
- **`scripts/GameState.gd:316`** — `resolve_offload_turn` calls `OffloadResolver.resolve`, applies
  landings via `GameData.set_brigade_hex`, reassigns `ship_reserve`, recomputes ownership, threads
  `pending_lost_at_sea`, emits `EventBus.offload_resolved`.
- **`data/beaches.json`** — 9 beaches with `offload_rate`, `to_number`, piers/barges (from TIV
  `defaults/beaches.json`). No port/airfield entities anywhere in `data/`.
- **Sealift interaction (plan 0004):** `SealiftResolver.drain_bn_ids` frees a cohort's hulls into the
  return pipeline only when its BNs fully drain (land/drown). Harder offload gating ⇒ cohorts linger
  ⇒ hulls stay busy ⇒ embark self-throttles. This coupling is the point — verify it holds.

### The delta to port (Part A must quantify + reconcile with `port_audit.md`)

1. **Ports & airbridges as offload nodes.** New data entities (port/airfield: hex, TO, operational
   state, per-unit rate), held/operational state derived from **hex ownership** (Red-controlled port
   hex ⇒ contributes; contested/Green ⇒ seized/0). Throughput per TIV: port op 11000 / deg 2200,
   airbridge op 2200 / deg 1100 (BN-equiv 5.0/1.0 and 1.0/0.5). Routing preference (TIV Day-2+):
   `locked beach → same-TO port → same-TO airbridge → any remaining port/airbridge`.
2. **Throughput cost multipliers** (BN-type × ship category). HexCombat currently flat `TONS_PER_BN`;
   TIV varies 0.5×/1.0×/2.0×. Needs the ship category the BN crossed on (Military/Civilian Amphibious
   vs Non-Amphibious) — currently BNs don't carry their carrying ship category. Decide if worth it.
3. **Global-day vs per-cohort assault day.** Decide whether a follow-on echelon's first landing
   should get Day-1 assault treatment (per-cohort day) or stay throughput-gated (current global day).
4. **Counter-offload damage** (Blue): beach rate −1 / destroy pier+barge, port op→deg→gone. Likely
   out of scope for v1 (no Blue offload-strike phase yet) — confirm against `port_audit.md`.
5. **Inland-clearance valve.** The empty-orders saturation is really "beaches never clear because
   units don't advance." A Day-1 beach stays locked until its brigade fully offloads AND (design
   question) vacates the beach hex. This is an offload↔movement interaction, not pure throughput.

## Part B — likely implementation shape (confirm against Part A; don't presume)

1. Model ports/airbridges: data files + `PortDef`/`AirfieldDef` (mirror `BeachDef`), loaded in
   `GameData`; operational state from hex ownership at resolve time.
2. Extend `OffloadCalculator.beach_capacity_bns` → a total-throughput function that adds
   held-port/airbridge BN-equiv capacity (using the already-present `OffloadRates` constants), keyed
   by TO for routing. Keep it a pure lib.
3. Wire through `OffloadResolver` (feed ownership/TO in) + `GameState.resolve_offload_turn`.
   Preserve determinism (no new RNG) and resolver purity.
4. New scenario/config knobs per `hexcombat-config-and-knobs` (port/airfield entities, rates already
   in `data/offload_rates.json` if present — verify). Give `scenario_default` a couple of seizable
   ports so the gate is exercised in the golden gate.
5. Decide the cost-multiplier + per-cohort-day + inland-clearance questions (USER checkpoints).
6. Golden re-baseline (digest shape changes) — coordinate with the pending sealift re-baseline.

## USER design checkpoints (surface; don't guess)

- **Fidelity/scope:** minimal (held beaches + ports throughput cap, flat cost) vs full TIV
  (airbridges + per-cohort day + BN-type/ship-category cost multipliers + counter-offload + DOS
  preload). Recommend deciding after Part A quantifies the delta.
- **"Held" definition:** port/airfield operational purely from hex ownership, or a separate
  seize/degrade state a scenario/adjudicator sets?
- **Inland-clearance rule:** does landing require/trigger vacating the beach hex (offload↔movement
  coupling), or is the beach a pure per-turn throughput number with no occupancy lock?
- **Force/infrastructure numbers on the Taiwan map** (which ports, where, what rates) — a wargame-
  design call; bring numbers to USER.

## Sequencing / dependencies

- **The sealift prerequisite has landed (2026-07-12).** The deep pool is now an opt-in
  (`auto_seed_followon_pool`) on `scenario_default` (the research default), the two lift-path bugs are
  fixed (amphibious classification via `ShipDef.is_amphibious_lift()`, `pack_bns_into_hulls`
  aggregation), and the golden gate runs a frozen `scenario_golden.json` via `HEXCOMBAT_SCENARIO`
  (byte-stable, no re-baseline). This plan builds on that. See `docs/DECISIONS.md` (2026-07-12) +
  `docs/systems/amphibious-offload.md` §8.
- **Golden shape to know:** the gate does NOT run `scenario_default`; it runs `scenario_golden`
  (one-shot assault). So this plan's offload changes only move the golden pins **if** they alter that
  assault laydown's scripted turn — most offload-cap work touches the deep-pool default and its
  coverage check (`tools/validate_deep_pool_smoke.gd`), not the golden. Re-baseline the golden only if
  a change genuinely reaches the frozen fixture (per `hexcombat-change-control`). Give
  `scenario_default` (and/or `scenario_golden` if intended) seizable ports so the gate exercises the
  new gate.

## Verification

- `bash tools/run_all_tests.sh` → ALL PHASES GREEN after re-baseline.
- Resolver unit tests for the new throughput math (held vs seized port, TO routing, degraded state).
- A research run (`hexcombat-research-runs`): empty-orders golden no longer overruns by turn 17;
  Red buildup tracks held offload capacity; seizing/losing a port visibly changes the landing rate.

## Checklist

- [x] Part A: TIV offload model documented with citations + the port delta; reconciled with
      `docs/archive/port_audit.md` (do not re-port intentionally-skipped items)
- [x] USER checkpoint: fidelity/scope + "held" definition + inland-clearance rule + map numbers
      (resolved 2026-07-15 via AskUserQuestion — see DECISIONS)
- [x] Ports/airbridges modeled (data + defs + ownership-driven operational state); throughput lib
      extended (pure, deterministic)
- [x] Wired through `OffloadResolver` / `GameState`; `scenario_default` given seizable ports
- [x] ~~Golden re-baseline~~ not needed — all features default-off, golden byte-stable; new
      resolver/calculator/JLSF tests; `run_all_tests.sh` ALL PHASES GREEN every commit
- [x] Research run confirms offload-capacity-gated tempo (no overrun over 40 turns × 3 seeds;
      Taichung seizure lifts landing rate ~5→~8 BN/turn and ends the game 2–5 turns earlier);
      also caught + fixed the heavy-BN sealift livelock (carry-over)
- [x] Closeout: `docs/systems/amphibious-offload.md` §9, STATUS bullet, DECISIONS entry,
      archaeology entry (sealift livelock); this plan archived
