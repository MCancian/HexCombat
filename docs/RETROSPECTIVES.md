# Retrospectives — implementer lessons learned

Per-sub-task "what would you do differently, knowing what you know now" notes, captured **after**
implementation and gating (see `docs/ORCHESTRATOR_HANDOFF.md` §3 step 4), plus the orchestrator's
triage. This is **process/quality feedback** — design rationale lives in `PLAN.md` → Decisions.
Append-only; newest at the bottom of each section. Cross-link decisions as `PLAN.md <date>`.

## Entry format

```
## <date> — <sub-task id>: <title>   (implementer: opencode <model> | direct)

**What would you do differently (implementer):**
- <specific, concrete lesson — fragility, tech debt, surprise, what'd make the next task easier>

**Orchestrator triage:**
- <lesson> → act now | act later (→ PLAN.md Open Question / backlog) | record only — <note>
```

---

## 2026-06-26 — Tooling: pi → opencode implementer switch   (direct)

**What would you do differently:**
- pi (the previous implementer CLI) is unusable on this Windows box — it spawns the `opencode`
  backend via `spawn('opencode')` with no `shell:true`, which can't resolve the `.cmd`/`.ps1`
  shim and dies `ENOENT`. Calling `opencode run` directly works. Would have switched at first
  failure instead of diagnosing pi's internals.
- The free model `opencode/deepseek-v4-flash-free` is weaker than the prior GPT-5.5 implementer;
  briefs must be tighter and the orchestrator's diff review more careful.

**Orchestrator triage:**
- Switch to opencode → **acted now**: updated `CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`
  (`Bash(opencode *)`), `docs/LLM_PLAYTESTING.md`. Historical pi references in dated logs left
  intact (append-only history). See `PLAN.md` Decisions (pending entry).

---

## D4-A…F port — carried-forward lessons (retro-logged 2026-06-26)

These were learned while porting the IJFS pure libs (mix of pi and direct); recorded here so the
next sub-tasks (D4-G/H, D3) don't relearn them.

**What would you do differently:**
- **ScriptedDice class_name collision.** An implementer declared a local `class ScriptedDice extends
  Dice`, colliding with the global `class_name ScriptedDice` → parse error. Always reuse
  `tests/helpers/ScriptedDice.gd`; brief the implementer on its ctor (`randf()` pops the 3rd arg
  `floats`; `choose_indices` pops the 2nd arg `choices`).
- **Cross-type comparison.** `value == ""` raises in GDScript when `value` is a bool/null (Python
  tolerates). Type-guard first (`if value is String:`). Bit `IjfsStrike._wildcard`.
- **Result-shape fidelity.** A test asserted `mobile_cap_applied` but the port returns
  `legacy_cap_applied`. Mirror the *source* key names exactly; grep the pytest for the asserted keys
  before writing the dict.
- **GdUnit assertion API.** `assert_object(dict).is_empty()/.is_same()` is invalid for dicts — use
  `assert_dict(...).is_empty()/.is_equal()`.
- **Fail-loud vs silent defaults.** Python `.get(key, 0)` hides missing config; the port fails loud
  on missing `firing_units`/`sorties`. Keep that — but brief the implementer so it doesn't
  "helpfully" re-add silent defaults.

**Orchestrator triage:**
- All → **record only / brief forward**: fold the relevant items into each sub-task brief. The
  ScriptedDice and key-shape items are the highest-value to repeat in every D3 brief.
