# Brief: source-of-truth sweep across HexCombat

Hand this to a fresh agent. It is written to be self-contained — paste it whole.

---

You are surveying **/var/home/qyfs/Projects/HexCombat**, a Godot 4.7 / GDScript operational wargame
(Chinese invasion of Taiwan). Read `AGENTS.md` and `CLAUDE.md` first for the house rules.

**REVIEW AND REPORT ONLY. Do not modify, create, or delete any file except the one report you are asked
to write at the end. Do not implement anything.**

## The question

For every kind of thing the game models — hexes, brigades, battalions, ships, anti-ship and IJFS
systems, supply, infrastructure, beaches, theatres, victory state, orders — **where does the truth about
its state actually live, and can that truth be contradicted?**

Then: **is there a rationalisation worth making**, or is the current arrangement already right and the
apparent inconsistency merely cosmetic?

Answer with evidence from the code, not from the docs. The docs are good here but they are a secondary
source, and at least one plan in `docs/plans/` has recently been found to contain a premise that was
false in the current tree.

## What prompted this

A prior session established the following. **Treat it as a hypothesis to confirm, refute, or refine —
not as a conclusion to elaborate.** It was produced quickly and has not been independently reviewed.

There appear to be three distinct shapes, which need different responses:

1. **A single authoritative field.** `HexState.owner` — one field, cannot disagree with itself.
   Nothing to do.
2. **A derived index over one authoritative source.** `GameData.brigades_by_hex` is a lookup cache over
   `Brigade.hex_id`, funnelled through one mutator and guarded after the fact by
   `GameData.validate_runtime_indexes()`. A cache-coherency problem, not a competing truth.
3. **A quantity distributed across several buckets.** Here the house pattern is: one model Resource owns
   every bucket, and carries a `validate()` conservation invariant asserted at construction and after
   mutation. Live in `ShipState` (`FleetBuilder.gd:27`, `ReinforcementPhases.gd:106`), `SealiftState`
   (`SealiftStateBuilder.gd:39`), `AirInsertionState` (`AirInsertionStateBuilder.gd:75`) and
   `InfrastructureState`. Note `ShipState` is **counts, not instances**, and that is sufficient because
   all its buckets live in one object with a known total.

**Battalions are the identified outlier**: a battalion's buckets are spread across `Brigade.composition`,
`SealiftState.mainland_pool` and `AirInsertionState.pool`, with no owning object and no total, so
"ashore" is derived by subtraction (`Brigade.landed_qty()`) and nothing can validate it centrally. Two
silent, result-changing bugs have already come out of that seam (`bff4a1c`, `5f79317`), both found by
inspection rather than by any gate. This is the subject of `docs/plans/0039-battalion-location-single-truth.md`.

## What I want from you

### 1. A complete inventory, entity by entity

For each modelled entity, state:

- **Where the truth lives** (file and class/field, by name — no line numbers, they rot).
- **Which of the three shapes it is**, or a fourth shape if you find one.
- **Whether anything can contradict it** — a second list, a cache, a derived value, a serialized copy.
- **What guards it, and whether that guard PREVENTS or merely DETECTS.** This distinction is the point
  of the exercise. A `validate()` asserted at mutation prevents; an end-of-turn tripwire detects after a
  turn has already resolved wrongly; a validator that runs in the gate detects at commit time.
- **Whether the guard has ever been seen to fire.** A check nobody has watched go red is not evidence.

Be exhaustive about where to look: `scripts/model/`, `scripts/calc/`, `scripts/interleaved/`, `scripts/GameData.gd`,
`scripts/GameState.gd`, `scripts/model/GameStateData.gd`, the `tools/validate_*.gd` family, and the
serialization surfaces (`scripts/LLMGameAPI.gd`, `docs/examples/*.json`, `schemas/*.schema.json`).

### 2. The specific questions I could not answer

- **IJFS and anti-ship systems.** `AntishipSystem.expended` looks like a bare counter. Is there a
  conservation relationship (fired + remaining == establishment) and is it checked anywhere? Do
  magazines, reload pipelines and attrition have an owner, or are they the battalion shape again?
- **Supply / DOS.** Is `SupplyState.current_dos_tons` a single truth, or is consumption reconciled
  against something that can disagree?
- **Orders.** Order kinds are enumerated independently in `GameState._apply_order`,
  `LLMGameAPI.apply_agent_response` and `schemas/llm_action_response.schema.json` (already in BACKLOG).
  Is that the same disease, or an unrelated duplication?
- **Serialized identity.** Battalion ids appear in fixtures and research records. Which entities have an
  identity that is a *serialization contract*, and is that identity derived or stored? A derived id that
  can change is a silent contract break.

### 3. A judgement, not a catalogue

The deliverable that matters is the recommendation:

- Is there a **rationalisation worth making** — a single stated rule the codebase should follow, and a
  list of the places that violate it, ranked by the cost of the bug each violation can produce?
- Or is the right answer **"leave it alone"** for most of them, because the shapes genuinely differ and a
  uniform abstraction would be ceremony? Say so plainly if that is what the evidence supports. A survey
  that recommends a large unifying refactor because unification sounds better than inconsistency is a
  bad survey.
- For anything you do recommend, give the **cheapest version that removes the risk**, not the most
  complete version. The house preference is legibility for a non-coding owner, and the standing lesson
  from plan 0040 is that a small preventive check often beats a large structural change.
- Flag anything that would be a **behaviour change** rather than a refactor. Those are the USER's call,
  not an agent's.

## Constraints that make an answer right here

- **The golden turn must stay byte-stable** through any refactor: `tools/validate_headless_turn.gd`,
  seed 20260624. Its `PASS:` line is the source of truth; never quote a pinned number in prose.
- **Dependency ceilings** are enforced by `tools/gd_metrics.py --check-ceiling`, and **every ceilinged
  file is currently at exactly zero headroom** (TurnConductor 20/20, GameState 28/28,
  ReinforcementPhases 22/22, FiresPhases 14/14, TurnClosure 7/7). Raising a ceiling to admit a change is
  forbidden. Any recommendation that adds a dependency to one of those files must say how it pays for it.
  Verify this yourself — run the metrics rather than trusting the numbers above.
- **Tool scripts under `tools/` may not name the `GameData` / `GameState` / `EventBus` autoloads**, even
  transitively through a class they reference — see `tools/validate_tool_script_purity.gd`.
- A **hand-maintained list that will rot is an anti-pattern**; derive from source where possible.
- New mechanics default OFF; behaviour changes are recorded in `docs/DECISIONS.md`.

## Method

Prefer measurement to reasoning. Concretely: grep for the guards and check whether they are *called*;
run `python3 tools/gd_metrics.py . /tmp/out.json` for real dependency numbers; read the two historical
bug commits (`bff4a1c`, `5f79317`) to see what the failure actually looked like rather than how it is
described. If you claim a guard is dead, show the absent caller. If you claim two things can disagree,
name the two write paths that let them.

Where you disagree with the hypothesis above, say so directly and show the code. That is the most
valuable thing you can return.

## Output

Write a single report to `docs/reports/YYYY-MM-DD-source-of-truth-sweep.md` (today's date), structured:

1. **Verdict** — three sentences. Is there a rationalisation worth making, or not?
2. **Inventory table** — entity, where truth lives, shape, what can contradict it, guard, prevents-or-detects.
3. **Violations, ranked by cost of the bug they permit** — with the concrete failure each one allows.
4. **Recommendation per violation** — cheapest fix that removes the risk, and what it would cost.
5. **Explicitly not worth changing** — with the reason, so the next agent does not re-propose it.
6. **What I could not determine** — be honest about the parts you did not get to.

Do not open a plan; the report is the deliverable. If it justifies work, the plan comes after the USER
has read the verdict.
