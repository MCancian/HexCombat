---
name: hexcombat-add-phase-resolver
description: Template for adding a NEW game phase or mechanic to the decomposed turn engine — resolver class, typed summary, GameState wiring, data files, validators, tests, observation surfacing. Use when implementing any new gameplay system (e.g. terrain, naval reinforcement, air defense expansion). ACTIVE as of 2026-07-02 — the decomposition campaign is complete; all phases follow this template.
---

# Adding a phase / mechanic (per-phase template, resolver era)

> **Activation status: ACTIVE** (decomposition campaign complete 2026-07-02). Every phase's
> logic now lives in `scripts/resolvers/`; never add a new inline phase body to `GameState`.

## The checklist (every box, in order)

1. **Design before code.** Is this a port/adaptation (read the source oracle + its tests first —
   `hexcombat-wargame-domain-reference` has the map) or new design (settle the design with the
   user; record in PLAN.md → Decisions)? Scope big phases into sub-tasks.
2. **Typed model** — new state shapes become `Resource` classes in `scripts/model/` with typed
   fields and `to_dict()` (exact key set/types = the JSON contract; `null` = unresolved sentinel).
3. **Pure resolver** — `scripts/resolvers/<Phase>Resolver.gd`, `RefCounted`, explicit
   `static func resolve(<inputs>, dice) -> <TypedSummary>`. No autoload access, no EventBus, no
   Node. If it needs randomness: a **derived substream** (`dice.derive("<phase>:<context>")`),
   never the base stream. **Check the body of any helper you pull in for hidden autoload reads**
   (e.g. `Theaters` reads `GameData` internally) — if found, materialize what it returns as plain
   data in the wrapper and pass that in instead.
4. **Content data** — `data/<phase>/*.json` (+ scenario keys per `hexcombat-config-and-knobs`).
   Loaders fail loud on unknown/missing keys.
5. **GameState wiring** — a thin `resolve_<phase>_turn()` wrapper: gathers inputs from state,
   calls the resolver, assigns the summary field (typed, `null` default), emits the EventBus
   signal with `to_dict()`, and slots into `resolve_turn`'s explicit sequence at a deliberate
   position (document why that position — what it must run after/before).
6. **Cross-phase state** — any new field other phases read gets its producer→consumer edge
   documented in the wiring commit and threaded explicitly.
7. **Validator** — `tools/validate_<phase>_data.gd` (data contract) and/or
   `tools/validate_headless_<phase>.gd` (behavior); auto-picked-up by the gate.
8. **GdUnit tests** — resolver in isolation (ScriptedDice for roll control); mirror source-oracle
   test cases when porting.
9. **Observation surfacing** — new player-relevant state goes into `LLMGameAPI.get_observation()`
   + `schemas/` + `REQUIRED_*_KEYS` + fixture regen (one commit). New phases must never break the
   observation contract; AI agents and validators read it.
10. **Golden discipline** — a new phase that consumes dice or moves units WILL change golden
    values: that's a deliberate, user-visible behavior change → expected re-baseline, done per
    `hexcombat-change-control` (user-aware, all pins updated in the same commit).
11. **Docs** — new `docs/systems/<phase>.md` (+ README index row), STATUS.md, Decisions entry,
    knob table in `hexcombat-config-and-knobs`.

## Reference implementations

Ground combat (BOOTS) is the original template; the D1–D5 systems each followed it (see
`docs/systems/`). Live resolver examples in `scripts/resolvers/`:
- **`OffloadResolver.gd`** — cleanest dice-free case: pure resolve + explicit
  wrapper split (state application, EventBus emit, and autoload access stay in GameState).
- **`IjfsResolver.gd`** — the derived-substream pattern (`dice.derive("ijfs:%d:%d")`) plus
  sanctioned in-place mutation of passed Resources.
- **`CombatResolver.gd`** — a pure dice-consuming core whose application deliberately stays in
  the wrapper (interleaving semantics); the model for when purity must stop at the summary.
