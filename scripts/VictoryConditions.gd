extends RefCounted
class_name VictoryConditions


static func evaluate(china_bn: int, taiwan_bn: int, arm: String, turn_number: int, china_has_landed: bool) -> Dictionary:
	# 1. Win: China has strict majority
	if china_bn > taiwan_bn:
		return {"game_over": true, "winner": "red", "reason": "china_majority"}

	# 2. Compute armed status
	var armed: bool
	if arm == "unconditional":
		armed = true
	elif arm == "after_first_landing":
		armed = china_has_landed
	elif arm.begins_with("after_turn:"):
		var parts := arm.split(":")
		if parts.size() == 2:
			var threshold := int(parts[1])
			armed = turn_number > threshold
		else:
			armed = true
	else:
		armed = true

	if armed and china_bn == 0:
		return {"game_over": true, "winner": "green", "reason": "china_eliminated"}

	return {"game_over": false, "winner": "", "reason": ""}
