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
