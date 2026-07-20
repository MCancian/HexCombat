---
title: "0017: Move Order Validation off push_error to a Typed Result"
status: "✅ Shipped 2026-07-20"
created: "2026-07-19"
updated: "2026-07-20"
---

> **CLOSEOUT (2026-07-20, agent):** Shipped. `scripts/model/OrderResult.gd` added; `OrderValidator`
> `add_move_order`/`add_commit_order` + `GameState` wrappers return `OrderResult`; LLM API branches
> on `result.ok` and surfaces `result.message`; 11 GdUnit assertions moved off `is_push_error` to
> `code`. Golden byte-stable, 120 suites green. Durable facts: `docs/DECISIONS.md` (2026-07-20),
> `docs/STATUS.md` (Engine), `docs/systems/turn-engine.md` §Planning, `docs/systems/llm-api-selfplay.md`
> §4, `OrderValidator.gd` header. Plan retained for history only.

# Plan 0017: Move Order Validation off push_error to a Typed Result

Order validation rejections (destroyed brigade commits, moves beyond allowance, team
mismatches, duplicates) are currently signalled by `push_error(<string>)` + early `return`
from `void` methods. Three costs:

1. **Tests are brittle** — they must regex-match the exact `push_error` string via
   `assert_error().is_push_error("...")`; any message edit breaks the test.
2. **Callers can't tell success from failure** — the methods return `void`. The LLM API
   currently *infers* rejection by counting `orders`/`commitments` before and after the call
   (`LLMGameAPI._apply_move_action`, `_apply_commit_action`) and then emits a generic
   `"move rejected: ..."` string that **discards the actual reason**.
3. **No structured reason reaches the agent** — the LLM sees a generic rejection, never
   *why*, so it can't correct the order.

`OrderValidator.gd`'s own class doc (lines 10–13) already names this plan as the owner of the
typed-Result migration; plan 0014 P4 deliberately preserved push_error semantics to keep that
extraction mechanical.

## Ground truth (verified against code 2026-07-20)

> ⚠️ The subagent research reports that seeded this plan were **inaccurate** for this repo —
> they invented an `add_jlsf_order` / `valid_move_targets` / `valid_commit_candidates` surface
> and wrong error strings. Trust the code, not those reports. Actual surface below.

**Validation chokepoint — `scripts/resolvers/OrderValidator.gd`** (static, take `GameStateData`):

| Method | Return | Rejection sites (push_error) |
|--------|--------|------------------------------|
| `add_move_order(state, team, brigade_id, target_hex, mode)` | `void` | 6: wrong phase, unknown brigade, team mismatch, unknown target_hex, unknown mode, pending move/commit dup, beyond allowance |
| `add_commit_order(state, team, brigade_id, target_hex)` | `void` | 9: wrong phase, unknown brigade, team mismatch, destroyed, admin-moved, unknown target_hex, already in hex, not adjacent, pending dup |
| `eligible_commit_brigades(state, team, target_hex)` | `Array` | 1: unknown target_hex |

Note: `eligible_commit_brigades`' lone `push_error` is a **programmer-error** guard (query
method fed a bad hex), not user-order validation — leave it as `push_error`. Migration scope is
`add_move_order` + `add_commit_order` only. There is **no** JLSF order inside OrderValidator;
`deploy_jlsf` is validated inline in `LLMGameAPI._apply_deploy_jlsf_action` and routed through
`GameState._apply_order`.

**Callers of the two migrated methods:**
- `scripts/GameState.gd:182,192` — thin `void` delegating wrappers (`add_move_order`,
  `add_commit_order`); also invoked from `GameState._apply_order` (lines 387/389).
- `scripts/LLMGameAPI.gd:142,155` — the before/after count workaround to be deleted.

**Tests asserting validation `is_push_error` (migration targets):**
`tests/composition_test.gd` (6), `tests/movement_test.gd` (3), `tests/game_state_test.gd` (4).
(`dice_ext_test.gd` and `symbol_library_test.gd` also use `is_push_error` but on unrelated
dice/symbol paths — **out of scope**.)

**No existing validation Result/enum type.** Precedent for typed Resource returns:
`scripts/model/CombatResult.gd`, `scripts/model/MineResult.gd` (outcome resources).

## Design

Introduce a typed `OrderResult` (a `Resource` in `scripts/model/`, matching the CombatResult /
MineResult pattern), carrying:
- `ok: bool`
- `code: OrderResult.Code` — an enum of rejection categories (e.g. `UNKNOWN_BRIGADE`,
  `TEAM_MISMATCH`, `DESTROYED`, `ADMIN_MOVED`, `NOT_ADJACENT`, `BEYOND_ALLOWANCE`,
  `DUPLICATE_ORDER`, `WRONG_PHASE`, `UNKNOWN_HEX`, `UNKNOWN_MODE`, `OK`)
- `message: String` — the human-readable detail (same text the push_error carried), for logs
  and agent feedback.

`add_move_order` / `add_commit_order` return `OrderResult` instead of `void`; each `push_error`
+ `return` site becomes `return OrderResult.reject(Code.X, "...")`; the success tail becomes
`return OrderResult.ok_result()`. Enum + message keeps machine-branchable codes *and* legible
text — the "harder up front, cleaner code" choice over a bare String or bare enum.

Rationale to record in DECISIONS: a typed Resource (not a Dictionary) so the code path is
type-checked and self-documenting, consistent with the resolver-summary convention.

## Objectives

1. Add `scripts/model/OrderResult.gd` (`Code` enum + `ok`/`code`/`message`, `reject`/`ok_result`
   factories).
2. Migrate `OrderValidator.add_move_order` + `add_commit_order` to return `OrderResult`;
   update the class doc (drop the "preserves push_error" note).
3. Update `GameState.gd` wrappers to return `OrderResult`; update `_apply_order` call sites.
4. Update `LLMGameAPI._apply_move_action` / `_apply_commit_action`: delete the before/after
   count hack; branch on `result.ok`; on reject, push `result.message` (the real reason) into
   the `errors` array that `_action_result` already surfaces to the agent.
5. Migrate the 13 validation assertions in `composition_test.gd`, `movement_test.gd`,
   `game_state_test.gd` from `assert_error().is_push_error("...")` to asserting
   `result.ok == false` and `result.code == OrderResult.Code.X` (drop the string match; the
   companion `_is_noop` state-mutation checks stay as-is).

## Open design question (USER)

None expected — this is technical hygiene. Surface only if the LLM observation schema should
gain a durable `last_action_result` field (vs. the existing per-call `errors` array), which is
an agent-UX call, not a code call.

## Verification

- `bash tools/run_all_tests.sh` (Linux) / `pwsh -File tools/run_all_tests.ps1` (Windows) —
  **ALL PHASES GREEN**. Migrated tests must still cover every rejection reason (assert on
  `code`, not incidentally).
- Golden gate byte-stable — this is control-flow-only; no RNG or resolution math touched.
- Drive one rejected order through the LLM API (`hexcombat-run-and-operate`) and confirm the
  `errors` array now carries the specific reason, not `"move rejected: ..."`.

## Closeout targets

`docs/systems/` order-validation doc (or the relevant module doc) updated; `docs/STATUS.md`
bullet; `docs/DECISIONS.md` 3–5 lines (typed OrderResult over push_error, enum+message
rationale); archive this plan.
