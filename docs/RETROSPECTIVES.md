# Retrospectives — implementer lessons learned

Per-sub-task "what would you do differently, knowing what you know now" notes.
Per-module retros live in `docs/systems/<module>/RETRO.md`. This file documents the entry format
and the inbox/archive workflow. Once triage actions are implemented or backlogged, **move the
entry to `docs/archive/RETROSPECTIVES_history.md`**.

## Entry format

```
## <date> — <sub-task id>: <title>   (implementer: <model> | direct)

**What would you do differently (implementer):**
- <specific, concrete lesson — fragility, tech debt, surprise, what'd make the next task easier>

**Orchestrator triage:**
- <lesson> → act now | act later (→ docs/plans/ plan or backlog) | record only — <note>
```

## Module retro files

| Module | File |
|---|---|
| Anti-ship & mines | `docs/systems/antiship-mine/RETRO.md` |
| Ground combat | `docs/systems/ground-combat/RETRO.md` |
| Turn engine | `docs/systems/turn-engine/RETRO.md` |
| Amphibious offload | `docs/systems/amphibious-offload/RETRO.md` |
| Research harness | `docs/systems/research-harness/RETRO.md` |

## 2026-08-01 — plan 0060: localize MANPADS and SAM air attrition to engagements   (implementer: direct)

**What would you do differently (implementer):**
- **The probe I wrote first measured a mechanic that could not fire.** Driving `IjfsEngine.run_daily`
  directly against `targets_master.json` reported ZERO MANPADS engagements at every factor I tried,
  and the honest reading of that would have been "the mechanic is broken". It was not: maneuver
  targets are built from the LIVE brigade OOB by `IjfsLoaders.build_maneuver_targets`, so a probe
  that skips `GameState.play_turn` has no Maneuver Units, and MANPADS' only trigger is a Maneuver-Unit
  strike. **The instrument answered a different question than the one I asked it** — the exact failure
  the plan's own Corrections section records against its predecessor, repeated one plan later. Drive
  the real pipeline when the mechanic depends on state the real pipeline builds.
- **The second probe silently applied no overrides at all**, and I only noticed because three
  different factor values produced byte-identical output. `DataOverrides` takes a FLAT map keyed
  `"path/file.json:dotted.key"`; I passed a nested dict, which matched nothing. Identical output
  across a swept parameter is the cheapest possible tell, and it is worth looking for deliberately
  rather than by luck — a sweep whose knob does nothing looks exactly like a knob with no effect.
- **A ceiling measurement is what turns "the fit is low" into "the fit is impossible".** Running the
  SAM factor up to 1.0 — every contact killing with near-certainty — produced 7.5 losses against a
  checkpoint of ~50. That single run converted an open calibration task into a reportable structural
  closure with a cause, which is what the plan asked for and what the USER can actually act on.
- **`git stash push` failing on an untracked file left `&&` short-circuited and popped SOMEONE
  ELSE'S stash**, conflicting four unrelated docs into my tree. Restoring the four paths from HEAD
  was easy; noticing was luck. Move the file aside instead of stashing when the goal is just to keep
  one new file out of a commit.
- **Extracting first paid for itself immediately.** `IjfsEngine` sat at exactly its dependency
  ceiling of 14 while this plan added three collaborators, so the extraction was forced — but doing
  it as its OWN commit, and proving it byte-neutral against the golden pins and the LLM fixture, meant
  every later red gate had one candidate cause instead of two.

**Orchestrator triage:**
- "Drive the real pipeline when the mechanic depends on state only it builds" → act now — this is the
  third instance of the measurement-inherits-its-question family and is recorded here with its cause.
- "Identical output across a swept parameter means the knob is not connected" → act now — recorded
  here; the sweep harnesses already assert unapplied override keys, which is the mechanical version.
- R10's 10%-per-day calibration checkpoint being unreachable → **reported to the USER, not fixed** —
  the closure and its four possible design responses are in
  `docs/archive/0060-air-attrition-before-the-strike.md`. Every reachable lever is a design change,
  which is the USER's call and not the implementer's.

## 2026-07-31 — plan 0049: accounting + turn-lifecycle mutation authorities   (implementer: direct)

**What would you do differently (implementer):**
- **Two reviewers CONTRADICTED each other on the plan's headline claim, and the one that said
  "verified/holds" was wrong.** agy confirmed that arbitrary phase assignment was inexpressible
  because `_advance` was private; Sol showed a GDScript underscore is a naming convention, not access
  control, so any file could call `_advance(state, state.phase, ANY, "x")` while the gate saw an
  authorized write. **A verification is not evidence — the reasoning behind it is.** Both reviewers
  reasoned about the same five lines and reached opposite conclusions; the tie was broken by reading
  the language semantics, not by counting votes. Same shape as the duplicate-JLSF disagreement one
  commit earlier, where agy again asserted a mechanism was load-bearing and tracing
  `queue_deployments` showed it was not.
- **My own structural test was written to pass, not to catch.** It enumerated the authority's methods
  and filtered out anything starting with `_` — which is precisely where the hole was. A test that
  cannot see the back door cannot prove the door is shut. After the fix I deliberately re-added an
  `_advance(state, to_phase)` and watched the test fail before reverting; that took one command and is
  the only reason I believe the test now.
- **A comment claiming "a test pins this" is a claim that gets checked.** I wrote that
  `CleanupResolver`'s own landing latch and the authority's derived one were pinned as agreeing. The
  test did not exist. Review found it. If a header asserts a proof, write the proof in the same edit.
- **Preflight paid for itself three times in one plan**: it deleted step 6 (the eleven `last_*` slots
  were already settled exclusions, not deferred work), dissolved `SupplyResolver`, and measured that
  ALL FOUR coordinators sat at exactly their dependency ceiling — which reshaped every call site
  before a line was written, rather than after a red gate.

**Orchestrator triage:**
- "Private is not a boundary; pin the COMPLETE method list when the guarantee is absence" → act now —
  added to `docs/systems/mutation-authority/mutation-authority.md` §6.
- "An authority handed a mutable object must copy it in and out" → act now — added to the same §6.
- Reviewers disagreeing on a mechanism, resolved by tracing rather than by vote → record only — the
  roster already says a tier-2 verification needs checking; this is the second measured instance in
  two rounds, and both times the citation line numbers were fabricated while the prose was plausible.
- Green-LLM-seat-can-deploy-Red-JLSF (pre-existing; needs an action-schema change) → act later,
  logged to `docs/plans/BACKLOG.md`.
- Whether duplicate `deploy_jlsf` orders should be rejected → act later — USER design call, logged to
  `docs/plans/BACKLOG.md` with the evidence both ways.

## 2026-07-30 — plan 0047 steps 4-8: map + infrastructure mutation authorities   (implementer: direct)

**What would you do differently (implementer):**
- **Verify each remaining step can go green ON ITS OWN before committing to the sequence — while
  designing the call shape, not after.** The previous session's step 3 could not: typing the node
  breached a ceiling only step 5 could pay, and the gate found that, not the plan. This session I
  measured `ndeps` for the one-for-one swap (`InfrastructureState` out, `InfrastructureTransitions`
  in) before writing a line, and it landed at exactly 22/22. That check cost one command.
- **The plan's "add illegal fixtures" instruction was not literally executable, and noticing that was
  worth more than obeying it.** The fixture world is deliberately ABSTRACT (`FixtureRow`,
  `FixtureHost`), scanned against its own `fixture_manifest.json`. Adding fixtures naming the real
  classes would mean copying the real manifest into the fixture manifest — the exact duplication the
  campaign doc forbids. Every form the plan listed was already proven there. Proving the six forms
  against the REAL aggregates by injecting and reverting them gave the same guarantee with no
  duplicated list, and took one command per aggregate. **When a plan step names a MECHANISM, check
  the mechanism still fits before implementing it; the plan was written before the tree was measured.**
- **A terse clean review is not a flake, but the launcher cannot tell.** The tier-1 reviewer returned
  342 bytes of "no actionable findings" plus three ABSENT determinations — a real read, scored `FLAKE`
  because it had no NUMBERED findings; the enumerator returned 34 KB of correct verbatim lists, also
  scored `FLAKE` for the same reason. The launcher auto-counted 1 of 2 and said "hold uncommitted".
  Both were genuine, and the quorum was met on content per the roster's enumerator rule — but I had
  to reason my way there, which is exactly the situation the rule exists to prevent me getting wrong.
  Next time, **ask every role for numbered findings explicitly, including "0 findings, here is what I
  checked" as a numbered list** — it costs one sentence in the brief and makes the triage mechanical.

**Orchestrator triage:**
- Per-step ceiling headroom check before designing a call shape → record only — now in
  `docs/systems/mutation-authority/mutation-authority.md` §5 (it was already there as a rule; this run
  confirms the cost of skipping it is a red gate, not a rewrite).
- The transitional-scaffolding lesson (name the step that DELETES it, and that step is the one that
  pays the ceiling) → act now — added to `mutation-authority.md` §5 as a fourth ordering trap.
- Enforce-by-absence and the ordered-event-list rule → act now — added to `mutation-authority.md` §6.
- **Correction to the fixture lesson (USER, 2026-07-30):** the abstract-fixture mechanism objection
  was right, but the reverted injections did not give “the same guarantee.” → act now — the validator
  now generates real-manifest probes every run and compares an independent claim pin; the procedure
  distinguishes repeating evidence from a one-time diagnostic.
- Reviewer briefs should demand numbered findings from every role, including nil returns → act later
  (→ `docs/plans/BACKLOG.md`, alongside the existing `--format json` launcher item; both are review
  TOOLING findings, which per `.claude/REVIEWERS.md` go to the backlog rather than re-opening a round).
