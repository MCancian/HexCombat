class_name GameNarrative
extends RefCounted

## Pure Markdown narrative renderer (research harness B4): one per-game record (as written by
## tools/run_selfplay_game.gd) → a readable turn-by-turn account of WHY that game went the way
## it did, rendered from the per-turn digests ("narratives explain, statistics conclude" —
## hexcombat-research-runs). Written for a wargaming researcher, not a programmer. No
## autoload/file/OS access; tools/make_game_narrative.gd does the I/O and game selection.


static func render(record: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("# Game narrative — %s" % String(record.get("scenario_name", record.get("scenario_id", "?"))))
	lines.append("")
	lines.append("**Identity.** scenario `%s`, policy `%s`, seed %d, commit `%s`." % [
		String(record.get("scenario_id", "?")), String(record.get("policy_id", "?")),
		int(record.get("base_seed", 0)), String(record.get("commit", "?")),
	])
	lines.append("")
	var digests: Array = record.get("turn_digests", [])
	for digest_value in digests:
		_render_turn(lines, digest_value)
	lines.append("## Outcome")
	lines.append("")
	var census: Dictionary = record.get("census", {})
	if bool(record.get("game_over", false)):
		lines.append("**%s wins** after %d turn(s)%s — terminal census %d PLA : %d ROC battalions on Taiwan." % [
			"Red" if String(record.get("winner", "")) == "red" else "Green",
			digests.size(),
			" (%s)" % String(record.get("victory_reason", "")) if String(record.get("victory_reason", "")) != "" else "",
			int(census.get("red", 0)), int(census.get("green", 0)),
		])
	else:
		lines.append("Undecided at the %d-turn cap — census %d PLA : %d ROC battalions on Taiwan." % [
			int(record.get("turns_requested", digests.size())), int(census.get("red", 0)), int(census.get("green", 0)),
		])
	lines.append("")
	return "\n".join(lines)


static func _render_turn(lines: Array[String], digest: Dictionary) -> void:
	lines.append("## Turn %d" % int(digest.get("turn_number", 0)))
	lines.append("")
	# move/commit events are buffered and flushed before the first combat/frontline/cleanup
	# event so the narrative reads chronologically (orders execute before combat resolves).
	var moves: Array[String] = []
	var commits: Array[String] = []
	for event_value in digest.get("events", []):
		var event: Dictionary = event_value
		var data: Dictionary = event.get("data", {})
		match String(event.get("kind", "")):
			"ijfs":
				_render_ijfs(lines, data)
			"antiship":
				_render_antiship(lines, data)
			"move":
				moves.append("%s moves %s to %s" % [String(event.get("team", "")), String(data.get("brigade_id", "?")), String(data.get("target_hex", "?"))])
			"commit":
				commits.append("%s commits %s into the fight at %s" % [String(event.get("team", "")), String(data.get("brigade_id", "?")), String(data.get("target_hex", "?"))])
			"combat":
				_flush_orders(lines, moves, commits)
				_render_combat(lines, data)
			"frontline":
				_flush_orders(lines, moves, commits)
				if int(data.get("moved_brigades", 0)) > 0:
					lines.append("- **Front line** redrawn: %d brigade(s) redistributed." % int(data.get("moved_brigades", 0)))
			"cleanup":
				_flush_orders(lines, moves, commits)
				lines.append("- **End of turn**: census %d PLA : %d ROC battalions on Taiwan%s." % [
					int(data.get("china_battalions_on_taiwan", 0)), int(data.get("taiwan_battalions_on_taiwan", 0)),
					"; **game over — %s wins** (%s)" % [String(data.get("winner", "")), String(data.get("victory_reason", ""))] if bool(data.get("game_over", false)) else "",
				])
	_flush_orders(lines, moves, commits)
	lines.append("")


static func _flush_orders(lines: Array[String], moves: Array[String], commits: Array[String]) -> void:
	if not moves.is_empty():
		lines.append("- **Maneuver**: " + "; ".join(moves) + ".")
		moves.clear()
	if not commits.is_empty():
		lines.append("- **Commitments**: " + "; ".join(commits) + ".")
		commits.clear()


static func _render_ijfs(lines: Array[String], data: Dictionary) -> void:
	var attacks: Dictionary = data.get("attacks", {})
	var destroyed: Dictionary = data.get("destroyed_targets_by_category", {})
	var destroyed_bits: Array[String] = []
	var keys := destroyed.keys()
	keys.sort()
	for category in keys:
		destroyed_bits.append("%d %s" % [int(destroyed[category]), String(category)])
	var before: Dictionary = data.get("taiwan_ad_health_before", {})
	var after: Dictionary = data.get("taiwan_ad_health_after", {})
	var manpads: Dictionary = data.get("manpads", {})
	var manpads_bit := ""
	var interceptions := int(manpads.get("interceptions", 0))
	var air_losses := int(data.get("red_air_losses", 0))
	if interceptions > 0 or air_losses > 0:
		var pieces: Array[String] = []
		if air_losses > 0:
			# All channels: SEAD return fire + SAM free shot + MANPADS contest.
			pieces.append("%d Red aircraft lost to air defenses" % air_losses)
		if interceptions > 0:
			pieces.append("%d strike(s) intercepted by MANPADS" % interceptions)
		manpads_bit = " %s (%d MANPADS ready)." % [
			"; ".join(pieces), int(manpads.get("ready_systems_by_to", {}).get("total", 0))]
	lines.append("- **Red joint fires (IJFS)**: %d strike(s) executed (%d skipped)%s.%s%s" % [
		int(attacks.get("executed", 0)), int(attacks.get("skipped", 0)),
		", destroying " + ", ".join(destroyed_bits) if not destroyed_bits.is_empty() else "",
		" Taiwan integrated air defense degraded %d%% → %d%% effective." % [
			int(round(100.0 * float(before.get("effective_ad_health", 0.0)))),
			int(round(100.0 * float(after.get("effective_ad_health", 0.0)))),
		] if not before.is_empty() else "",
		manpads_bit,
	])


static func _render_antiship(lines: Array[String], data: Dictionary) -> void:
	var sent: Dictionary = data.get("sent_by_type", {})
	var sent_total := 0
	for ship_type in sent:
		sent_total += int(sent[ship_type])
	var destroyed: Dictionary = data.get("destroyed_by_ship_type", {})
	var destroyed_total := 0
	for ship_type in destroyed:
		destroyed_total += int(destroyed[ship_type])
	var beaches: Array[String] = []
	for beach_value in data.get("target_beaches", []):
		beaches.append(str(int(beach_value)))
	lines.append("- **The crossing**: %d ship(s) sail%s; ROC shore fire + mines destroy %d, costing Red %d battalion(s) lost at sea (%d anti-ship system(s) fired)." % [
		sent_total,
		" for beaches %s" % ", ".join(beaches) if not beaches.is_empty() else "",
		destroyed_total,
		int(data.get("bns_lost_at_sea", 0)),
		int(data.get("systems_fired_count", 0)),
	])


static func _render_combat(lines: Array[String], data: Dictionary) -> void:
	var feba := float(data.get("feba_movement_km", 0.0))
	var feba_text := "the line holds"
	if feba > 0.0:
		feba_text = "Red pushes the FEBA %.2f km inland" % feba
	elif feba < 0.0:
		feba_text = "Green pushes the FEBA %.2f km back toward the beach" % absf(feba)
	lines.append("- **Ground combat at %s** (%s vs %s): Red loses %d battalion(s), Green %d; %s; hex ends %s." % [
		String(data.get("hex_id", "?")),
		", ".join(PackedStringArray(data.get("attacker_brigade_ids", []))),
		", ".join(PackedStringArray(data.get("defender_brigade_ids", []))),
		int(data.get("attacker_losses", 0)), int(data.get("defender_losses", 0)),
		feba_text, String(data.get("owner_after", "?")),
	])
