#!/usr/bin/env python3
"""GDScript static metrics for HexCombat audit.

Outputs JSON: per-function complexity/length, per-file deps, magic numbers,
duplication windows.
"""
import json, os, re, sys, hashlib
from collections import defaultdict

CHECK_CEILING = "--check-ceiling" in sys.argv
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
    "scripts/GameState.gd": 27,
    # TurnConductor.gd legitimately depends on every phase resolver it orchestrates (IjfsResolver,
    # SealiftResolver, AntishipResolver, OffloadResolver, InfrastructureResolver, SupplyResolver,
    # CleanupResolver, FrontlineResolver, CombatResolver, …) — that is cohesion, not lamination.
    # Ceiling here catches it acquiring UNRELATED responsibilities (the god-object failure mode),
    # not the resolver fan-out that is its actual job. Measured 32 at commit time.
    "scripts/resolvers/TurnConductor.gd": 36,
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
            params = m.group(4)
            nparams = 0 if params.strip().startswith(")") else params.count(",") + 1
            cur = {"file": rel, "name": m.group(3), "start": i+1, "indent": indent,
                   "cc": 1, "params": nparams, "returns": 0, "match_arms": 0}
        elif cur is not None:
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
    if breaches:
        print("FAIL: dependency ceiling breach(es):")
        for b in breaches:
            print("  -", b)
        sys.exit(1)
    print("PASS: dependency ceilings OK (%d file(s) checked)" % len(DEP_CEILINGS))
