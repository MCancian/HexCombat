---
title: "0019: Consolidate the Brigade.Team → string converters"
status: "Ready"
created: "2026-07-20"
---

# Plan 0019: Consolidate the `Brigade.Team → "Red"/"Green"` converters

The enum-to-display-string conversion `Brigade.Team → "Red"/"Green"` is reimplemented in **six**
places, each byte-identical or near-identical, none owned by the enum's owner (`Brigade`). This is
a cross-module seam: UI, API, resolver, and content layers each carry their own copy, free to drift.

## Ground truth (verified 2026-07-20)

Six converters, all mapping `GREEN → "Green"`, else `"Red"`:

| Location | Symbol | Kind |
|----------|--------|------|
| `scripts/model/Brigade.gd` | — (enum `Team { RED, GREEN }` lives here) | owner |
| `scripts/resolvers/OrderValidator.gd:124` | `team_to_string` (static, public) | resolver |
| `scripts/GameData.gd:729` | `_team_to_string` | content autoload |
| `scripts/GameController.gd:154` | `_team_to_string` | UI |
| `scripts/InfoPanel.gd:91` | `_team_to_string` | UI |
| `scripts/LLMGameAPI.gd:404` | `_team_to_string` (static) | API |
| `scripts/TurnEventLog.gd:67` | `_team_str` (static) | event log |

Inverse (string→Team): `scripts/LLMGameAPI.gd:393` `_parse_team_string`.

## ⚠️ Scope exclusion — the lowercase mapping is different

Game-record serialization uses **lowercase** `"red"/"green"` (e.g. `GameNarrative.gd:30` compares
`winner == "red"`; record `winner` field). That is a **distinct** mapping with its own home and
**must not** be folded into the capitalized display converter. This plan touches only the six
capitalized `"Red"/"Green"` converters above.

## Design

Add one canonical static to the enum's owner:

```gdscript
# scripts/model/Brigade.gd
static func team_name(team: Team) -> String:
	return "Green" if team == Team.GREEN else "Red"
```

Repoint the six call sites to `Brigade.team_name(...)` and delete the six local defs. Before
repointing each, check whether the local copy actually has callers — if a copy is itself dead,
delete it rather than repoint.

Optional (fold in only if clean): pair the inverse as `Brigade.team_from_name(name: String) -> Team`
and route `LLMGameAPI._parse_team_string` through it — but `_parse_team_string` also appends a
parse error to an `errors` array, so it likely stays a thin API-layer wrapper over the pure helper.

## Objectives

1. Add `Brigade.team_name` (and optionally `team_from_name`).
2. Repoint all six converters; delete the local defs (or delete outright if dead).
3. Keep `OrderValidator.team_to_string`'s *callers* working — it is public/static and used inside
   the file's error messages; repoint those to `Brigade.team_name` too.

## Verification

- `bash tools/run_all_tests.sh` (or `.ps1`) — ALL PHASES GREEN. Team strings feed narrative and
  observation fixtures, so **golden must stay byte-stable** — this is the real regression guard.
- `grep -rn "_team_to_string\|_team_str\|team_to_string" scripts/` returns nothing but the new
  `Brigade.team_name` (proves no straggler copy survived).

## Closeout targets

`docs/systems/` (only if a converter is documented anywhere — likely none); `docs/DECISIONS.md`
3-line entry (seam consolidated onto `Brigade`); archive this plan. No STATUS change expected
(pure internal dedup).
