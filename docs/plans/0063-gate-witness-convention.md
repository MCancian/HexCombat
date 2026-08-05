---
title: "0063: Gate the consumer: / pinned by: witness convention"
status: "Exploring"
created: "2026-08-05"
---

# Plan 0063: Gate the `consumer:` / `pinned by:` witness convention

## Golden-pin budget

none — this is an additive validator (a new check inside `validate_doc_anchors.gd`), not a move in the
turn path. No game-state golden (`validate_headless_turn`, the `validate_cleanup` fingerprint) is
touched. The plan's fixtures are the new in-memory self-test cases in the validator itself, so nothing
external is re-baselined. The one caveat: the new scan is only safe to land because every witness
token currently in the tree resolves (verified, 2026-08-05 — see Diagnosis); if any existing witness
named a dead symbol, landing the pass would go RED immediately, which is the failure we want, but the
gate must pass-by-default on the commit that adds it.

## Goal

BACKLOG item "Gate the `consumer:` / `pinned by:` witness convention" (opened 2026-07-29). Today the
convention is a prose rule in `hexcombat-docs-and-writing` ("a greppable witness for any claim that
something is/isn't consumed, serialized, pinned, or expensive") and has spread to 13 witnesses across
11 `scripts/model/*.gd` headers — with **zero enforcement**. A witness is a claim, and every unfalsified
claim in this repo is a false negative waiting to happen: if `tools/validate_llm_api.gd` is ever
deleted or renamed, the seven `pinned by:` witnesses pointing at it rot silently, exactly like
`RosterMutations` rotted in `docs/systems/turn-engine/turn-engine.md` for six plans before check 4 was
inverted.

Extend `tools/validate_doc_anchors.gd` to resolve the witness's named symbol (a `pinned by:` /
`consumer:` witness must name a symbol that exists on disk / in the class registry), and to enforce
the convention's own date rule on written `none` witnesses. Proven by fixtures in both directions, per
the E_VACUOUS standard.

**Scope boundary (this is the whole discipline of the plan):** this gates the witness convention
ONLY. It does NOT touch the sibling "doc-anchor bare ALL_CAPS symbols" item, the `last_*` transport
dicts, or the off-map pool typing (plan 0062). Those are separate backlog items; folding any of them
in here is scope creep.

## Read these first

| What | Where |
|---|---|
| The validator to extend | `tools/validate_doc_anchors.gd` — header (checks 1–5, the inverted check-4), `_check_doc`, `_check_token`, `_self_test`, `_gd_index` / `_alias_index` / `_index_dir` |
| The convention being gated | `.claude/skills/hexcombat-docs-and-writing/SKILL.md` §"Name a witness for any claim about consumers, boundaries or cost" |
| The fixture precedent to copy | `tools/validate_mutation_authority.gd` E_VACUOUS family + `tools/fixtures/mutation_authority/` README ("a claim no fixture exercises is a claim nobody has checked") |
| The validator that must stay vacuous-safe by a different route | `tools/validate_pool_enumeration.gd` — structural, shape-probe, self-proving |
| The plan-format contract this file must satisfy | `tools/validate_plan_docs.gd` (Golden-pin heading, README row ≤200 chars) |
| How the gate auto-discovers validators | `tools/run_all_tests.py` `Phase 3/4` — every `tools/validate_*.gd` runs; no wiring change needed for a new check inside an existing validator |

## Diagnosis — measured, not assumed (2026-08-05)

### The witness population is real and above the ~10 threshold — but it is narrower than the BACKLOG assumed

`grep -rn "consumer:\|pinned by:" scripts/` → **13 mentions across 11 files**. Classification:

| Class | Count | Files |
|---|---|---|
| (a) `pinned by: <repo path>` | **9** | CleanupSummary, CombatSummary, FrontlineSummary, IjfsWriteback, AntishipSummary, MobilizationSummary, AirInsertionSummary (all → `tools/validate_llm_api.gd`), SealiftHullLossReceipt, SealiftState (→ `tests/transitions/sealift_transitions_test.gd`) |
| (b) `consumer: <ClassName>` | **0** | — |
| (c) `consumer: none (checked <date>)` | **4** | SealiftState, MobilizationState, AirInsertionState, SealiftHullLossReceipt (`none yet`) |
| (d) bare ALL_CAPS / unpinned-to-symbol | **0** | — |
| **Total** | **13** | 11 files |

The precondition threshold is **met**: 13 ≥ ~10. Say so plainly. But say this too: the population is
**more uniform than the BACKLOG hoped**. All 9 positive witnesses name a **file path** (seven under
`tools/`, two under `tests/`), and **none** name a `ClassName.member` or bare class symbol. So the positive-direction
check's real workload is repo-path resolution (the validator's existing check 2/3 machinery), not the
`ClassName.member` branch, and there is exactly one positive ClassName example in the whole tree today
(the skill's teaching example `consumer: OffloadCostModel` — a real class, `scripts/calc/OffloadCostModel.gd`,
which resolves). The fixtures must therefore cover the class branch even though no production witness
exercises it yet — that is precisely a fixture-pinned future case.

### The decisive finding: the witnesses live in source headers the validator does NOT scan

`validate_doc_anchors.gd` builds `_gd_index` from `CODE_ROOTS` (`scripts/`, `tools/`, `tests/`) but
its anchor scan (`DOC_ROOTS` → `_check_doc`) reads only `.md` files under `docs/` and `.claude/skills/`.
**Every one of the 13 production witnesses sits in a `scripts/model/*.gd` header comment**, which the
current scan never reads. Extending the validator to resolve them therefore requires adding a **new
scan pass over `scripts/` comment text** — a genuine domain expansion, and the plan's principal risk
(Trap 1). This is not free: `scripts/model/*.gd` headers are full of backticked tokens (e.g.
`` `mobilization_state.to_dict` ``, `` `mainland_pool` ``) that today are never evaluated as anchors.
The new pass must be **witness-marker-scoped, not full check-2-4 over scripts/** — otherwise those
header tokens become a blast radius of new red.

### Direction P is designable and non-vacuous. Direction N (semantic) is not.

- **P (the named symbol must exist)** — designable, proven by fixtures both ways (below). Reuses the
  validator's existing path + class/member resolution.
- **N ("a `consumer: none` must not sit next to a live reference")** — **NOT cleanly designable in a
  text scanner.** Verifying that a "no consumer" claim is still true requires type-aware call-graph
  analysis (resolve every `to_dict` call site to a `SealiftState` receiver to prove zero callers). A
  text grep is either vacuous (matches nothing meaningful) or false-positive-prone (any other type's
  `.to_dict`, or the word in prose). The closest defensible text-only proxy — "re-run the literal
  search the witness's parenthetical claims it ran" — false-negatives the moment a real consumer spells
  the receiver differently, which is the repo's exact "false negative waiting to happen" failure mode.
  **Therefore the semantic half of Direction N is explicitly out of scope** (Open Questions), and the
  plan delivers the part N that IS non-vacuous: `consumer: none` must carry `(checked <date>)`, which
  enforces the convention's own date rule and turns a bare "unused" (which ages into a lie) into a
  dated claim (which ages into a question).

## The check semantics (the core design decision)

### Scoping rule — marker-anchored, shape-guarded, never bare-symbol

A line is a witness candidate only when it contains the literal marker `pinned by:` or `consumer:`
(colon required — prose "pinned by the fixture" has no colon and is not a marker). Extract the token
immediately following the marker (up to the next whitespace, `,`, `(`, `)`, or `:`). That token is
checked only if it matches a **plausible symbol shape**; anything else is prose, and the line is
ignored (this is the discipline that keeps ordinary prose from false-positiving the way bare `PI` /
`INFINITY` would — see sibling item):

1. **Repo path** — begins with a known root (`scripts/`, `tools/`, `data/`, `tests/`, `schemas/`,
   `docs/`, `.claude/`). Resolve via file-exists / dir-exists (reuse `_truncate_to_file` for
   `path.suffix.key` forms).
2. **`ClassName[.member]`** — matches `^[A-Z][A-Za-z0-9]*(\.[a-zA-Z_][A-Za-z0-9]*)?$`. Resolve via the
   existing `_gd_index` (filename OR declared `class_name`) and, when a `.member` is present, the
   member-exists check. Variant types / ClassDB built-ins / placeholders short-circuit exactly as
   check 4 already does.
3. **`none`** — legal ONLY after `consumer:` (never after `pinned by:` — a pin must name a symbol),
   and only when followed by `(checked <date>`. A `consumer: none` without the date-check fails.

Token extraction is scoped to the token immediately after the marker, so witness-internal prose
backticks inside the `(checked <date>) ...` tail (e.g. `` `air_insertion_state.to_dict` ``) are not
re-interpreted as witness symbols.

### The new scan pass (contained blast radius)

Add `_check_witnesses()`: a dedicated pass that (a) scans `.gd` comment text under `scripts/` **for
witness markers only** (not the existing checks 2–4), plus (b) reuses the existing `docs/` and
`.claude/skills/` `.md` scan so a doc or skill witness is validated too (the skill's own teaching
examples — `consumer: OffloadCostModel`, `consumer: none (checked …)`, `pinned by:
tests/transitions/sealift_transitions_test.gd` — all resolve and must pass). Check 2–4 in `_check_doc`
is left untouched; the scripts/ expansion is isolated to witness detection. This keeps the gate out of
the "every header backtick is an anchor" trap (Trap 1).

### Fixtures — both directions, matching the E_VACUOUS precedent

Land as new `_self_test()` cases (synthetic lines fed through the new `_check_witness_line`), asserting
before any real file is read, exactly as `_self_test` already does for check 4.

**Must FAIL (each names its own reason):**
1. `pinned by: tools/does_not_exist.gd` — a dead-path witness.
2. `pinned by: TotallyMadeUpClass.never_a_member` — a dead ClassName.member witness (proves the class
   branch that no production witness currently exercises).
3. `consumer: SomeMadeUpClass` — a positive consumer witness naming a dead class.
4. `consumer: none` — the negative witness with NO `(checked <date>)` (date rule).
5. `pinned by: none` — a pin that names no symbol.

**Must PASS (each names its own reason):**
1. `pinned by: tools/validate_llm_api.gd` — a real repo path (the production-heavy case).
2. `pinned by: tests/transitions/sealift_transitions_test.gd` — a real test path.
3. `consumer: OffloadCostModel` — a real class, no member (the skill's own example).
4. `consumer: none (checked 2026-07-29)` — a dated legal negative.
5. Prose with the marker words but no colon — `these are pinned by the fixture` → ignored (no marker).
6. Prose with the marker colon but a non-symbol token — `consumer: the observation payload` → token
   `the` is not a plausible shape → ignored (the false-positive guard).
7. A witness-internal backtick `consumer: none (checked 2026-07-29; see `` `x.to_dict` ``)` → the inner
   backtick is not extracted (scope to immediate-marker token).

Deleting the witness resolver, or dropping the scripts/ comment scan root, must both go red — measured,
not assumed (mirrors `_self_test`'s philosophy and the empty-scope guard).

## Approach (steps)

1. **Add the scan**: `_check_witnesses()` over `scripts/` `.gd` comment lines (strip line-leading `#`,
   keep comment bodies; skip `docs/archive`, `(historical)`, RETRO per the existing escape hatches)
   plus the existing `.md` doc/skill scan. Do not touch `_check_doc` / `_check_token`.
2. **Add the resolver**: a `_witness_token(line, marker)` that extracts the immediate token and the
   shape-guard above, delegating resolution to the existing path / `_gd_index` / `_alias_index`
   machinery. Keep the new param count within the gate's 5-param ceiling (the existing `_check_token`
   already at its ceiling — a new function, not a widened signature).
3. **Add the `none` rules**: date-required, and `pinned by: none` rejected.
4. **Fixture it**: extend `_self_test` with the 12 cases above (both directions).
5. **Verify non-vacuous on the real corpus**: count witnesses resolved across `scripts/model/*.gd` and
   the skill — must be non-zero (9 production `pinned by` + 4 `none` + 3 skill examples) and must print
   that count in the pass body, so a future refactor that deletes all witnesses makes the gate fail
   (the empty-scope guard, mirroring `validate_pool_enumeration._pools_seen == 0`).
6. **Gate green** (`bash tools/run_all_tests.sh` — all phases), `validate_plan_docs` PASS, run the full
   validator standalone twice (change-control non-negotiable #4).
7. **Docs closeout**: note the new check in `validate_doc_anchors.gd`'s header (check 6), update
   `docs/systems/<module>/STATUS.md` + a 3–5-line `docs/DECISIONS.md` entry, close out this plan.

## Traps

1. **The scripts-scan blast radius.** `scripts/model/*.gd` headers are dense with backticked tokens
   today. If the new pass runs full check-2-4 over script headers, `mobilization_state.to_dict`
   (lowercase — fails the uppercase class test only if scanned as an anchor), `` `mainland_pool` ``,
   and dozens of other header mentions could all turn red. The pass MUST be witness-marker-scoped.
2. **`(historical)` / `docs/archive` handling.** A witness naming a symbol that was later deleted, in a
   passage describing the past, must be exemptable the way check 4 already exempts `(historical)` /
   `docs/archive` / RETRO lines — otherwise the first legitimately-historical witness is an unfixable
   red. Reuse the existing markers; do not invent a new silencer.
3. **`pinned by: none`.** The convention's own prose says "none" is for consumers. Shim this before
   someone writes a vacuous pin and the gate blesses it.
4. **Pass-by-default.** All 13 production tokens resolve (verified). The commit that lands the gate
   must be green on first run; if it isn't, a witness is already dead and that is a genuine finding to
   surface, not to sweep.
5. **Date discipline, not date-truth.** The date in `(checked <date>)` is asserted present, not
   checked for "correctness" (we have no clock). Do not over-reach into verifying the date is recent.

## Open questions

- **Direction N (semantic "no live reference").** Deliberately out of scope. A text scanner cannot
  verify a "no consumer" claim without type-aware call-graph analysis; the cheapest proxy false-
  negatives when a real consumer renames the receiver. **Unblocks when:** there is a cheap, fixture-
  proveable way to assert the absence of callers for a *specific* typed receiver — e.g. a type-aware
  call-site index we do not have. Until then, the plan enforces only that a `none` witness is dated.
  If a reviewer believes a literal-search proxy ("re-run the exact grep the parenthetical claims")
  is defensible *despite* the false-negative risk, flag it here rather than folding it in silently —
  but note it weakens toward vacuousness the moment a caller spells a variable differently.
- **Scan breadth.** Should the new pass scan all of `scripts/` or only `scripts/model/` where all 13
  production witnesses live? `scripts/` is correct-by-architecture (the convention applies to any
  header), but the fixture population only pins `scripts/model/`. Decision needed at implementation:
  scan `scripts/` broadly now (broader promise, more unexplored header surface = more first-run risk),
  or scope to `scripts/model/` and widen only when a witness appears elsewhere.
- **Docs-side witnesses.** The convention asks for witnesses "inline" in docs and headers; today only
  the skill teaches them in `.md`. The new pass covers `.md` too at zero extra cost, so a future
  doc-side witness is already gated. No action beyond that.

## Residual risks

- The scripts-scan expansion (Trap 1) is the largest new surface; mitigated by marker-scoping and by
  verifying `scripts/` header tokens stay unevaluated.
- Direction N is only half-delivered (date discipline, not semantic truth). The BACKLOG item should
  keep its "none next to a live reference" note as a standing-limits note describing what would unblock
  it, or be re-flagged — see the recommended finding.
- ClassName-branch fixtures pin a behavior no production witness uses today; if the class branch later
  diverges, the fixture (not a real file) is what guards it.
