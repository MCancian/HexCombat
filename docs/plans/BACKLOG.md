# HexCombat — Tech Debt & Hygiene Backlog

> **Read budget.** `grep -n '^- \[ \]' docs/plans/BACKLOG.md` lists every OPEN item's headline.
> That grep is now exact: every open item carries a checkbox and nothing else in this file does.
> (Before the 2026-08-01 triage it undercounted by four — items written as bare `- **Bold.**` were
> invisible to the documented command, and two sub-items were malformed as `-[ ]` / `- [ ]Text`.)
> Read an item's body only if you are about to act on it.
>
> **Items under "Standing limits & blocked" are deliberately NOT checkboxed.** They are notes, not
> work: each is either a rule to follow rather than a defect to fix, or is waiting on something that
> does not yet exist. Each says what would turn it into work. Do not open a plan for one without
> that precondition.

This document is strictly a place for agents to dump observations of tech debt, hygiene issues, and necessary refactors encountered during development.

Focused multi-session efforts (features, content, balancing) get a numbered plan in the `docs/plans/` directory and are tracked in [README.md](README.md).

## Items that travel together

Bundled 2026-08-01. These are not dependencies — each item stands alone — but doing a bundle's
members separately means editing the same file, schema or gate two and three times, and in one case
means writing prose you then have to un-write.

| Bundle | Items | Why together |
|---|---|---|
| **LLM action vocabulary** | JLSF team, duplicate `deploy_jlsf`, order-kind dispatch | All three edit `schemas/llm_action_response.schema.json` + `LLMGameAPI` + `GameState._apply_order`. The dispatch item's proposed gate check is exactly what would have caught the JLSF-team hole. |
| **LLM fixture byte-stability** | seven summary headers, fixture drift check | **Order matters.** The headers item proposes weakening seven headers to admit the gate only checks key presence; the drift item (USER-approved) makes the gate actually check drift. Do the drift check FIRST and the headers item collapses to naming a now-true witness. |
| **Review tooling** | opencode read-only, numbered findings, `--format json` | All touch `tools/review_fanout.sh` / `.claude/REVIEWERS.md` / opencode config, and `tools/validate_reviewer_facts.gd` gates roster edits — one commit is cheaper than three. The last two already say "do them together". |
| **Validator proof surfaces** | `--census` flag, preload-alias blindness, `E_STALE_ALLOWANCE` | The first two both modify `tools/validate_authority_call_placement.gd` and both need a self-test case in the same commit. The third is the same shape (a check nothing exercises) on a different validator. **Keep the validator-harness dedup OUT** — a 30-file sweep riding on a capability change is how scope drifts. |

Three open items are blocked only on a USER design call and can be answered in one sitting: duplicate
`deploy_jlsf`, which number `losses_today` should carry, and wire-or-drop the combat advantage ratios.

## Deferred Debt & Hygiene Items

*(Agents: append new technical debt and hygiene observations here. One `- [ ]` per item — the read
budget above depends on it. If the observation is a standing rule or is blocked on something absent,
put it in the section below WITHOUT a checkbox and say what would unblock it.)*

- [ ] **The applies/pure CENSUS scan is still prose in two homes.**
  Only the pass/fail half became a tool (plan 0055, 2026-07-31). `.claude/skills/hexcombat-structure-map` asked whoever implemented 0055 to
  promote its `grep`-based census to a real script under `tools/`, because the comment-stripping detail
  is load-bearing and was being kept in two copies. **Half of that happened and half did not.**
  `tools/validate_authority_call_placement.gd` now owns the *verdict* — is any file in a forbidding
  directory calling an authority, and has any `interleaved/` file gone inert — and derives its authority
  list from the manifest. What it does NOT emit is the census: per-file counts, which is what the skill
  needs to regenerate the structure map and what a future plan needs to re-derive a table. So the `grep`
  still lives as prose in the skill. The cheap fix is a `--census` flag on the existing validator that
  prints `path count authority,...` and exits 0, letting the skill call it instead of restating it.
  Not done here because the validator's own commit was already the plan's last step and adding an output
  mode is a separate, testable change.
- [ ] **`IjfsLedgers` applies MANPADS initialization transitively while living in `scripts/calc/`.**
  Found by plan 0061's generated effect map. `IjfsLedgers._manpads_totals` calls
  `IjfsManpads.ready_systems_by_to`; that reaches `systems_remaining`, whose lazy first read calls
  `set_remaining` and then `IjfsTransitions.set_manpads_remaining`. The direct-call placement gate
  cannot see this transitive authority path, so the `scripts/calc/` claim (“applies no campaign state
  by any route”) is false whenever a MANPADS bin has not yet been seeded. Hoist seeding to the IJFS
  build/day boundary or make the query non-mutating; then pin that a ledger-only call leaves state
  byte-identical. Do not move the reporter to `interleaved/`: reporting has no draw-point reason to
  apply state.
- [ ] **The authority-call detector is blind to an ALIASED receiver.**
  So a FORBIDS file could call an authority under another name (found 2026-07-31 by the Sol diff-review role on plan 0057; a standing
  limit of the detector, NOT a regression). `tools/validate_authority_call_placement.gd` matches the
  literal manifest class name as the receiver:
  `regex.compile("(?<![A-Za-z0-9_])%s\\.[a-z_][a-z0-9_]*\\s*\\(" % authority)`. A file that does
  `const FT = preload("res://scripts/transitions/ForceTransitions.gd")` and then calls `FT.apply_x()`
  matches nothing — the path string is removed by `_strip`, and the local receiver name is not the
  manifest class name. The detector's self-test has cases for comments, strings, longer identifiers
  and constant reads, but **none for a preload alias**, so the hole is not even pinned as known-open.
  **Not fixed in 0057** because it is new detector capability rather than the placement layout that
  plan was about, and because it needs a design call first: the cheap version tracks
  `const X = preload("<authority_path>")` and treats `X` as an authority receiver, which is bounded
  and testable; the general version is local alias analysis, which is not. Do the cheap version, and
  add the self-test case for it in the same commit. Weigh against how the codebase actually calls
  authorities today — every current call site uses the bare class name, so this is prophylactic, which
  is also why it is worth doing while it is still cheap and not a migration.
- [ ] **`E_STALE_ALLOWANCE` is the one mutation-manifest check with no proof surface.**
  Found 2026-07-30 by the DeepSeek enumeration role; pre-existing, not a regression. Every other manifest-check code
  is either declared by a `bad_manifest_*.json` fixture or perturbed by a `_capture_failures`
  self-test. `tools/validate_mutation_authority.gd`'s `_report_stale_allowances` is not: it is the
  only emission site, and nothing exercises it. So if a construction or legacy writer outlives its
  last write, nothing proves the gate would say so. It cannot use the existing broken-manifest harness
  — `_check_manifest_error_fixtures` runs only `_check_manifest` + `_build_ownership`, never `_scan`,
  and a stale allowance is only visible after a scan produces a Verdict. It needs the same treatment
  `_check_inert_authority_fixture` got: re-judge the fixture findings against a doctored usage record.
- [ ] **A Green LLM seat can deploy Red JLSF cargo.**
  Found 2026-07-31 by the Sol diff-review role on plan 0049 commit 3; PRE-EXISTING, not a regression. `deploy_jlsf` has no team in the action
  schema (`schemas/llm_action_response.schema.json`), `LLMGameAPI._apply_deploy_jlsf_action` parses
  none, and the façade `GameState.add_jlsf_order` hardcodes `Brigade.Team.RED` — exactly as the
  pre-0049 code hardcoded it when calling the private `_apply_order`. `OrderValidator.check_jlsf_order`
  now HAS a `TEAM_MISMATCH` arm, but nothing on the LLM path can ever reach it, and both seats buffer
  through the same unlabelled path in `SelfPlayRunner`. Plan 0049 deliberately did not fix it: the fix
  requires adding `"team"` to the action schema, which is "new action-schema vocabulary" and explicitly
  out of that plan's scope. Fixing it means threading seat identity through `SelfPlayRunner` so a Green
  seat cannot claim Red. Worth doing before any research run where both seats are live LLMs.
- [ ] **Order-kind dispatch lives in three places.**
  `GameState._apply_order`, `LLMGameAPI.apply_agent_response`
  and `schemas/llm_action_response.schema.json` each enumerate the order kinds independently. Adding
  `air_insert` (plan 0032) meant editing all three, and the duplication had already rotted: `deploy_jlsf`
  was missing from the schema until 2026-07-24. Give the kinds one home and derive the dispatch (or at
  minimum add a gate check that every dispatch arm has a schema variant and vice versa).
- [ ] **The LLM result fixture is key-presence-checked, not drift-checked (found 2026-07-29).**
  `tools/LLMFixtures.gd:7` records "the rot that left `llm_result_after_turn.json` stale" as the reason
  that generator exists — but the current check (`validate_llm_api.gd:271-277`) cannot catch that rot
  returning: a fixture with all the right keys and stale VALUES passes. Adding a real drift comparison
  is a gate change with a re-baseline decision attached (the fixture would then move whenever any
  summary's payload legitimately changes). **USER call 2026-07-29: re-baselining is acceptable — build
  the real drift comparison.** So the trade is settled; what remains is implementation, and the fixture
  regenerator (`tools/LLMFixtures.gd`) is the intended way to move it rather than hand-editing.
- [ ] **Seven summary headers promise byte-stability the gate does not check.**
  Found 2026-07-29, witness sweep. `CleanupSummary`, `CombatSummary`, `FrontlineSummary`, `AntishipSummary`,
  `MobilizationSummary`, `AirInsertionSummary` and `IjfsWriteback` each say `to_dict()` is "the
  JSON-serialization boundary … so golden/observation fixtures stay byte-stable". The boundary half is
  TRUE — all seven land in `turn_result` in `docs/examples/llm_result_after_turn.json` (verified: that
  fixture's `turn_result` holds `air_insertion_summary`, `antiship_summary`, `cleanup_summary`,
  `combat_summaries`, `frontline_summary`, `ijfs_summary`, `ijfs_writeback`, `mobilization_summary`,
  `offload_summary`). The byte-stability half is NOT: `tools/validate_llm_api.gd:271-277` only checks the
  fixture HAS the required top-level keys — no value or key-order comparison. Fix: name the witness in
  each header per `hexcombat-docs-and-writing` ("pinned by: …, which checks key presence only").
  **Do the drift-check item above FIRST** — if the gate gains a real value comparison, these headers
  become true as written and this item reduces to naming the real witness instead of documenting a hole.
- [ ] **`docs/plans/` is excluded from the doc-anchor gate, so an ACTIVE plan's code references rot silently.**
  Found 2026-07-31 while widening the gate; accepted trade-off, not an oversight. Plans are
  excluded because a proposal legitimately names classes it intends to CREATE — failing a plan for
  describing its own work would make the gate an obstacle to planning. The cost is the other half: a
  Sketch that cites six real files (0055 does) rots the moment one is renamed, and the agent who picks
  it up follows a dead reference. The symmetric fix is a `(planned)` line marker beside `(historical)`
  and `(upstream)`, then removing the exclusion — but turning it on means triaging every active Sketch
  at once, several of which predate two refactor campaigns. Do it as its own unit of work, not as a
  rider on something else.
  **Scope narrowed 2026-08-01 by measurement — a second item claiming "`docs/*.md` has no anchor gate"
  was merged in here and was already mostly stale.** `tools/validate_doc_anchors.gd` was widened on
  2026-07-31: `DOC_ROOTS` is now `["res://docs", "res://.claude/skills"]`, so `docs/STATUS.md` and
  `docs/DECISIONS.md` ARE anchor-checked today, and the `(historical)` marker work that item said had
  to come first was done as part of that widening. What remains excluded is `DOC_ROOT_EXCLUDES`
  (`docs/archive/`, `docs/plans/`, `docs/reports/`) plus `HISTORY_DOCS` (`docs/RETROSPECTIVES.md` and
  two skills). Of those, only **`docs/plans/`** is the accidental gap this item is about; archive,
  reports and RETROSPECTIVES are deliberate — each is a point-in-time record where a dead anchor is
  correct. Note check 5 (doc-to-doc `docs/plans/<name>.md` pointers must resolve) already applies
  everywhere with no escape hatch, so plan *filenames* are gated; only the code references inside a
  plan are not.
- [ ] **Validator harness: `_fail` / `_finish` / asserts are copy-pasted across the validators.**
  Found 2026-07-25, refactor review. Measured: `func _fail` in **30 of 36** `tools/validate_*.gd`,
  `_finish` in 31, `_assert_equal_int` in 12, `_assert_true` in 11. A `tools/ValidatorHarness.gd`
  owning the assert vocabulary would remove the duplication. **Note the claim that failed review:**
  this does NOT fix the gate-hang class — a script that fails to COMPILE never runs, harness included
  (caught by agy-explore; two other models wrongly agreed it would). That hole is closed separately by
  `--quit-after` in `run_all_tests.py`. So this is deduplication only, worth doing when validators are
  being touched anyway, in slices of 5-6 with the gate green between. Good `opencode` delegation.
- [ ] **`data/ijfs/grouped_targets.json` is orphaned AND now factually wrong.**
  Found 2026-08-01 by the plan-0060 diff review, and confirmed by measurement: a scan of `scripts/`,
  `tools/` and `tests/` finds ZERO readers, so `docs/systems/ijfs/ijfs.md`'s old "used by validation
  scripts" claim was false (that line is now corrected). Worse, its `groups[].replaces_target_ids`
  still names `sam_mobile_antelope_to2`..`_to5` — the four TO-split source rows plan 0060 R10
  consolidated into one 50-instance row with a `to_distribution`. So the file describes a target
  topology that no longer exists and nothing would notice.
  **Not deleted as part of 0060**, deliberately: removing a content file is a USER call about what
  the project keeps as design record, not an implementation detail of an air-attrition plan. Either
  delete it, or re-point it at the new source ids and give it a reader that the gate exercises — a
  data file with no reader is a data file that cannot be wrong out loud.

- [ ] **The `turn_result` schema is now gated on KEY PRESENCE only — the nested shapes are still unchecked.**
  Opened 2026-08-01, replacing the five-field drift item, which is FIXED. The drift
  itself is closed: `air_insertion_summary`, `mobilization_summary`, `offload_summary`, `game_over` and
  `winner` are declared, and `tests/turn_result_serialization_test.gd` now fails if any `TurnResult`
  key is absent from the schema. What that check does NOT do is verify the other direction (a schema
  property with no model field) or any nested shape: `air_oob` is declared as bare
  `{"type": "object"}`, so a future loss of `model_version`, `squadrons`, `kind` or a counter's type
  would not register as a contract violation. Worth doing when the turn record is next treated as a
  durable research contract rather than a convenience payload — and note the same
  presence-not-shape weakness is what the LLM fixture drift-check item above is about.
- [ ] **Nothing enforces `sweepable`, so the flag records intent and no more.**
  Measured 2026-08-01 while marking the combat advantage ratios `false`. `tools/run_sweep.py` never consults the knob registry;
  the only code that touches the field is `tools/validate_knob_registry.gd`, which checks it is a bool
  and that a `kind` knob is not sweepable. So a `sweepable:false` knob can still be swept via
  `DataOverrides` and nothing complains. Two checks are wanted and they are NOT the same:
  (a) **a `sweepable:true` knob whose override does not actually apply should fail** — this is the
  original 2026-07-23 item, and it would have caught the phantom `offload_beach_base_rate` path;
  (b) **a `sweepable:false` knob that is swept anyway should be refused** — which is what would make
  the advantage-ratio decision real rather than advisory.
  **Note (a) would NOT have caught the advantage ratios**, which is why both checks are listed: their
  override *does* apply — it changes the `result` label in the record. A check that only asks "did
  anything move?" sees them move and passes. Only (b) expresses "this knob must not be a study
  variable".
- [ ] **`UnitStats.FALLBACK_CATEGORY_DEFS` reachability is unknown.**
  90 entries, and NO composition entry in either OOB declares a `category` — the table is reachable only through `_fallback_category_for_type`'s
  type-name heuristics. Plan 0032 anchored two new airborne strengths on entries that were dead until
  then. Instrument `_fallback_category_for_type` over both OOBs, list the keys actually hit, and delete
  or document the rest. Do NOT delete on inspection alone; the matching is indirect.
- [ ] **`OffloadCalculator` applies campaign state through a handed dict, so it cannot go to `scripts/calc/`.**
  Scoped as plan 0058, PLAN FILE NOT YET OPENED (found 2026-07-31 preflighting 0057; PRE-EXISTING, not a regression). This entry is currently the only home of 0058's preflight
  measurement — `docs/plans/0058-*.md` does not exist. Do not delete it until that file does.
  `scripts/OffloadCalculator.gd:259` banks leftover tonnage into
  `bn["offload_progress_tons"]`, `:244` erases it on landing, `:241` reads it back a turn later. The
  dicts are live campaign state the whole way down with no `duplicate()`:
  `ReinforcementPhases.gd:165` passes `state.ship_reserve` → `OffloadResolver.gd:63` appends the same
  entries into `troop_reserve` → `:68` hands them to `resolve_offload_day`. The field is cross-turn
  persistent **by design** — it is the plan 0006 C8 fractional-flow carry-over, not an accident — so
  the fix is to hoist the write, not to delete it. This fails the `calc/` test on its "**or through
  arrays/dicts it was handed**" clause, and `tools/validate_authority_call_placement.gd` **cannot see
  it**: that validator detects direct authority calls, and this is a bare dictionary write. Note
  `OffloadResolver` already sits in `calc/` and applies transitively through this helper.
  **This is the bounded instance of the aliased-container blind spot** logged under Standing limits —
  and a data point toward the measurement that note says would make the general case actionable. Unlike
  the general case it IS bounded: one field, one writer, one owning aggregate (`ship_reserve`, owned by
  `ForceTransitions`). Shape of the fix: `OffloadCalculator` returns banked-progress deltas in its
  manifest and `ForceTransitions.apply_offload` — which already receives both the reserve and the
  force request at `ReinforcementPhases.gd:169` — performs the write.
  **The deferrability question is half answered, and the answer is the awkward one.** `ordered_ids` CAN
  repeat a brigade id: `OffloadCalculator.gd:104-107` appends every id in `priority_order` that is in
  `brigade_map` with **no dedup check**, and only the second loop (`:108-111`) tests
  `bid not in ordered_ids`. Upstream, `OffloadResolver.priority_order` (`:22-27`) emits one id per
  reserve ENTRY, not per brigade. So if two `ship_reserve` entries ever carry the same `brigade_id`,
  that brigade is processed twice in one `_resolve_day_n`, its BNs' banked value is read back within
  the call, and the write is **not** freely deferrable — which would make this an `interleaved/`
  candidate rather than a hoist. (Independently reached by the Sol plan-review role, 2026-07-31.)
  Note `brigade_map[bid] = brigade` at `:100` also keeps only the LAST entry per id, so a duplicate
  would additionally drop a reserve entry's own BN list — **if duplicates are reachable, that is a latent double-processing bug independent of any file move, and 0058 should open there.**
  **Measured, and it resolves the other way — the hoist IS the right shape.** `ship_reserve` holds at
  most one entry per `brigade_id` by construction: `ForceTransitions._merge_reserve_entry` (`:857-862`)
  searches for an existing entry with the same `brigade_id` and **merges the BNs into it**, appending a
  new entry only when none matches. So the duplicate path above is unreachable on the embark route, no
  banked value is read back within a `_resolve_day_n` call, the write is freely deferrable, and 0058
  should hoist into `ForceTransitions.apply_offload` rather than re-home the file to `interleaved/`.
  Two residual notes for whoever opens it: the dedup is an invariant of the *authority*, not of
  `OffloadCalculator`, which still has the un-deduped loop and would double-process if ever handed one
  — worth an assert rather than a rewrite; and `ShipReserveBuilder.gd:33` appends one entry per
  scenario row without a dedup check, so malformed scenario content is the one way in.
  Golden exposure is still real (offload sequencing), so this needs its own gate run and must not ride
  on a path move.
- [ ] **DeepSeek's strength is narrower than "bounded enumeration" — it needs the material HANDED to it.**
  It times out on multi-module call-chain tracing (measured 2026-08-01, two flakes). The roster
  records 3/3 as a bounded enumerator, which is true but under-specified. Measured across four
  invocations in one session: **succeeded twice** when given material to read — a committed plan file
  (16.3 KB return) and a frozen diff (23.9 KB, and it caught a second `model_version` pin nobody else
  did. **Failed twice**, `exit 124` with ZERO bytes at both 15 and 25 minutes, when asked to trace
  reads/writes through five modules (`IjfsEngagement`, `IjfsManpads`, `IjfsDetection`, `IjfsStrike`,
  `IjfsTransitions`) — open-ended exploration needing many tool calls. Narrowing the brief between the
  two attempts changed nothing, so it is the task SHAPE, not the wording. A trivial probe returned `OK`
  in seconds immediately afterwards, so the route was alive throughout.
  **So: give DeepSeek a document and ask it to enumerate what is IN it; give `agy-explore` anything
  that requires finding the material first** — its own contract lists "mapping deps; tracing a flow" as
  what it is for, and its measured record is 4/4 substantive. Fold this into `.claude/REVIEWERS.md`'s
  "Use it for" column next time that file is edited; it is a sharpening of an existing row, not a new
  fact needing its own home.
  **And note how the failure presents:** `opencode` buffers until exit, so a timeout leaves an empty
  file and a wrapper that can still report success. The only signal is exit code 124. An empty return
  read as "reviewed, nothing found" is the exact flake-is-not-a-pass trap.
- [ ] **Reviewer read-only is still a prompt, not a sandbox — opencode can enforce it.**
  Found 2026-07-30, plan 0054; USER raised the config route. `opencode` supports per-agent permissions
  (`opencode.json` → `agent.plan.permission`), so `"edit": "deny"` would make read-only ENFORCED for the
  DeepSeek route instead of merely requested in prose — the hole `.claude/REVIEWERS.md` § Safety
  currently just warns about. Measured context: `external_directory` defaults to `ask`, and an "ask" in
  a non-interactive opencode invocation is auto-rejected, which is why that reviewer read no artifact for
  four rounds. **Do NOT use opencode's `--auto` flag** as the fix: it approves everything not explicitly denied,
  including `edit`, and these models have been measured announcing a fallback from the read-only agent to
  the writing `build` agent. Verify any change by having the `plan` agent attempt an edit and watching it
  be denied. Global `~/.config/opencode/opencode.json` currently has no `permission` block at all.
- [ ] **A reviewer brief should demand NUMBERED findings from every role, including nil returns.**
  Found 2026-07-30, plan 0047 steps 4-7 round. `tools/review_fanout.sh --report` scores a return
  `FLAKE` on "no numbered findings", which is right as a default — a died-early route is
  indistinguishable from approval. But that round produced two genuine returns it could not count: the
  tier-1 reviewer's 342-byte "no actionable findings" (a real read: it named a non-equivalence and two
  ABSENT determinations) and the enumerator's 34 KB of correct verbatim lists (an enumeration role
  produces lists, not findings). Auto-count said 1 of 2 and "hold uncommitted"; the quorum was in fact
  met, on content. **The cheap fix is in the BRIEF, not the launcher:** require every role to answer as
  a numbered list, with "1. No defect found — here is what I checked and what I concluded" as a legal
  entry, and require an enumeration role to number its lists. Then the mechanical count matches reality
  and no agent has to reason its way past a `QUORUM NOT MET` line. Pairs with the `--format json` item
  below; do them together if either is touched.
- [ ] **DeepSeek's return is unparseable by the byte band because its stdout contains noise.**
  Its stdout is prompt echo + tool traces + report (found 2026-07-30, plan 0047; USER raised it). Both plan-0047 rounds were
  substantive enumerations (23.6 KB and 14.7 KB) and both were labelled `SUSPECT` on size alone, so a
  future agent may discard a good return — one of them held the only catch of its round. **The fix is
  `--format json`** on the opencode route (it emits raw JSON events), plus a `tools/review_fanout.sh`
  change to extract the final assistant message, plus the gated invocation row in `.claude/REVIEWERS.md`
  updated in the same commit or `tools/validate_reviewer_facts.gd` goes red. **Do NOT instead ask the
  reviewer to write its report to a file:** it contradicts the `REVIEW ONLY` line the launcher prepends,
  `--agent plan` has been measured not honoured by some opencode models, and the only writable location
  is inside the worktree — which is the measured cross-contamination incident in `~/.claude/AGY.md`
  (one reviewer's artifact read off disk and returned verbatim by another as fake corroboration).
  Note an enumeration return is legitimately long even once the noise is stripped, so the 1–10 KB band
  needs a role-aware exception either way.
- **A typed turn-resolution outcome carrying all phase reports — proposed by the tier-1 reviewer during
  plan 0059's review, and MEASURED DOWN rather than adopted (2026-08-01).** The idea: instead of each
  phase writing a report onto `GameStateData` and `GameState.play_turn` reading eleven fields back out,
  `TurnConductor` returns one typed outcome carrying them all. It is a genuinely better shape in the
  abstract, and it is **not worth doing here** for a reason that only shows up when you count the
  fields. Of the eleven `phase_output` fields on `GameStateData`:
  - **Five are read by `LLMGameAPI` at PLANNING time, between turns** — `last_ijfs_summary`,
    `last_antiship_summary`, `last_combat_summaries`, `last_contested_hexes`, `last_ijfs_writeback`.
    A resolution outcome exists only from resolve until `play_turn` returns; these are read long after
    that, when a seat builds its next observation. **They must stay on the state whatever happens**, so
    a typed outcome cannot replace them — it runs in parallel with them.
  - **Seven are read by a later phase**, which is genuine cross-phase state; the architecture contract
    routes exactly that through `GameStateData` fields on purpose.
  - **Three are transport-only** — `last_offload_summary` (read by nothing but `play_turn`),
    `last_air_insertion_summary` and `last_mobilization_summary` (read only by `TurnEventLog`).
  So the refactor cleans up three fields, cannot touch five, and adds a second transport mechanism
  alongside the one it failed to remove — across every phase, `TurnConductor` and `play_turn`.
  **Unblocks when:** the transport-only set grows materially (say past half), or the observation API
  stops reading phase reports off the state between turns. Plan 0059's `last_ijfs_air_oob` is a twelfth
  field in the transport-only group; it does not make this refactor harder, and folds into it if it is
  ever built.
- **Mutation-authority protection reaches only TYPED receivers, so state passed through an untyped
  `Dictionary`/`Array` is unprotected and the gate cannot say so (standing limit, restated 2026-07-31;
  NOT a defect to fix, a rule to follow).** The enforcement gate judges a write by resolving the
  receiver's type; a value reached through an untyped container has no type to resolve, so the write is
  neither permitted nor refused — it is invisible. The manifest's `_schema_rules` documents this as the
  "aliased-container blind spot", and it is not theoretical: `SealiftResolver`'s last illegal write was a
  `ship_category` stamp put into force-owned reserve rows through exactly such an alias, found by hand in
  plan 0045, not by the gate. **Deliberately not opened as a plan.** The fix is "make shared state a typed
  `Resource` before registering its fields", which is what plans 0042–0050 already did aggregate by
  aggregate — there is no bounded remaining unit of work, only a standing rule for new code.
  **Unblocks when:** someone produces the measurement nobody has — how much live campaign state still
  travels through untyped containers. If that number is large, this becomes a plan. The `OffloadCalculator`
  item above is the one bounded instance, and a data point toward that measurement.
- **`tools/review_fanout.sh` residual hardening, all deliberately declined during plan 0054's review
  rounds.** (a) A snapshot made with `git diff --binary` is rejected by the structural check; a stateful
  binary-patch parser was declined, and `--freeze` never passes `--binary`. (b) `--report`'s auto-count
  is a labelled lower bound rather than an explicit per-reviewer acceptance protocol; exit 3 covers the
  failure mode instead. (c) `_dirty_paths` does not handle paths containing a literal newline. (d) The
  gate cannot watch `~/.claude/*`, so the global agy contract and slash command are kept roster-free by
  convention only. **Unblocks when:** one of these produces an actual failure to point at. Re-raising
  without one re-opens a decision already made twice.
- **Gate the `consumer:` / `pinned by:` witness convention (opened 2026-07-29).**
  `hexcombat-docs-and-writing` now requires a greppable witness for any claim that something is or is
  not consumed, serialized, pinned, or expensive, and the convention is seeded in
  `scripts/model/SealiftState.gd` and `SealiftHullLossReceipt.gd`. Extending
  `tools/validate_doc_anchors.gd` to resolve those witnesses (a named symbol must exist; a "none
  (checked `<date>`)" must not sit next to a live reference) was deliberately NOT done yet: with two
  usages the check would match almost nothing, and this repo's standard is that a detector is proven by
  fixtures or it is a false negative waiting to happen (see `validate_mutation_authority.gd`'s
  E_VACUOUS family). **Unblocks when:** ~10 usages exist. Then add fixtures proving each direction fails.
- **Doc-anchor validator checks links, not bare symbols (found 2026-07-25).**
  `tools/validate_doc_anchors.gd` matches `ClassName.member` in backticks, so a doc naming a bare
  `CONSTANT` that no longer exists passes — `docs/systems/ground-combat.md` described
  `CombatCalculator.TERRAIN_MODIFIERS` as "dead code, left untouched" long after the symbol was deleted
  (fixed 2026-07-25). Extending the check to bare backticked ALL_CAPS identifiers was considered and
  **deferred deliberately**: `PI`, `INFINITY` and ordinary prose constants would false-positive.
  **Unblocks when:** someone has a scoping rule that survives scrutiny. Neither reviewer had one.
- **Combat-loop caches live as mutable fields on `GameStateData` (found 2026-07-25).**
  `isolated_air_landed_brigades` (`:43`) and `not_ashore_by_type` (`:49`) are both computed once per
  turn at `TurnConductor:65`/`:70` and read by every contested hex; nothing enforces that a third such
  cache follows the rule or that either is cleared between turns. A `begin_combat_loop(state)`
  returning a context value object would make staleness impossible by construction. **Deferred:**
  reviewers split on risk/reward — the caches are correct today and the change touches
  `CombatResolver.resolve_at`'s signature for no behavioural gain. **Unblocks when:** that seam is open
  for another reason, or a third such cache appears.
- **`CombatResolver` assumes attacker=Red / defender=Green.** `resolve_at` hardcodes it — the two
  defender-side `inject_supply_effectiveness` calls were no-ops for exactly this reason and were removed
  2026-07-24, leaving a comment. Supply injection and anything else keyed on side must be driven by each
  side's actual team, not its role. Ported combat semantics, so a USER-aware change, not a refactor.
  **Unblocks when:** Green counterattacks — i.e. plan 0029 Tier B. Until then there is no second case to
  generalize against.
