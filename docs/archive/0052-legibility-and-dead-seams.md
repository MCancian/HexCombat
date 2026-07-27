---
title: "0052: Legibility sweep — an unenforced budget, three dead seams, and the half-finished role layout"
status: "✅ Shipped"
created: "2026-07-27"
shipped: "2026-07-27"
---

> **Closeout:** Shipped 2026-07-27. Durable facts landed in `tools/gd_metrics.py`,
> `docs/STATUS.md`, `.claude/skills/hexcombat-code-quality/SKILL.md`, and the affected systems docs.
> Byte-stable validation: canonical gate green; parameter ceiling now reports/enforces real counts.

# Plan 0052: Legibility sweep — an unenforced budget, three dead seams, and the half-finished role layout

## Goal

Six independent cleanups found while shipping plan 0043, ranked and ordered. Five are legibility or
dead-code removal and must be **byte-stable**; one is a gate fix that makes a documented budget
actually enforced for the first time.

Nothing here changes game behaviour. **If any step moves a pinned fingerprint, stop — you have
found a bug, not finished a refactor.**

Each step is independently shippable and independently revertable. Two couplings, both real:
**step 6 needs step 1** (its fix is unfalsifiable until the counter is honest), and **step 5 must
update step 1's ceiling list** because it moves the files that list is keyed on.

## Settled before you start — do not relitigate

- Every step must end **ALL PHASES GREEN** with **no pin movement**. Run single validators the way
  the gate does (`hexcombat-validation-and-qa` → "Adding a validator" has the exact invocation).
- `scripts/calc/` means *writes nothing that outlives the call*. A file that mutates anything live
  does not go there, however pure the rest of it is (plan 0043 rule).
- Ownership facts live in `tools/mutation_authority_manifest.json`. Moving a file that the manifest
  names **requires editing the manifest in the same commit** — see Trap 1.

## The evidence

Measured on this tree, 2026-07-27. Re-measure rather than trusting these numbers; they are here so
you can tell whether the tree has moved under you.

| Claim | Measurement |
|---|---|
| The param budget is unenforced | 44 functions in `scripts/` + `tools/` over the documented 5-param hard cap; **36 invisible** to `tools/gd_metrics.py` |
| The worst case | `AntishipResolver.resolve` — **12 parameters, metric reports 1** |
| `HexGrid` is dead | zero references in `scripts/`, `tools/`, `scenes/`, `tests/`, `project.godot`, and no `preload` |
| `launch_attrition` is a dead return | read by 2 test files; never reaches `GameState`, `EventBus` or the LLM observation |
| The façade chains are test-only | `GameState._build_warmup_context` → `FiresPhases` → `IjfsResolver`, two hops, one caller (a test) |

An independent count by a second model got 42/34 rather than 44/36 — the difference is counting
convention (whether `tools/` is included, how a default value containing a comma is treated). **Do
not try to reproduce 44.** Record whatever your fixed counter reports as the baseline.

---

## Step 1 — make the parameter budget real (`tools/gd_metrics.py`)

**This is first because nothing else in the parameter category is measurable until it lands.**

`hexcombat-code-quality` documents a ≤4 target and a 5 hard cap on parameters. The counter reads
only the FIRST LINE of a signature:

```python
params = m.group(4)
nparams = 0 if params.strip().startswith(")") else params.count(",") + 1
```

A signature wrapped across lines is therefore counted as 1 — and a long signature is exactly the one
that gets wrapped. So the budget is blind to precisely the functions that breach it. This is the
same failure family as a validator that silently scans nothing: a rule that is documented, believed,
and enforcing nothing.

1. Join the signature across lines until the parens balance, then count top-level commas only —
   **strip nested `()`, `[]`, `{}` first**, or a default like `= [1, 2]` or a type like
   `Dictionary = {"a": 1, "b": 2}` inflates the count.
2. Add a grandfathered allow-list with the same RULE as `DEP_CEILINGS` — an entry is the measured
   count at the commit that set it, and **you never raise one to silence a breach** — but **not the
   same SHAPE**. `DEP_CEILINGS` is `filepath -> limit` and `--check-ceiling` iterates
   `result["files"]`. Parameter counts live per function in `result["functions"]`, so a flat
   path-keyed dict cannot name the offending function. Key it on a composite
   `"path::function_name" -> limit`.
3. **Plumb `--check-ceiling` to iterate `result["functions"]` as well.** It does not today; it only
   walks `result["files"]`. Without this the new list is inert — a ceiling table nobody reads, which
   is worse than no table because it looks like enforcement. Keep the existing stale-entry error
   ("ceiling entry stale — file moved/deleted?") for functions that vanish or get renamed.
4. Seed the list from the real numbers, so the gate goes green immediately and ratchets DOWN as
   later plans fix individual functions.

**Validation.** Assert the counter on all four shapes before trusting it: single-line; multi-line;
a default value containing a comma; a nested-bracket type annotation. The decisive check is
`AntishipResolver.resolve` reporting **12**, not 1. Then confirm `--check-ceiling` still passes.

**Risk.** Turning this on without the allow-list fails the gate on 40+ files at once. Do not "fix"
those functions in this step — the list is the point; step 6 fixes one of them properly.

---

## Step 2 — delete `scripts/HexGrid.gd`

Four one-line delegations to the `GameData` autoload, with **zero callers anywhere**. Same shape as
`scripts/Theaters.gd`, deleted in plan 0043 for the same reason: a façade that re-exposes what an
autoload already holds, which nothing uses.

1. Re-confirm zero references (including `.tscn`, `project.godot` autoloads, and any `preload`/`load`
   by path string — a class with no `class_name` reference can still be reached by path).
2. `git rm` the `.gd` **and its `.gd.uid`**.
3. `godot --headless --path . --import`, then the full gate.

**Risk.** Near zero. If a reference exists that the search missed, the import fails loudly.

---

## Step 3 — drop the dead `launch_attrition` return

`AntishipCalculator.resolve_launch_attrition` returns three parallel arrays. Production reads
`systems_fired` (fed to the crossing) and `outcomes` (fed to the mutation authority).
`launch_attrition` is read by two test files and nothing else — it never reaches `GameState`, the
`EventBus`, or the LLM observation. It is a ledger nobody prints.

1. Remove it from the returned dict and from `_build_attrition_reports`.
2. Repoint the assertions in `tests/antiship_firing_plan_test.gd` and
   `tests/transitions/antiship_establishment_test.gd` onto `outcomes`, which carries the same
   numbers in typed form.
3. **Fix the stale signatures in `docs/systems/antiship-mine.md` (§8 key-functions table, ~line 110).**
   Plan 0043 removed the `systems` parameter from `resolve_launch_attrition` and the doc still shows
   it, and still advertises `{systems_fired, launch_attrition}` as the return. Both are now wrong.

**Risk.** Nit. The only judgement call is whether a human-readable per-(TO,type) ledger is worth
keeping for a future report; the answer is no — `outcomes` carries the same data, typed, and a
report that wants it can format from there.

---

## Step 4 — collapse the test-only façade chains

`scripts/phases/FiresPhases.gd` carries two functions whose own comments say they exist only so a
test can reach them through the `GameState` façade:

```
GameState._build_warmup_context → FiresPhases.build_warmup_context → IjfsResolver.build_warmup_context
GameState._mine_ship_meta       → FiresPhases.mine_ship_meta       → AntishipResolver.mine_ship_meta
```

Two forwarding hops each, existing for one test apiece. **The proof that the direct call works is
already in the tree:** `tests/antiship_resolver_test.gd` calls `AntishipResolver.mine_ship_meta`
directly, while `tests/mine_neutralization_override_test.gd` goes through all three hops — for the
same function.

1. Delete both functions from `FiresPhases` **and** their `GameState` wrappers. Removing only the
   `FiresPhases` hop and pointing `GameState` at the resolvers would ADD dependencies to
   `GameState`, which is ceilinged — do both ends or neither.
2. Repoint `tests/ijfs/ijfs_warmup_context_guard_test.gd` at `IjfsResolver.build_warmup_context`.
3. Repoint `tests/mine_neutralization_override_test.gd` at `AntishipResolver.mine_ship_meta`, and
   **pass it a LOCAL dictionary of synthetic ship defs — do not keep mutating `GameData.ship_defs`.**
   The whole reason that test has a `GameData.load_all()` in `after_test()` is that it swaps
   synthetic hulls into the global autoload and must put it back. The resolver takes `ship_defs` as
   a parameter, so the test can build its own `{name: ShipDef}` and never touch the global at all —
   at which point the restore becomes genuinely unnecessary.
   **Do NOT simply pass `GameData.ship_defs` and then delete the restore.** That combination still
   mutates the global to inject the synthetic hulls and then never puts it back, corrupting
   `GameData.ship_defs` for every test that runs afterwards in the same process. Local dict first,
   restore removed second, in that order — or leave the restore alone.
4. Re-measure `ndeps` for `GameState` and `FiresPhases`.

**Be honest about the payoff: this is legibility only, not headroom.** Both files name those
resolvers elsewhere, so neither dependency count is expected to fall. The win is that production
code stops carrying a shape that exists for test access.

---

## Step 5 — finish the role directories

Plan 0043 created `scripts/{phases,builders,calc,transitions}/` but stopped at the anti-ship files.
`scripts/` root still holds calculators and loaders. **A half-applied taxonomy is worse than none**:
a reader who learns the rule from `calc/` will assume everything outside it is *not* a calculator.

Two directories, two commits.

**5a — `scripts/calc/`.** The directory's whole claim is that its files write nothing live, so each
candidate has to be PROVEN, not assumed. Checked 2026-07-27:

| File | Verdict |
|---|---|
| `CombatCalculator` | **qualifies** — its writes are on `var result := CombatResult.new()` and on `var off_map := attacker_support.duplicate()`, i.e. a fresh result and a COPY |
| `OffloadCostModel` | **qualifies** — no writes of any kind |
| `DosConsumption` | **qualifies** — writes only into locals (`var by_brigade: Dictionary = {}` and friends) |
| `OffloadCalculator` | **DOES NOT QUALIFY** — mutates the caller's live battalions: `bn["offload_progress_tons"] = …` and `bn.erase("offload_progress_tons")` on `brigades_at_sea` entries. Leave it in `scripts/`. |
| `ShipLoadingModel` | **DOES NOT QUALIFY** — `bn["ship_category"] = category` on the `bns` array passed into `pack_bns_into_hulls`. Leave it in `scripts/`. |

**Read this before screening anything yourself.** The first draft of this plan cleared all five,
because the screen only matched dot-access writes (`x.field = …`) and GDScript's other write form is
a **Dictionary subscript** (`x["key"] = …`, plus `.erase()`). That blind spot hid 17 writes in
`OffloadCalculator` and 5 in `ShipLoadingModel` — the exact two files that turned out to be
disqualified. A purity screen that does not match `recv["key"] =` and `recv.erase(` is not a purity
screen. (This is the same lesson `tools/validate_mutation_authority.gd`'s header already records
about write FORMS; it is easy to forget when writing a throwaway grep.)

**5b — `scripts/loaders/` (new).** `AntishipLoaders`, `ScenarioCatalog`, `DataOverrides`. These are
NOT calculators and must not go in `calc/` — the distinction is that a loader produces objects from
content files, which is why `AntishipLoaders` is a *construction writer* in the mutation manifest.
(This correction came from review; the first draft of this plan wrongly lumped them together.)

Each commit: move `.gd` + `.gd.uid` together, update path citations in `tools/`, live `docs/`, and
skills (archive keeps its historical paths), `godot --headless --path . --import`, full gate. Keep
class names unchanged.

**Update step 1's parameter-ceiling list in the same commit.** Its keys start with the file path, so
moving a file makes every entry for it stale and `--check-ceiling` fails exactly the way a moved
`DEP_CEILINGS` entry does. This is the gate working; it is also the one way step 5 can break the
"no step breaks the gate" promise, so do it in the move commit, not after.

### Trap 1 — moving `AntishipLoaders` breaks the mutation manifest

`tools/mutation_authority_manifest.json` names it by exact path as the construction writer for
`AntishipSystem`:

```json
"path": "res://scripts/AntishipLoaders.gd"
```

Move the file without editing that line and `tools/validate_mutation_authority.gd` fails with
`E_DEAD_PATH`. Update the manifest **in the same commit** — this is the gate working correctly, not
an obstacle.

---

## Step 6 — a typed context for `AntishipResolver.resolve` (12 parameters)

`hexcombat-code-quality` prescribes exactly this on a parameter breach: *"pass a typed context
object (`scripts/model/`)"*. `resolve` takes 12.

**Do this after step 1**, or you cannot demonstrate the breach is fixed — the metric currently
reports 1 either way, so a "fix" here is unfalsifiable until the counter is honest.

Group the arguments by what they are, not by what fits: the crossing wave (`crossing_reserve`,
`sent_by_type`), the establishment (`antiship_systems`), the world (`ship_defs`, `beach_to_to`,
`active_tos`, `to_adjacency`), and the carried state (`lost_at_sea_accumulator`, `escort_sam`).
`turn_number` and `dice` stay as explicit arguments — a reader should be able to see the turn and
the RNG source at the call site without opening a struct.

**Risk.** This is the hot path of a golden-pinned phase. Pure re-shaping of arguments, so the
acceptance test is a **byte-stable gate with no pin movement**; if anything moves, an argument
changed meaning in transit.

---

## Explicitly out of scope (checked, don't re-raise)

- **Moving `AntishipResolver.remaining_reserve_after_losses` into `RosterMutations`.** It was the
  original idea #2 and it is dropped. `ship_reserve` is claimed by **plan 0045**, which would
  immediately move it again; and while `RosterMutations` already *reads* the reserve
  (`apply_crossing_casualties`), it *writes* the OOB — adding a reserve-writer changes its character
  right before 0045 assigns that state a proper authority. It stays where it is, and
  `AntishipResolver`'s header already records that this is what keeps the file out of `calc/`.
- **Extracting the `if dice is SeededDice: … derive(…)` substream boilerplate.** Only TWO copies
  (`FiresPhases`, `IjfsResolver`), below this repo's "third copy = extract" rule.
- **Deleting `AntishipMagazine` / `IndividualShip`.** Dormant BY DESIGN, named in plans 0002 and
  0045. Zero references is not the same as dead when a plan owns the wiring.
- **Unifying the four validator comment-strippers.** `BACKLOG.md` records a measured 2026-07-26
  decision not to, with the reasons. The `_fail`/`_finish` harness dedup remains separately open.
- **`IjfsResolver.apply_maneuver_casualties` bypassing the roster seam.** Real divergence, and
  reviewer-flagged: it decrements `battalion.qty` but never removes a zero-qty battalion from
  `composition`, and never calls `GameData.remove_brigade_from_map` when a brigade is wiped out.
  It is **not this plan's**, for two reasons. (1) `docs/plans/0044-force-mutation-authority.md`
  already owns it by name — *"Replace `RosterMutations.apply_casualty` and IJFS's independent…"*.
  (2) Fixing it is a **behaviour change**: removing zero-qty entries and de-indexing destroyed
  brigades moves combat contributor sets and the census, so pins move. Doing that under a
  legibility banner is exactly what change control forbids. Backlogged with the specifics so 0044
  does not have to rediscover them.

## Review record (2026-07-27, pre-implementation)

Ideas reviewed by `agy-explore` and `opencode/deepseek-v4-flash-free` before this plan was written.

- **opencode** wrote its own independent parameter counter and reproduced step 1's premise (42/34
  against my 44/36 — same conclusion, different counting convention). It returned no narrative
  findings: useful as an *explorer*, consistent with its measured 0/3 record as a reviewer.
- **agy** returned six verdicts. Three changed this plan: original idea #2 dropped (above); step 5
  reshaped after it caught loaders being wrongly filed as calculators; step 4's "remove both ends"
  requirement made explicit. Its ceiling argument for step 4 rested on a different implementation
  than intended, but its recommendation and mine converged.
- agy's "missed item" (the IJFS casualty divergence) is real but **already owned by plan 0044** — it
  had not read the plan index. Recorded in `BACKLOG.md` as evidence for 0044 rather than actioned.

A second `agy-explore` pass reviewed this plan AS WRITTEN, in the "what will a weaker implementer get
wrong" role. Four findings, all verified against the tree and all folded in above:

1. **Step 4 would have corrupted global test state.** Passing `GameData.ship_defs` and then deleting
   the restore leaves the synthetic hulls in the autoload for every later test in the process. The
   step now says: local dict first, restore removed second, or leave the restore alone.
2. **Step 5 breaks step 1's ceiling list** by moving the files it is keyed on. Now an explicit
   instruction in the move commit.
3. **The ordering claim was wrong** — the plan said only step 6 depended on an earlier step.
4. **Two `scripts/calc/` candidates were misfiled** (`OffloadCalculator`, `ShipLoadingModel`), and
   the reason is instructive enough to be worth keeping: the screen that cleared them matched only
   dot-access writes and missed Dictionary-subscript writes entirely.

It also caught that step 1's allow-list could not work as first described — `--check-ceiling` walks
`result["files"]`, and parameter counts are per function.

## Closeout homes

Steps are self-contained; most need only a commit message. On completion: `docs/STATUS.md` if the
directory layout description changes (step 5), `hexcombat-code-quality` for the new parameter
ceiling list (step 1), `docs/systems/antiship-mine.md` for the corrected signatures (step 3), and a
single `docs/DECISIONS.md` entry only if step 1's ceiling list is worth recording as a convention.
No report — nothing here changes outcomes.

## Dependencies

Step 6 requires step 1. Nothing else is ordered by necessity; the sequence is by risk and payoff.
Independent of plans 0044–0051, except that step 5 must not run concurrently with a plan that is
moving the same files.
