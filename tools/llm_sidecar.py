#!/usr/bin/env python3
"""Out-of-process LLM sidecar for HexCombat (harness B6).

Reads a game observation, asks a LOCAL OpenAI-compatible model (vLLM by default) for this side's
orders, validates every returned action against the observation's authoritative legal sets, logs
the observation/action pair for replay, and prints the validated action array to stdout. Standard
library only (no pip dependencies) so the engine can shell out to it with nothing installed.

Contract mirrors tools/llm_sidecar_stub.py so both are interchangeable behind scripts/LLMPolicy.gd:
  stdin/args:  --obs <file>  --perspective Red|Green  [--log <jsonl>]
  stdout:      a JSON array of validated action objects (never any prose)
  exit code:   0 on success (including "model gave nothing usable" -> []),
               non-zero ONLY on hard failure (model unreachable / HTTP error).

Provider config from the environment (inherited from the Godot process):
  HEXCOMBAT_LLM_BASE_URL  default http://localhost:8088/v1
  HEXCOMBAT_LLM_MODEL     required (the vLLM served model id)
  HEXCOMBAT_LLM_API_KEY   default "EMPTY"  (sent as Authorization: Bearer <key>)
"""
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

DEFAULT_BASE_URL = "http://127.0.0.1:8088/v1"
HTTP_TIMEOUT_SECONDS = 300
# Reasoning models burn output tokens on a chain-of-thought BEFORE emitting the answer, so the
# budget must cover reasoning + the action JSON or `content` comes back null (finish_reason=length).
# Sized against DeepSeek-V4-Flash's 131072-token context: worst observed prompt ≈21K tokens
# (Green seat, 32 brigades), so 32768 output still leaves ~60% of context unused. Overruns were
# observed at 8192 (game 20260710, 5 forfeited turns). The budget is also the cap on how long one
# rambling turn can grind on the local GPU before the parse-failure retry — that wall-clock cost,
# not context, is the reason this isn't higher.
DEFAULT_MAX_TOKENS = 32768
DEFAULT_TEMPERATURE = 0.7

# Observation keys worth sending to the model — the big static fields (rules text lives in the
# system prompt; map geometry, ship data, etc.) are omitted to keep the prompt small.
COMPACT_KEYS = [
    "turn", "perspective_team", "brigades", "occupied_hexes",
    "legal_moves", "legal_commits", "pending_orders", "last_combat",
]


# Diagnostics collected for the JSONL record — stderr is DROPPED by the engine's OS.execute
# (read_stderr=false so it can't corrupt the stdout action array), so the replay log is the only
# place warnings reliably surface.
WARNINGS = []


def log(message):
    print(message, file=sys.stderr)
    WARNINGS.append(message)


def _prior_turn_duplicate_brigades(log_path, perspective):
    """Scan JSONL for this side's last turn; return brigade IDs with duplicate-order warnings.

    Iterates line-by-line (never loads whole file) and only extracts brigade IDs from
    the last matching-perspective record's warnings. No --log, missing file, or failed
    parse -> empty list.
    """
    if not log_path or not os.path.isfile(log_path):
        return []
    pat = re.compile(r"dropping duplicate order for (\S+)")
    found = []
    with open(log_path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except (ValueError, TypeError):
                continue
            if record.get("perspective") != perspective:
                continue
            # Hit a matching record — reset and collect this turn only
            found = []
            for w in record.get("warnings", []):
                m = pat.search(str(w))
                if m:
                    found.append(m.group(1))
    return found


def load_observation(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def build_messages(observation, perspective, prior_duplicate_brigades=None):
    rules = observation.get("rules_summary", {})
    glossary = observation.get("field_glossary", {})
    system = (
        "You are the commander of the {side} side in a WeGo hex wargame (HexCombat: a PLA "
        "amphibious assault on Taiwan). Each planning turn you issue orders; then both sides' "
        "orders resolve simultaneously.\n\n"
        "RULES:\n{rules}\n\nGLOSSARY:\n{glossary}\n\n"
        "You may ONLY use brigade IDs and hex IDs that appear in this turn's legal_moves and "
        "legal_commits — never invent an ID. If a brigade is not listed it cannot act this turn.\n"
        "Reply with ONLY a JSON array of action objects and nothing else (no prose, no markdown "
        "code fences). An empty array [] is a valid reply meaning 'no orders'."
    ).format(side=perspective, rules=json.dumps(rules, indent=2), glossary=json.dumps(glossary, indent=2))

    compact = {k: observation[k] for k in COMPACT_KEYS if k in observation}
    user = (
        "Current situation (your perspective). Choose this side's orders for the turn.\n"
        "Action shapes:\n"
        '  {"type":"move","team":"' + perspective + '","brigade_id":<id>,"target_hex":<hex>,'
        '"mode":"tactical"|"administrative"}\n'
        '  {"type":"commit","team":"' + perspective + '","brigade_id":<id>,"target_hex":<hex>}\n\n'
        + json.dumps(compact)
    )
    if prior_duplicate_brigades:
        user += (
            "\n\nReminder: last turn you issued more than one order for these brigades and only "
            "the first was kept: %s. Issue AT MOST ONE order per brigade this turn."
            % ", ".join(prior_duplicate_brigades)
        )
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def call_model(messages):
    """POST to the chat-completions endpoint. Returns (text, model), where text is the assistant's
    answer — `content`, falling back to `reasoning`/`reasoning_content` for reasoning models that
    leave `content` null. Raises on a hard failure (unreachable / HTTP error / malformed envelope)."""
    base_url = os.environ.get("HEXCOMBAT_LLM_BASE_URL", DEFAULT_BASE_URL).rstrip("/")
    model = os.environ.get("HEXCOMBAT_LLM_MODEL", "")
    api_key = os.environ.get("HEXCOMBAT_LLM_API_KEY", "EMPTY")
    if not model:
        raise RuntimeError("HEXCOMBAT_LLM_MODEL is not set")
    max_tokens = int(os.environ.get("HEXCOMBAT_LLM_MAX_TOKENS", DEFAULT_MAX_TOKENS))
    temperature = float(os.environ.get("HEXCOMBAT_LLM_TEMPERATURE", DEFAULT_TEMPERATURE))

    body = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens,
    }).encode("utf-8")
    request = urllib.request.Request(
        base_url + "/chat/completions",
        data=body,
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + api_key},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
        payload = json.load(response)
    choice = payload["choices"][0]
    message = choice.get("message", {})
    text = message.get("content") or message.get("reasoning") or message.get("reasoning_content") or ""
    if choice.get("finish_reason") == "length":
        log("llm_sidecar: finish_reason=length — model hit the token budget; raise "
            "HEXCOMBAT_LLM_MAX_TOKENS if actions are missing")
    return text, model


def extract_actions(content):
    """Pull the first JSON array out of the model reply. Returns a list, or None if nothing parses."""
    if content is None:
        return None
    text = content.strip()
    for candidate in _candidate_json_arrays(text):
        try:
            parsed = json.loads(candidate)
        except (ValueError, TypeError):
            continue
        if isinstance(parsed, list):
            return parsed
    return None


def _candidate_json_arrays(text):
    # 1) the whole reply; 2) inside ```json ... ``` / ``` ... ``` fences; 3) the first [...] block.
    yield text
    fence = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    if fence:
        yield fence.group(1).strip()
    bracket = re.search(r"\[.*\]", text, re.DOTALL)
    if bracket:
        yield bracket.group(0)


def validate_actions(actions, observation, perspective):
    """Keep only actions this side may legally issue; force team = perspective; drop end_turn.

    One order per brigade per turn (engine rule, GameState.queue_move): later duplicates in the
    same reply are dropped here so the logged actions match what the engine actually applies.
    """
    legal_moves = observation.get("legal_moves", {})
    legal_commits = observation.get("legal_commits", {})
    kept = []
    ordered_brigades = set()
    for action in actions:
        if not isinstance(action, dict):
            continue
        atype = action.get("type")
        brigade_id = action.get("brigade_id")
        if brigade_id in ordered_brigades:
            log("llm_sidecar: dropping duplicate order for %s (one order per brigade per turn)"
                % brigade_id)
            continue
        if atype == "move" and _is_legal_move(action, legal_moves, perspective):
            kept.append(_with_team(action, perspective, ["brigade_id", "target_hex", "mode"], "move"))
            ordered_brigades.add(brigade_id)
        elif atype == "commit" and _is_legal_commit(action, legal_commits, perspective):
            kept.append(_with_team(action, perspective, ["brigade_id", "target_hex"], "commit"))
            ordered_brigades.add(brigade_id)
        # anything else (end_turn, unknown, illegal, wrong team) is dropped.
    return kept


def _is_legal_move(action, legal_moves, perspective):
    brigade_id = action.get("brigade_id")
    entry = legal_moves.get(brigade_id)
    if not isinstance(entry, dict) or entry.get("team") != perspective:
        return False
    mode = action.get("mode", "tactical")
    return action.get("target_hex") in entry.get(mode, [])


def _is_legal_commit(action, legal_commits, perspective):
    by_team = legal_commits.get(action.get("target_hex"), {})
    return action.get("brigade_id") in by_team.get(perspective, [])


def _with_team(action, perspective, keys, atype):
    out = {"type": atype, "team": perspective}
    for key in keys:
        if key in action:
            out[key] = action[key]
    if atype == "move":
        out.setdefault("mode", "tactical")
    return out


def append_log(log_path, perspective, observation, model, raw_reply, actions):
    os.makedirs(os.path.dirname(os.path.abspath(log_path)), exist_ok=True)
    record = {
        "perspective": perspective,
        "turn": observation.get("turn"),
        "model": model,
        "raw_reply": raw_reply,
        "actions": actions,
        "warnings": list(WARNINGS),
        # Full observation makes the JSONL the replay artifact (LLM games are not seed-reproducible).
        "observation": observation,
    }
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Local-LLM sidecar for HexCombat.")
    parser.add_argument("--obs", required=True, help="Path to the observation JSON file.")
    parser.add_argument("--perspective", required=True, choices=["Red", "Green"])
    parser.add_argument("--log", default="", help="Optional JSONL obs/action log to append to.")
    args = parser.parse_args()

    observation = load_observation(args.obs)
    prior_dups = _prior_turn_duplicate_brigades(args.log, args.perspective)
    messages = build_messages(observation, args.perspective, prior_dups)

    try:
        raw_reply, model = call_model(messages)
    except (urllib.error.URLError, OSError, RuntimeError, KeyError, ValueError) as error:
        log("llm_sidecar: hard failure calling model: %s" % error)
        return 1

    parsed = extract_actions(raw_reply)
    if parsed is None:
        # Reasoning models can burn the whole token budget thinking out loud (finish_reason=length
        # leaves content null; the reasoning fallback is truncated prose, no JSON). One strict
        # retry rescues the turn instead of forfeiting it.
        log("llm_sidecar: model reply had no parseable JSON array; retrying once with a strict nudge")
        retry_messages = messages + [
            {"role": "assistant", "content": raw_reply[:500] + "…[cut off]"},
            {"role": "user", "content": (
                "Your reply was cut off before any JSON appeared. Do NOT reason out loud. "
                "Output ONLY the JSON array of action objects now — nothing else. "
                "[] if no orders.")},
        ]
        try:
            raw_reply, model = call_model(retry_messages)
            parsed = extract_actions(raw_reply)
        except (urllib.error.URLError, OSError, RuntimeError, KeyError, ValueError) as error:
            log("llm_sidecar: retry hard failure: %s" % error)
            parsed = None
    if parsed is None:
        log("llm_sidecar: no parseable JSON array after retry; issuing no orders")
        actions = []
    else:
        actions = validate_actions(parsed, observation, args.perspective)

    if args.log:
        append_log(args.log, args.perspective, observation, model, raw_reply, actions)
    sys.stdout.write(json.dumps(actions))
    return 0


if __name__ == "__main__":
    sys.exit(main())
