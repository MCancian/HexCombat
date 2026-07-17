class_name BatchReport
extends RefCounted

## Pure aggregation + Markdown rendering for batch outcome reports (research harness B3).
## Input: the per-game record dicts written by tools/run_selfplay_game.gd. No autoload/file/OS
## access — the tools/make_batch_report.gd wrapper does the reading/writing. "A result is a
## distribution" (hexcombat-research-runs): everything reports per condition
## (scenario_id × red policy × green policy) across the seed set.


## records: Array of per-game record Dictionaries. Returns condition_key -> aggregate Dictionary;
## condition_key is "<scenario_id>|<red_policy_id>|<green_policy_id>".
static func aggregate(records: Array) -> Dictionary:
	var conditions: Dictionary = {}
	for record_value in records:
		var record: Dictionary = record_value
		var agg: Dictionary = _condition_for(conditions, record)
		_append_record(agg, record)
	return conditions


static func _condition_for(conditions: Dictionary, record: Dictionary) -> Dictionary:
	var policies := _policy_ids(record)
	var scenario_id := String(record.get("scenario_id", "?"))
	var key := "%s|%s|%s" % [scenario_id, policies["red"], policies["green"]]
	if not conditions.has(key):
		conditions[key] = {
			"scenario_id": scenario_id,
			"red_policy_id": policies["red"],
			"green_policy_id": policies["green"],
			"n": 0,
			"seeds": [],
			"commits": {},
			"red_wins": 0, "green_wins": 0, "undecided": 0,
			"turns_played": [],
			"census_red": [], "census_green": [], "census_margin": [],
			"red_bn_combat_losses": [], "green_bn_combat_losses": [],
			"ships_destroyed": [], "bns_lost_at_sea": [],
		}
	return conditions[key]


static func _append_record(agg: Dictionary, record: Dictionary) -> void:
	agg["n"] += 1
	(agg["seeds"] as Array).append(int(record.get("base_seed", 0)))
	agg["commits"][String(record.get("commit", ""))] = true
	if bool(record.get("game_over", false)):
		match String(record.get("winner", "")):
			"red": agg["red_wins"] += 1
			"green": agg["green_wins"] += 1
			_: agg["undecided"] += 1
	else:
		agg["undecided"] += 1
	(agg["turns_played"] as Array).append(int(record.get("turns_played", 0)))
	var census: Dictionary = record.get("census", {})
	var red_census := int(census.get("red", 0))
	var green_census := int(census.get("green", 0))
	(agg["census_red"] as Array).append(red_census)
	(agg["census_green"] as Array).append(green_census)
	(agg["census_margin"] as Array).append(red_census - green_census)
	var totals := _sum_digest_losses(record.get("turn_digests", []))
	(agg["red_bn_combat_losses"] as Array).append(totals["red_bn"])
	(agg["green_bn_combat_losses"] as Array).append(totals["green_bn"])
	(agg["ships_destroyed"] as Array).append(totals["ships"])
	(agg["bns_lost_at_sea"] as Array).append(totals["lost_at_sea"])


## Version-1 records used one policy for both sides. Preserve their report compatibility.
static func _policy_ids(record: Dictionary) -> Dictionary:
	var legacy_policy := String(record.get("policy_id", "?"))
	return {
		"red": String(record.get("red_policy_id", legacy_policy)),
		"green": String(record.get("green_policy_id", legacy_policy)),
	}


## Sum per-game loss totals out of the turn digests. Red is always the attacker in ground
## combat (amphibious assault), so attacker_losses accrue to Red and defender_losses to Green.
static func _sum_digest_losses(turn_digests: Array) -> Dictionary:
	var red_bn := 0
	var green_bn := 0
	var ships := 0
	var lost_at_sea := 0
	for digest_value in turn_digests:
		var digest: Dictionary = digest_value
		for combat_value in digest.get("combat_summaries", []):
			var combat: Dictionary = combat_value
			red_bn += int(combat.get("attacker_losses", 0))
			green_bn += int(combat.get("defender_losses", 0))
		var antiship: Dictionary = digest.get("antiship_summary", {})
		for ship_type in antiship.get("destroyed_by_ship_type", {}):
			ships += int(antiship["destroyed_by_ship_type"][ship_type])
		lost_at_sea += int(antiship.get("bns_lost_at_sea", 0))
	return {"red_bn": red_bn, "green_bn": green_bn, "ships": ships, "lost_at_sea": lost_at_sea}


## Render the aggregate as the Markdown report shape from hexcombat-research-runs.
## manifest: the batch manifest dict (may be {} — fields degrade gracefully).
static func render_markdown(conditions: Dictionary, manifest: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("# Batch report — %s" % String(manifest.get("batch_name", "(unnamed)")))
	lines.append("")
	var commits := {}
	for key in conditions:
		for c in (conditions[key]["commits"] as Dictionary):
			commits[c] = true
	var commit_list := commits.keys()
	commit_list.sort()
	lines.append("**Methods.** commit `%s`%s; %d game record(s); turns cap %s; created %s." % [
		"`, `".join(PackedStringArray(commit_list)),
		" (WARNING: mixed commits!)" if commit_list.size() > 1 else "",
		int(manifest.get("games_total", _total_n(conditions))),
		str(int(manifest["turns"])) if manifest.get("turns") is float else str(manifest.get("turns", "?")),
		String(manifest.get("created_utc", "?")),
	])
	if bool(manifest.get("dirty", false)):
		lines.append("")
		lines.append("> **WARNING:** batch ran on a dirty working tree — not exactly reproducible from the commit.")
	lines.append("")
	lines.append("## Outcomes by condition")
	lines.append("")
	lines.append("| Scenario | Red policy | Green policy | N | Red wins | Green wins | Undecided | Turns (med/min–max) | Census R:G (mean) | Margin (med) |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|")
	var keys := conditions.keys()
	keys.sort()
	for key in keys:
		var agg: Dictionary = conditions[key]
		var n := int(agg["n"])
		lines.append("| %s | %s | %s | %d | %d (%d%%) | %d (%d%%) | %d | %s / %s–%s | %.1f : %.1f | %+.1f |" % [
			agg["scenario_id"], agg["red_policy_id"], agg["green_policy_id"], n,
			agg["red_wins"], _pct(agg["red_wins"], n),
			agg["green_wins"], _pct(agg["green_wins"], n),
			agg["undecided"],
			_fmt(median(agg["turns_played"])), str(_min(agg["turns_played"])), str(_max(agg["turns_played"])),
			mean(agg["census_red"]), mean(agg["census_green"]),
			median(agg["census_margin"]),
		])
	lines.append("")
	lines.append("## Losses by condition (per-game means)")
	lines.append("")
	lines.append("| Scenario | Red policy | Green policy | Red BN (ground) | Green BN (ground) | Ships destroyed | BNs lost at sea |")
	lines.append("|---|---|---|---|---|---|---|")
	for key in keys:
		var agg: Dictionary = conditions[key]
		lines.append("| %s | %s | %s | %.1f | %.1f | %.1f | %.1f |" % [
			agg["scenario_id"], agg["red_policy_id"], agg["green_policy_id"],
			mean(agg["red_bn_combat_losses"]), mean(agg["green_bn_combat_losses"]),
			mean(agg["ships_destroyed"]), mean(agg["bns_lost_at_sea"]),
		])
	lines.append("")
	lines.append("## Caveats")
	lines.append("")
	lines.append("- Outcomes are statements about scenario × **policy matchup** pairs, not the invasion per se —")
	lines.append("  compare policies under identical conditions before attributing anything to the scenario.")
	if _has_llm_seat(conditions):
		lines.append("- `llm_local` seats are not seed-reproducible; their JSONL replay logs are the replay artifacts.")
	lines.append("- Model limits: no terrain effects; secondary-use divergences — see `docs/systems/` fidelity notes.")
	lines.append("- Green ground losses count combat defender losses only (IJFS strikes on maneuver units are")
	lines.append("  reflected in the terminal census, not in the ground-loss column).")
	lines.append("")
	return "\n".join(lines)


static func _has_llm_seat(conditions: Dictionary) -> bool:
	for key in conditions:
		var condition: Dictionary = conditions[key]
		if condition["red_policy_id"] == "llm_local" or condition["green_policy_id"] == "llm_local":
			return true
	return false


static func mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / values.size()


static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) / 2.0


static func _min(values: Array) -> Variant:
	return 0 if values.is_empty() else values.min()


static func _max(values: Array) -> Variant:
	return 0 if values.is_empty() else values.max()


static func _pct(count: int, n: int) -> int:
	return 0 if n == 0 else int(round(100.0 * count / n))


static func _fmt(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


static func _total_n(conditions: Dictionary) -> int:
	var total := 0
	for key in conditions:
		total += int(conditions[key]["n"])
	return total
