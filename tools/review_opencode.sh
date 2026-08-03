#!/usr/bin/env bash
# DeepSeek reviewer route — runs the opencode plan agent with `--format json` and emits the
# assistant's message text, so the byte band sees the report and not opencode's prompt echo / tool
# traces (docs/plans/BACKLOG.md "DeepSeek's return is unparseable by the byte band", closed
# 2026-08-03). That noise mislabelled two real 23.6 KB / 14.7 KB enumeration returns as SUSPECT.
#
# Interface: tools/review_opencode.sh "PROMPT"
#   tools/review_fanout.sh launches this with the prompt as "$1" and records our exit code in
#   <name>.done, so a nonzero opencode exit propagates as a failed review. The prompt reaches
#   opencode as its message argument, never the extractor's argv.
#
# Why the wrapper runs from the repo root: opencode scopes its workspace to the CWD, and the
# launcher hands reviewers a frozen artifact at an absolute path inside the repo — the workspace
# must be the repo for that path to be readable.
#
# Why all assistant text, not just the last message: a review interleaves tool calls with its
# findings, so a report can be fragmented across several assistant messages. Emitting only the
# last would silently drop every finding written before a final tool call. Tool traces (`tool`
# parts) and reasoning (`reasoning` parts) are excluded; only `text` parts are emitted.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ -n "${1:-}" ]] || { echo "review_opencode: no prompt argument" >&2; exit 2; }

tmp="$(mktemp "${TMPDIR:-/tmp}/review-opencode.XXXXXX.ndjson")"
trap 'rm -f "$tmp"' EXIT

opencode run --agent plan --model opencode/deepseek-v4-flash-free --format json "$1" >"$tmp" &
pid=$!
# The launcher wraps every route in `timeout`. A single `kill "$pid"` leaves opencode's tool
# children orphaned (measured 2026-08-03 with a stub that spawned a sleep child), so the trap
# walks the descendant tree. opencode is not a process-group leader — it inherits the wrapper's
# group — so a group kill would also signal this script and the launcher's `.done` writer.
_kill_tree() {
	local p="$1" child
	for child in $(ps -o pid= --ppid "$p" 2>/dev/null); do
		_kill_tree "$child"
	done
	kill -TERM "$p" 2>/dev/null || true
}
trap '_kill_tree "$pid"' TERM
wait "$pid"
oc_status=$?
trap - TERM

# NDJSON events carry each assistant message as `text` parts keyed by messageID; a message may be
# fragmented across several parts. Texts are joined per message and ALL messages are emitted in
# order, so a report interleaved with tool calls loses nothing.
python3 - "$tmp" <<'PY'
import json
import sys

messages: dict = {}
order: list = []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except json.JSONDecodeError:
        continue
    part = ev.get("part") or {}
    if part.get("type") in ("text", "text.delta") and isinstance(part.get("text"), str):
        mid = part.get("messageID")
        if mid not in messages:
            messages[mid] = ""
            order.append(mid)
        messages[mid] += part["text"]
if order:
    print("".join(messages[oid] for oid in order), end="")
PY
py_status=$?

if [[ "$oc_status" -ne 0 ]]; then
    exit "$oc_status"
fi
exit "$py_status"
