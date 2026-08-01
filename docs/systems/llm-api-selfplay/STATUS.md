# LLM API & Self-Play — Status

**AI-readiness (Track E)** — `GameState.play_turn(red, green, dice) -> TurnResult`, per-turn event
log, `LLMGameAPI` observation/action contract (JSON-schema-gated), headless self-play harness.
Deterministic scripted policies: `inland_clear`, `garrison_draw`, `noop`, `selfplay_default`,
`roc_defense` (plan 0029 Tier A — concentrating defender: every Green brigade steps toward the
nearest red/contested threat, holds pre-landing; shared id-geometry in `scripts/policies/PolicyGeometry.gd`).

**LLM players (research harness B6)** — policy id `llm_local` (`LLMPolicy`) marshals a seat's
perspective observation to an out-of-process Python sidecar (`tools/llm_sidecar.py`) that calls a
local OpenAI-compatible model (`HEXCOMBAT_LLM_BASE_URL`/`_MODEL`/`_API_KEY`, default vLLM at
`localhost:8088/v1`), validates the returned actions against the legal sets, and appends every
observation/action pair to a JSONL replay log. `SelfPlayRunner.play_game_seats` runs two
independent seats to a simultaneous WeGo resolve; `godot --headless --path . -s
res://tools/run_selfplay_game.gd -- --seed=S --red-policy=llm_local --green-policy=llm_local
[--scenario=X] [--turns=N] [--model=M] [--out=f.json] [--log=f.jsonl]` plays one full
LLM-vs-LLM game and writes a record + replay log.
`HEXCOMBAT_LLM_SIDECAR` overrides the sidecar (e.g. `tools/llm_sidecar_stub.py`, the network-free
stub used by the gate). LLM decisions are NOT seed-reproducible; the JSONL log is the replay
artifact — each entry carries the full observation, the raw model reply, the validated actions,
and any sidecar `warnings` (stderr is dropped by the engine's `OS.execute`, so the log is where
diagnostics surface). Hardening from live runs: duplicate orders for one brigade
are deduped in the sidecar (engine rule mirrored, first order wins); an unparseable reply gets
ONE strict "JSON only" retry before forfeiting the turn (rescues reasoning-model token-budget
overruns); `HEXCOMBAT_LLM_MAX_TOKENS` default raised 8192→32768 (observed CoT overruns at 8192;
worst prompt ≈21K tokens vs DeepSeek-V4-Flash's 131072 context, so headroom is cheap — the
budget's real cost is wall-clock on rambling turns). Use IPv4 (`127.0.0.1`, default) not
`localhost`. Live-verified against local vLLM (model `jarvis`): seeds 20260710/20260711, both
30/30 turns GAME OK; the second (post-fix) run had zero forfeited turns. `llm_local` now also
runs in either B7 batch seat (mixed or LLM-vs-LLM); mixed game logs include both seat
observations/actions so they remain bundle-ready.
