---
name: hexcombat-structure-map
description: Regenerate the visual structure map of the codebase — the published Artifact showing the turn pipeline, what each directory is allowed to do, the ten state owners, and where the enforcement gaps are. Use when the USER asks to see how the codebase is laid out, after a plan moves files between role directories, or when a structural claim needs checking. Holds the commands that produce every number and the URL of the page to UPDATE rather than replace.
---

# Regenerating the structure map

The USER is a non-coding wargame designer and asked for a way to *see* the architecture. The result is
a published Artifact, first built 2026-07-31. **This skill exists so nobody rebuilds it from scratch.**

**The page to update:** `https://claude.ai/code/artifact/a01ab75d-2803-43e6-a9de-2fae52815e95`

Pass that as the Artifact tool's `url` parameter. A conversation that did not itself publish the page
mints a **new** URL without it, and the USER ends up with two maps and no way to tell which is current.
Keep the favicon (🗺️) and the `<title>` stable for the same reason — people find the tab by its icon.

## The one rule

**Every number on the page comes from a command below, run in this session. None of them live in this
file.** They all drift: file counts move whenever a plan lands, coupling numbers move whenever anyone
adds an import, and the aggregate table moves whenever an aggregate is added. A skill that quoted them
would be a second, rotting home for facts that already have one — see the library's own maintenance
rule about pinned numbers.

If a command's output contradicts the published page, the page is stale. That is the expected state,
and regenerating is cheap.

## Producing each plate

Run these first; build nothing until they have all returned.

**Whole-repo metrics** — file counts, per-file dependency counts, complexity, duplication:

```bash
python3 tools/gd_metrics.py . <scratchpad>/metrics.json   # arg 1 is the ROOT, arg 2 the output
python3 tools/gd_metrics.py --check-ceiling               # reports its own coverage
```

Argument order bites: the first positional is the scan root, **not** the output path. Passing only a
filename scans that name as a directory, finds nothing, and reports `files 0` — which reads as a broken
repo rather than a misuse.

The second command's `PASS:` line reports its own scope — that number against the total file count is
the coupling-budget finding, not something to assert from memory.

**The ten aggregates and their owners** — do not read the manifest by hand:

```bash
python3 tools/mutation_ownership.py
```

This is the only home for ownership facts. Plate III is a restatement of its output in plain English;
if an aggregate is added, it appears here first.

**The applies/pure census** — which files change campaign state, and which only calculate:

```bash
for f in scripts/*/*.gd; do
  n=$(grep -vE '^\s*#' "$f" | grep -cE '\b[A-Za-z]+Transitions\.[a-z_]+\(')
  [ "$n" -gt 0 ] && printf '%-48s %s\n' "$f" "$n"
done
```

Three traps, all of which have already produced a wrong answer in this repo:

**1. Strip comment lines — not optional.** Without `grep -vE '^\s*#'` the scan reports ten false hits in
`scripts/calc/` alone, because header prose legitimately names the authority a file used to call.

**2. A hit is not a finding. Ask whether the file's DIRECTORY permits it.** Calling an authority is how
campaign state is *supposed* to change, so most hits are correct code. Compare each against the claim in
`docs/STATUS.md` → "Where a file goes":

| Directory | May it call an authority? |
|---|---|
| `scripts/phases/` | **Yes** — ordering those calls is the entire job. It is normal for these files to hold the most hits in the repo by a wide margin. |
| `scripts/transitions/` | They *are* the authorities. |
| `scripts/ijfs/` | **Yes** — its claim is "computes AND applies at its own draw point". |
| `scripts/calc/` | **No.** Its claim is that it applies nothing. A hit here is a finding. |
| `scripts/builders/`, `loaders/`, `model/` | **No.** |

So the number worth reporting is never the raw total — it is the count in directories whose claim
forbids it. Reporting the raw total as "N files change state illegally" is a fabricated finding.

**3. Ask which question your instrument answers.** After the 0042–0050 campaign, the only remaining way
to change campaign state is to *call* an authority — a function call, not an assignment. A scan built to
hunt illegal direct writes (the alias-taint scan from plan 0050) cannot see legitimate application, and
reports a busy file as inert. Plan 0055 was written on exactly that error — it declared six files
write-free when two of them change campaign state every turn — and had to be rewritten at preflight.

**Why this scan and not the alias-taint scan.** After the 0042–0050 campaign, the only remaining way to
change campaign state is to *call* an authority — a function call, not an assignment. A scan built to
hunt illegal direct writes cannot see legitimate application, and reports a busy file as inert. Ask
which question you need before reusing either instrument.

**The turn pipeline** — `docs/systems/turn-engine/STATUS.md` holds the numbered list with the function
each step calls. That is the one home. The prose summary in `docs/STATUS.md` is a restatement and has
been out of step with it before; trust the numbered list.

**Directory claims** — `docs/STATUS.md` → "Where a file goes". Plate II is that table rewritten for a
reader who does not code. Where a directory's claim is not currently true of everything in it, say so
on the page: a map that hides the exceptions is worse than no map, because it gets trusted.

## Building the page

Load the `artifact-design` skill first, then write the HTML to the scratchpad and publish with the
`url` above.

The existing design, if you are updating rather than redesigning: drafting-vellum ground with a petrol
staff-map accent, condensed grotesque headings against a Charter/Georgia body and a mono utility face,
content in numbered plates. Both light and dark themes are defined at token level — restyle through
the tokens, never inside the media query, and the `data-theme` overrides must win in both directions.
Fonts are system stacks by necessity: the Artifact CSP blocks font CDNs.

Keep the provenance block honest — commit, date, and which tool produced which number. It is what lets
the next reader tell a stale page from a wrong one.

## When to regenerate

- The USER asks how something is structured, or for the map.
- A plan lands that moves files between role directories — 0055, 0057 and 0056 all do, and each
  changes at least one plate.
- An aggregate is added to the manifest. Plate III is wrong the moment that happens.
- A structural claim in `docs/STATUS.md` is being questioned. Run the commands rather than arguing
  from the doc; the doc has been wrong twice.

## Worth promoting

The applies/pure scan above is inline prose here, and plan 0055's step 1 requires running the same
scan. Whoever implements 0055 should promote it to a real script under `tools/` and have both this
skill and that plan call it, rather than keeping two copies of a `grep` whose comment-stripping detail
is load-bearing. Left as prose for now because a `tools/` script is a code change with its own gate,
and this skill is documentation.
