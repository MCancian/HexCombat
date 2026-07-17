---
name: hexcombat-change-control
description: How changes are classified, gated, verified, and committed in HexCombat. Read BEFORE making any code or data change — it tells you which verification tier the change needs, when a golden re-baseline is allowed, the commit/push policy, and the non-negotiables with the incidents behind them.
---

# HexCombat change control

## Classify the change first

| Class | Examples | Required gate |
|---|---|---|
| **Docs-only** | `docs/`, `*.md`, skill files | None (review your own diff) |
| **Data-only** | `data/*.json` values, new scenario | Relevant `tools/validate_*_data.gd` + full gate; expect golden/fixture impact if the golden scenario reads the value |
| **Additive logic** | New pure lib, new validator, new test, new observation field | Full gate + a new test covering the addition + fixture regen if the JSON contract grew |
| **Golden-touching** | Anything in the turn path: `GameState`, resolvers, combat math, RNG use, loaders feeding the golden scenario | Full gate + golden byte-stability proof (below); work in the smallest possible steps, one commit each |
| **Architectural** | Module boundaries, autoloads, serialization seams, decomposition slices | All of the above + re-read `hexcombat-architecture-contract` first; sequence per the campaign/handoff doc if one exists |

When unsure, treat it as the higher class.

## The golden invariant

`tools/validate_headless_turn.gd`, seed **20260624**, must print the pinned casualties/feba
values. The validator's PASS line is the source of truth — this file deliberately does NOT
repeat the numbers (they rotted here twice on 2026-07-09 alone). The scripted turn's SHAPE
(mover/defender/hexes) lives in `tools/GoldenScript.gd`, shared by all golden validators;
re-baseline history is in `docs/DECISIONS.md` (pre-2026-07-10: `docs/archive/PLAN.md`).

- A refactor/cleanup/extraction must keep it **byte-stable**. If it moves, your change consumed or
  reordered RNG draws, or changed math — that is a bug in the change, not a new baseline.
- A **re-baseline is legitimate only** when a deliberate, user-visible behavior change is the
  point (a rebalance the user asked for, a fixed correctness bug like the odd-r adjacency fix).
  Re-baselining requires: (1) the user's call or an explicit correctness argument recorded in
  docs/DECISIONS.md, (2) updating the pinned values everywhere (`validate_headless_turn`,
  `validate_cleanup` fingerprint, `docs/STATUS.md`, fixtures, tests keyed to the old values).
- The item-8 gate (`tools/validate_fixtures.gd`) byte-compares committed `docs/examples/*.json`
  every run — serialization drift fails loud. If it fires, regenerate via `tools/export_llm_*.gd`
  and **review the diff**: intended contract growth → commit the regen; unintended → your change
  leaked into the JSON contract.

## Non-negotiables (with the incident behind each)

1. **All randomness through injected `Dice`; new randomness gets a derived substream.** Global
   RNG or base-stream borrowing silently shifts every later roll. (Gated by
   `validate_no_global_rng.gd`; topology in `hexcombat-architecture-contract`.)
2. **Fail loud — no `dict.get(key, default)` across module boundaries.** The exquisite-intel
   warmup config was silently dead the entire project because every consumer defaulted the missing
   keys (see `hexcombat-failure-archaeology`). Use typed Resources or key-allowlist asserts.
3. **One extraction/conversion per commit, gate green after each.** The item-9/item-3 typed
   Resource migrations survived only because each field was its own verified commit.
4. **Verify a determinism failure standalone before "fixing" it.** A census flake was nearly
   "fixed" with a phantom reset change; isolated re-runs proved it was a stale class cache from
   running the gate mid-edit. Re-import, re-run the failing validator alone, twice, before
   touching reset/state code.
5. **Design changes are the user's; divergences get documented.** HexCombat is the design of
   record (TIV was the port oracle — divergences from it are allowed when the user directs them),
   but every behavior divergence/rebalance lands in docs/DECISIONS.md with pointers to the why.
6. **Never commit `.mcp.json`** (machine-specific Godot path, intentionally locally modified).
7. **Tie tuning hooks to a need.** Don't populate optional knobs speculatively — an unused field
   is byte-stable; a populated one silently re-baselines results.

## Verification protocol (golden-touching work)

1. Re-import: `& "C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" --import` — zero SCRIPT/Parse errors.
2. Golden: run `validate_headless_turn.gd` standalone; confirm the pinned values.
3. Full gate: `pwsh -File tools/run_all_tests.ps1` → **ALL PHASES GREEN** (teardown-flake
   warnings are OK; see `hexcombat-debugging-playbook` before overriding any red).
4. Review your own diff for scope drift before committing.
5. For serialization-adjacent changes, the extra proof: regenerate a fixture with and without
   your change and hash-compare.

## Commit & push policy

- Commit each verified unit; **push at milestones** (a coherent item fully done and green).
- Message style: `<type>: <what> (<tracking ref>)` matching `git log`; end with the
  `Co-Authored-By` / session trailer the harness specifies.
- Record per `hexcombat-docs-and-writing`: canonical homes updated (STATUS, systems doc), 3–5-line
  `docs/DECISIONS.md` entry with pointers, plan closeout (checklist + archive move) if a
  `docs/plans/NNNN-*` plan drove the work; **status** → `docs/STATUS.md`
  (present tense, no dates); **lessons** → `docs/RETROSPECTIVES.md`; delete the completed backlog item.
  Details: `hexcombat-docs-and-writing`.
- **Pause and surface to the user** on: a genuine design decision the docs don't answer, a gate
  you can't get green after a couple of focused attempts, anything destructive/irreversible.

## Who implements

The frontier agent implements directly (user call 2026-07-02). `opencode run` (small free model)
is reserved for cheap mechanical or read-only exploratory chores — never for golden-touching or
architectural work, and its output is always independently verified.
