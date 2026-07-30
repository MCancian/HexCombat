class_name IjfsTransitions
extends RefCounted

## THE mutation authority for persistent IJFS campaign state (plan 0046) — the exact and only
## production writer of `IjfsTarget` / `IjfsMunition` / `IjfsSquadron`, of the three containers
## `IjfsDailyState` carries across days, and of the IJFS handles `GameStateData` hosts. Living in
## scripts/transitions/ grants nothing by itself: authority is granted to this exact file by name in
## tools/mutation_authority_manifest.json, which is also the only home for the field and writer
## lists. Do not copy them here.
##
## WHY THIS ONE LOOKS DIFFERENT FROM AntishipTransitions. There, a calculator returns a typed outcome
## and the phase coordinator hands it over — one call per phase, at the end. IJFS cannot work that
## way: its six stages consume dice CONDITIONALLY on state an earlier stage just wrote, and later
## target selection reads that state (IjfsTargeting.targets_to_attack filters on `destroyed` and
## `detected_this_turn`; IjfsManpads sorts on ready stock). Deferring application to end-of-day would
## change which targets are iterated and therefore how many draws are consumed — the one thing this
## plan may not do. So the stages call in here at the exact point they used to assign, and what the
## authority buys is a named, checked, single-file boundary rather than a deferred one.
##
## Guards `push_error` and change nothing rather than `assert(false)`: a research batch should not die
## on one bad row, and a guard that only push_errors can be exercised by a test
## (`assert_error(...).is_push_error(...)`), which is how tests/transitions/ijfs_transitions_test.gd
## pins each of them.


# ── Munition inventory ──────────────────────────────────────────────────────────────────────────

## Spend `rounds` from a munition, or refuse. Returns false when the magazine cannot cover the
## engagement, which is NORMAL — it is how a strike is skipped, not an error.
##
## Both callers reach here at their existing point: IjfsStrike for a delivered strike, and IjfsEngine
## for a round MANPADS intercepted (spent, delivers nothing). Organic munitions never come here —
## strike aircraft draw from a sortie budget, not a magazine.
##
## Insufficiency is unreachable through the engine today, because selection already refuses an
## unaffordable pairing (IjfsTargeting._rule_affordable) and nothing decrements between selection and
## here. It is still checked and still tested directly: the day a selection path stops checking, this
## is what stands between that and a negative magazine.
static func consume_munition(munition: IjfsMunition, rounds: int) -> bool:
	if munition == null:
		push_error("IjfsTransitions: consume_munition called with no munition")
		return false
	if rounds < 0:
		push_error("IjfsTransitions: refusing a negative consumption of %d rounds of %s" % [
			rounds, munition.munition_id])
		return false
	if munition.inventory_remaining < rounds:
		return false
	munition.inventory_remaining -= rounds
	return true
