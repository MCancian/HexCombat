class_name AntishipLaunchOutcome
extends Resource

## What one crossing's launch attrition DID to one (TO, type) row — the typed receipt
## AntishipCalculator returns and AntishipTransitions applies (plan 0043). It is a report, not
## state: the calculator never touches an AntishipSystem, and nothing but the authority turns these
## numbers into losses.
##
## Identity is (to_number, type_id), which is exactly how AntishipLoaders aggregates the rows, so the
## authority resolves the target row by key and fails loudly on one it does not recognise.
##
## attempted            launchers ordered to fire this crossing
## launched             of those, the ones that got a missile away (survivors + post-launch kills)
## prelaunch_destroyed  killed before the missile left the rail — no missile away
## postlaunch_destroyed killed after the missile left the rail — missile still counts
##
## Attempting to fire does not by itself consume a launcher; only the two destruction counts reduce
## the surviving establishment.

@export var to_number: int = 0
@export var type_id: int = 0
@export var attempted: int = 0
@export var launched: int = 0
@export var prelaunch_destroyed: int = 0
@export var postlaunch_destroyed: int = 0


## Launchers permanently lost on this crossing, both kinds together.
func destroyed_total() -> int:
	return prelaunch_destroyed + postlaunch_destroyed


## "" when the row is self-consistent, otherwise the reason it is not. The authority refuses to
## apply a request that fails this, so a calculator bug cannot silently become campaign state.
func consistency_error() -> String:
	if attempted < 0 or launched < 0 or prelaunch_destroyed < 0 or postlaunch_destroyed < 0:
		return "negative count in outcome %d:%d" % [to_number, type_id]
	if destroyed_total() > attempted:
		return "outcome %d:%d destroyed %d of only %d attempted" % [
			to_number, type_id, destroyed_total(), attempted]
	if launched > attempted:
		return "outcome %d:%d launched %d of only %d attempted" % [
			to_number, type_id, launched, attempted]
	return ""
