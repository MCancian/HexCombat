# Orchestrator Handoff — continue the TIV port via opencode subagents

**Audience:** the next Claude orchestrator session. Read `AGENTS.md` → `CLAUDE.md` → `ROADMAP.md`
→ `PLAN.md` first; this doc is the *active build plan* for finishing the TaiwanInvasionViewer
(TIV) port, the **opencode** implementer workflow, and the **per-sub-task retrospective loop** the
user asked for. The full per-sub-task breakdown lives in the approved plan file
`C:\Users\mdogg\.claude\plans\where-we-left-we-gentle-parnas.md` (written for pi — the *backlog* is
still correct; only the implementer CLI changed). Do not duplicate it here; point at it.

---

## 1. Where the port stands (verify before trusting)

Confirm with `git log --oneline -15` + a fresh `pwsh ./tools/run_all_tests.ps1` (must exit 0).

- **Wave 0 foundations — DONE:** Dice/RNG extensions (`randf`/`weighted_choice`/`weighted_choices`/
  `shuffle_indices`/`derive`), Theater model (`scripts/Theaters.gd` + `data/theaters.json`),
  Ship-type model (`scripts/model/ShipState.gd` + `data/ships.json`).
- **D4 IJFS A–F — DONE & committed:** models (`scripts/model/ijfs/`), loaders, data (`data/ijfs/`),
  and the six pure libs — `IjfsDetection`, `IjfsTargeting`, `IjfsStrike`, `IjfsFiringCapacity`,
  `IjfsEngagement`, `IjfsAdHealth`, `IjfsWarmup` — each with a GdUnit4 suite in `tests/ijfs/`
  (~238 cases, gate green).
- **D4-G, D4-H — NOT STARTED.** ← resume here.
- **D3 anti-ship & mine warfare — NOT STARTED** (no `scripts/antiship/`, `data/antiship/` yet).
- **Final integration** (turn-sequence wiring, LLM observation contract) — after D3.

**Backlog order (dependency-checked):** `D4-G → D4-H → D3-A → {D3-B, D3-C, D3-D, D3-E} → D3-F →
final integration`. D3-B consumes D4-H's per-(TO,Type) destroyed/suppressed output; D3-F consumes
D0-C's ship layer via the `lost_at_sea` seam. Sub-task specs: approved plan §"Wave 1+ — D4" and
§"Wave N — D3". TIV oracle file/line refs: `ROADMAP.md` §D3/§D4.

---

## 2. The implementer: opencode (not pi)

pi is broken on this box (it spawns the `opencode` backend via `spawn('opencode')`, which can't
resolve the Windows `.cmd`/`.ps1` shim → `ENOENT`). Call `opencode` directly. Full usage is in
`CLAUDE.md` §"Using opencode". Quick reference:

```bash
# implement (read/write; build agent auto-allows its tools)
opencode run -m opencode/deepseek-v4-flash-free -s hexcombat-d4g "<self-contained brief>" -f scripts/ijfs/IjfsEngine.gd
# read-only review (explore subagent has no write tools)
opencode run -m opencode/deepseek-v4-flash-free --agent explore "<question>"
# continue the SAME session (keeps context — needed for the retrospective step below)
opencode run -m opencode/deepseek-v4-flash-free -s hexcombat-d4g "<follow-up>"   # or -c for last session
```

**Caveat:** `deepseek-v4-flash-free` is a small free model — weaker than a frontier implementer.
Keep briefs tight and self-contained, keep your verification bar high, and review every diff for
fidelity (formulas, constants, clamp bounds, RNG draw order) and scope drift. If a sub-task is too
intricate for the free model after a couple of focused attempts, implement it yourself and note
that in the retrospective.

---

## 3. The per-sub-task loop (with retrospective)

For **each** sub-task, run this loop. Steps 4 and 6b are the new parts the user requested.

1. **Plan.** Read the TIV oracle source for the sub-task *and its pytest* (the behavioral oracle).
   Write a self-contained brief: exact TIV source + line refs, target HexCombat files, the
   constants/formulas/RNG-order to preserve, the repo patterns to reuse, and the pytest cases to
   mirror. Tell opencode to follow `AGENTS.md`.
2. **Implement.** Dispatch to opencode in a named session (`-s hexcombat-<subtask>`).
3. **Report.** Have opencode report what it changed and how it self-checked.
4. **Retrospective — ask the implementer what it would do differently.** In the **same session**
   (so it still has full context), ask — *after* implementation and *after* it has seen the gate
   result:
   > "Knowing what you know now that it's implemented and gated: what would you do differently?
   > What surprised you, what's fragile or under-tested, what tech debt did you take on, and what
   > would make the *next* sub-task easier or safer? Be specific and concrete."
   Capture the answer. This is the implementer's lessons-learned, recorded *separately* from design
   decisions (see §4).
5. **Verify independently (orchestrator gates).** Never trust the report. Run, with captured
   stdout/stderr: `--import` (class cache) → the smoke test → the relevant `tools/validate_*.gd` →
   `pwsh ./tools/run_all_tests.ps1`. Confirm exit 0, the GdUnit4 case count grew, and the **ground
   combat golden invariant is byte-stable** (seed 20260624 → casualties=2, feba=0.76).
6. **Review — implementation *and* lessons.**
   a. **Diff review:** scope drift (exclude tooling/settings; never commit `.mcp.json`), fidelity
      to the TIV math/RNG order, faithful-port divergences justified (see §5).
   b. **Lessons review:** read the retrospective from step 4. Decide per item: *act now* (fold into
      this sub-task before committing), *act later* (turn into a backlog/Open-Question item), or
      *just record*. Apply the "act now" items.
7. **Record.** Append **design decisions** to `PLAN.md` → Decisions (existing append-only log) and
   the **retrospective + your triage** to `docs/RETROSPECTIVES.md` (see §4). Cross-link them.
8. **Commit on green.** One coherent commit per sub-task; end with the `Co-Authored-By` trailer.
   **Push at milestones** (D4 fully green; D3 fully green), not per micro-commit.

> Waves: dependency-independent sub-tasks (e.g. D3-B…E once D3-A + D4-H are in) can run as separate
> concurrent opencode sessions; gate + commit + retrospect each as it returns.

---

## 4. What gets recorded, and where

Two distinct records — keep them separate so later review is clean:

- **`PLAN.md` → Decisions log** — *real design decisions*: a choice you (or the implementer) made
  that isn't forced by the source — a faithful-port divergence, a key/shape mapping, an ordering
  decision, an Open Question resolution. Append-only, dated, one entry per decision. This is the
  authoritative "why we did it this way" record for later review.
- **`docs/RETROSPECTIVES.md` → per-sub-task entries** — the *implementer's lessons learned* from
  step 4 ("what I'd do differently") **plus the orchestrator's triage** (act now / act later /
  record) from step 6b. This is process/quality feedback, not design rationale. Format and the
  seed entries are in that file.

If a retrospective surfaces a genuine design question, promote it to a `PLAN.md` Decision or Open
Question and cross-link (`see RETROSPECTIVES.md <date>/<subtask>`).

---

## 5. Guardrails (carry over from AGENTS.md — do not relax)

- **Faithful port.** Preserve formulas, constants, clamp bounds, RNG **draw order**, and result
  dict key shapes exactly. The settled strategy mirrors **formulas + draw order**, *not* numpy's
  PCG64 bitstream (not reproducible in Godot) — tests inject scripted draws.
- **Documented divergences (in-spirit, already used in D4):** Python tuple → GDScript Dictionary
  with stable source-parallel keys; type-guard before cross-type comparison (`bool == ""` raises in
  GDScript); fail-loud on missing config keys vs Python's silent `.get(...,0)`. Log any *new*
  divergence in the Decisions log.
- **Golden invariant.** Ground combat seed 20260624 → casualties=2, feba=0.76 must stay
  byte-stable. New phases use their own seeded streams and must not consume combat RNG.
- **Integration tests go in validators, not GdUnit.** Full-turn/turn-resolution assertions live in
  `tools/validate_*.gd` (`extends SceneTree`) to dodge the Godot 4.7 GdUnit teardown
  heap-corruption flake. Keep GdUnit for pure-lib units.
- **ScriptedDice.** Use the shared `tests/helpers/ScriptedDice.gd` (global `class_name`); never
  declare a local `class ScriptedDice` (class_name collision = parse error). `randf()` pops the
  3rd ctor arg (`floats`); `choose_indices` pops the 2nd (`choices`).
- **Commits.** Only the orchestrator commits. Never commit `.mcp.json`. Review every diff for scope
  drift before staging.

---

## 6. Immediate next action: D4-G

`scripts/ijfs/IjfsEngine.gd` — `run_daily(state, dice) -> Dictionary` of ledgers (detection,
strike, engagement, contest, free-shot, target-status, inventory, OOB, summary) porting TIV
`run_daily_ijfs.py`'s 6-phase sequence + `run_context.py` (IJFSRunContext/WarmupContext
day-semantics) + a state container + `summarize_run` (logging_utils.py). **Do NOT port
`write_outputs` file IO** — return the ledgers dict directly. Add day-to-day continuity (carry
target destroyed/suppressed/known flags, depleted munitions, attrited OOB into next day). Mirror
the full-run + continuity cases from `test_ijfs_standalone.py` (the 67KB oracle). Then **D4-H**
(GameState wiring + writeback), then **push the D4 milestone**.
