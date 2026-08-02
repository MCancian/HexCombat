#!/usr/bin/env bash
# Fan a review brief out to the quorum reviewers, then triage the returns.
#
# Usage:
#   tools/review_fanout.sh --brief FILE [--role NAME=FILE]... [--freeze]
#                          [--out DIR] [--tier3] [--dry-run] [--no-roles]
#   tools/review_fanout.sh --report DIR
#
# WHY THIS IS A SCRIPT AND NOT A PARAGRAPH IN A SKILL. Three rules kept being restated in prose and
# kept being broken, each at the cost of a full review round:
#   1. every brief must open with REVIEW ONLY  -> this script prepends it; it cannot be forgotten
#   2. reviewers must be handed a FROZEN artifact, never a live tree -> this script REFUSES to launch
#      against a dirty tree without --freeze (measured 2026-07-29: two of three reviewers read a tree
#      mid-edit and one reported eight failures in a state that never shipped)
#      --freeze is the ONLY way to name a dirty artifact, deliberately. `--sha` and a caller-supplied
#      `--snapshot` both existed and were both DELETED (USER call 2026-07-30) after four review rounds
#      spent patching them: a caller-built snapshot needs existence, containment, completeness and
#      structural validation, and each of those checks arrived as its own defect. The reason they
#      existed is the reason they were dangerous — measured 2026-07-30, a hand-made `git diff > file`
#      was silently a TOKEN-COMPACTED SUMMARY, because a shell hook rewrites `git` in the agent's
#      session. Zero `diff --git` headers; two reviewers quietly reviewed the working tree instead and
#      returned clean verdicts. A CLEAN tree still needs no snapshot: the artifact is HEAD.
#   3. a flake is indistinguishable from "reviewed, no findings" -> --report prints bytes and a
#      findings count per reviewer, so the triage is mechanical rather than remembered
#
# ROLES: --brief is the shared context every reviewer needs; --role NAME=FILE appends that reviewer's
# OWN job to it. Use them. Three reviewers given one identical brief are one opinion measured three
# times, which is the correlated-noise failure the roster warns about; the differentiated roles are
# where the blockers actually came from (the oracle and weaker-implementer passes each caught one
# nothing else did).
#
# The roster, the tiers, the quorum rule and the read-only flags live in .claude/REVIEWERS.md. This
# script is the executable copy of that file's Invocations table; when they disagree, that file wins.
#
# It deliberately does NOT read, rank or summarize findings. Reading and refuting them is the primary
# agent's job — a summarizer here would launder exactly the fabricated citations tier 3 produces.
set -euo pipefail

REVIEW_ONLY_LINE='REVIEW ONLY — DO NOT MODIFY, CREATE, OR DELETE ANY FILE. Do not write a report file into the repo. Do not print or quote the diff; findings only.'
TIMEOUT_MINUTES=15
HEALTHY_MIN_BYTES=1000
HEALTHY_MAX_BYTES=10240

brief=""
snapshot=""
out=""
report_dir=""
want_tier3=0
do_freeze=0
dry_run=0
allow_no_roles=0
roles=()

die() { echo "review_fanout: $*" >&2; exit 2; }

## Every path git currently reports as dirty, one per line, UNQUOTED.
## -z is not optional: without it git C-quotes any path with a space or non-ASCII byte (verified
## 2026-07-30 — a probe file named `probe file ünïcode.md` was captured by the freeze and then reported
## MISSING by the presence check, because the two spellings did not match). With -z, rename and copy
## entries carry a second path, which is consumed and discarded here.
_dirty_paths() {
	local entry code path
	while IFS= read -r -d '' entry; do
		code="${entry:0:2}"
		path="${entry:3}"
		if [[ "$code" == R* || "$code" == C* ]]; then
			IFS= read -r -d '' _origin || true
		fi
		[[ -n "$path" ]] && printf '%s\n' "$path"
	done < <(git status --porcelain -uall -z)
}

## md5 of every dirty path. Taken at launch and again at report time; the pair is what makes a reviewer's
## edit to an ALREADY-dirty file visible, which a status-line comparison cannot see.
_hash_dirty_paths() {
	while IFS= read -r path; do
		[[ -f "$path" ]] || continue
		md5sum -- "$path" 2>/dev/null || echo "UNREADABLE  $path"
	done < <(_dirty_paths) | LC_ALL=C sort
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--brief)    brief="${2:-}"; shift 2 ;;
		--out)      out="${2:-}"; shift 2 ;;
		--report)   report_dir="${2:-}"; shift 2 ;;
		--tier3)    want_tier3=1; shift ;;
		--freeze)   do_freeze=1; shift ;;
		--dry-run)  dry_run=1; shift ;;
		--no-roles) allow_no_roles=1; shift ;;
		--role)     roles+=("${2:-}"); shift 2 ;;
		-h|--help)  sed -n '4,8p' "$0" | cut -c3-; exit 0 ;;
		*)          die "unknown argument '$1'" ;;
	esac
done

# ---------------------------------------------------------------- report mode

classify() {
	# echoes: VERDICT<TAB>bytes<TAB>findings
	local file="$1" bytes findings verdict
	bytes=$(wc -c <"$file" | tr -d ' ')
	findings=$(grep -cE '^[[:space:]]*(#{1,4} )?(Finding )?[0-9]+[.)]' "$file" || true)
	if [[ "$findings" -eq 0 ]]; then
		verdict="FLAKE"
	elif [[ "$bytes" -lt "$HEALTHY_MIN_BYTES" ]]; then
		# Measured 2026-07-30: a correct single BLOCKER ("your snapshot is truncated, the round is
		# unreviewable") came back at 823 bytes. Short-with-findings is not the flake shape; it is
		# usually a reviewer that stopped early ON PURPOSE. Read it.
		verdict="SHORT"
	elif [[ "$bytes" -gt "$HEALTHY_MAX_BYTES" ]]; then
		verdict="SUSPECT"
	else
		verdict="REVIEW"
	fi
	printf '%s\t%s\t%s\n' "$verdict" "$bytes" "$findings"
}

if [[ -n "$report_dir" ]]; then
	[[ -d "$report_dir" ]] || die "--report dir '$report_dir' does not exist"
	[[ -f "$report_dir/manifest" ]] || die "'$report_dir' holds no manifest — not a fan-out directory"
	printf '%-14s %-9s %8s %9s  %s\n' REVIEWER STATE BYTES FINDINGS VERDICT
	quorum_ok=0
	unresolved=0
	while IFS=$'\t' read -r name quorum _cmd; do
		file="$report_dir/$name.txt"
		if [[ ! -f "$file" ]]; then
			printf '%-14s %-9s %8s %9s  %s\n' "$name" "no-output" - - "-"
			# No output file at all: launched and silent, or never launched. Either way a quorum slot is
			# unaccounted for and the round is not finished.
			[[ "$quorum" == "quorum" ]] && unresolved=$((unresolved + 1))
			continue
		fi
		if [[ -f "$report_dir/$name.done" ]]; then
			state="done($(cat "$report_dir/$name.done"))"
		else
			state="running"
		fi
		IFS=$'\t' read -r verdict bytes findings <<<"$(classify "$file")"
		# A reviewer mid-answer has no verdict yet; calling it FLAKE reads as "nobody reviewed".
		[[ "$state" == "running" ]] && verdict="pending"
		printf '%-14s %-9s %8s %9s  %s%s\n' "$name" "$state" "$bytes" "$findings" "$verdict" \
			"$([[ "$quorum" == "quorum" ]] || echo " (non-quorum)")"
		# Exit status is part of the verdict: a CLI that errored can still print 1-10 KB containing
		# numbered lines, which would otherwise be counted as a substantive review.
		if [[ "$quorum" == "quorum" && "$verdict" == "REVIEW" && "$state" == "done(0)" ]]; then
			quorum_ok=$((quorum_ok + 1))
		elif [[ "$quorum" == "quorum" && "$state" == "running" ]]; then
			# STILL RUNNING is not "no findings" — the blocker may be seconds away. Two finished returns
			# must not produce a green report while a third reviewer is mid-answer (reviewer finding,
			# round 5).
			unresolved=$((unresolved + 1))
		elif [[ "$quorum" == "quorum" && "$findings" -gt 0 ]]; then
			# ANY quorum return carrying findings that was not auto-counted — SHORT, SUSPECT, or a
			# healthy-looking review whose CLI exited nonzero. Reviewer finding, round 4: the nonzero-exit
			# case was silently neither counted nor flagged, so two other returns still produced exit 0
			# with a real review sitting unread.
			unresolved=$((unresolved + 1))
		fi
	done <"$report_dir/manifest"
	echo
	echo "Auto-counted quorum returns: $quorum_ok of 2 required."
	echo "Counted = quorum reviewer + exit 0 + numbered findings + 1-10 KB. Everything else needs YOUR"
	echo "judgement and is not counted for you:"
	echo "  SHORT   = findings but <1 KB. Often ONE deliberate blocker, and often the most important"
	echo "            return of the round. Read it; count it yourself if it is a real review."
	echo "  SUSPECT = findings but >10 KB, usually dumped tool output around a real review."
	echo "  Also unresolved: any quorum return with findings whose CLI exited nonzero."
	echo "  FLAKE   = no numbered findings. The only verdict decided mechanically: nobody reviewed."
	echo "Non-quorum rows never count (tier 3, and the verify wrapper)."
	# Only files that appeared DURING the round are strays; the tree state at launch was recorded then,
	# so a legitimately dirty working tree does not cry wolf every time.
	strays=""
	if [[ -f "$report_dir/tree_before" ]]; then
		strays=$(LC_ALL=C comm -13 "$report_dir/tree_before" <(_dirty_paths | LC_ALL=C sort) || true)
	else
		strays=$(_dirty_paths || true)
	fi
	if [[ -f "$report_dir/tree_hashes" ]]; then
		# comm -3, not -13: a file whose hash DISAPPEARED (deleted or emptied by a reviewer) is
		# contamination too, and only shows up on the left-hand side.
		differing=$(LC_ALL=C comm -3 "$report_dir/tree_hashes" <(_hash_dirty_paths) \
			| awk '{print $NF}' | LC_ALL=C sort -u || true)
		[[ -n "$differing" ]] && strays="$strays"$'\n'"content differs from launch: $(printf '%s ' $differing)"
	fi
	if [[ -n "$strays" ]]; then
		echo
		echo "!! files changed since launch. A file written by one reviewer contaminates the others —"
		echo "   a concurrent model has read such an artifact off disk and returned it as its own review:"
		echo "$strays"
		# Contamination is a judgement call, so it counts as unresolved: exiting 0 here would claim
		# "nothing left to judge" while cross-review corroboration may be fake (reviewer finding, round 5).
		unresolved=$((unresolved + 1))
	fi
	if [[ "$quorum_ok" -lt 2 ]]; then
		echo; echo "QUORUM NOT MET — hold the work UNCOMMITTED."
		exit 1
	fi
	# The auto-count is a LOWER BOUND. Exiting 0 while a SHORT return sits unread is how the void round
	# of 2026-07-30 would have been missed: its blocker was an 823-byte SHORT.
	if [[ "$unresolved" -gt 0 ]]; then
		echo; echo "QUORUM MET on the auto-counted returns, but $unresolved item(s) need YOUR judgement:"
		echo "a SHORT or SUSPECT return, a quorum reviewer still running or silent, a return whose CLI"
		echo "exited nonzero, or files changed since launch. Resolve them before calling the round finished."
		exit 3
	fi
	exit 0
fi

# ---------------------------------------------------------------- launch mode

[[ -n "$brief" ]] || die "need --brief FILE (or --report DIR)"
[[ -f "$brief" ]] || die "brief '$brief' does not exist"

# Rule 2: a dirty tree must be frozen. A CLEAN tree needs nothing — the artifact is HEAD.
if [[ -n "$(git status --porcelain)" && "$do_freeze" -eq 0 ]]; then
	cat >&2 <<'EOF'
review_fanout: REFUSING to launch — the working tree is dirty and no artifact was frozen.

Reviewers handed a live tree report failures in states that never shipped. Pass --freeze and this
script snapshots the tree itself. There is deliberately no way to supply your own snapshot.
EOF
	exit 2
fi

if [[ -z "$out" ]]; then
	out="${TMPDIR:-/tmp}/review-fanout-$(date +%Y%m%d-%H%M%S)"
fi
# The out dir must live OUTSIDE the worktree. Reviewer finding, round 4: an in-repo --out fills with
# prompts, outputs and completion markers AFTER tree_before is taken, so the launcher reports its own
# files as contamination — and worse, concurrent reviewers can read each other's outputs off disk and
# manufacture corroboration, which is the exact failure the safety rules exist to prevent.
mkdir -p "$out"
out_abs=$(cd "$out" && pwd -P) || die "cannot resolve --out '$out'"
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) \
	|| die "not inside a git repository (git rev-parse --show-toplevel failed) — there is nothing to freeze."
repo_root=$(cd "$repo_root" && pwd -P)
if [[ "$out_abs" == "$repo_root" || "$out_abs" == "$repo_root"/* ]]; then
	die "--out must be OUTSIDE the worktree ('$out_abs' is inside '$repo_root'): reviewers would find each other's output files on disk. Use a scratch dir."
fi

# The SNAPSHOT, by contrast, must live INSIDE the worktree. Measured 2026-07-30: the opencode CLI is
# scoped to its workspace and auto-rejected reading a snapshot under /tmp — "permission requested:
# external_directory … auto-rejecting" — so that reviewer had never once read a frozen artifact. The
# directory is gitignored, which also keeps it out of `git status` and out of the freeze itself.
SNAPSHOT_DIR="$repo_root/.review-fanout"


# An --out holding ANY previous result would let --report count last round's returns as this one's,
# manifest or not.
if [[ -n "$(ls -A "$out" 2>/dev/null)" ]]; then
	die "'$out' is not empty. A leftover .txt/.done from a previous round would be counted as this round's return; pass a fresh --out."
fi

_dirty_paths | LC_ALL=C sort >"$out/tree_before"
# Content hashes, not just status lines: a reviewer editing a file that was ALREADY dirty at launch does
# not change `git status --porcelain` output at all, so line comparison alone misses it. `-uall` expands
# untracked DIRECTORIES to their files, so a file added inside one is visible too.
_hash_dirty_paths >"$out/tree_hashes"

if [[ "$do_freeze" -eq 1 ]]; then
	mkdir -p "$SNAPSHOT_DIR"
	snapshot="$SNAPSHOT_DIR/frozen-$(date +%Y%m%d-%H%M%S).diff"
	# A freeze cannot be trusted when the index is told to ignore worktree edits, or when a submodule is
	# dirty (the superproject diff shows only the gitlink). Reviewer finding, round 4: fail closed.
	hidden=$(git ls-files -v | grep -E '^[hsS]' | cut -c3- || true)
	[[ -z "$hidden" ]] || die "cannot freeze: these paths carry assume-unchanged/skip-worktree, so their edits appear in no diff: $(printf '%s ' $hidden)"
	# `git submodule status`'s "+" means the checked-out commit differs from the recorded gitlink; it says
	# NOTHING about uncommitted content AT the recorded commit, which is equally absent from the
	# superproject diff (reviewer finding, round 5). Ask each initialized submodule directly.
	dirty_subs=$(git submodule foreach --recursive --quiet 'test -z "$(git status --porcelain)" || echo "$displaypath"' 2>/dev/null || true)
	[[ -z "$dirty_subs" ]] || die "cannot freeze: submodule(s) with uncommitted content $(printf '%s ' $dirty_subs)— it is not in the superproject diff. Commit or stash inside them first."
	moved_subs=$(git submodule status --recursive 2>/dev/null | grep -E '^\+' | awk '{print $2}' || true)
	[[ -z "$moved_subs" ]] || die "cannot freeze: submodule(s) $(printf '%s ' $moved_subs)sit at a commit other than the recorded one; the superproject diff carries only the gitlink."

	# `git diff HEAD`, NOT `git diff`: the latter compares the worktree with the INDEX, so a file with
	# both staged and unstaged edits contributes only its unstaged hunks and the artifact silently omits
	# the rest while still passing the path-presence check below. (Reviewer finding, verified 2026-07-30
	# in a scratch repo: `git diff` showed one hunk, `git diff HEAD` showed both.)
	git diff HEAD -- >"$snapshot"
	# Then each untracked file as its own /dev/null diff, so a new file's BODY is in the artifact.
	# `git diff --no-index` exits 1 when files differ, which is the normal case here.
	# -z, not newlines: `git ls-files` C-QUOTES paths containing spaces or non-ASCII by default, and the
	# quoted spelling is then passed to git as a filename that does not exist.
	while IFS= read -r -d '' untracked; do
		[[ -n "$untracked" ]] || continue
		# 0 = identical, 1 = differ (the normal case here); anything else is a real failure, not noise.
		git diff --no-index -- /dev/null "$untracked" >>"$snapshot" || [[ $? -eq 1 ]] \
			|| die "could not diff untracked file '$untracked' into the snapshot"
	done < <(git ls-files --others --exclude-standard -z)
fi

# SELF-CHECK on our own output. This script calls `git` from PATH, and the incident that started all of
# this was a `git` wrapper emitting a compacted summary instead of a diff. A shim on PATH would do the
# same here, so the artifact is verified to BE a diff before any reviewer is pointed at it.
if [[ -n "$snapshot" ]]; then
	snapshot_files=$(grep -c '^diff --git' "$snapshot" || true)
	[[ "$snapshot_files" -gt 0 ]] || die "snapshot '$snapshot' contains no 'diff --git' header — it is not a diff. Regenerate it (--freeze does this for you)."
	# `git diff --binary` output would fail this, which is acceptable: --freeze never passes --binary.
	# STRUCTURAL check, not a word search: every line of real `git diff` output starts with one of the
	# diff sigils. A summariser's prose lines ("... (more changes truncated)", "[full diff: ...]") do
	# not, so they are caught without false-positiving on source code that happens to discuss
	# truncation — which a word search did, on this very script.
	prose=$(grep -cvE '^([-+@ \\]|$|diff |index |new file|deleted file|old mode|new mode|rename |similarity |dissimilarity |copy |Binary )' "$snapshot" || true)
	if [[ "$prose" -gt 0 ]]; then
		die "snapshot '$snapshot' has $prose line(s) that are not diff output — it is a summary or is truncated, and a partial diff produces confident findings about code the reviewer never saw. Regenerate it (--freeze does this for you). Offenders: $(grep -nvE '^([-+@ \\]|$|diff |index |new file|deleted file|old mode|new mode|rename |similarity |dissimilarity |copy |Binary )' "$snapshot" | head -3 | tr '\n' ' ')"
	fi
	echo "Snapshot: $snapshot_files file diff(s), every line verified as diff output."
fi

{
	echo "$REVIEW_ONLY_LINE"
	echo "REQUIREMENT: You must answer as a numbered list. Include \"1. No defect found — here is what I checked and what I concluded\" as a legal entry if you find nothing. Enumeration roles must number their lists."
	echo
	if [[ -n "$snapshot" ]]; then
		echo "THE FROZEN ARTIFACT UNDER REVIEW is the snapshot at $snapshot. Read that file."
		echo "Do NOT judge the working tree; it may have moved on."
	else
		echo "THE ARTIFACT UNDER REVIEW is the committed tree at HEAD ($(git rev-parse --short HEAD));"
		echo "the working tree is clean."
	fi
	echo
	cat "$brief"
} >"$out/prompt.txt"

# --role NAME=FILE -> the shared brief plus that reviewer's own job.
declare -A role_file=()
for spec in ${roles+"${roles[@]}"}; do
	[[ "$spec" == *=* ]] || die "--role expects NAME=FILE, got '$spec'"
	role_name="${spec%%=*}"
	role_path="${spec#*=}"
	[[ -f "$role_path" ]] || die "--role file '$role_path' does not exist"
	role_file["$role_name"]="$role_path"
done

# name<TAB>quorum|extra<TAB>command. Mirrors .claude/REVIEWERS.md § Invocations.
manifest=()
manifest+=("sol	quorum	pi -p --no-session --tools read,grep,find,ls --model openai-codex/gpt-5.6-sol")
manifest+=("agy	quorum	agy-explore")
manifest+=("deepseek	quorum	opencode run --agent plan --model opencode/deepseek-v4-flash-free")
if [[ "$want_tier3" -eq 1 ]]; then
	manifest+=("minimax	extra	pi -p --no-session --tools read,grep,find,ls --model nvidia/minimaxai/minimax-m3")
	manifest+=("nemotron	extra	pi -p --no-session --tools read,grep,find,ls --model nvidia/nvidia/nemotron-3-ultra-550b-a55b")
fi

# A --role naming a reviewer that is not in this round would be silently dropped, and a dropped role
# means an unbriefed reviewer answering the shared question — the correlated-noise case again.
if [[ "${#role_file[@]}" -gt 0 ]]; then
	for role_name in "${!role_file[@]}"; do
		printf '%s\n' "${manifest[@]}" | cut -f1 | grep -qx "$role_name" \
			|| die "--role '$role_name' names no reviewer in this round (have: $(printf '%s\n' "${manifest[@]}" | cut -f1 | tr '\n' ' '))"
	done
fi

# Roles are mandatory for quorum reviewers, not advisory: an unbriefed reviewer answers the shared
# question, and three identical answers are one opinion measured three times. Checked BEFORE launch.
if [[ "$allow_no_roles" -eq 0 ]]; then
	unbriefed=()
	for row in "${manifest[@]}"; do
		IFS=$'\t' read -r name quorum _cmd <<<"$row"
		[[ "$quorum" == "quorum" ]] || continue
		[[ -n "${role_file[$name]:-}" ]] || unbriefed+=("$name")
	done
	if [[ "${#unbriefed[@]}" -gt 0 ]]; then
		die "no --role for quorum reviewer(s): ${unbriefed[*]}. Give each its own job, or pass --no-roles to deliberately ask all three the same question."
	fi
fi

: >"$out/manifest"
for row in "${manifest[@]}"; do
	IFS=$'\t' read -r name quorum cmd <<<"$row"
	printf '%s\t%s\t%s\n' "$name" "$quorum" "$cmd" >>"$out/manifest"
	cp "$out/prompt.txt" "$out/$name.prompt.txt"
	if [[ -n "${role_file[$name]:-}" ]]; then
		{ echo; echo "## YOUR ROLE IN THIS ROUND"; echo; cat "${role_file[$name]}"; } >>"$out/$name.prompt.txt"
	fi
	prompt="$(cat "$out/$name.prompt.txt")"
	if [[ "$dry_run" -eq 1 ]]; then
		echo "would launch: $name -> $cmd  (prompt $(wc -c <"$out/$name.prompt.txt") bytes)"
		continue
	fi
	# Each reviewer buffers until exit, so there is nothing to poll; detach and record the exit code.
	# $2/$3 carry the output paths so a path containing a quote cannot end up as shell source.
	# `timeout` around EVERY route: AGY_TIMEOUT bounds only the agy wrappers, so without this the
	# "expect up to N minutes" promise was false for pi and opencode (reviewer finding, round 4).
	setsid nohup bash -c \
		"AGY_TIMEOUT=${TIMEOUT_MINUTES}m timeout ${TIMEOUT_MINUTES}m $cmd \"\$1\" >\"\$2\" 2>&1; echo \$? >\"\$3\"" \
		_ "$prompt" "$out/$name.txt" "$out/$name.done" </dev/null >/dev/null 2>&1 &
done

if [[ "$dry_run" -eq 1 ]]; then
	echo "DRY RUN — nothing launched. Prompts and manifest are in $out"
	exit 0
fi
echo "Launched ${#manifest[@]} reviewer(s) from $brief"
if [[ "${#role_file[@]}" -gt 0 ]]; then
	echo "Roles: ${!role_file[*]}"
else
	echo "NOTE: --no-roles was used; all reviewers got the identical brief (one opinion, measured N times)."
fi
if [[ -n "$snapshot" ]]; then
	echo "Frozen artifact: $snapshot"
else
	echo "Artifact: HEAD ($(git rev-parse --short HEAD)); the tree was clean."
fi
echo "Output dir: $out"
echo
echo "Reviews buffer until exit — expect up to ${TIMEOUT_MINUTES} minutes and do not poll for progress."
echo "Triage with:  tools/review_fanout.sh --report $out"
