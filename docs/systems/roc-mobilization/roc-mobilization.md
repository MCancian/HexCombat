# ROC mobilization phase-in (plan 0029 Tier A2)

## 1. Purpose

The pre-0029 laydown put the **entire** ROC order of battle on its garrison hexes at H-hour,
including the OOB's 12 `nato_type: "reserve"` infantry brigades (36 of the 124 ROC battalions, 29%
of the force). That assumes the reserve establishment is manned, equipped and deployed on D-Day.

The mobilization mechanic lets a scenario hold a slice of the **existing** force off-map and phase it
in over the opening turns. It invents no units: the total ROC force is unchanged. What changes is
**exposure timing** — an off-map brigade is not an IJFS target and not in the victory census, so
held-back battalions sit out the front-loaded fires campaign and arrive intact into the fight.

This is the defender-side answer to the research question in `docs/plans/0029-dynamic-roc-defense.md`
(USER call 2026-07-24 selected model (b), phase in existing brigades; deny-only victory).

## 2. Files & responsibilities

| File | Role |
|---|---|
| `scripts/model/MobilizationState.gd` | `MobilizationState` (Resource). Cross-turn state: `pending` (brigades still forming, each `{brigade_id, garrison_hex, release_turn}`) and `released` (arrival log). `pending_battalions()` sums the off-map force. |
| `scripts/model/MobilizationSummary.gd` | `MobilizationSummary` (Resource). Per-turn result: `arrivals`, `deferred`, `battalions_arrived`, `pending_brigades`, `pending_battalions`. `to_dict()` is the JSON contract. |
| `scripts/builders/MobilizationStateBuilder.gd` | Pure builder. `select_held_back()` picks WHICH brigades start off-map; `build()` turns that list into the release schedule. |
| `scripts/calc/MobilizationResolver.gd` | Pure resolver. `resolve()` releases due brigades; `find_arrival_hex()` is the BFS fallback when a garrison hex is overrun. Consumes no dice. |
| `scripts/phases/ReinforcementPhases.gd` | `resolve_mobilization_turn()` — the coordinator: hands the summary's force request to `ForceTransitions.release_mobilized_brigades`, appends IJFS targets, recomputes ownership, emits `EventBus.mobilization_resolved`. `hex_can_receive_mobilized()` is the arrival-site rule. `rebuild_mobilization_state()` is the reset pass-through. |
| `scripts/transitions/ForceTransitions.gd` | The authority: `release_mobilized_brigades()` drains `pending`, appends `released` and places the brigades in one transaction; `rebuild_mobilization_state()` installs a fresh schedule at scenario reset. |
| `scripts/GameData.gd` | Parses the scenario `green_mobilization` block into `green_mobilization`; `load_scenario` computes `mobilization_holdback` BEFORE the placement loop and leaves those brigades off-map. |
| `scripts/GameState.gd` | Holds `mobilization_state` / `last_mobilization_summary` (on `GameStateData`), `_rebuild_mobilization_state()` at scenario reset. |
| `scripts/resolvers/IjfsResolver.gd` | `add_maneuver_targets()` — append-only IJFS targets for brigades that just arrived. |
| `scripts/LLMGameAPI.gd` | `_mobilization_observation()` — the `mobilization` observation block (both seats). |
| `tools/validate_mobilization.gd` | End-to-end gate coverage on `scenario_default`. |
| `tests/mobilization_builder_test.gd`, `tests/mobilization_resolver_test.gd` | Pure unit coverage for selection, schedule, release, displacement, deferral, BFS bounds. |

## 3. Scenario configuration

```json
"green_mobilization": {
  "held_back_brigades": 0,
  "brigade_types": ["reserve"],
  "first_release_turn": 4,
  "release_interval_turns": 2,
  "brigades_per_release": 2
}
```

- **`held_back_brigades`** — how many eligible brigades start off-map. **0 (default) holds nobody
  back and is byte-identical to the pre-0029 laydown**; this is what keeps the golden pins stable.
- **`brigade_types`** — eligible `nato_type` values. Default `["reserve"]` = the OOB's 12 reserve
  infantry brigades.
- **Schedule** — `brigades_per_release` brigades arrive on `first_release_turn` and every
  `release_interval_turns` thereafter. Turn = 1 day, so the shipped default fields all 12 by turn 14:
  a mobilization that starts producing formed units inside a week and finishes through D+14.

An unknown key in the block fails loud (`MobilizationStateBuilder.KNOWN_KEYS`), and
`tools/validate_scenario_data.gd` rejects a `held_back_brigades` larger than the eligible pool — a
silently-clamped holdback would misreport every sweep cell above the cap.

All four fields are registry knobs (`data/knobs/registry.json`, group `mobilization`, path prefix
`scenario:`), so they are sweepable and dumped into every game record.

## 4. Selection and release

**Selection** (`select_held_back`, at scenario load): eligible = placed **Green** brigades whose
`nato_type` is in `brigade_types`, sorted by `brigade_id`; the first `held_back_brigades` of them are
held. Sorting by id — not by placement order — keeps release order independent of file layout.

**Off-map representation**: a held brigade has `hex_id == ""`, the same "not present" state Red's
at-sea brigades already use. Everything downstream therefore excludes it with no special-casing:
the victory census (`CleanupResolver.census` skips hex-less brigades), `legal_moves`, the `brigades`
observation array, and combat.

**Release** (`MobilizationResolver.resolve`, once per turn): every pending entry whose
`release_turn <= turn_number` arrives. The arrival hex is:

1. its **garrison hex** (the placement the scenario gave it), if that hex is still available;
2. otherwise the nearest available hex by BFS ring, ties broken by hex id (`displaced: true`);
3. otherwise nothing — the brigade stays pending and retries next turn (`deferred`).

"Available" (`ReinforcementPhases.hex_can_receive_mobilized`) = a placed, passable hex that is neither
RED nor CONTESTED. Enemy-held ground is not a mobilization site: taking it back is a counterattack
(plan 0029 Tier B), not a reinforcement. The search is bounded by
`MobilizationResolver.MAX_ARRIVAL_SEARCH_RINGS` (6) — beyond that the sector is gone and waiting a
turn is the honest outcome, not teleporting the formation across the island.

## 5. Turn position

`resolve_turn` order: IJFS → sealift → anti-ship crossing → amphibious offload → **mobilization** → air insertion →
movement & commit → ground combat → front-line → cleanup.

Green's reinforcement step deliberately sits at the same seam as Red's (offload): both sides' new
arrivals are on the map for this turn's combat, but neither can be given orders until the next
planning phase (the orders were bought before they existed). The phase consumes **no dice**, so the
golden RNG stream is untouched and a scenario with an empty schedule is byte-identical to the
pre-0029 engine.

## 6. IJFS coupling

A formation only becomes an IJFS maneuver target once it is on the island:

- `GameStateBuilder.build_ijfs_state` excludes the brigades in `GameData.mobilization_holdback`.
- On arrival, `IjfsResolver.add_maneuver_targets` **appends** that brigade's per-battalion targets to
  the live target list. Append-only, so existing targets keep their list positions and their
  detection continuity (`known_to_red` / `last_detected_day`), and
  `sync_maneuver_targets_to_oob` — which only ever marks excess targets destroyed — leaves them alone.

The exclusion is keyed on **mobilization membership, not on "has no hex"**. Every scenario loads the
full ROC OOB, so a scenario that places only some brigades (`scenario_golden` places 4 of 32) has
always had its unplaced brigades in the IJFS target pool. Narrowing that is a separate,
golden-touching decision — see `docs/plans/BACKLOG.md`.

## 7. Surfacing

- **Observation** — `mobilization: {pending_brigades, pending_battalions, pending[], arrived[]}`,
  visible to both seats (it is a schedule, not hidden intent) and described in `field_glossary`.
- **Turn record** — `TurnResult.mobilization_summary` lands in every game record's turn digest, so
  arrivals are directly analysable in batches and sweeps.
- **Event log** — a `mobilization` event is emitted **only** on turns with arrivals, so a scenario
  that holds nobody back produces the same event log as before.

## 8. Oracle fidelity

No TIV oracle: TaiwanInvasionViewer has no mobilization model (its ROC laydown is static). This is
HexCombat design, settled with the USER on 2026-07-24 — see `docs/DECISIONS.md`.

## 9. State & authority

This subsystem mutates the **`force`** aggregate; its designated authority is `ForceTransitions`,
which owns every field of `MobilizationState` (plan 0044) and the `mobilization_state` handle on the
turn state (plan 0048). There is deliberately no mobilization authority of its own: an authority
class whose only field were a handle to another authority's model would be one in name only.

- **Outcome/receipt types:** `MobilizationSummary` → `ForcePlacementReceipt`.
- **Manifest:** [tools/mutation_authority_manifest.json](../../../tools/mutation_authority_manifest.json) — the field lists live there and are deliberately not repeated here.
