# Reviewer roster — who can review, how to invoke them, how well they do it

**This file is the single home for reviewer INVOCATIONS and measured reliability.** The review
*procedure* — brief format, roles, how to evaluate findings — lives in
`.claude/skills/hexcombat-plan-review` (plans) and `.claude/skills/hexcombat-diff-review` (diffs).
`CLAUDE.md` points here; do not copy this table into either skill or into a plan.

The point of a roster is that the consultation rule cannot be satisfied by a reviewer that is down.
**Probe availability BEFORE you start implementing, not when you are ready to commit** — on
2026-07-29 `agy` was quota-blocked for a whole session and its reset counter moved the *wrong way*
(3h46m, later 3h09m), so an estimate made at the start was worthless by the end. A 30-second probe
reshapes the order you do the work in; discovering it at commit time strands finished work.

## Invocations

`pi` (v0.82.1, `/home/linuxbrew/.linuxbrew/bin/pi`) is the general multi-model front end. It is
**alive** on the Linux box — an older note in `CLAUDE.md` claiming otherwise was stale and is removed.

```bash
# Nemotron Ultra via NVIDIA NIM
pi -p --no-session --model nvidia/nvidia/nemotron-3-ultra-550b-a55b "YOUR PROMPT"

# MiniMax M3 via NVIDIA NIM
pi -p --no-session --model nvidia/minimaxai/minimax-m3 "YOUR PROMPT"

# GPT-5.6 Sol via OpenAI Codex
pi -p --no-session --model openai-codex/gpt-5.6-sol "YOUR PROMPT"

# DeepSeek V4 Flash via OpenCode
opencode run --model opencode/deepseek-v4-flash-free "YOUR PROMPT"

# DeepSeek V4 Flash via the NVIDIA-hosted route
opencode run --model nvidia/deepseek-ai/deepseek-v4-flash "YOUR PROMPT"
```

**Read-only reviews** — add `--tools read,grep,find,ls` to any `pi` command, or `--agent plan` to an
`opencode` command. Do this in addition to the REVIEW ONLY line in the prompt, never instead of it:
`--agent explore` was measured NOT honoured by some opencode models (they announce a fallback to the
*writing* `build` agent and carry on), so the prompt text is the only guarantee that survives.

**agy** (`agy-explore`, `agy-verify`) is a separate path with its own contract in `~/.claude/AGY.md`;
`agy-verify` is still the only reviewer that can catch a methodology error, because catching one means
running the thing. It is quota-limited per individual.

## Measured reliability

Two sessions of evidence. Treat these as the reason to pick a reviewer, not as adjectives.

| Reviewer | Substantive | Good for | Watch for |
|---|---|---|---|
| `agy-explore` | 4/4 (0043/0051) | Everything: plan review, diff review, oracle checks against TIV | Quota. Outputs are 2.7–4.5 KB when real |
| `agy-verify` | the only method check | "Reproduce my measurement; is the conclusion supported?" | Sees COMMITTED state only |
| `pi` / `gpt-5.6-sol` | untested | USER: "extremely capable, but costly" — save it for a high-stakes read | Costs real money. See the spend rule below |
| `pi` / `minimax-m3` | untested | (unmeasured — record the result the first time you use it) | — |
| `nemotron-3-ultra` | 1/3, then 1/1 (0045) | Broad sweeps, "what did I miss" sections | Counts and line numbers frequently wrong; re-measure anything numeric |
| `deepseek-v4-flash` | 0/3 as reviewer, 1/1 as enumerator | Bounded mechanical enumeration ("every read/write of these 8 fields") | Zero output twice on 2026-07-29 (10 min, and 200 s) |

### What was actually measured on 2026-07-29, invoking these myself

Both cheap routes returned **zero bytes** before their timeout:

| Invocation | Timeout | Result |
|---|---|---|
| `pi -p --no-session --tools read,grep,find,ls --model nvidia/nvidia/nemotron-3-ultra-550b-a55b` | 240 s | exit 124, 0 bytes |
| `opencode run --agent plan --model opencode/deepseek-v4-flash-free` | 200 s | exit 124, 0 bytes |

The task was deliberately trivial and verifiable (read one JSON file, name its three aggregates), so
this is a measurement of the ROUTE, not of the model's reasoning. Do not conclude these models are
broken; conclude that **an invocation returning nothing is the common case and you must plan for it**:

- These CLIs **buffer output until exit** — there is no interim progress to poll, so a run that looks
  hung may simply be working. `agy` reviews routinely need `AGY_TIMEOUT=15m`; budget minutes, not
  seconds, and start with 900 s before deciding a route is dead.
- Meanwhile the same three models produced full, structured reviews the same day **when the USER spun
  them up**. So the practical status is: the USER can reach these reliably, my own in-session
  invocations of the cheap routes have not yet produced output. If you need a review and have no
  budget for a 15-minute experiment, **ask the USER to run it** rather than rediscovering this.
- Record what you learn in the table above the first time an invocation works or fails. An unmeasured
  row is an invitation to repeat someone else's 20 minutes.

### Spending rule for `gpt-5.6-sol`

USER, 2026-07-29: extremely capable, but **costly**. So: one shot, on something whose cost is justified
by the stakes — a golden-touching diff, an architectural boundary, a plan whose premises decide a whole
migration. Not for enumeration, not for routine passes, and not for a retry of something a free model
already answered. If you are unsure whether the stakes justify it, ask; while the USER is away, prefer
holding work uncommitted over spending on a review they did not authorise.

**Flake detection, before reading a single finding.** A flaked reviewer is indistinguishable from
"reviewed, no findings" — the most dangerous failure mode in the procedure, because it silently turns
"nobody looked" into "approved". Substantive `agy-explore` reviews came back 2.7–4.5 KB; flakes were
either under 1 KB (died early) or over 10 KB (dumped tool output — one was 123 KB of pasted diff).
**No numbered findings ⇒ not a review ⇒ re-run it.** Never record a flake as a clean pass.

## What every review brief must contain

Beyond the per-skill brief format:

1. **`REVIEW ONLY — DO NOT MODIFY, CREATE, OR DELETE ANY FILE.`** as the first line.
2. **The frozen artifact under review** — a commit SHA, or a `git diff > file` snapshot. Never "the
   working tree". Measured 2026-07-29: two of three reviewers read the tree *while it was being
   edited* and one returned an eight-item failure report describing a state that never shipped;
   disproving it cost a full round. Freeze first, then hand it over.
3. **How to verify** — `bash tools/run_all_tests.sh`. Say explicitly: *do not run individual
   validators*. A validator run bare resolves the research default while its pins were taken under the
   gate's `scenario_golden`; that has been mistaken for a code regression in three separate sessions
   (0043, 0045, and twice in one day by two different reviewers).
4. **Evidence discipline** — "quote the matching line verbatim; if a symbol has zero hits say ABSENT
   rather than inferring a caller." Measured 2026-07-29: a reviewer cited `dice.substream(...)` as
   proof — a method that does not exist in this codebase — plus a file path that does not exist, in
   support of conclusions that happened to be true. Right answer, invented proof.
5. **Scope consistency** — if the brief forbids touching a set of files, its verification command must
   be scoped to the same set. A brief of mine forbade editing historical records and then asked for a
   repo-wide grep to return nothing, which only its own forbidden edits could achieve.

## Reviewer safety

- Read-only is a PROMPT instruction plus a tool allowlist, not a sandbox. `agy-verify` is deliberately
  not read-only, which is why it runs in a throwaway worktree.
- **Run `git status --short` after every round.** A stray file written by one reviewer contaminates
  the others: a concurrently running model has read such an artifact off disk and returned it verbatim
  as its own review, which looks like independent corroboration and is not.
- Treat identical findings from two models as ONE review until proven otherwise.
- Give each parallel pass a different ROLE (fact-check premises / consequences / what a weaker
  implementer gets wrong / oracle against TIV / method check). Two passes with the same brief are one
  opinion, not two.
