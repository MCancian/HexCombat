# Plan 0054 — Reviewer tiers, one canonical home, one fan-out command

**CLOSED OUT 2026-07-30.** Durable facts landed in: `.claude/REVIEWERS.md` (the round, tiers, routes,
brief invariants, flake band, safety, roles), `tools/review_fanout.sh` + `tools/validate_reviewer_facts.gd`
(their headers hold the measured decisions and the explicitly rejected fixes),
`hexcombat-failure-archaeology` (the compacted-summary incident), `docs/DECISIONS.md` 2026-07-30, and
`docs/plans/BACKLOG.md` (residual hardening). Nothing here needs to be read to act.

**Status:** `In progress` — implemented; in pre-commit review. Round 1 void, round 2 met quorum, round 3
covers the fixes those rounds forced. Nothing is committed until the quorum holds on the artifact that
will actually be committed.
**Priority:** Medium (agent workflow; every future plan and diff pays the current tax).
**Depends on:** nothing. **Blocks:** nothing, but every subsequent consultation round is cheaper after it.

## Goal

Turn the reviewer layer from eight overlapping prose homes into **one roster + one command + one
mechanical gate**, and encode the USER's tier model (2026-07-30) so reviewer choice stops being a
judgement call re-derived each session.

Two outcomes, both checkable:

1. **A fact about a reviewer lives in exactly one place.** `.claude/REVIEWERS.md` owns tiers,
   invocations, the quorum rule, brief invariants, flake detection, safety. Everything else points.
2. **A consultation round is one command.** `tools/review_fanout.sh --brief <file> --freeze …` fires all three
   required reviewers with the correct read-only flags, timeouts, frozen-artifact check and per-file
   byte sizes for flake triage — instead of hand-assembled `setsid nohup` lines copied out of a skill
   and mutated each time.

## USER design calls (2026-07-30) — settled, do not re-litigate

- **Tiers.** Tier 1 (peer): GPT-5.6 Sol. Tier 2 (mid): the agy explore and verify wrappers, DeepSeek V4
  Flash. Tier 3 (sometimes helpful, occasionally dangerous): MiniMax M3, Nemotron Ultra. (Routes and ids
  for all of them: `.claude/REVIEWERS.md`, the single home.)
- **The round is a fan-out of three, with a 2-of-3 quorum.** Every consultation round asks **Sol +
  agy + DeepSeek**. **Two substantive returns = the round is satisfied.** A third that flakes,
  quota-blocks or returns nothing is expected, not a failure of the round. This replaces "two
  substantive independent reads" as the operative rule — same floor of two, but the *fan-out* is now
  fixed rather than chosen, which is what makes it a command instead of a decision.
- **The quorum binds the IMPLEMENTATION of a numbered plan, and only that** (USER call 2026-07-30,
  answering this plan's open question). A plan *document* needs at least one substantive read; smaller
  work (a BACKLOG bullet, a doc fix) is judgement. Fan out regardless — it is one command — but nothing
  below a plan implementation is blocked on reaching two.
- **Sol runs on every plan and every diff.** The old "costly, save it for high stakes" spend rule is
  retired. Sol is a peer reviewer of record, not a break-glass.
- **Tier 3 never counts toward the quorum.** Bonus roles only ("what did I miss", breadth sweeps), and
  every citation it produces is verified before use.
- **Scope includes the global docs** — `~/.claude/AGY.md` and `~/.claude/commands/dual-review.md` — not
  just the repo, because they contradict the project roster in every session.

## Measured current state (preflight, done 2026-07-30 — this is the plan's evidence)

Eight homes hold reviewer facts. Duplication counts are grep-measured, not estimated:

| Home | Lines | What it holds today |
|---|---|---|
| `.claude/REVIEWERS.md` | 126 | roster, invocations, reliability, brief invariants, safety — the intended single home |
| `.claude/skills/hexcombat-plan-review/SKILL.md` | 176 | plan-round procedure **+ its own model table + flake band + roles + safety + `setsid` snippets** |
| `.claude/skills/hexcombat-diff-review/SKILL.md` | 143 | diff-round procedure **+ short restatements of all of the above** |
| `CLAUDE.md` (Consultation §) | ~40 | the loop rule **+ five restated "things worth knowing"** |
| `AGENTS.md` | 1 row | pointer only — correct already, leave alone |
| `~/.claude/AGY.md` (global) | 4.6 K | agy CLI contract **+ a reliability table + roles + flake band + safety** |
| `~/.claude/commands/dual-review.md` (global) | 29 | a whole third copy of table + flake band + roles + safety |
| `.claude/skills/hexcombat-build-and-env/SKILL.md` | 99 | an opencode invocation block **+ a stale claim that `pi` is broken** |

Duplication, by phrase, across `AGENTS.md` + `CLAUDE.md` + `.claude/**` + `docs/plans/**`:
`REVIEW ONLY` in 4 files; `git status --short` reviewer rule in 4; the 2.7–4.5 KB flake band in 4
(counting `docs/plans/BACKLOG.md`); the read-only-flag fallback warning in 4; verify-wrapper semantics in 4.

**The copies have already diverged — this is the cost, not a hypothetical:**

- Both review skills and the global `dual-review` command named the `opencode/*-free` variants of
  Nemotron and DeepSeek as the whole roster. **Precision, after a reviewer challenged an earlier
  overbroad version of this line:** the DeepSeek `-free` route is LIVE — it answered in both rounds of
  this plan's own review — while Nemotron's now routes through `pi` against an NVIDIA-hosted endpoint.
  The defect was never that every id was dead; it was that the skills listed a two-model roster with no
  tier-1 reviewer in it, and no way to reach the routes that had moved.
- **Sol and MiniMax do not exist** in either skill or in the global command. An agent that reads
  `hexcombat-plan-review` and follows it — the documented path — cannot reach the tier-1 reviewer.
- `hexcombat-build-and-env:80` states **"`pi` CLI is broken on this box"**. `REVIEWERS.md:16` states pi
  is alive, v0.82.1, verified 2026-07-29. One of these is read as an instruction by the next agent.
- `~/.claude/AGY.md`'s reliability table is a project fact living in a cross-project file, so it is both
  wrong for other projects and stale for this one.

## Target shape

### `.claude/REVIEWERS.md` — the single home, restructured by tier

Sections, in this order:

1. **The round** — the fan-out of three, the 2-of-3 quorum, when to run it (plan round, diff round),
   what to do when quorum fails (hold work **uncommitted**; surface to the USER — unchanged rule).
2. **Tiers and routes** — one row per reviewer, with **two separate columns that must never be
   collapsed into one**:
   - **Tier** — USER-set capability ceiling: what class of judgement this model may be trusted with.
   - **Route record** — measured: does this invocation return a usable review at all.

   They disagree on purpose. DeepSeek V4 Flash is **tier 2 by capability** and **0/3 as a reviewer,
   1/1 as a bounded enumerator** by measurement; the agy explore wrapper is tier 2 and 4/4. Both columns
   is what stops a future agent "correcting" one from the other — and the 2-of-3 quorum exists
   precisely because a tier-2 route can return nothing.
3. **Invocations** — verbatim command per reviewer (USER-supplied 2026-07-30), read-only flags, and the
   one-line reason each flag is there. This is the block `tools/review_fanout.sh` implements; the script
   is the executable copy and this section says so.
4. **Brief invariants** — the five requirements already in the file (REVIEW ONLY line, frozen artifact,
   how to verify, evidence discipline, scope consistency). Unchanged content; now the only copy.
5. **Flake detection** — the band and the "no numbered findings ⇒ not a review" rule. Only copy.
6. **Safety** — read-only is a prompt not a sandbox; `git status --short` after every round; strays
   contaminate; identical findings from two models are one review; tier 3 citations always verified.
7. **Roles** — the differentiated-role list (fact-check / consequences / weaker-implementer /
   oracle / method). Only copy.

Target length ~150 lines: it grows, because it absorbs three other files' content.

### The two review skills — procedure only

Strip everything the roster now owns. What stays is **exactly what differs between the rounds** — the
part that is genuinely per-skill:

- `hexcombat-plan-review`: what a plan review catches (false premise, unbuildable step, missed consumer,
  fix-that-does-not-fix, bad ordering) + the plan-brief format + "after the review: fold accepted
  findings into the plan, record rejected ones under *explicitly out of scope (checked, don't re-raise)*".
  Delete: the model table, flake band, roles list, `agy-verify` explainer, safety section, `setsid`
  snippet. Replace with one line: *the round, the roster, safety and flake triage are in
  `.claude/REVIEWERS.md`; run it with `tools/review_fanout.sh`.* 176 → ~85 lines.
- `hexcombat-diff-review`: what a green gate cannot see (missed consumer, staleness, luck-invariant,
  default that returns the pre-fix answer, dead code, test that proves nothing) + the diff-brief format
  + verify-by-measurement + "after the review". Delete the same categories. 143 → ~75 lines.

Both keep the cross-reference to each other and the statement that **both rounds are required**.

### `CLAUDE.md` — the loop rule and a pointer

The Consultation section drops from ~40 lines to ~12: both rounds are mandatory; the round is the
three-way fan-out with a 2-of-3 quorum; reviewers never implement; **probe availability before you
implement, not at commit time**; hand over a **frozen artifact**; if quorum fails, hold uncommitted and
surface to the USER. Everything else → `.claude/REVIEWERS.md`. `AGENTS.md` needs no change; its pointer
row is already correct.

### `tools/review_fanout.sh` — the workflow half

```
tools/review_fanout.sh --brief <file> [--role NAME=FILE]... [--freeze] \
                       [--out DIR] [--tier3] [--dry-run] [--no-roles]
tools/review_fanout.sh --report DIR
```

Behaviour, all of it load-bearing for a rule that is currently prose:

- Prepends the `REVIEW ONLY — DO NOT MODIFY, CREATE, OR DELETE ANY FILE.` line itself, so it cannot be
  forgotten (`AGENTS.md`: prefer making a mistake impossible over documenting it).
- **Refuses to launch against a dirty tree unless the artifact is frozen.** This is the frozen-artifact
  rule, which cost a full round on 2026-07-29 when two reviewers read a tree mid-edit and one reported
  eight failures in a state that never shipped.
- **`--freeze` produces the snapshot itself** — at gitignored `.review-fanout/frozen-<ts>.diff` inside
  the worktree, where a workspace-scoped reviewer CLI can read it — and verifies its own output is a
  diff (`diff --git` headers present, every line a diff sigil). `--sha` and caller-supplied
  `--snapshot` were **deleted** at round 5 (USER call): four rounds went into validating a snapshot
  someone else built, and each check was a fresh defect. `--out`, conversely, is refused *inside* the
  worktree, so reviewers cannot read each other's outputs.
- **`--role NAME=FILE` gives each reviewer its own job** on top of the shared brief, and rejects a role
  naming a reviewer not in the round. Without it, three reviewers answer one question — the
  correlated-noise failure the roster warns about.
- Launches the quorum reviewers backgrounded and detached with the correct read-only flags and the
  15-minute review timeout; writes one file per reviewer under `--out`.
- `--report DIR` prints `reviewer state bytes findings verdict` and the auto-counted quorum. Verdicts:
  `REVIEW` (exit 0, findings, 1–10 KB — the only shape counted automatically), `FLAKE` (no numbered
  findings — the only verdict decided mechanically), `SHORT`/`SUSPECT` (read it yourself, then count it
  yourself). Exits `1` if fewer than two were auto-counted, `3` if two were but a `SHORT`/`SUSPECT`
  return is unread, `0` only when there is nothing left to judge.
- `--tier3` adds MiniMax and Nemotron as clearly-labelled **non-quorum** extras. `--dry-run` composes
  prompts and launches nothing, so testing the plumbing costs no reviewer calls.
- Reports any file that changed **since launch** — strays written by a reviewer — rather than any dirty
  file, so a legitimately dirty tree does not cry wolf.

It does **not** parse or summarize findings. Reading and refuting them stays the primary agent's job —
a summarizer here would launder exactly the fabricated citations tier 3 produces.

### `tools/validate_reviewer_facts.gd` — the gate that keeps it consolidated

Consolidation without a gate decays; that is the whole lesson of the current state. New validator,
picked up automatically by the gate's `validate_*.gd` glob (`tools/run_all_tests.py:108` — no wiring
needed):

- **Fails** when a reviewer invocation or model id appears in any `.md` under `.claude/skills/`, or in
  `CLAUDE.md`, `AGENTS.md`, or `docs/plans/*.md` — everywhere except `.claude/REVIEWERS.md`.
- Pattern set, deliberately narrow in the style of `tools/validate_skill_references.gd`: concrete CLI
  invocation fragments plus the model ids — never prose. The list itself lives in the validator's own
  header, because repeating it here would be the very duplication it exists to stop. Tool NAMES stay
  legal (a skill may say what the verify wrapper can and cannot see); pasted commands and ids do not.
- **Escape markers** reuse the existing idiom (`docs/archive`, `(historical)`) so retrospectives and
  archived plans keep their record. `docs/archive/**` and `docs/systems/**/RETRO.md` are out of scope
  entirely — history is allowed to name dead routes.
- Prints `PASS:`/`FAIL:` via `ValidatorHarness`, like every other validator.

Known limit, stated in its header: it cannot gate `~/.claude/*`, which is outside the repo. The global
files get a contract line instead ("no roster here — see the project's `.claude/REVIEWERS.md`").

### Global files (not repo commits — flag separately to the USER)

- `~/.claude/AGY.md` → **agy CLI contract only**: the two wrappers, the extra-workspace flag, the timeout variable, the
  worktree/committed-state semantics of `agy-verify`, and the read-only-by-prompt caveat. Delete the
  reliability table, the roles list, the flake band, the HexCombat anecdotes; they are project facts.
- `~/.claude/commands/dual-review.md` → rewritten to the three-way fan-out + quorum, project-agnostic,
  with **no embedded model table** (it names the tiers and says the per-project roster is authoritative).
  Keep the two things that are genuinely generic and were right: reviewers never implement, and
  verify-then-implement.

## Commit sequence (smallest verifiable steps)

Order matters: the new home is complete **before** any other copy is deleted, so no window exists where
a fact lives nowhere.

1. **`REVIEWERS.md` rewrite** — tiers, quorum, invocations, briefs, flake, safety, roles. Additive; no
   other file touched yet. Gate: docs only, `bash tools/run_all_tests.sh` green.
2. **Strip the two skills + `CLAUDE.md`** to procedure + pointer. Gate green (`validate_skill_references`
   still passes — no `.gd` citations change).
3. **`tools/review_fanout.sh`** + the one line in `REVIEWERS.md` naming it as the executable copy of the
   invocation table. Smoke: run it against a throwaway brief with a dirty tree and confirm it **refuses**;
   then with `--freeze` and confirm three files appear with sizes and a contamination report.
4. **`tools/validate_reviewer_facts.gd`** + fix every violation it reports. Expected first-run hits:
   `hexcombat-build-and-env` (the `opencode` block and the stale "`pi` is broken" claim — the latter
   deleted outright, since `failure-archaeology` already holds the history), `hexcombat-change-control:92`,
   and any residue from step 2. Gate must be green with the new validator in the glob.
5. **Global files** (`~/.claude/AGY.md`, `~/.claude/commands/dual-review.md`) — outside the repo, so
   **not a commit**. Report the change to the USER explicitly in the closeout summary; nothing in git
   records it.
6. **Closeout** — `docs/DECISIONS.md` entry (3–5 lines: tier model, quorum rule, one home, the gate),
   index row → `✅ Shipped`, plan file → `docs/archive/`. Per `hexcombat-docs-and-writing`, no durable
   fact may be left living only in this plan; the durable homes are `REVIEWERS.md` and the validator
   header.

## Verification

- `bash tools/run_all_tests.sh` → **ALL PHASES GREEN** after each commit. The new validator is the real
  acceptance test for "one home".
- **Dogfood:** this plan's own **diff** round is run with `tools/review_fanout.sh` — the first real
  exercise of the command is the change that introduces it. (The plan round predates the script and is
  run by hand.)
- A round is recorded as satisfied only when **two** returns carry numbered findings. Byte sizes and
  finding counts get pasted into the commit message, so "2 of 3" is auditable after the fact.

## What round 1 caught (2026-07-30, the diff round on this plan's own implementation)

Reviewers: tier-1 Sol, agy, DeepSeek, one role each, run through the new script.
**Result: 1 of 2 quorum — the round was VOID and had to be re-run.** Recorded because the void was the
useful part.

1. **Sol, blocker, CONFIRMED and worse than reported.** The frozen artifact was a token-compacted
   summary, not a diff — `git diff > file` had been rewritten by the `rtk` shell hook. Sol reported
   truncation; measurement showed **zero** `diff --git` headers, i.e. no diff content at all. Sol
   refused the round rather than reviewing the working tree. Fix: `--freeze` plus structural snapshot
   validation, and an entry in `hexcombat-failure-archaeology`.
2. **agy and DeepSeek silently reviewed the live tree instead** and returned clean verdicts — "ABSENT"
   across three categories, one nit. Nothing in their output disclosed the substitution. This is why an
   unreadable artifact is more dangerous than a missing one.
3. **agy, nit, CONFIRMED.** This plan's usage block for the script conflated `--sha` with `--snapshot`
   and omitted `--role`. Fixed above.
4. **DeepSeek's enumeration was accurate and produced two scope facts** (both spot-verified, both now
   in the validator's header): `docs/systems/**/RETRO.md` legitimately records reviewer facts as
   history, and the DeepSeek route's model id is *also* an LLM-player model name asserted in
   `tests/knob_registry_test.gd` and printed by `docs/presentation.html` — so widening the scan to code
   would fail the gate on files that have nothing to do with reviewers.
5. **Triage heuristic corrected by the incident.** The 823-byte blocker classified as `FLAKE` under a
   pure byte-band rule. Short-with-findings is now `SHORT`: read it. A correct blocker can be tiny.

## What round 2 caught (the first round with a valid artifact — 2/2 quorum)

Sol 7.7 KB / 10 findings, agy 3.6 KB / 3 findings, DeepSeek 27 KB / **0** numbered findings (flake — tool
trace only, so it did not count). Every finding below was verified before acting; the two blockers were
reproduced in a scratch git repo rather than argued about.

**Accepted — real bugs in the new launcher, all fixed:**

1. **`--freeze` omitted STAGED changes** (`git diff` compares the worktree with the *index*). Verified in
   a scratch repo: with one staged and one unstaged edit to the same file, `git diff` showed one hunk and
   `git diff HEAD` showed both. The artifact would have passed every structural check while silently
   missing content. Now `git diff HEAD --`.
2. **An `--out` directory inside the worktree contaminated its own snapshot.** Verified: `git ls-files
   --others` enumerated `out/frozen.diff` and `out/tree_before`, so the snapshot was appended to itself.
   Now the out dir is skipped in both the enumeration and the path-presence check.
3. **Any completed run counted, regardless of exit status** — a CLI error printing numbered lines in the
   healthy byte band would have manufactured a quorum. Now `done(0)` is required.
4. **A reused `--out` would have counted the previous round's `.done` files.** Now refused outright.
5. **Roles were documented as mandatory but only warned about.** Now an error before launch, waivable
   only with an explicit `--no-roles`.
6. **Stray detection compared status LINES**, so a reviewer editing an already-dirty file was invisible.
   Now content hashes are recorded at launch and compared at report time.
7. **Output paths were interpolated into the inner shell source.** Now passed as positional parameters.
8. **Both review skills still recommended the hand-built snapshot** that voided round 1. Now `--freeze`.
9. **The validator's "one home" claim was overstated** — it is a token check; prose duplication passes.
   The claim is narrowed everywhere it appeared (roster, `CLAUDE.md`, the validator header) rather than
   pretending the gate proves more than it does.
10. **The validator's scan set was four roots**, blind to `.claude/*.md` outside skills, `docs/*.md` and
    `docs/systems/**`. Widened to all repo markdown minus history (`docs/archive/`, `docs/reports/`, any
    `RETRO.md`). **This widening then exposed a worse bug of my own:** `DirAccess` hides dotted entries
    by default, so the first widened version scanned 89 files, silently skipped all 20 under `.claude/`,
    and **passed a forbidden invocation fragment injected into a skill**. Fixed with
    `include_hidden = true`; the probe now fails as it should, and the scan covers 113 files.
11. **agy: the plan-review skill's example passed a plan `.md` to `--snapshot`**, which the new structural
    check rejects; and this plan showed the script invoked without `--brief`. Both fixed.
12. **agy: `docs/systems/ground-combat/RETRO.md` pointed at the deleted launch snippet** in
    `hexcombat-plan-review`. Marked closed-and-historical, with the serial-opencode rule now in the roster.

**Recorded, not silently changed:** the roster's third quorum slot is DeepSeek, whose route record is 0/3
as a reviewer, so in practice Sol and agy carry the quorum. That is now stated as a known property in
`.claude/REVIEWERS.md`, because changing the roster is a USER decision, not mine.

## What round 3 caught (review of the round-2 fixes — 2/2 quorum)

Sol 6.2 KB / 11 findings, agy 3.6 KB / 5 findings, DeepSeek 569 bytes / 0 findings (flake). agy reported
dead pointers, prose duplicates and quorum-rule consistency all **ABSENT** — the consolidation itself is
clean, and every remaining finding was about the new tooling.

**Accepted and fixed (16 of 16 doc findings, 10 of 11 shell/validator findings):**

1. `out_rel` was computed only under `--freeze`, so an in-repo `--out` broke `--snapshot` validation;
   paths are now resolved with `pwd -P` (a symlink into the worktree was invisible), **any** directory
   inside the repository is refused as `--out` (not just the root), and failure to find the repo is now
   fatal instead of silent.
2. `git ls-files` **C-quotes** paths with spaces or non-ASCII, so the quoted spelling was passed back to
   git as a nonexistent filename. Now `-z` with `read -r -d ''`, and a `git diff` exit status other than
   0/1 is a hard failure rather than swallowed by `|| true`.
3. The path-completeness check used a **substring** search, which passes a missing file whenever its name
   appears in another hunk's content. Now a set comparison against the paths the snapshot's own headers
   name — and it is skipped under `--freeze`, because re-deriving a list to compare it with itself proves
   nothing and produced a **false "missing" verdict on a real file** (verified with a probe named
   `probe file ünïcode.md`: git writes `+++ "b/…"`, quoting outside the prefix and C-escaping the
   non-ASCII bytes, so no spelling matched).
4. Stray detection now uses `-uall` (a file added inside an already-untracked directory was invisible),
   `comm -3` so a *disappeared* hash counts as contamination too, a guarded `md5sum`, and one NUL-safe
   `_dirty_paths` helper shared by launch and report.
5. A non-empty `--out` is refused outright, not merely one containing a `manifest` — a leftover `.done`
   from a previous round would have been counted as this round's return.
6. `--report` now exits **3** when a `SHORT`/`SUSPECT` quorum return is present even though two others
   were auto-counted. Exiting 0 with an unread `SHORT` is exactly how round 1's void would have slipped
   through: its blocker was an 823-byte `SHORT`.
7. Validator: a **visited-set of canonical paths** guards the walker against symlink loops and against a
   symlink reaching past the lexical exclusions.
8. Validator: it now checks that **every reviewer command the launcher builds appears verbatim in the
   roster** — the executable copy could previously drift from its documented table while the gate stayed
   green. Probed by drifting one model id and watching it fail.
9. Validator: `(llm-player)` joins the escape markers, so a self-play doc can name the model it ran
   without tripping a reviewer-route gate.
10. Roster/skills/plan: the launcher runs the three quorum routes plus `--tier3`, not every row of the
    Invocations table (now stated); the byte band is reconciled with the launcher's 1–10 KB thresholds;
    `--report`'s counting rule is documented; the synopsis gains `--no-roles`; the global slash command
    no longer recommends the hand-built snapshot.
11. **A rule genuinely lost in the consolidation, restored.** The old skill said to treat an unexpected
    modification as out of bounds and revert it; the roster only said "delete strays", which is wrong
    advice for a reviewer's edit to a file that was *already dirty with your own work*. The rule now
    distinguishes created (delete) from modified (reverse the reviewer's delta only — never
    `git checkout`, which would discard your pre-round work as a second self-inflicted incident).

**Declined, with the reason recorded in the code:** a snapshot made with `git diff --binary` is rejected
by the structural check, and Sol asked for a stateful binary-patch parser. Reviewers read text, `--freeze`
never passes `--binary`, and failing closed with a clear message beats a binary-patch parser inside a
script whose whole value is being obviously correct.

**Partially declined:** Sol wanted `--report` to auto-count nothing and require explicit per-reviewer
acceptance. The auto-count is retained as an explicitly-labelled **lower bound**, with the exit-3
behaviour above as the actual protection — the failure mode was a green exit hiding an unread return, and
that is now impossible without inventing an acceptance protocol nobody will follow.

## What round 4 caught (final round — 2/2 quorum, 22 findings, all accepted)

Sol 6.3 KB / 10 findings (3 blockers), agy 6.4 KB / 13 findings, DeepSeek 448 bytes / flake. agy's
"content that moved" category: **ABSENT** for the third round running — the consolidation is settled and
every finding was about the new tooling.

**The tooling surfaced a finding no reviewer could have:** DeepSeek's flake was not a route failure. Its
output was `permission requested: external_directory (…/scratchpad/round4/*); auto-rejecting` — the
opencode CLI is scoped to its workspace, so it **had never once read a frozen artifact** in any round.
The snapshot now lives in a gitignored `.review-fanout/` inside the worktree, where every reviewer can
read it, while `--out` is refused *inside* the worktree (see below). Two rules that look contradictory
until you know which failure each one prevents.

**Blockers, fixed:**

1. A quorum return with findings that was not auto-counted could be silently neither counted nor
   flagged — the case being a healthy 1–10 KB review whose CLI exited nonzero. Any quorum return with
   findings is now `unresolved` whatever the reason, so exit 3 fires and nothing goes unread.
2. The launcher-drift check compared commands but discarded their quorum classification: deleting a
   route, duplicating one, or promoting a tier-3 row from `extra` to `quorum` all passed while changing
   *who can satisfy a round*. It now checks the row set — expected quorum/extra counts and no duplicate
   names. **Its own first run failed**, correctly: an anchored `^manifest` pattern had silently matched
   only the three unindented rows and reported zero extras.
3. An in-repo `--out` filled with prompts and outputs after `tree_before` was taken, so the launcher
   reported its own files as contamination — and concurrent reviewers could read each other's outputs
   off disk and manufacture corroboration. `--out` inside the worktree is now refused outright.

**Should-fixes, fixed:** `--freeze` now refuses when `assume-unchanged`/`skip-worktree` paths or dirty
submodules would make the artifact silently incomplete; exactly one artifact selector is enforced
(`--sha` with `--snapshot` used to validate one and hand reviewers the other — both flags are gone as of
round 5); every route is wrapped in
a real `timeout`, because the agy timeout variable bounds only the agy wrappers and the "expect up to 15
minutes" promise was therefore false for two of three reviewers; the roster's "single home / others do not
restate" claim contradicted `CLAUDE.md` and both skills, which deliberately summarise the quorum and
freeze rules — narrowed to "canonical home", with one-line summaries explicitly permitted and rival
copies still forbidden; the validator header stopped repeating the overbroad "no longer route anywhere"
claim the plan itself corrects.

**A fix of mine that measurement rejected.** Round 3 asked for a symlink-loop guard; I added
`DirAccess.is_link()`. Sol then pointed out `simplify_path()` is lexical, so the visited set was a false
guard — correct. But `is_link()` turned out to be worse: it dropped the scan from **113 files to 100 in a
repository containing no symlinks at all** (`find . -type l` is empty). Replaced with a depth cap, which
cannot skip a real file, and the rejection is recorded in the validator's header so nobody re-adds it.

**Coverage re-proved by probe, not by reading:** a forbidden fragment injected into `CLAUDE.md`,
`AGENTS.md`, `docs/STATUS.md`, `docs/DECISIONS.md`, `docs/plans/BACKLOG.md`,
`docs/systems/turn-engine/turn-engine.md` and a skill each turned the gate red; each file was restored
immediately afterwards.

**Process note against myself:** round 4's report flagged `.claude/REVIEWERS.md`,
`docs/plans/0054-*.md` and `tools/validate_reviewer_facts.gd` as *changed since launch* — because I
applied agy's findings while Sol was still running. The detector was right, and the rule is to leave the
tree alone until a round closes.

## What round 5 caught — and the USER call that ended the regress (3/3 quorum, the first ever)

Sol 3.1 KB / 6 findings, agy 3.8 KB / 5, DeepSeek 6.6 KB / 4. **First round in which all three returned
substantively** — because round 4's fix put the artifact inside the worktree where DeepSeek could read it.

**The trend, stated plainly:** rounds 2-5 found 13, 16, 22 and 10 findings, and *every blocker after
round 2 was in the launcher*, never in the consolidation (reported clean four rounds running). The bug
surface was the launcher's flexibility: three artifact selectors, two output-location rules, a triage
classifier. **USER call 2026-07-30: simplify rather than keep patching.** `--sha` and caller-supplied
`--snapshot` are DELETED. `--freeze` is the only way to name a dirty artifact; a clean tree reviews HEAD.
That removed the containment, existence and completeness checks wholesale instead of fixing them — the
option that is harder up front and leaves the cleanest code, per the standing instruction.

**Blockers fixed:**

1. **A tier-3 model could satisfy a quorum.** The drift check counted roles but never checked WHO held
   them: swap DeepSeek to `extra` and MiniMax to `quorum` and the 3/2 counts, the unique names and every
   roster command still passed. It now compares the reviewer SETS by name. Probed: the swap is caught.
   This was the rule the USER was most explicit about, and the gate had a hole in exactly it.
2. **A still-running reviewer did not block a green report** — two finished returns exited 0 while the
   third was mid-answer. Any quorum row that is running, or has produced no output file at all, now
   counts as unresolved.
3. **A caller-supplied snapshot was never checked for worktree containment**, so the DeepSeek permission
   failure could recur through the other input path. Moot: that path is deleted.
4. **`git submodule status`'s `+` does not mean "dirty"** — it means the checked-out commit differs from
   the recorded gitlink, and says nothing about uncommitted content at the recorded commit, which is
   equally absent from the superproject diff. Now each initialized submodule is asked directly.
5. **Detected contamination printed but did not affect the exit status**, so exit 0 could claim "nothing
   left to judge" while cross-review corroboration was possibly fake. It now counts as unresolved.

**Documentation, from agy:** `--out` must be outside the worktree and the snapshot lands inside it — both
now documented, because a future agent will reach for `--out out/` and be refused; the timeout wording
now says the script *enforces* it via `timeout` rather than merely exporting a variable only agy reads;
`CLAUDE.md`'s agy section was still a COPY of wrapper detail rather than a one-line summary, which the
newly-narrowed "canonical home" wording forbids.

**Three of my own comments described behaviour the code no longer had** (Sol, nit): the claim that
exactly one selector was required when zero is legal on a clean tree; "the out dir is skipped" when it is
refused; "canonical paths are the loop guard" when the depth cap is. All corrected — a comment that lies
is worse than no comment, and these were mine.

## What round 6 caught, and where the rounds stopped (2/2 quorum)

Sol 1.6 KB / 2 findings, agy 1.7 KB / 3, DeepSeek 10.3 KB / 4 (SUSPECT by 44 bytes over the band; read,
and real). Both blockers accepted:

1. **Sol independently found the `$sha` unbound-variable abort** — the simplification deleted the variable
   but left it referenced in the launch summary, so under `set -u` every real launch started three
   reviewers and *then* exited with an error, which reads as failure and invites a duplicate launch. I had
   already hit and fixed this by running the thing; Sol found it by reading the frozen artifact, which is
   also proof the freeze discipline works — it reviewed exactly the state it was handed.
   **Disclosure:** that fix (a six-line `echo` block, no logic) landed *after* round 6's artifact was
   frozen, so it is the one part of this commit no reviewer saw. Verified by `bash -n` and a live
   `--freeze --dry-run`. DeepSeek noticed the drift unprompted and said so — "the frozen diff has 405
   lines, working tree has 408".
2. **The keyed-mapping hole, third attempt at the same rule.** Round 4 checked commands were present;
   round 5 checked the role counts; round 5's fix checked the names. Sol then showed you could swap the
   *commands* between the `agy` and `minimax` rows — names correct, counts correct, every command still
   in the roster — and a tier-3 route occupies a quorum slot. The roster now carries the round as a
   machine-readable `name  role  command` block and the validator compares it as a keyed set. Probed all
   three attack shapes: command swap, route deletion, role promotion. All red.

agy's three: `hexcombat-failure-archaeology` still claimed a caller-supplied snapshot "is validated"
(that path is gone); `.claude/REVIEWERS.md` said `--role` was needed "always" and then "quorum only" two
lines later; and it flagged that "a 30-second probe" cannot coexist with "budget 900 s" unless the doc
says a probe is a trivial prompt rather than a review — which is exactly what was meant and was not
written down.

**Rounds stopped here, by USER call.** Two rounds per unit of work; findings about the *change* get
fixed, findings about the *review tooling* go to `docs/plans/BACKLOG.md` instead of re-opening the round.
This plan ran six because its subject WAS the tooling, which made every tooling finding in scope — a
condition that will not recur. Residual declined items are logged in BACKLOG.

## Explicitly out of scope (checked — don't re-raise)

- **Re-measuring reliability.** The route record stays as measured; this plan moves facts and adds a
  gate. New measurements get appended as they happen, per the existing rule.
- **Changing the two-round structure.** Plan review before code, diff review before commit — both still
  required. Only the fan-out and its bookkeeping change.
- **Auto-summarizing reviewer output.** Rejected above: it would launder fabricated citations.
- **Gating the global files by tooling.** Impossible from a repo validator; handled by making them
  contract-only.
- **`hexcombat-failure-archaeology`'s `pi`/`opencode` entries.** Those are historical records with a
  `Status:` line and stay verbatim — the validator's escape markers must not fire on them. Only
  `build-and-env`'s live *instruction* is wrong.
- **Reviewer prompts for non-review delegation** (mechanical sweeps handed to weak models). Different
  job, different rules; `CLAUDE.md`'s "Weaker models" section keeps that content.

## Open question — RESOLVED

*Does the 2-of-3 quorum apply to both rounds?* **No.** USER call 2026-07-30: it binds the
**implementation of a numbered plan** only. A plan document needs one substantive read; anything
smaller is judgement. Folded into `.claude/REVIEWERS.md` § The round, `CLAUDE.md` work-loop step 6, and
both review skills.
