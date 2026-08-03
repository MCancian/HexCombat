# Reviewers — the round, the roster, the routes

**This file is the CANONICAL home for every reviewer fact:** the round and its quorum, the tiers, the
invocations, measured route reliability, brief invariants, flake detection, safety, and the roles. When
another file disagrees with this one, this one is right and the other is stale.
The review *procedure* — what a plan review looks for vs what a diff review looks for, and the brief
format for each — lives in `.claude/skills/hexcombat-plan-review` and
`.claude/skills/hexcombat-diff-review`.

**What other files may say.** A one-line *summary* of a rule an agent must act on at that moment is
allowed, and `CLAUDE.md`'s work loop plus both review skills deliberately carry a few: the quorum, the
freeze, the hold-uncommitted rule. What is not allowed is a second COPY of the detail — a rival model
table, an invocation, a byte band, a roster. (A reviewer caught the earlier wording of this paragraph
claiming those files "do not restate" while they visibly did; a rule stated in a way the tree
contradicts is how the last set of copies started.)

**What the gate actually enforces.** `tools/validate_reviewer_facts.gd` is a token check: a copied
**invocation fragment or model id** fails the gate anywhere but this file, in either direction (it also
fails if this file stops naming one). That is the mechanical half. Duplicated *prose* — a tier claim, a
byte band, a safety rule restated in your own words — is invisible to it and remains convention. Do not
read a green gate as proof that nothing is duplicated.

The executable copy of the Invocations section is **`tools/review_fanout.sh`**. Run a round with that
script rather than hand-assembling commands — it prepends the REVIEW ONLY line, refuses to launch
against an unfrozen tree, and prints the flake triage numbers for you.

```bash
tools/review_fanout.sh --brief SHARED.txt --freeze \
    --role sol=ROLE_A.txt --role agy=ROLE_B.txt --role deepseek=ROLE_C.txt --out DIR
tools/review_fanout.sh --report DIR        # bytes + findings + quorum verdict, per reviewer
```

- **`--freeze` is the only way to hand over a dirty tree, and there is deliberately no alternative.**
  Measured 2026-07-30: a hand-made `git diff > file` was silently a token-compacted **summary** — the
  `rtk` shell hook rewrites `git` in the agent's session — with zero `diff --git` headers. Two reviewers
  quietly reviewed the working tree instead and returned clean verdicts; only the tier-1 reviewer
  refused and named the truncation. `--sha` and a caller-supplied `--snapshot` used to exist and were
  **deleted** (USER call 2026-07-30) after four rounds spent patching their validation; every check they
  needed arrived as its own defect.
- **The snapshot lands at `.review-fanout/frozen-<timestamp>.diff`, inside the worktree** and
  gitignored. It has to be in-repo: the opencode CLI is scoped to its workspace and auto-rejects a path
  under `/tmp` (`permission requested: external_directory … auto-rejecting`), which is why that reviewer
  never once read an artifact before this was fixed. That is also where you read the artifact yourself.
- **`--out` must be OUTSIDE the worktree** — the script hard-refuses a directory inside it, because a
  reviewer would then find the other reviewers' output files on disk and corroboration would be fake.
  Use a scratch dir. (Yes, the two rules point in opposite directions: the artifact must be readable by
  every reviewer, the *outputs* must be readable by none of them.)
- **`--role NAME=FILE` for every quorum reviewer.** The shared brief is context; the role is the job.
  Three reviewers handed one identical brief are one opinion measured three times. The script refuses
  to launch if a quorum reviewer has no role; a tier-3 extra added with `--tier3` may go without one.
- **A clean tree needs no freeze.** With nothing uncommitted the script reviews `HEAD` and says so.
- **Every route is wrapped in a real 15-minute `timeout`.** The agy timeout variable is exported too,
  but only the agy wrappers read it — so without the wrapper the "expect up to 15 minutes" promise was
  false for two of the three reviewers.
- **`--dry-run`** composes the prompts and launches nothing — use it when testing the plumbing so a
  test does not burn three reviewer calls. `--no-roles` deliberately asks all three the same question;
  without it, a missing role is an error, not a warning.
- **A fresh `--out` per round.** The script refuses a directory that already holds a fan-out, because
  stale `.done` files from a previous round would be counted as this round's returns.
- **Only one `opencode` process at a time.** Two simultaneous invocations make the second die with
  `database is locked`; that cost two review slots before it was diagnosed (plan 0040). The default
  round launches exactly one, so this only matters if you add a second opencode route.

## The round

| When | What is required |
|---|---|
| **Implementing a numbered plan** (`docs/plans/NNNN-*.md`) — before committing the diff | **Fan out to all three quorum reviewers; TWO substantive returns satisfy the round.** Mandatory. |
| **A plan document**, before implementation starts | At least **one** substantive read. Fan out anyway — it is one command — but the quorum does **not** bind here. |
| Anything smaller (a BACKLOG bullet, a doc fix, a hygiene sweep) | Your judgement. A review is cheap and usually worth it; nothing is blocked on one. |

USER call 2026-07-30. The point of naming the fan-out is that reviewer choice stops being a decision:
**Sol + agy-explore + DeepSeek V4 Flash, every time.** A third reviewer that flakes, quota-blocks or
returns nothing is the expected case, not a failure of the round — that is what 2-of-3 is for.

**Two rounds per unit of work, and cap the fixing** (USER call 2026-07-30). Findings about **the change**
get fixed. Findings about **the review tooling itself** go to `docs/plans/BACKLOG.md` — they do not
trigger another round. Plan 0054 ran *six* rounds because tooling findings kept re-opening it: rounds
2-5 returned 13, 16, 22 and 10 findings and every blocker after round 2 was in the launcher, never in
the work being reviewed. Two rounds catch the change; the third onward audits your instruments.

**If quorum cannot be reached, the finished work stays UNCOMMITTED.** That is the sanctioned holding
pattern; surface the situation to the USER, who can spin up reviewers you cannot reach. "Reviewers were
unavailable" must never become "committed unreviewed."

**Probe availability BEFORE you implement, not when you are ready to commit.** On 2026-07-29 `agy` was
quota-blocked for a whole session and its reset counter moved the *wrong way* (3h46m, later 3h09m), so
an estimate made at the start was worthless by the end. Discovering it at commit time strands finished
work.

A probe is **a trivial prompt, not a review** — `"reply with the single word OK"` — which is why it can
return in seconds while a real review needs 900 s. Probing with anything substantive just buys you the
same 15-minute wait twice.

## Tiers and routes

Two columns that must **never be collapsed into one**. **Tier** is the USER's capability call: what
class of judgement this model may be trusted with. **Route record** is measured: whether that
invocation returns a usable review at all. They disagree on purpose — a tier-2 reviewer with a flaky
route is exactly why the quorum is 2-of-3 rather than 3-of-3.

| Reviewer | Tier (USER, 2026-07-30) | Quorum | Route record (measured) | Use it for |
|---|---|---|---|---|
| **GPT-5.6 Sol** | **1 — peer** | yes | untested by me; the USER has run it | Both rounds, every time. The one reviewer expected to reason about the change rather than pattern-match it. |
| **agy-explore** | 2 — mid | yes | **4/4 substantive** (plans 0043/0051); real reviews land 2.7–4.5 KB | Both rounds; oracle checks against TIV; large-file sweeps |
| **agy-verify** | 2 — mid | no (extra) | the only method check there is | "Reproduce my measurement; is the conclusion supported?" — **sees COMMITTED state only** |
| **DeepSeek V4 Flash** | 2 — mid | yes | **0/3 as a reviewer, 3/3 as a bounded enumerator**; returned zero bytes twice on 2026-07-29, then two substantive enumerations on 2026-07-30 (plan 0047, both rounds) | Quorum slot; strongest at bounded mechanical enumeration ("every read/write of these 8 fields, with file:line"). Requires the material to be handed to it (bounded enumeration of a document) rather than being asked to explore or trace flows. |
| **MiniMax M3** | 3 — sometimes helpful, occasionally dangerous | **no** | unmeasured — record the first result here | Bonus roles only: breadth sweeps, "what did I miss" |
| **Nemotron Ultra** | 3 — sometimes helpful, occasionally dangerous | **no** | 1/3, then 1/1 (0045); counts and line numbers frequently wrong | Bonus roles only |
| **GLM 5.2** (OpenRouter) | 3 — sometimes helpful, occasionally dangerous | **no** | unmeasured — record the first result here | Bonus roles: reasoning-heavy reviews, long-horizon agentic tasks, complex coding |
| **Kimi K3** (OpenRouter) | 3 — sometimes helpful, occasionally dangerous | **no** | unmeasured — record the first result here | Bonus roles: multimodal reasoning, knowledge work, complex coding, large-context sweeps |

**Give DeepSeek an enumeration role, and expect its return to be long.** Measured across both
plan-0047 rounds: given "produce four exhaustive verbatim lists", it returned usable work twice
(23.6 KB and 14.7 KB), and one of those findings — an unregistered container writer — was found by
nothing else. Both were labelled `SUSPECT` purely on size because its stdout was prompt echo + tool
traces + the real report. **That noise is now stripped at the route:** the deepseek row runs `tools/review_opencode.sh`, which
drives opencode with `--format json` and emits the assistant's message text (all assistant messages,
in order — a review interleaves tool calls with its findings), so the byte band sees the report and
nothing else. A clean enumeration is still
legitimately long, so it can still land over the 10 KB band — **judge an enumeration by whether the
lists are verbatim and scoped, not by its size**, and count it yourself once read. That is the
SUSPECT verdict's normal contract: the band flags what to READ, not what to believe.

**A known property of this roster, not a bug:** DeepSeek's route record is 0/3 as a *reviewer*, so in
practice the quorum is usually carried by Sol and agy, and the third slot is redundancy that frequently
does not arrive. It earns its place as the bounded *enumerator* — in the 0054 round it produced an
accurate four-list inventory that surfaced two scan-scope facts nothing else found. If you want genuine
one-reviewer redundancy, that is a roster change and a USER decision.

**Tier 3 never counts toward the quorum, and every citation it produces is verified before use.**
Measured 2026-07-29: at least four fabricated citations in one report, including `dice.substream(...)`
as proof — no such method exists here — plus a nonexistent file path, in support of conclusions that
happened to be true. Right answer, invented proof.

## Invocations

`pi` (v0.82.1, `/home/linuxbrew/.linuxbrew/bin/pi`) is the multi-model front end and is **alive** on
the Linux box.

**Which of these the launcher runs:** the three quorum routes, plus the two tier-3 routes under
`--tier3`. The rest of this table — the verify wrapper, the oracle pass with an extra workspace dir, the
NVIDIA-hosted DeepSeek route — you invoke directly when a round needs them.
`tools/validate_reviewer_facts.gd` fails the gate if a command the launcher builds is not present here
verbatim, so the executable copy cannot drift from this table unnoticed.

```bash
# Tier 1 — GPT-5.6 Sol, via OpenAI Codex
pi -p --no-session --tools read,grep,find,ls --model openai-codex/gpt-5.6-sol "PROMPT"

# Tier 2 — agy-explore (read-only by contract; own wrapper, see ~/.claude/AGY.md)
AGY_TIMEOUT=15m agy-explore "PROMPT"
AGY_TIMEOUT=15m agy-explore -d ~/Projects/TaiwanInvasionViewer "PROMPT"   # TIV oracle pass

# Tier 2 — agy-verify (MAY RUN COMMANDS; throwaway worktree of HEAD, deleted on exit)
AGY_TIMEOUT=15m agy-verify "PROMPT"

# Tier 2 — DeepSeek V4 Flash, via OpenCode. The launcher route is the wrapper, which drives the
# opencode line with `--format json` and emits the assistant's message text, so the byte band
# sees the report and not the prompt echo / tool traces (BACKLOG "unparseable by the byte band",
# closed 2026-08-03). The raw line below is the NVIDIA-hosted route.
tools/review_opencode.sh "PROMPT"
opencode run --agent plan --model nvidia/deepseek-ai/deepseek-v4-flash "PROMPT"   # NVIDIA-hosted route

# Tier 3 — bonus roles only, never quorum
pi -p --no-session --tools read,grep,find,ls --model nvidia/minimaxai/minimax-m3 "PROMPT"
pi -p --no-session --tools read,grep,find,ls --model nvidia/nvidia/nemotron-3-ultra-550b-a55b "PROMPT"
pi -p --no-session --tools read,grep,find,ls --model openrouter/z-ai/glm-5.2 "PROMPT"
pi -p --no-session --tools read,grep,find,ls --model openrouter/moonshotai/kimi-k3 "PROMPT"
```

### The round, machine-readable — this block is gated

`tools/validate_reviewer_facts.gd` requires the launcher's manifest to match these rows EXACTLY:
name, role, command. Presence of a command somewhere in this file was not enough — a reviewer
demonstrated that commands could be swapped between the `agy` and `minimax` rows while every name and
count stayed correct, putting a tier-3 route in a quorum slot. Edit here and in the launcher together,
or the gate goes red.

```text
sol       quorum  pi -p --no-session --tools read,grep,find,ls --model openai-codex/gpt-5.6-sol
agy       quorum  agy-explore
deepseek  quorum  tools/review_opencode.sh
minimax   extra   pi -p --no-session --tools read,grep,find,ls --model nvidia/minimaxai/minimax-m3
nemotron  extra   pi -p --no-session --tools read,grep,find,ls --model nvidia/nvidia/nemotron-3-ultra-550b-a55b
glm       extra   pi -p --no-session --tools read,grep,find,ls --model openrouter/z-ai/glm-5.2
kimi      extra   pi -p --no-session --tools read,grep,find,ls --model openrouter/moonshotai/kimi-k3
```

**Read-only flags:** `--tools read,grep,find,ls` for `pi`, `--agent plan` for `opencode`. The opencode
route is additionally enforced by config: the version-controlled repo-root `opencode.json` carries
`agent.plan.permission` edit+`bash:deny`, deep-merged with the machine-local global config (verified
empirically via `opencode debug config`, 2026-08-03), so the deny survives a fresh clone. Do NOT rely
on it to stop a fallback — `--agent explore` was measured NOT honoured by some opencode models (they
announce a fallback to the *writing* `build` agent and carry on), and the config deny is scoped to the
`plan` agent only. Use the flags **in addition to** the REVIEW ONLY line in the prompt; the actual net
is the report's contamination check (`tree_before`/`tree_hashes`), which catches an escaped writing
model by the file it writes. Prompt text plus that check, never config alone, is the guarantee.

**Budget minutes, not seconds.** These CLIs buffer output until exit — there is no interim progress to
poll, so a run that looks hung may simply be working. Start at **900 s** before deciding a route is
dead. My own invocations of the cheap routes have returned zero bytes at 240 s and 200 s on a task
trivial enough to measure the route rather than the model; the USER has reached the same models the
same day. If a route dies and you have no budget for a 15-minute experiment, **ask the USER to run it**
rather than rediscovering this.

**Record what you learn in the Route record column the first time an invocation works or fails.** An
unmeasured row is an invitation to repeat someone else's 20 minutes.

## What every brief must contain

Beyond the per-round brief format in the two review skills:

1. **`REVIEW ONLY — DO NOT MODIFY, CREATE, OR DELETE ANY FILE.`** as the first line.
   `tools/review_fanout.sh` prepends this so it cannot be forgotten.
2. **The frozen artifact under review** — a commit SHA, or a snapshot from `--freeze`. Never "the
   working tree". Measured 2026-07-29: two of three reviewers read the tree *while it was being
   edited* and one returned an eight-item failure report describing a state that never shipped;
   disproving it cost a full round. And **check that the snapshot is a diff** (2026-07-30, above): a
   truncated or summarised artifact does not announce itself — reviewers silently fall back to reading
   the live tree and hand you clean verdicts about code they never saw.
3. **How to verify** — `bash tools/run_all_tests.sh`. Say explicitly: *do not run individual
   validators*. A validator run bare resolves the research default while its pins were taken under the
   gate's `scenario_golden`; that has been mistaken for a code regression in three separate sessions
   (0043, 0045, and twice in one day by two different reviewers).
4. **Evidence discipline** — "quote the matching line verbatim; if a symbol has zero hits say ABSENT
   rather than inferring a caller."
5. **Scope consistency** — if the brief forbids touching a set of files, its verification command must
   be scoped to the same set. A brief of mine forbade editing historical records and then asked for a
   repo-wide grep to return nothing, which only its own forbidden edits could achieve.
6. **What you have ALREADY VERIFIED, so the round does not re-buy it.** State the facts you measured
   and how, and say "re-check only if you think it is wrong — do not spend a finding confirming it."
   Measured on plan 0047's first round: roughly 40% of the tier-1 reviewer's findings duplicated
   things already measured before launch. That is reviewer attention spent on agreement instead of on
   what you missed — and "what did I miss" is the section that reliably returns the best finding.
   This is NOT the same as hiding your reasoning: give them the claims and the evidence, and invite
   them to falsify. Several of the most valuable returns have been a reviewer disproving a number the
   brief asserted.

## Flake detection — before reading a single finding

A flaked reviewer is **indistinguishable from "reviewed, no findings"**, which is the most dangerous
failure mode in the whole procedure: it silently converts "nobody looked" into "approved".

- Substantive `agy-explore` reviews came back **2.7–4.5 KB**. `tools/review_fanout.sh` uses the wider
  **1–10 KB** (1000–10240 bytes) as its healthy band, so the thresholds it prints are the ones below.
- Flakes were **under 1 KB** (died before answering) or **over 10 KB** (dumped tool output — one was
  123 KB of pasted diff, another was pages of `Grep` traces).
- **No numbered findings ⇒ not a review ⇒ it does not count toward the quorum.** Re-run it. Never
  record a flake as a clean pass. The launcher's prepended REQUIREMENT demands a numbered list and
  makes *"1. No defect found — here is what I checked and what I concluded"* a legal nil return
  (settled rule, 2026-08-03: a real 342-byte clean review and an enumerator were both scored FLAKE on
  2026-07-30 for lacking numbers, so every role must number its findings, nil included). A nil return
  carrying that one numbered entry is counted as a finding, lands `SHORT` if under 1 KB, and — per the
  823-byte precedent below — is READ and judged, never dismissed.
- **`--report` auto-counts only the unambiguous case:** a quorum reviewer that exited 0, produced
  numbered findings, and landed in the healthy band (verdict `REVIEW`). A `SHORT` or `SUSPECT` return is
  **excluded from that count and printed for you to judge** — and **you may count it yourself** once you
  have read it and decided it is a real review. The count is a lower bound, not the verdict.
- **Exit codes:** `0` = two auto-counted and nothing left to judge. `1` = fewer than two auto-counted
  (checked first, so it wins over everything below). `2` = the script refused to run at all. `3` = two
  auto-counted **but** something needs your judgement: a `SHORT`/`SUSPECT` return, a quorum reviewer
  still running or silent, a return whose CLI exited nonzero, or files changed since launch. A green
  exit therefore cannot hide an unread blocker, which is the only reason the distinction exists.
- **But size alone does not decide it — a correct blocker can be tiny.** Measured 2026-07-30: an
  **823-byte** return was the most valuable of its round; it was one finding saying "your frozen
  artifact is truncated, so nothing here is reviewable". The byte band flags what to READ, not what to
  believe. The script labels this shape `SHORT` rather than `FLAKE` for exactly that reason.

Adding *"do not print or quote the diff; findings only"* to the brief helps but does not fix it — both
cheap models ignored it on the retry. `tools/review_fanout.sh` prints bytes and a findings-present flag
per reviewer so this check is mechanical.

## Safety

- Read-only is a **prompt instruction plus a tool allowlist, not a sandbox.** `agy-explore` is
  read-only by contract only, and has previously written a review artifact into the repo root despite
  the instruction. `agy-verify` is deliberately not read-only, which is why it runs in a throwaway
  worktree.
- **Read the report's contamination lines; `git status --short` alone is not enough.** If a reviewer
  edits a file that was **already dirty** before the round, the status line stays ` M path` and nothing
  changes — only the launch-time/report-time content-hash comparison sees it. Use `git status --short` as
  the coarse check for *new* files, and the report for edits to existing ones. A stray file written by one reviewer **contaminates the
  others**: a concurrently running model has read such an artifact off disk and returned it verbatim as
  its own review, which looks like independent corroboration and is not.
  - A file the reviewer **created**: delete it.
  - A file the reviewer **modified**: treat it as out of bounds and **reverse that reviewer's delta
    only** — inspect the change and undo it. Do **not** `git checkout` the file: it was probably already
    dirty with your own pre-round work, and discarding that is a self-inflicted second incident.
- **Treat identical findings from two models as ONE review until proven otherwise**, and check they are
  not both agreeing with a false claim *you* put in the brief. Three models once agreed a validator
  harness would fix the gate-hang class; it does not, because a script that fails to compile never runs.
- **Reviewers never implement.** You are the sole implementer, and every finding is a claim to verify
  against the code — not an instruction. Reject plainly, in writing, with the evidence.

## Roles — spend extra capacity on different jobs, not repeats

Two passes given the SAME brief are one opinion, not two. The quorum three each get their own role;
anything beyond that picks from:

1. **Fact-check** — "verify these premises against the current tree; several are counts and `file:line`
   claims I produced myself and may be wrong."
2. **Consequences** — "what breaks, what did I miss."
3. **Weaker implementer** — "this will be implemented by a LESS CAPABLE agent working alone; what will
   they get wrong despite the plan saying otherwise? Name the sentence that is not explicit enough."
   *Produced the best finding on plan 0051* — a filter that would have made the mechanic do nothing in
   its headline case while every unit test passed.
4. **Oracle** — `agy-explore -d ~/Projects/TaiwanInvasionViewer`: "does this match the source it was
   ported from?" **Standard for any TIV-lineage change.** On plan 0051 it *reversed* the naive reading:
   the ported arithmetic is correct for TIV's inputs and wrong for ours. Reasoning about the oracle from
   our port is how ported bugs get preserved as "faithful".
5. **Method** — `agy-verify`: the only pass that catches a **methodology** error, because catching one
   means running the thing. Both worst errors of the 0043 session were methodology: a validator run
   without the gate's `HEXCOMBAT_SCENARIO`, whose pin therefore never matched and was chased as a
   phantom regression; and a hand-rolled turn loop that looked like 25 turns, resolved **one**, and
   summed a stale summary 25 times. Use it whenever a plan or diff is justified by a measurement.
