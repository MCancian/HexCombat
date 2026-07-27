#!/usr/bin/env python3
"""GDScript static metrics for HexCombat audit.

Outputs JSON: per-function complexity/length, per-file deps, magic numbers,
duplication windows.
"""
import json, os, re, sys, hashlib
from collections import defaultdict

CHECK_CEILING = "--check-ceiling" in sys.argv
SELF_TEST = "--self-test" in sys.argv
_positional = [a for a in sys.argv[1:] if not a.startswith("--")]

ROOT = _positional[0] if len(_positional) > 0 else "."
OUT_PATH = _positional[1] if len(_positional) > 1 else None
SKIP_DIRS = {".godot", "addons", ".git"}

# Dependency ceilings (plan 0014 P5): a file's `ndeps` (distinct class_name/autoload references)
# exceeding its ceiling fails the gate with --check-ceiling. Add a new entry only when a file's
# role genuinely changes; bumping an existing ceiling to silence a real regression defeats the
# point — fix the coupling instead. Each ceiling = the measured count at the commit that set it,
# plus small headroom for legitimate growth (a new field, a new phase call), not room to launder
# a god-object back in.
DEP_CEILINGS = {
    # GameState.gd (plan 0014): decomposed into GameStateData (state) + GameStateBuilder
    # (scenario-load builders) + TurnConductor (turn orchestration) + OrderValidator (order
    # legality) — GameState.gd itself is now a thin autoload shell: typed forwarding properties
    # (var x: T: get/set) for the external byte-stable API, plus a few one-line delegating
    # wrappers kept because GdUnit tests call them directly on the autoload. Most of its 24
    # measured deps are property-type annotations (SealiftState, SupplyState, CombatSummary, …)
    # inherent to that forwarding surface, not turn-orchestration coupling — measured 24 at
    # commit time, well above the plan's ~8-12 prediction (which assumed a looser/untyped
    # forwarding mechanism; the typed-property design was chosen deliberately after a generic
    # _get/_set override proved unreliable for legitimately-null fields).
    # 27 -> 29 (plan 0032): AirInsertionState / AirInsertionSummary forwarding properties, the same
    # typed-property tax every phase's state pays here.
    # 29 -> 28 (plan 0038 step 2): `_build_warmup_context` and `_mine_ship_meta` now delegate through
    # FiresPhases instead of naming IjfsResolver/AntishipResolver directly, so the façade trades two
    # resolver deps for one module dep. LOWERED, not held, so the slack cannot be silently re-spent.
    # 28 -> 28 (plan 0038 step 3): +TurnClosure, -CombatResolver (`_brigade_ids` routes through
    # TurnConductor, the combat owner, like every other phase surface). A swap, not growth.
    # 28 -> 29 (plan 0041): FrontlinePhase extracted from TurnConductor. GameState depends on FrontlinePhase for façade redirection.
    # 29 -> 29 (plan 0052): test-only `_build_warmup_context` / `_mine_ship_meta` façades were
    # deleted; measured deps stayed flat because the remaining typed forwarding surface dominates.
    "scripts/GameState.gd": 29,
    # TurnConductor.gd legitimately depends on every phase resolver it orchestrates (IjfsResolver,
    # SealiftResolver, AntishipResolver, OffloadResolver, InfrastructureResolver, SupplyResolver,
    # CleanupResolver, FrontlineResolver, CombatResolver, …) — that is cohesion, not lamination.
    # Ceiling here catches it acquiring UNRELATED responsibilities (the god-object failure mode),
    # not the resolver fan-out that is its actual job. Measured 32 at commit time.
    # 36 -> 38 (plan 0032): AirInsertionResolver + AirInsertionStateBuilder, i.e. one more phase in
    # the fan-out this ceiling explicitly does not police.
    # 38 -> 28 (plan 0038): the arrival phases (sealift/offload/mobilization/air insertion) moved to
    # ReinforcementPhases and the roster-shrinking seam to RosterMutations, so their resolvers and
    # value types left with them. LOWERED to the newly-measured value, per the plan — the headroom
    # bought is locked in rather than silently re-spent by the next mechanic.
    # 28 -> 22 (plan 0038 step 2): the fires phases (IJFS + anti-ship) moved to FiresPhases, taking
    # IjfsResolver, AntishipResolver, SealiftResolver, GameStateBuilder, Theaters, ShipDef, ShipState.
    # 22 -> 20 (plan 0038 step 3): supply + cleanup moved to TurnClosure, taking CleanupResolver,
    # SupplyResolver and Battalion. What is left is the turn ORDER plus movement/combat/FEBA/frontline.
    # 20 -> 18 (plan 0041): FrontlinePhase extracted from TurnConductor.
    "scripts/phases/TurnConductor.gd": 18,
    # ReinforcementPhases.gd (plan 0038): owns the four "force arrives" phases and their resolvers.
    # Ceilinged from birth because a phase-owning module is exactly where a god-object would be
    # laundered back in — a NEW arrival phase belongs here (and may justify a small bump), an
    # unrelated responsibility does not. Measured 22 at commit time.
    "scripts/phases/ReinforcementPhases.gd": 22,
    # FiresPhases.gd (plan 0038 step 2): owns IJFS + the anti-ship/mine crossing defence. Same
    # reasoning as ReinforcementPhases — ceilinged from birth. Measured 14 at commit time.
    # Plan 0043 held it at 14 by a one-for-one swap, not a bump: `Theaters` left (its only remaining
    # caller re-derived a map GameData already holds, so the file was deleted) and the anti-ship
    # mutation authority `AntishipTransitions` took its place.
    # 14 -> 15 (plan 0052): `AntishipResolutionContext` is the typed model that replaces the
    # anti-ship resolver's 11-parameter signature; this coordinator is the call-site assembler.
    "scripts/phases/FiresPhases.gd": 15,
    # TurnClosure.gd (plan 0038 step 3): the end-of-turn accounting pair (supply bills who fought,
    # cleanup censuses who is left). Measured 7 at commit time.
    "scripts/phases/TurnClosure.gd": 7,
}

# Parameter ceilings (plan 0052): a function's measured params exceeding the hard cap of 5 fails
# the gate with --check-ceiling unless grandfathered here. Keyed by "path::function_name" because
# parameter counts live per function, not per file. Same ratchet rule as DEP_CEILINGS: each entry is
# the measured count at the commit that set it; lower after refactors, never raise to hide a breach.
# Seeded after the multi-line signature counter was fixed so the existing tree stays green while
# future touched functions have a real, enforceable budget.
PARAM_HARD_CAP = 5
PARAM_CEILINGS = {
    "scripts/calc/CombatCalculator.gd::_force_strengths": 8,
    "scripts/calc/CombatCalculator.gd::_loss_counts": 6,
    "scripts/calc/CombatCalculator.gd::_select_casualties": 6,
    "scripts/calc/CombatCalculator.gd::resolve_map_attack": 8,
    "scripts/JlsfCargo.gd::queue_deployments": 7,
    "scripts/LLMGameAPI.gd::_action_result": 6,
    "scripts/OffloadCalculator.gd::_resolve_day_n": 10,
    "scripts/OffloadCalculator.gd::resolve_offload_day": 9,
    "scripts/builders/SealiftStateBuilder.gd::build": 6,
    "scripts/calc/AntishipCalculator.gd::build_firing_plan": 6,
    "scripts/calc/AntishipCrossing.gd::_apply_homing": 6,
    "scripts/calc/AntishipCrossing.gd::_apply_interception": 6,
    "scripts/calc/AntishipCrossing.gd::_resolve_damage": 6,
    "scripts/calc/AntishipCrossing.gd::_resolve_launches": 9,
    "scripts/calc/AntishipCrossing.gd::resolve_crossing_damage": 9,
    "scripts/calc/MineWarfareService.gd::_apply_beach_outcome": 7,
    "scripts/calc/MineWarfareService.gd::_beach_result": 8,
    "scripts/calc/MineWarfareService.gd::_count_dangerous_mines": 9,
    "scripts/calc/MineWarfareService.gd::resolve_ship_losses": 7,
    "scripts/ijfs/IjfsDetection.gd::_log_detection": 7,
    "scripts/ijfs/IjfsDetection.gd::_run_detection_phase": 8,
    "scripts/ijfs/IjfsDetection.gd::aircraft_detect_target_ids": 7,
    "scripts/ijfs/IjfsEngagement.gd::resolve_sead_engagement": 6,
    "scripts/ijfs/IjfsEngine.gd::_append_final_skips": 6,
    "scripts/ijfs/IjfsEngine.gd::_run_strike_phase": 11,
    "scripts/ijfs/IjfsEngine.gd::_skip_log": 6,
    "scripts/ijfs/IjfsManpads.gd::intercepted_strike_log": 6,
    "scripts/ijfs/IjfsStrike.gd::resolve_strike": 9,
    "scripts/ijfs/IjfsTargeting.gd::apply_exquisite_intel": 6,
    "scripts/ijfs/IjfsTargeting.gd::select_munition_with_doctrine": 8,
    "scripts/resolvers/AirInsertionResolver.gd::resolve": 7,
    "scripts/resolvers/CleanupResolver.gd::resolve": 6,
    "scripts/resolvers/IjfsResolver.gd::build_warmup_context": 8,
    "scripts/resolvers/OffloadResolver.gd::resolve": 8,
    "tests/batch_report_test.gd::_legacy_record": 7,
    "tests/batch_report_test.gd::_record": 8,
    "tests/ijfs/ijfs_loaders_test.gd::_container": 6,
    "tests/ijfs/ijfs_targeting_test.gd::_pairing": 8,
    "tests/ijfs/ijfs_targeting_test.gd::_target": 7,
    "tools/run_selfplay_game.gd::_build_record": 9,
    "tools/validate_mutation_authority.gd::_protected_finding": 6,
}

FUNC_RE = re.compile(r"^(\s*)(static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)$")
BRANCH_RE = re.compile(r"^\s*(if|elif|for|while)\b")
MATCH_ARM_RE = re.compile(r"^\s*[^#\s].*:\s*(#.*)?$")
BOOL_OP_RE = re.compile(r"\b(and|or)\b|&&|\|\|")
NUM_RE = re.compile(r"(?<![\w.])-?\d+\.?\d*(?:[eE][+-]?\d+)?(?![\w.])")
CONST_RE = re.compile(r"^\s*const\s+")
DEP_PATTERNS = [
    re.compile(r'preload\(\s*"([^"]+)"'),
    re.compile(r'load\(\s*"(res://[^"]+\.gd)"'),
]
# class_name registry pass 1
CLASSNAME_RE = re.compile(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)")
EXTENDS_RE = re.compile(r"^extends\s+([A-Za-z_][A-Za-z0-9_.]*)")

def gd_files():
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            if fn.endswith(".gd"):
                yield os.path.join(dp, fn)

files = sorted(gd_files())

# pass 1: collect class_names
classnames = {}
for f in files:
    for line in open(f, encoding="utf-8", errors="replace"):
        m = CLASSNAME_RE.match(line)
        if m:
            classnames[m.group(1)] = f
            break

CLASSNAME_TOKEN_RE = re.compile(r"\b(" + "|".join(re.escape(c) for c in classnames) + r")\b") if classnames else None

# Known autoload singletons (heuristic: referenced as bare CamelCase.method)
AUTOLOADS = set()
proj = os.path.join(ROOT, "project.godot")
if os.path.exists(proj):
    in_auto = False
    for line in open(proj, encoding="utf-8", errors="replace"):
        s = line.strip()
        if s.startswith("["):
            in_auto = (s == "[autoload]")
        elif in_auto and "=" in s:
            AUTOLOADS.add(s.split("=")[0].strip())

result = {"files": {}, "functions": [], "magic": {}, "dup": {}}

def strip_str_comment(line):
    # crude: remove string literals then comments
    line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    line = re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)
    return line.split("#")[0]


def _signature_params_and_end(lines, start_idx, first_line_after_open):
    """Count top-level params in a GDScript func signature and return its closing line index.

    The regex has already consumed the function name and the opening "(". Continue across lines
    until that outer paren closes, counting only commas whose nesting stack is exactly the function
    parameter list. Commas in default Array/Dictionary literals, Callable signatures, or comments do
    not split parameters.
    """
    stack = ["("]
    chunks = []
    idx = start_idx
    pending = first_line_after_open
    while idx < len(lines):
        code = strip_str_comment(pending if idx == start_idx else lines[idx])
        for ch in code:
            if ch in "([{":
                stack.append(ch)
                chunks.append(ch)
                continue
            if ch in ")]}":
                if ch == ")" and len(stack) == 1 and stack[-1] == "(":
                    params = "".join(chunks).strip()
                    if not params:
                        return 0, idx
                    return _count_top_level_params(params), idx
                if stack:
                    stack.pop()
                chunks.append(ch)
                continue
            chunks.append(ch)
        chunks.append("\n")
        idx += 1
    raise ValueError("unterminated function signature starting at line %d" % (start_idx + 1))


def _count_top_level_params(params):
    depth = 0
    current = []
    parts = []
    for ch in params:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth = max(0, depth - 1)
        if ch == "," and depth == 0:
            parts.append("".join(current))
            current = []
            continue
        current.append(ch)
    parts.append("".join(current))
    return len([part for part in parts if part.strip()])


def _self_test_signature_params():
    cases = [
        (["func a(x: int, y: int) -> void:"], 2, "single-line"),
        (["func b(", "\tx: int,", "\ty: int,", ") -> void:"], 2, "multi-line"),
        (["func c(x: Array = [1, 2], y: Dictionary = {\"a\": 1, \"b\": 2}) -> void:"], 2, "default comma"),
        (["func d(cb: Callable[Array[int], Dictionary], y: int) -> void:"], 2, "nested annotation"),
        (["func e() -> void:"], 0, "zero params"),
    ]
    for lines, expected, label in cases:
        m = FUNC_RE.match(lines[0])
        got, _sig_end = _signature_params_and_end(lines, 0, m.group(4))
        if got != expected:
            raise AssertionError("%s: expected %d params, got %d" % (label, expected, got))


if SELF_TEST or CHECK_CEILING:
    _self_test_signature_params()

norm_windows = defaultdict(list)  # hash -> [(file, startline)]
W = 6

for f in files:
    rel = os.path.relpath(f, ROOT)
    lines = open(f, encoding="utf-8", errors="replace").read().splitlines()
    deps = set()
    extends = None
    magic_count = 0
    magic_lines = []
    in_match_stack = []  # indents of active match statements

    # dependency + magic scan
    const_block_depth = 0  # >0 while inside a multi-line const {...}/[...] literal
    for i, raw in enumerate(lines):
        code = strip_str_comment(raw)
        in_const_block = const_block_depth > 0
        if CONST_RE.match(raw) or in_const_block:
            const_block_depth += code.count("{") + code.count("[") - code.count("}") - code.count("]")
            const_block_depth = max(0, const_block_depth)
        for pat in DEP_PATTERNS:
            for m in pat.finditer(raw):
                deps.add(m.group(1))
        if CLASSNAME_TOKEN_RE:
            for m in CLASSNAME_TOKEN_RE.finditer(code):
                cn = m.group(1)
                if classnames.get(cn) != f:
                    deps.add(cn)
        for a in AUTOLOADS:
            if re.search(r"\b" + re.escape(a) + r"\b", code):
                deps.add("autoload:" + a)
        m = EXTENDS_RE.match(raw)
        if m:
            extends = m.group(1)
        # magic numbers: numeric literals outside const declarations (incl. multi-line const
        # tables) and @export defaults; exponent-notation epsilons (1e-9) don't count.
        if not CONST_RE.match(raw) and not in_const_block and "export" not in raw:
            for m in NUM_RE.finditer(code):
                v = m.group(0)
                if v in ("0","1","-1","2","0.0","1.0","-1.0","0.5","100","1000"): continue
                if "e" in v or "E" in v: continue
                magic_count += 1
                if len(magic_lines) < 400:
                    magic_lines.append((i+1, v))

    # function scan
    funcs = []
    cur = None
    for i, raw in enumerate(lines):
        m = FUNC_RE.match(raw)
        if m:
            if cur: cur["end"] = i; funcs.append(cur)
            indent = len(m.group(1))
            nparams, sig_end = _signature_params_and_end(lines, i, m.group(4))
            cur = {"file": rel, "name": m.group(3), "start": i+1, "indent": indent,
                   "sig_end": sig_end + 1, "cc": 1, "params": nparams, "returns": 0, "match_arms": 0}
        elif cur is not None:
            if i + 1 <= cur["sig_end"]:
                continue
            code = strip_str_comment(raw)
            if code.strip() and (len(raw) - len(raw.lstrip())) <= cur["indent"] and not raw.lstrip().startswith(")"):
                cur["end"] = i; funcs.append(cur); cur = None; continue
            if BRANCH_RE.match(code): cur["cc"] += 1
            cur["cc"] += len(BOOL_OP_RE.findall(code))
            if re.match(r"^\s*match\b", code): cur["_match_indent"] = len(code) - len(code.lstrip())
            if "_match_indent" in cur and MATCH_ARM_RE.match(code):
                ind = len(code) - len(code.lstrip())
                if ind == cur["_match_indent"] + 1 or ind == cur["_match_indent"] + 4 or ind == cur["_match_indent"] + 2:
                    if not re.match(r"^\s*(if|elif|for|while|func|else)\b", code):
                        cur["cc"] += 1
            if re.match(r"^\s*return\b", code): cur["returns"] += 1
    if cur: cur["end"] = len(lines); funcs.append(cur)
    for fn in funcs:
        fn.pop("_match_indent", None)
        fn.pop("sig_end", None)
        fn["len"] = fn["end"] - fn["start"] + 1
    result["functions"].extend(funcs)

    result["files"][rel] = {
        "loc": len(lines),
        "deps": sorted(deps),
        "ndeps": len(deps),
        "extends": extends,
        "magic": magic_count,
        "magic_sample": magic_lines[:15],
        "nfuncs": len(funcs),
    }

    # duplication: normalized sliding windows (scripts+tools only meaningful, but scan all)
    norm = []
    for i, raw in enumerate(lines):
        c = strip_str_comment(raw).strip()
        if not c or c in ("pass",):
            norm.append(None); continue
        c = re.sub(r"\s+", " ", c)
        norm.append((i+1, c))
    seq = [x for x in norm if x]
    for j in range(len(seq) - W + 1):
        chunk = "\n".join(x[1] for x in seq[j:j+W])
        h = hashlib.md5(chunk.encode()).hexdigest()
        norm_windows[h].append((rel, seq[j][0]))

# duplication summary: windows appearing 2+ times, merge overlapping
dups = {h: locs for h, locs in norm_windows.items() if len(locs) > 1}
dup_lines_per_file = defaultdict(set)
for h, locs in dups.items():
    for rel, start in locs:
        for k in range(W):
            dup_lines_per_file[rel].add(start + k)
result["dup"] = {
    "n_dup_windows": len(dups),
    "dup_lines_by_file": {k: len(v) for k, v in sorted(dup_lines_per_file.items(), key=lambda kv: -len(kv[1]))},
    "total_dup_lines": sum(len(v) for v in dup_lines_per_file.values()),
}
result["classnames"] = {k: os.path.relpath(v, ROOT) for k, v in classnames.items()}
result["autoloads"] = sorted(AUTOLOADS)

if OUT_PATH:
    json.dump(result, open(OUT_PATH, "w"), indent=1)
print("files", len(files), "funcs", len(result["functions"]),
      "dup_windows", result["dup"]["n_dup_windows"],
      "total_dup_lines", result["dup"]["total_dup_lines"])

if CHECK_CEILING:
    breaches = []
    for rel, ceiling in DEP_CEILINGS.items():
        info = result["files"].get(rel)
        if info is None:
            breaches.append("%s: not found (ceiling entry stale — file moved/deleted?)" % rel)
            continue
        if info["ndeps"] > ceiling:
            breaches.append("%s: ndeps=%d exceeds ceiling %d" % (rel, info["ndeps"], ceiling))

    functions_by_key = defaultdict(list)
    for fn in result["functions"]:
        functions_by_key["%s::%s" % (fn["file"], fn["name"])].append(fn)
    for key, ceiling in PARAM_CEILINGS.items():
        matches = functions_by_key.get(key, [])
        if not matches:
            breaches.append("%s: not found (ceiling entry stale — function moved/renamed?)" % key)
            continue
        for fn in matches:
            if fn["params"] > ceiling:
                breaches.append("%s:%d: params=%d exceeds ceiling %d" % (
                    key, fn["start"], fn["params"], ceiling))

    for fn in result["functions"]:
        key = "%s::%s" % (fn["file"], fn["name"])
        if fn["params"] > PARAM_HARD_CAP and key not in PARAM_CEILINGS:
            breaches.append("%s: params=%d exceeds hard cap %d (add/fix typed context or grandfather ceiling)" % (
                key, fn["params"], PARAM_HARD_CAP))

    if breaches:
        print("FAIL: metric ceiling breach(es):")
        for b in breaches:
            print("  -", b)
        sys.exit(1)
    print("PASS: metric ceilings OK (%d file(s), %d function(s) checked)" % (
        len(DEP_CEILINGS), len(PARAM_CEILINGS)))
