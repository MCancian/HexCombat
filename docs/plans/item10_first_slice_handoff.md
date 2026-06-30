# Handoff — refactor_audit item 10, FIRST SLICE (GameState decomposition, safe front of the sequence)

> Paste everything below into the overnight agent. It is self-contained. This is the **low-risk first
> slice only** — it deliberately stops before the coupled parts of item 10.

---

ROLE: You are an autonomous frontier agent implementing the **first, lowest-risk slice** of
refactor_audit **item 10** — decomposing the 1,414-line `GameState` god-object — in the HexCombat
codebase (Godot 4.7 / GDScript). This is golden-regression-prone work and was explicitly flagged
"favor up-front effort, do with attention" — work carefully and self-verify. NOT a free-model task.

## START HERE (read in this order)
- `AGENTS.md` (canonical rules) and `CLAUDE.md` (orchestrator role).
- `docs/plans/refactor_audit.md` → "Larger structural refactors" → **item 10** for the full spec,
  the **DECIDED interface**, the shared-mutable-state map, and the **verified extraction order**.
- `PLAN.md` Decisions log, the **2026-06-30** entries for items **9** and **10**: item 9 is the
  proven typed-Resource pattern you will lean on; the item-10 entry records the USER interface call
  (pure `RefCounted` resolvers, NOT autoloads).
- The canonical gate is `tools/run_all_tests.ps1`. Godot: `C:\Godot_v4.7-stable_win64.exe`.
  **Golden invariant:** `validate_headless_turn` → seed 20260624, **casualties=3, feba=-0.96**.

## THE DECIDED INTERFACE (from PLAN.md, USER call — do not relitigate)
Each extracted unit becomes a **pure `RefCounted` class with explicit `static` signatures**, NOT a
new autoload. Dependencies are visible in the signature; the unit is headless-testable in isolation.
`GameState` shrinks toward a thin orchestrator that *sequences* these units.

**The critical adaptation for THIS slice — keep the public surface stable:**
The targets below are called directly by tests/tools/validators (e.g. `GameState._rebuild_ijfs_state()`,
`GameState.resolve_supply_turn()`, `GameState.resolve_frontline_phase()`). So **extract the LOGIC into
the new pure class, but leave the existing `GameState` method as a THIN DELEGATING WRAPPER** that calls
the new class and assigns/sequences the result. This keeps every existing call site green with zero
churn. Do **not** rename or delete the public methods in this slice.

**Pure-class boundary rules (AGENTS.md logic layer):** the new classes must have **no `Node`/engine
dependency** — no `EventBus` emits, no reaching for the `GameData`/`GameState` autoloads from inside the
class. Pass plain data in, return plain data/typed Resources out. **EventBus signal emits and autoload
access stay in the `GameState` wrapper.** Put the new classes in `scripts/resolvers/`.

## WHY THIS SLICE IS SAFE (state it back to yourself before you start)
**None of these targets consume dice.** The rebuild helpers are pure construction; `resolve_supply_turn`
takes no `Dice` and consumes none; `resolve_frontline_phase` is deterministic (no `Dice` param). So if
you preserve the logic exactly, the combat RNG draw order is untouched and the golden is structurally
protected. The item-8 `validate_fixtures` gate byte-compares `docs/examples/*.json` every run and will
catch any serialization drift.

## SCOPE — exactly what is IN this slice
Extract these, **safest first**, each its **own commit**, full gate + golden green after each:

**Builders (pure constructors — cleanest; do these first):**
1. `_ensure_antiship_systems` (`GameState.gd:510`) → builds `antiship_systems` + `antiship_containers`
   from `AntishipLoaders`. **Keep the lazy `if not antiship_systems.is_empty(): return` guard in the
   GameState wrapper**; the new class just does the three loader calls and returns both arrays. The
   `ANTISHIP_*_PATH` consts can move onto the new class or be passed in — pick one and keep a single
   source of truth.
2. `_rebuild_ship_reserve` (`:1096`) → returns the `ship_reserve` Array; wrapper assigns it.
3. `_rebuild_fleet` (`:1137`) → returns the `fleet` Dictionary; wrapper assigns it.
4. `_rebuild_supply_state` (`:1127`) → returns a fresh `SupplyState`; wrapper assigns it.
5. `_rebuild_ijfs_state` (`:518`) → returns a built `IjfsDailyState`. **Note the dependency:** it calls
   `_ensure_antiship_systems()` first (antiship must exist before IJFS) and reads `GameData.brigades`
   (Green OOB → maneuver targets). Pass the `antiship_containers` and the Green brigade list **in** as
   params (keep the class autoload-free). The wrapper keeps `_ensure_antiship_systems()` ordering and
   the `_ijfs_day = 0` reset.

**Phase resolvers (more involved — only after the builders are all green + committed):**
6. `resolve_supply_turn` (`:399`) → `SupplyResolver.resolve(supply_state, units, moved_ids,
   engaged_ids, turn_number) -> Dictionary`. The pure class computes the `DosConsumption` summary +
   pool math and mutates the passed `SupplyState` (a plain Resource — allowed). **The
   `EventBus.supply_updated.emit(...)` stays in the GameState wrapper.**
7. `resolve_frontline_phase` (`:1051`) → `FrontlineResolver` that takes the flat hex centers + the Red
   brigade list and returns a `FrontlineSummary` + the moves map. **The `GameData.set_brigade_hex(...)`
   application and the `EventBus.frontline_resolved.emit(...)` stay in the GameState wrapper.**
   (`FrontLineService` is already pure — reuse it.)

It is acceptable and expected to **stop after the 5 builders** if the resolvers (6–7) prove more
involved than one safe session allows — the builders alone are a complete, committable unit. Do NOT
rush 6–7.

## HARD STOP — do NOT touch in this slice (these are the coupled parts; attended work)
- `resolve_cleanup_phase` (more coupled than it looks — resets antiship flags, reads `ship_reserve`,
  latches brigade flags IJFS reads next turn).
- The bodies of `resolve_ijfs_turn`, `resolve_antiship_turn`, `resolve_offload_turn`, the combat loop,
  `_resolve_combat_at`, `_apply_*`, `begin_next_turn`, `play_turn`.
- The shared-mutable-state threading (`ship_reserve`/`fleet`/`pending_lost_at_sea`/`last_ijfs_writeback`
  /`supply_state`/`game_over`/per-brigade flags between phases). Mapping/threading that is the NEXT,
  attended slice — leave the fields on `GameState` as-is, owned by the orchestrator.
- `last_ijfs_summary` — USER-decided to stay an untyped Dictionary (item 9); do not type it.

## PER-STEP VERIFICATION (every single extraction)
1. Re-import: `"C:\Godot_v4.7-stable_win64.exe" --headless --path <repo> --import` — zero SCRIPT/Parse
   errors.
2. Golden: run `tools/validate_headless_turn.gd` → must print **casualties=3, feba=-0.96**.
3. Full gate: `pwsh -File tools/run_all_tests.ps1` → **ALL PHASES GREEN** (40 GdUnit suites + every
   validator, including `validate_fixtures` which byte-compares the committed JSON fixtures).
4. Review your own diff for scope drift, then **commit that one extraction alone** (end the message
   with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`). Do not batch multiple extractions
   into one commit. Push at the milestone (slice complete + green), not per micro-commit.

Optional but encouraged: add a small GdUnit test per new pure class (they are now isolation-testable —
that's the whole point of the interface). Keep it focused; don't gold-plate.

## GUARDRAILS
- Preserve all logic exactly — these are pure storage/construction moves. No behavior change, no math
  change, no dice consumed or reordered.
- Typed GDScript throughout; fail loud (`push_error`/`assert`), no silent dict-key defaults.
- Keep `GameState`'s public/`_`-prefixed method names intact as delegating wrappers (tests + tools +
  validators call them directly — see `tests/ijfs/ijfs_maneuver_*_test.gd`,
  `tools/sweep_antiship_crossing.gd`, `tools/validate_dos_consumption.gd`, `tools/validate_frontline.gd`).
- Never commit `.mcp.json`. **There is a pre-existing cosmetic whitespace change in `ROADMAP.md` in the
  working tree — leave it alone, do not stage or bundle it.**
- If you hit a genuine design decision the interface/PLAN.md doesn't answer (e.g. an unexpected hidden
  cross-phase read in one of these helpers), STOP and surface it (record in `PLAN.md` → Open Questions)
  rather than guessing.

## DONE WHEN
The 5 builders (and, if cleanly achievable, the 2 resolvers) are extracted into pure
`scripts/resolvers/` classes with `GameState` delegating to them; each is its own commit; full gate
green and golden byte-stable after each; and `PLAN.md` has a short Decisions-log entry recording what
was extracted, the delegating-wrapper approach, and where you stopped (so the next session resumes at
the cleanup/shared-state slice). Update `refactor_audit.md` item 10 to note the first slice is done and
what remains. Leave the rest of item 10 (cleanup + shared-state threading) for the attended follow-up.
