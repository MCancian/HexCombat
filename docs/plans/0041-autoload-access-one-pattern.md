---
title: "0041: One pattern for reaching an autoload from tool-loadable code"
status: "Sketch"
created: "2026-07-25"
---

# Plan 0041: One pattern for reaching an autoload from tool-loadable code

## Golden-pin budget

none

## The problem

A `-s` SceneTree tool script is loaded **before** the autoload singletons are registered as
identifiers. Everything in that script's compile-time closure is compiled at that moment, so any class
in it that names `GameData` / `GameState` / `EventBus` fails to compile — and the tool then runs its
`_initialize`, prints its banner, and never reaches `quit()`, hanging the gate.

The workaround is a node-path accessor, and it is currently **copy-pasted per file**:

| File | Accessor |
|---|---|
| `scripts/LLMGameAPI.gd:30,34` | `_game_data()` / `_game_state()` |
| `scripts/SelfPlayRunner.gd:26,29` | `_gd()` / `_gs()` |
| `scripts/InlandClearPolicy.gd:26` | inline `var game_data: Node = Engine.get_main_loop()…` |
| `scripts/GarrisonDrawPolicy.gd:16` | inline, same shape |

Four files, six sites, three different naming conventions, one of them inline inside a function. The
correct pattern is discoverable only by already knowing the rule.

**Cost so far:** plan 0032 broke it and took four validators plus the batch runner down. Plan 0037
broke it again in `SelfPlayRunner` and hung the gate for two full runs (~10 min each) before it was
diagnosed.

## What already exists

`tools/validate_tool_script_purity.gd` (shipped 2026-07-25) now **catches** this across the whole
`-s` compile closure — 77 scripts — and reports the offending `file:line`. `run_all_tests.py` passes
`--quit-after`, so the failure is loud rather than a hang.

**So the bleeding is stopped.** This plan is about not needing the bandage: making the correct pattern
the obvious one, so the gate rarely has to fire.

## Shape of the fix

A single `ScriptRuntime` (name TBD) in `scripts/`, itself autoload-free, owning the accessors:

```gdscript
class_name ScriptRuntime
extends RefCounted

static func game_data() -> Node
static func game_state() -> Node
static func event_bus() -> Node
```

Then the four files call `ScriptRuntime.game_data()`. One home, one convention, and the class carries
the explanation of *why* it exists — which is currently duplicated in prose across several file
headers.

**Open question to settle in code, not by drift:** whether `ScriptRuntime` should cache the lookup.
Do **not** cache initially. `GameData` is an autoload whose identity is stable, but caching introduces
a lifetime question across `reset_to_scenario` and across the multiple `load_all()` calls validators
make, and the current per-call `get_node` has never shown up as a cost. Measure before optimising.

## Verification

- `tools/validate_tool_script_purity.gd` must stay green — `ScriptRuntime` itself lands in the
  closure, so it is checked automatically.
- Gate ALL PHASES GREEN, no pin moved. This is a pure call-site rename; if any pin moves, something
  else changed.
- **Prove the gate still catches a regression** after the change: reintroduce a direct `GameState.`
  reference in `SelfPlayRunner`, confirm the purity validator names the `file:line`, revert. A guard
  not seen to fire is not a guard (`hexcombat-diff-review`).
- `tools/validate_llm_api_purity.gd` no longer exists — the validator is
  `validate_tool_script_purity.gd`. Do not resurrect the old name.

## Optional second half — worth doing, worth judging separately

Extend the purity validator to also flag the **inline** form
(`Engine.get_main_loop().root.get_node("GameData")`) outside `ScriptRuntime`, so the convention is
enforced rather than merely available. This is a style gate, not a correctness gate — the inline form
is *correct*, just undiscoverable. Land it only if the convention has actually settled; a style gate
on a convention nobody follows yet is just noise.

## Design calls for the USER — none

## Risks

- **Low value relative to the others.** The failure it prevents is now caught by a gate that names the
  file and line. This is ergonomics and legibility, not risk. Ranked accordingly.
- Naming: `ScriptRuntime` may not be the right name; it is not a runtime. Consider `Autoloads` or
  `RuntimeNodes`. Decide once, do not leave two.

## Dependencies / notes

- Independent of 0038, 0039, 0040. Small enough to slot in as filler.
- Do not do this **instead of** the plan-review/diff-review discipline — the 0037 regression was
  caught by neither a gate nor a convention, but by a hang; the gate is what fixed that.
