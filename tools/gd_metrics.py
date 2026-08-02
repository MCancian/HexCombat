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
    # OffloadResolver, InfrastructureResolver, CleanupResolver, FrontlineResolver, CombatResolver, …)
    # — that is cohesion, not lamination. (Historically this list also named SealiftResolver,
    # AntishipResolver and SupplyResolver; the first two moved to scripts/calc/ and SupplyResolver was
    # dissolved in 0049, and most of the fan-out now reaches TurnConductor through the phase modules.)
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
    # 15 -> 13 (plan 0050): the slack 0052 left was never spent, so the closeout takes it back to the
    # measured value. The crossing-ledger writes this file gave up went to SealiftTransitions, which
    # it already depended on, so nothing was traded for it — it is headroom being locked in rather
    # than left available to the next mechanic.
    "scripts/phases/FiresPhases.gd": 13,
    # TurnClosure.gd (plan 0038 step 3): the end-of-turn accounting pair (supply bills who fought,
    # cleanup censuses who is left). Measured 7 at commit time.
    # 7 -> 9 (plan 0055): the cleanup phase's two applications — the anti-ship transient-flag reset
    # and the roster-wide activity latch — moved OUT of CleanupResolver, which is now pure and lives
    # in calc/. This is the ceiling doing its job rather than being evaded: the two new deps are
    # AntishipTransitions and ForceTransitions, i.e. the phase owner acquiring the authority calls
    # that are precisely what scripts/phases/ exists to hold. The raw hoist measured 11; hosting the
    # latch loop inside ForceTransitions as a batch (plan 0048's pattern) kept `Brigade` and
    # `ForceActivityRequest` off this budget. Bumped to the value that buys the purity, not to the
    # value the first attempt happened to produce.
    "scripts/phases/TurnClosure.gd": 9,
    # ---- Seeded 2026-08-01 (plan 0056), at each file's MEASURED value ----------------------
    # These eleven entries were generated, not hand-written: before this plan the dependency budget
    # was enforced only where someone had opted in, so every file below was unbounded. Seeding at the
    # measured value converts "unbounded" into "cannot grow", which is the whole change — it forgives
    # nothing and asks for no reduction. The ratchet rule in this header applies to them from now on:
    # lower them after a refactor, never raise one to silence a breach.
    #
    # None carries a rationale yet, deliberately. The per-file prose above was written by whoever had
    # cause to move that ceiling and therefore knew why its coupling was legitimate; inventing that
    # reasoning at seeding time would be fabrication. Write it when you first need to move one.
    #
    # ForceTransitions at 30 is the number worth arguing about: it is the most-connected file in the
    # repo and, unlike the orchestrators above, an authority whose whole design purpose is to own ONE
    # aggregate narrowly. Plan 0056 deliberately does not reduce it — that is a refactor with its own
    # risk, and this plan only stops it growing further.
    "scripts/transitions/ForceTransitions.gd": 30,
    "scripts/GameData.gd": 25,
    "scripts/api/LLMGameAPI.gd": 22,
    "scripts/interleaved/IjfsEngine.gd": 14,
    "scripts/model/GameStateData.gd": 14,
    "scripts/calc/OrderValidator.gd": 12,
    "scripts/interleaved/IjfsResolver.gd": 12,
    "scripts/calc/AntishipResolver.gd": 11,
    # 11 -> 8 (plan 0060): four preload consts named the same model classes their `class_name`
    # already makes global, so deleting them cost nothing and freed three slots that the plan then
    # spent on IjfsAttritionProfile. LOWERED, so the slack cannot be silently re-spent.
    "scripts/loaders/IjfsLoaders.gd": 8,
    "scripts/calc/ForceValidationHelper.gd": 10,
    "scripts/ui/HexMap.gd": 10,
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
    "scripts/interleaved/JlsfCargo.gd::queue_deployments": 7,
    "scripts/api/LLMGameAPI.gd::_action_result": 6,
    "scripts/OffloadCalculator.gd::_resolve_day_n": 10,
    "scripts/OffloadCalculator.gd::resolve_offload_day": 9,
    "scripts/builders/SealiftStateBuilder.gd::build": 6,
    "scripts/calc/AntishipCalculator.gd::build_firing_plan": 6,
    "scripts/calc/AntishipCrossing.gd::_apply_homing": 6,
    "scripts/calc/AntishipCrossing.gd::_apply_interception": 6,
    "scripts/calc/AntishipCrossing.gd::_resolve_damage": 6,
    "scripts/calc/MineWarfareService.gd::_apply_beach_outcome": 7,
    "scripts/calc/MineWarfareService.gd::_beach_result": 8,
    "scripts/calc/MineWarfareService.gd::_count_dangerous_mines": 9,
    "scripts/calc/MineWarfareService.gd::resolve_ship_losses": 7,
    "scripts/interleaved/IjfsDetection.gd::_log_detection": 7,
    "scripts/interleaved/IjfsDetection.gd::_run_detection_phase": 8,
    "scripts/interleaved/IjfsDetection.gd::aircraft_detect_target_ids": 7,
    "scripts/interleaved/IjfsEngagement.gd::resolve_sead_engagement": 6,
    # 9 -> 6 (plan 0060): the day/phase/doctrine/survivor-fraction arguments collapsed into the
    # typed IjfsStrikeContext, so the package geometry landed WITHOUT a tenth parameter.
    "scripts/interleaved/IjfsStrike.gd::resolve_strike": 6,
    "scripts/interleaved/IjfsTargeting.gd::apply_exquisite_intel": 6,
    "scripts/interleaved/IjfsTargeting.gd::select_munition_with_doctrine": 8,
    "scripts/calc/AirInsertionResolver.gd::resolve": 7,
    "scripts/calc/CleanupResolver.gd::resolve": 6,
    "scripts/interleaved/IjfsResolver.gd::build_warmup_context": 8,
    "scripts/calc/OffloadResolver.gd::resolve": 8,
    "tests/batch_report_test.gd::_legacy_record": 7,
    "tests/batch_report_test.gd::_record": 8,
    "tests/ijfs/ijfs_loaders_test.gd::_container": 6,
    "tests/ijfs/ijfs_targeting_test.gd::_pairing": 8,
    "tests/ijfs/ijfs_targeting_test.gd::_target": 7,
    "tools/run_selfplay_game.gd::_build_record": 9,
    "tools/validate_mutation_authority.gd::_protected_finding": 6,
}

# Dependency budget scope (plan 0056). The budget itself is NOT new: hexcombat-code-quality has
# declared "File class references (preload/class_name/autoload) | <= 8 | 10" since it was written.
# What was opt-in was its ENFORCEMENT — a file's ndeps was checked only if someone remembered to add a
# DEP_CEILINGS entry, which covered 5 files out of 167. DEP_THRESHOLD makes the gate agree with the
# stated hard cap: at or above it, a scripts/ file MUST carry a ceiling or the gate fails.
#
# Scope is scripts/ only, deliberately. tests/ legitimately names many classes to build fixtures (the
# top test file is at 19) and capping that discourages thorough tests for no architectural gain;
# tools/ is validators and one-shot scripts. Neither is a place where architecture is claimed.
# PARAM_CEILINGS keeps its own, WIDER scope — it grandfathers tests/ and tools/ entries above, and
# must not be "tidied" to match this one.
DEP_THRESHOLD = 10
DEP_SCOPE_PREFIX = "scripts/"


def dep_ceiling_breaches(files_by_rel, ceilings, threshold=DEP_THRESHOLD, scope=DEP_SCOPE_PREFIX):
    """Dependency-budget verdict. Pure: takes the measurements and the table as ARGUMENTS.

    Explicit arguments rather than the module globals so a fixture can exercise this against a
    temporary tree without inheriting the production table (every real entry would then report stale
    against a fixture tree) and without editing the live tool.

    Two directions, and the second is the one plan 0056 adds:
      1. a LISTED file that is gone, or has grown past its entry, fails;
      2. an UNLISTED file in scope at or above `threshold` fails — the opt-out this closes.
    """
    breaches = []
    for rel, ceiling in sorted(ceilings.items()):
        info = files_by_rel.get(rel)
        if info is None:
            breaches.append("%s: not found (ceiling entry stale — file moved/deleted?)" % rel)
            continue
        if info["ndeps"] > ceiling:
            breaches.append("%s: ndeps=%d exceeds ceiling %d" % (rel, info["ndeps"], ceiling))
    for rel, info in sorted(files_by_rel.items()):
        if not rel.startswith(scope) or rel in ceilings:
            continue
        if info["ndeps"] >= threshold:
            breaches.append(
                "%s: ndeps=%d is at/above the dependency threshold %d with NO ceiling entry. "
                "Reduce the coupling, or add an entry at the measured value with a comment saying why "
                "it is legitimate (see the DEP_CEILINGS header)." % (rel, info["ndeps"], threshold))
    return breaches


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

def to_posix(path, sep=os.sep):
    """Separator normalization, split out from rel_path so it is testable on a POSIX box.

    `sep` is injectable for exactly one reason: on Linux `os.sep` is already "/", so a test that
    round-trips a natively-joined path proves nothing — delete the replace and it still passes. Passing
    sep="\\" lets the Linux gate prove the Windows behaviour. (Diff-review finding, 2026-08-01.)
    """
    return path.replace(sep, "/")


def rel_path(path, root=None):
    """Path relative to ROOT, ALWAYS with forward slashes.

    Every key this tool emits — result["files"], fn["file"], result["classnames"] — and every key the
    ceiling tables are written with is forward-slash. `os.path.relpath` returns the OS separator, so on
    Windows an unnormalized key is "scripts\\GameState.gd" and no ceiling lookup can ever match it:
    all five entries would report "stale (file moved/deleted?)" and --check-ceiling would fail for a
    reason that has nothing to do with the code. Normalize once, here, at the only two places a
    relative path is produced. `_self_test_path_wiring` asserts those are still the only two.
    """
    return to_posix(os.path.relpath(path, ROOT if root is None else root))


def gd_files(root=None):
    root = ROOT if root is None else root
    for dp, dns, fns in os.walk(root):
        # Prune ONLY at the top level. `dns[:] = ...` at every depth meant any nested directory that
        # happened to be named "addons"/".godot"/".git" was pruned too, so scripts/addons/foo.gd was
        # invisible to this tool entirely — no metrics, and silently exempt from the dependency budget
        # that claims to cover all of scripts/. These three are project-root artifacts; nothing nested
        # should match them. (Diff-review finding, 2026-08-01, reproduced before fixing.)
        if os.path.abspath(dp) == os.path.abspath(root):
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


def _self_test_dependency_budget():
    """Prove the dependency budget fires in BOTH directions.

    Fixture measurements only — no real file is read and the production table is never consulted,
    which is why `dep_ceiling_breaches` takes its inputs as arguments. Case 2 is the point: a test
    that only shows "the current table passes" would still pass if the new branch did nothing at all.

    (Plan 0056 also had three cases covering the one-shot `--seed-ceilings` generator. They were
    removed with it — a permanent seeder is an opt-out for every future high-coupling file. Its
    ADD-ONLY and comment-preserving behaviour was watched to hold against the real table before
    removal; the generator and those tests are recoverable from this plan's history if a future
    baseline ever needs reseeding.)
    """
    def _files(**kw):
        return {rel: {"ndeps": n} for rel, n in kw.items()}

    # 1. a seeded table passes, and out-of-scope files are ignored however coupled they are.
    measured = {"scripts/a.gd": {"ndeps": 12}, "tests/big_test.gd": {"ndeps": 40},
                "tools/t.gd": {"ndeps": 30}, "scripts/small.gd": {"ndeps": 3}}
    if dep_ceiling_breaches(measured, {"scripts/a.gd": 12}):
        raise AssertionError("seeded table should pass: %s" % dep_ceiling_breaches(measured, {"scripts/a.gd": 12}))

    # 2. THE WHOLE FEATURE: an UNLISTED in-scope file at the threshold fails.
    #    LITERAL 10 and 9, not DEP_THRESHOLD +/- 1. A fixture that derives its expectation from the
    #    constant under test moves with it, so changing the policy to 11 would pass unchanged — the
    #    self-test-reads-its-own-table failure this repo has hit before. The pin is the assertion.
    if DEP_THRESHOLD != 10:
        raise AssertionError(
            "DEP_THRESHOLD is %d, but hexcombat-code-quality declares a hard cap of 10 for file class "
            "references. Change both together and update the literals below, deliberately."
            % DEP_THRESHOLD)
    hits = dep_ceiling_breaches(_files(**{"scripts/new.gd": 10}), {})
    if len(hits) != 1 or "NO ceiling entry" not in hits[0]:
        raise AssertionError("unlisted file at 10 must fail: %r" % hits)
    if dep_ceiling_breaches(_files(**{"scripts/new.gd": 9}), {}):
        raise AssertionError("a file at 9 must NOT require an entry")

    # 3. a listed file grown past its entry still fails — the pre-existing direction, kept because
    #    seeding eleven files made it cover eleven more, and a regression here would be silent.
    grown = {"scripts/a.gd": {"ndeps": 14}}
    hits = dep_ceiling_breaches(grown, {"scripts/a.gd": 12})
    if len(hits) != 1 or "exceeds ceiling" not in hits[0]:
        raise AssertionError("growth past a ceiling must fail: %r" % hits)

    # 4. a listed file that has VANISHED is reported stale rather than passing quietly.
    hits = dep_ceiling_breaches({}, {"scripts/gone.gd": 12})
    if len(hits) != 1 or "stale" not in hits[0]:
        raise AssertionError("a ceiling entry whose file is gone must fail: %r" % hits)

    # 5. path keys are forward-slash on EVERY platform. Feed a Windows-shaped path with an explicit
    #    separator: on Linux os.sep is already "/", so joining natively and round-tripping would pass
    #    even with the normalization deleted. This case fails here if it is.
    if to_posix("scripts\\builders\\a.gd", "\\") != "scripts/builders/a.gd":
        raise AssertionError("to_posix must normalize the Windows separator")
    if rel_path(os.path.join("root", "scripts", "a.gd"), "root") != "scripts/a.gd":
        raise AssertionError("rel_path must produce a forward-slash relative key")


def _self_test_walker_scope():
    """A nested directory named like a project-root artifact must NOT be pruned.

    `dns[:] = [...]` applied at every depth silently excluded scripts/addons/ from the tool entirely —
    no metrics and, worse, exemption from the dependency budget that claims to cover all of scripts/.
    Reproduced before it was fixed: a probe file there left the file count unchanged at 305 and its key
    absent from the JSON. Root-level addons/ (GdUnit4) and .godot/ must still be skipped.
    (Diff-review finding, 2026-08-01.)
    """
    import shutil, tempfile
    tmp = tempfile.mkdtemp(prefix="gd_metrics_walker_")
    try:
        for rel in ("addons/root_addon.gd", ".godot/cache.gd",
                    "scripts/addons/nested_addon.gd", "scripts/plain.gd"):
            full = os.path.join(tmp, *rel.split("/"))
            os.makedirs(os.path.dirname(full), exist_ok=True)
            open(full, "w", encoding="utf-8").write("extends RefCounted\n")
        found = sorted(rel_path(p, tmp) for p in gd_files(tmp))
        expected = ["scripts/addons/nested_addon.gd", "scripts/plain.gd"]
        if found != expected:
            raise AssertionError("walker scope wrong: expected %r, found %r" % (expected, found))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _self_test_path_wiring():
    """Assert the normalization is still WIRED IN, not merely present.

    Cases above prove `to_posix`/`rel_path` behave. They cannot see the failure that actually matters:
    someone reverting a call site to a bare relpath call, which on Linux is indistinguishable and on
    Windows silently un-keys every ceiling. So derive the check from this file's own source — the
    technique this repo already uses for combat-knob threading and tool-script purity — and require
    that the only such call lives inside `rel_path` itself.
    (Diff-review finding, 2026-08-01: "which realistic regression would still pass these tests?")

    The needle is assembled from fragments on purpose: written literally, this function's own lines
    would match it and the check would fail against itself. That is not cleverness for its own sake —
    it is the reason the first version of this test could not pass.
    """
    needle = "os.path." + "relpath("
    src = open(os.path.abspath(__file__), encoding="utf-8").read()
    hits = [ln.strip() for ln in src.splitlines()
            if needle in ln and not ln.strip().startswith("#")]
    expected = ["return to_posix(%spath, ROOT if root is None else root))" % needle]
    if hits != expected:
        raise AssertionError(
            "the relpath call must appear ONLY inside rel_path(); every emitted key has to go "
            "through the separator normalization. Expected %r, found %r" % (expected, hits))


if SELF_TEST or CHECK_CEILING:
    _self_test_signature_params()
    _self_test_dependency_budget()
    _self_test_walker_scope()
    _self_test_path_wiring()

norm_windows = defaultdict(list)  # hash -> [(file, startline)]
W = 6

for f in files:
    rel = rel_path(f)
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
result["classnames"] = {k: rel_path(v) for k, v in classnames.items()}
result["autoloads"] = sorted(AUTOLOADS)

if OUT_PATH:
    json.dump(result, open(OUT_PATH, "w"), indent=1)
print("files", len(files), "funcs", len(result["functions"]),
      "dup_windows", result["dup"]["n_dup_windows"],
      "total_dup_lines", result["dup"]["total_dup_lines"])

if CHECK_CEILING:
    breaches = dep_ceiling_breaches(result["files"], DEP_CEILINGS)

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
    # The "PASS: metric ceilings OK" prefix is asserted verbatim by tools/validate_gd_metrics.py, which
    # is how this check reaches the gate. Counts inside the parentheses may change freely; the prefix
    # may not — rewording it turns the gate red in a file nobody edited.
    _in_scope = sum(1 for r in result["files"] if r.startswith(DEP_SCOPE_PREFIX))
    print("PASS: metric ceilings OK (%d file(s), %d function(s) checked; "
          "dependency budget enforced over %d file(s) in %s at threshold %d)" % (
              len(DEP_CEILINGS), len(PARAM_CEILINGS), _in_scope, DEP_SCOPE_PREFIX, DEP_THRESHOLD))
