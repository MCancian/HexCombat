---
title: "0020: The lowercase \"red\"/\"green\" team-token seam"
status: "Sketch"
created: "2026-07-20"
---

# Plan 0020: Consolidate the lowercase `"red"/"green"` team-token seam

Companion to plan 0019 (which owned the **capitalized** `"Red"/"Green"` display converter on
`Brigade.team_name`/`team_from_name`). This plan covers the **lowercase** `"red"/"green"` strings —
the ones 0019 deliberately scoped OUT because they are a *distinct* mapping. Survey done 2026-07-20
(opencode explore sweep, corrected against the code).

## Ground truth — the lowercase token is NOT one domain

The literal `"red"/"green"` shows up in three semantically distinct roles that only coincidentally
share a spelling. Conflating them is the trap.

| Domain | Meaning | Canonical home today | Drift sites (bare literal) |
|--------|---------|----------------------|----------------------------|
| **(a) hex ownership** | `HexState.owner` value | ✅ `HexOwner.RED/GREEN` — used on the **write** side (`GameData.gd:509,511,516`; `HexState.gd:8` default; `HexMap.gd:326,328`; `LLMGameAPI.gd:204,252`; `TurnConductor.gd:653`) | **read side only:** `OffloadResolver.gd:85`, `InfrastructureResolver.gd:26,73` |
| **(b) game-record `winner`** | `record["winner"]` = `""`/`"red"`/`"green"` | ❌ none | `VictoryConditions.gd:8,27` (producer); `GameNarrative.gd:30`, `BatchReport.gd:49–50` (consumers) |
| **(c) census / aggregation dict KEY** | `{"red": n, "green": n}` team-indexed counts | ❌ none | `CleanupResolver.gd:45,73,76,87,88`; `BatchReport.gd:25,29,56,76,83`; `GameNarrative.gd:33,37` |

Excluded (not team tokens): `MineWarfareService.status_color` `"red"/"amber"/"green"` traffic-light;
all doc-comment mentions (`CleanupSummary.gd:15`, `TurnResult.gd:15`, `GameStateData.gd:51`, etc.).

## Tier A — mechanical, no design call (ready now)

Domain (a) already HAS a home (`HexOwner`); three resolver **comparisons** just bypass it with a
bare `"red"`. Repoint them:

- `OffloadResolver.gd:85` `== "red"` → `== HexOwner.RED`
- `InfrastructureResolver.gd:26` `== "red"` → `== HexOwner.RED`
- `InfrastructureResolver.gd:73` `!= "red"` → `!= HexOwner.RED`

**Why:** these read a value the rest of the engine writes via the const; a rename of the const
would silently miss them, breaking invasion/offload eligibility with no compile error.
**Risk:** near-zero — comparison only, same string value, no golden output changes.
**Validate:** full gate green + `grep -rn '"red"\|"green"' scripts/resolvers/` returns nothing.

## Tier B — needs a USER design call (the real question)

Domains (b) winner and (c) census-key have **no home** and are the genuinely open question. They are
a "lowercase team token" that is *derived from the `Brigade.Team` enum* (see `CleanupResolver.gd:43–45`:
`Team.RED → "red"` key) yet written as bare literals everywhere, and they feed the **game record /
narrative / batch fixtures** — so any change is **golden-touching** and must prove byte-stability.

**The design question for USER:** is the lowercase team token *the same concept* as hex ownership,
or its own thing?

- **Option 1 — one token module.** Promote a single canonical `Team → "red"/"green"` producer
  (e.g. `Brigade.team_key(team) -> String`, the lowercase sibling of `team_name`). Ownership,
  winner, and census keys all derive from the enum through it. Maximal dedup; `HexOwner.RED/GREEN`
  become `Brigade.team_key(...)` or alias it. Biggest blast radius, touches golden producers.
- **Option 2 — two homes, kept distinct.** `HexOwner` stays the ownership vocabulary; add a separate
  `Brigade.team_key` (or record-token const) for winner/census. Honors the "coincidental spelling"
  reading; less churn; the winner/census literals still get a home.
- **Option 3 — leave winner/census as protocol literals, document the single home.** Winner is a
  serialized wire/record contract; treat `"red"/"green"` as protocol constants with one documented
  definition and stop there. Smallest change; accepts the literals as a boundary format.

**Recommendation:** Option 2 — ownership and game-outcome are different domains that shouldn't be
coupled by a shared string, and a `Brigade.team_key` cleanly pairs with `team_name`/`team_from_name`.
But this is a **design decision, not a technical one** → USER call before implementing Tier B.

**Risk (Tier B):** HIGH relative to Tier A — `winner` and census counts feed narrative and batch
report fixtures; changing how the token is produced must be proven byte-identical. Route the census
keys off enum-derived tokens only if the emitted JSON is unchanged.

## Suggested order

1. **Tier A** — ship immediately as its own commit (mechanical, golden-safe).
2. **Tier B** — surface the Option 1/2/3 design question to USER; implement only after a call, with
   golden byte-stability as the guard.

## Closeout targets

`docs/DECISIONS.md` (per tier); `docs/systems/` only if an ownership/record token gets documented;
archive this plan when both tiers land (or Tier B is explicitly deferred).
