# LLM Observation and Action Schema

Canonical human-readable reference for the JSON-style API exposed by `scripts/LLMGameAPI.gd`.

Machine-readable schemas live in:

- `schemas/llm_observation.schema.json`
- `schemas/llm_action_response.schema.json`

Examples live in `docs/examples/`.

## How an LLM should read observations

- `legal_moves` and `legal_commits` are authoritative. Do not invent brigade IDs or hex IDs.
- Movement-mode keys are exact strings: `tactical` and `administrative`.
- `pending_orders` and `pending_commitments` mean a brigade may already be unavailable for another order this turn.
- `end_turn` resolves all buffered orders with the required deterministic `seed`, then advances to the next planning turn.
- `last_contested_hexes` is a hex-ID list from the previous resolution.
- `last_combat` contains rich combat summaries from the previous resolution, and is empty before any combat or when no combat occurred.
- `objectives` is currently provisional and empty until scenario scoring is implemented.

## Enumerations

| Domain | Values | Notes |
| --- | --- | --- |
| `team` | `Red`, `Green` | Serialized display strings for `Brigade.Team`. |
| `phase` | `planning`, `resolution`, `end` | Observations normally appear in `planning` after `end_turn` advances. |
| movement mode | `tactical`, `administrative` | Exact JSON keys under `legal_moves[brigade_id]`. |
| owner | `red`, `green`, `contested`, `none` | Current `HexOwner` string values. |
| observation schema | `hexcombat.llm_observation` | Top-level `schema` value. |
| action response schema | `hexcombat.llm_action_response` | Top-level action-response `schema` value. |
| action result schema | `hexcombat.llm_action_result` | Returned by `LLMGameAPI.apply_agent_response`. |

## Observation object

Top-level object returned by `LLMGameAPI.observation(perspective_team)`.

| Field | Type | Status | Meaning |
| --- | --- | --- | --- |
| `protocol_version` | string | stable | Protocol version, currently `0.1.0`. |
| `schema` | string | stable | Always `hexcombat.llm_observation`. |
| `scenario` | string | stable | Loaded scenario name. |
| `turn` | integer | stable | Current turn number. |
| `phase` | string | stable | One of `planning`, `resolution`, `end`. |
| `turn_length_days` | integer | stable | Scenario turn length in days. |
| `perspective_team` | string | stable | Requested perspective (`Red`, `Green`, or empty for omniscient). |
| `rules_summary` | object | stable | Short natural-language rule hints for LLMs. |
| `field_glossary` | object | stable | Short explanations of important fields/units. |
| `map_summary` | object | stable | Counts and enum values useful for validation. |
| `brigades` | array | stable | Placed brigade summaries. |
| `occupied_hexes` | array | stable | Hexes that currently contain brigades. |
| `legal_moves` | object | stable | Legal destination lists by brigade and movement mode. |
| `legal_commits` | object | stable | Legal commit/support options by target hex and team. |
| `pending_orders` | object | stable | Buffered move orders by team. |
| `pending_commitments` | object | stable | Buffered commit orders by team. |
| `last_contested_hexes` | array | stable | Hex IDs contested during the most recent resolution. |
| `last_combat` | array | stable | Combat summary dictionaries from the most recent resolution; empty before combat. |
| `objectives` | array | provisional | Empty until scenario objectives/scoring are implemented. |

## `map_summary`

```json
{
  "hex_count": 455,
  "placed_brigade_count": 8,
  "owner_values": ["red", "green", "contested", "none"],
  "movement_modes": ["tactical", "administrative"],
  "teams": ["Red", "Green"]
}
```

## Brigade object

Each item in `brigades`:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | string | Stable brigade identifier used in actions. |
| `name` | string | Human-readable unit name. |
| `team` | string | `Red` or `Green`. |
| `nato_type` | string | Unit type key used for rendering/symbols. |
| `hex_id` | string | Current hex. |
| `battalions` | integer | Current battalion count in the brigade. |
| `organization` | number | Readiness value, 0-100. |
| `destroyed` | boolean | True if destroyed. |
| `moved_this_turn` | boolean | True after movement is applied this turn. |
| `moved_admin_this_turn` | boolean | True after administrative movement is applied this turn. |
| `fought_this_turn` | boolean | True after combat involving this brigade this turn. |

## Occupied hex object

Each item in `occupied_hexes`:

| Field | Type | Meaning |
| --- | --- | --- |
| `hex_id` | string | Hex identifier. |
| `owner` | string | `red`, `green`, `contested`, or `none`. |
| `feba_km` | number | Forward edge of battle progress in kilometers. |
| `brigades` | array[string] | Brigade IDs currently in the hex. |
| `neighbors` | array[string] | Adjacent hex IDs. |

## `legal_moves`

Object keyed by brigade ID. Each value has exact movement-mode keys:

```json
{
  "PLA-71-2-Amphibious": {
    "team": "Red",
    "from_hex": "hex_44_16",
    "tactical": ["hex_44_16", "hex_43_17"],
    "administrative": ["hex_44_16", "hex_43_17", "hex_42_17"]
  }
}
```

An LLM should select `target_hex` only from the relevant movement-mode array.

## `legal_commits`

Object keyed by target hex, then by team:

```json
{
  "hex_43_17": {
    "Green": ["BDE-77"]
  }
}
```

## Action response object

Top-level object passed to `LLMGameAPI.apply_agent_response(response)`:

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `protocol_version` | string | optional for compatibility | Should be `0.1.0`. |
| `schema` | string | optional for compatibility | Should be `hexcombat.llm_action_response`. |
| `perspective_team` | string | optional | Returned observation perspective (`Red`, `Green`, or empty). |
| `actions` | array | yes | Ordered action list. |
| `notes` | string | optional | Short rationale for logs; ignored by game rules. |

### `move` action

```json
{"type": "move", "team": "Red", "brigade_id": "PLA-71-2-Amphibious", "target_hex": "hex_43_17", "mode": "tactical"}
```

- `mode` must be `tactical` or `administrative`.
- `target_hex` must be listed in `legal_moves[brigade_id][mode]`.

### `commit` action

```json
{"type": "commit", "team": "Green", "brigade_id": "BDE-77", "target_hex": "hex_43_17"}
```

- `brigade_id` must be listed under `legal_commits[target_hex][team]`.

### `end_turn` action

```json
{"type": "end_turn", "seed": 20260624}
```

- `seed` is required. Missing seed is invalid because benchmark/playtest reproducibility is a core requirement.
- Resolves buffered orders and advances to the next planning turn.

## Action result object

Returned by `LLMGameAPI.apply_agent_response`:

| Field | Type | Meaning |
| --- | --- | --- |
| `protocol_version` | string | Protocol version. |
| `schema` | string | `hexcombat.llm_action_result`. |
| `ok` | boolean | True if no validation/application errors occurred. |
| `errors` | array[string] | Rejections/errors. |
| `resolved` | boolean | True if an `end_turn` action successfully resolved and advanced the turn. |
| `seed` | integer | Seed used for turn resolution, or `-1` if no resolution happened. |
| `observation` | object | Post-action observation. |
