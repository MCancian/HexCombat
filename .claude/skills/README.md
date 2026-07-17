# HexCombat skill library

Procedures for agents working in this repo. **Facts live in docs** (`docs/STATUS.md`,
`docs/systems/`, `docs/DECISIONS.md`); **skills tell you how to act** and where the traps are.
Frontmatter descriptions are the triggers — read the skill before doing its kind of work.

## Task → skill map

| You are about to… | Read |
|---|---|
| Design/change a module, boundary, autoload, RNG use, or cross-phase state | `hexcombat-architecture-contract` |
| Make ANY code/data change (classify + gate + commit it) | `hexcombat-change-control` |
| Set up / repair the environment, fresh checkout, tool won't launch | `hexcombat-build-and-env` |
| Launch the game, drive turns headlessly, capture screenshots, export fixtures | `hexcombat-run-and-operate` |
| Verify work, add a test/validator, judge a red gate | `hexcombat-validation-and-qa` |
| Debug a failure, flake, or "knob does nothing" | `hexcombat-debugging-playbook` |
| Check whether a problem was already fought | `hexcombat-failure-archaeology` |
| Understand a game mechanic's meaning / source lineage | `hexcombat-wargame-domain-reference` |
| Change a balance value, add a scenario parameter | `hexcombat-config-and-knobs` |
| Author a scenario variant | `hexcombat-scenario-authoring` |
| Run Monte Carlo batches, sweeps, LLM-vs-LLM games, outcome reports | `hexcombat-research-runs` |
| Add a whole new phase/mechanic | `hexcombat-add-phase-resolver` |
| Extract logic out of GameState / resolver-boundary questions | `hexcombat-gamestate-decomposition-campaign` (campaign COMPLETE — kept as the record of method) |
| Write/modify any function or test (quality budgets, naming, magic numbers) | `hexcombat-code-quality` |
| Finish/plan/record anything (docs of record) | `hexcombat-docs-and-writing` |

Diagnostics/measurement guidance is folded into `validation-and-qa` (evidence),
`debugging-playbook` (triage), and `run-and-operate` (tools) — there is no separate
diagnostics skill.

## Activation states

Some skills describe capabilities that are partly future (noted in their bodies):
`hexcombat-research-runs` (batch-runner layer is an active build track),
`hexcombat-scenario-authoring` (scenario-path selection lands with the first variant).
When you complete the enabling work, **update the skill** — remove the activation note and
replace placeholders with the real commands. Skills are code: stale ones get fixed in the same
commit as the change that staled them.

## Maintaining this library

- One skill = one job; link between skills instead of duplicating.
- Pinned numbers (golden values, counts) drift — validators are the truth; skills should say
  "verify in the validator" wherever they quote a pin.
- New hard-won lesson → append to `hexcombat-failure-archaeology` (and
  `docs/RETROSPECTIVES.md` per the tracking rules).
- Superseded draft that seeded this library: `.claude/draft_skills.md`.
