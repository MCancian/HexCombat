---
title: "0035: Scenario variant inheritance — stop copying the research default"
status: "Sketch"
created: "2026-07-24"
---

# Plan 0035: Scenario variant inheritance

## Golden-pin budget

none

## The problem

A scenario variant is a full copy of its base. `data/scenarios/red_airborne.json` is 43 keys of
`scenario_default.json` differing by **one block**; `roc_full_defense.json` is a similar copy with a
different delta. Every combat coefficient, FEBA parameter, victory block and sealift setting is
duplicated in each file.

For a research instrument this is a correctness risk, not a style preference. **Comparability is the
product.** A batch that runs `scenario_default` against `red_airborne` and attributes the difference
to the air path is only valid if the two differ *only* in the air path — and today that holds by
authorial care, checked by nobody. Dial `combat_base_loss_rate` in the default and the variants
silently keep the old value; the next comparison is quietly measuring two things at once and will
report it as one.

The copies are already drifting-shaped: `scenario_default` carries a `_combat_comment` block of
tuning knobs that `roc_full_defense` and `scenario_golden` simply lack, so those scenarios run on
`GameData`'s hardcoded defaults instead. Whether that is intended is currently unanswerable by
reading the files.

## Shape of the fix

An `"extends": "<scenario-id>"` key resolved at load: read the base, deep-merge the child over it,
and use the result. A variant file then *is* its delta, and "differs only in X" becomes readable and
checkable.

Decisions to settle before building:

- **Merge semantics.** Dict keys merge recursively; what about arrays — replace wholesale, or merge
  by index/id? `placements` and `red_ship_reserve` are arrays where replace-wholesale is almost
  certainly right, but that must be stated, not assumed.
- **Chain depth.** One level, or transitive with cycle detection? One level covers every current
  case; transitive is barely more work and avoids a later migration.
- **Deletion.** Does a child need to *remove* a base key (e.g. drop the whole `green_mobilization`
  block)? A `null` value could mean delete — or that could be banned as too subtle.
- **Interaction with `DataOverrides`.** Overrides address `data/scenarios/<file>.json:<path>` against
  the *file*. If a variant no longer contains the key being overridden (it now lives in the base),
  the override silently misses — and `DataOverrides.unapplied()` would catch it only if it fails
  loudly. **This is the sharp edge of the whole plan**; the knob registry's `scenario:` prefix
  resolution has to be taught about inheritance in the same commit.
- **`scenario_golden` stays standalone.** It is the frozen golden fixture; it should NOT inherit from
  a file that evolves, and that should be stated in the file itself.

## Objectives

1. `extends` resolution in scenario loading, with settled merge semantics documented in
   `docs/systems/` and enforced by `validate_scenario_data`.
2. `red_airborne.json` and `roc_full_defense.json` reduced to their actual deltas.
3. Knob/override path resolution follows inheritance, or fails loud when a path cannot be resolved.
4. A gate check that every scenario resolves to the same content it does today.

## Verification

- **Every existing scenario must resolve byte-identically** to its current fully-expanded content.
  The cleanest proof: dump the resolved dictionary for each scenario before and after and diff.
- Golden byte-stable (`scenario_golden` unaffected by construction).
- Re-run one recorded game per shipped scenario and diff turn digests.
- A deliberately-broken `extends` (missing base, cycle) must fail loud at load, not at first use.
- An override targeting a key that now lives in the base must either apply or fail loudly — never
  silently miss. Test both directions; this is the regression most likely to escape review.

## Risks

- Touches scenario load, which every validator, batch and sweep depends on. Medium blast radius.
- The override/knob interaction is the part that can silently corrupt research results rather than
  crash. If it cannot be made fail-loud, the plan should be reconsidered — a silent miss here is
  worse than the duplication it removes.

## Dependencies / notes

- Independent of 0033 and 0034.
- Related: the plan-0032 study hit a *different* silent-override trap (unreadable overrides file
  reading as "no overrides"), fixed 2026-07-24 in `DataOverrides.load_error()`. Same failure family —
  worth reading that fix before designing this one.
