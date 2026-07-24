extends Resource
class_name AirInsertionState

## Cross-turn state for the PLAAF air insertion path (plan 0032) — the non-amphibious way onto
## Taiwan. Owned by GameState, built by AirInsertionStateBuilder at scenario load, drained by
## AirInsertionResolver once per turn between the reinforcement phases and movement.
##
## The mechanic in one sentence: each turn Red may fly a capped number of battalions from the
## `pool` onto ordered hexes, and every battalion the air defences kill both dies AND permanently
## removes one battalion of lift from the cap that carried it — airframes, not just troops.
##
## Two lift classes draw on two separate budgets (LiftClass): AIRBORNE is fixed-wing at altitude
## and faces the SAM/radar layer only; AIR_ASSAULT is rotary-wing down low and faces the MANPADS
## layer on top of it. Which class a brigade belongs to comes from its OOB nato_type.
##
## An un-inserted brigade is `hex_id == ""` — the same "not present" state Red's at-sea brigades
## and Green's mobilizing brigades already use — so the victory census, legal moves and the
## observation exclude it with no special-casing. Once its first battalion lands, the brigade is on
## the map and `pool` still holds the rest; the census subtracts those exactly as it subtracts BNs
## still at sea.
##
## An empty `pool` (the default — no scenario opted in) makes the whole phase a no-op that consumes
## no dice, which is what keeps the golden byte-stable.
## to_dict() is the JSON-serialization boundary; its key order and value types are the contract.

## Battalions waiting to fly, one entry per brigade, in insertion-priority order. Each entry:
##   {brigade_id: String, lift_class: String, bns: Array[{id: String, type: String}]}
## Same entry shape family as GameState.ship_reserve / SealiftState.mainland_pool, deliberately: the
## census and the observation walk all three the same way. Drained in place as battalions fly; an
## entry whose `bns` empties is dropped.
@export var pool: Array = []

## CURRENT per-turn lift budget, lift_class -> battalions per turn. Permanently decremented by one
## for every battalion lost on insertion (the airframe is gone, not just the cargo), so a bloody
## early drop costs throughput for the rest of the game. Never rises.
@export var caps: Dictionary = {}

## The budget each class started with, lift_class -> int. Report-only: `caps` vs `initial_caps` is
## how much lift the air defences have destroyed.
@export var initial_caps: Dictionary = {}

## First turn insertions are allowed. Before it, orders are rejected rather than silently deferred.
@export var first_turn: int = 1

## Brigades with at least one battalion delivered by air, in arrival order. These are the formations
## the supply-isolation rule applies to: they fight out of supply until a friendly corridor links
## them to a beachhead (plan 0032). A brigade appears at most once.
@export var landed: Array[String] = []

## Append-only insertion log, in resolution order. Each entry:
##   {turn: int, brigade_id: String, lift_class: String, hex_id: String, landed: int, lost: int}
@export var history: Array = []


## Battalions still waiting to fly. lift_class "" totals every class.
func pending_battalions(lift_class: String = "") -> int:
	var total := 0
	for entry_value in pool:
		var entry: Dictionary = entry_value
		if lift_class != "" and String(entry["lift_class"]) != lift_class:
			continue
		total += (entry["bns"] as Array).size()
	return total


## Brigades with battalions still waiting to fly. lift_class "" totals every class.
func pending_brigades(lift_class: String = "") -> int:
	var total := 0
	for entry_value in pool:
		var entry: Dictionary = entry_value
		if lift_class == "" or String(entry["lift_class"]) == lift_class:
			total += 1
	return total


## Brigades that could legally receive an air_insert order right now: pool entries that are neither
## destroyed nor already ordered this turn. Each row:
##   {brigade_id, lift_class, battalions_waiting, locked_hex}
## locked_hex is "" until the brigade's first packet lands and, after that, the ONLY legal target —
## a formation occupies one hex, so follow-up battalions reinforce it where it stands.
##
## brigades: brigade_id -> Brigade (the same argument-not-autoload shape MobilizationState uses), so
## both the order validator and the observation can call this without either reaching a singleton.
func eligible_orders(brigades: Dictionary, pending_orders: Array) -> Array:
	var ordered: Dictionary = {}
	for pending_value in pending_orders:
		ordered[String((pending_value as Dictionary)["brigade_id"])] = true

	var eligible: Array = []
	for entry_value in pool:
		var entry: Dictionary = entry_value
		var brigade_id := String(entry["brigade_id"])
		if ordered.has(brigade_id):
			continue
		var brigade: Brigade = brigades.get(brigade_id, null)
		if brigade == null or brigade.destroyed:
			continue
		eligible.append({
			"brigade_id": brigade_id,
			"lift_class": String(entry["lift_class"]),
			"battalions_waiting": (entry["bns"] as Array).size(),
			"locked_hex": brigade.hex_id,
		})
	return eligible


## The pool entry for a brigade, or {} when it has nothing left to fly.
func entry_for(brigade_id: String) -> Dictionary:
	for entry_value in pool:
		var entry: Dictionary = entry_value
		if String(entry["brigade_id"]) == brigade_id:
			return entry
	return {}


func to_dict() -> Dictionary:
	return {
		"pool": pool.duplicate(true),
		"caps": caps.duplicate(true),
		"initial_caps": initial_caps.duplicate(true),
		"first_turn": first_turn,
		"landed": landed.duplicate(),
		"history": history.duplicate(true),
	}


## Fail-loud structural invariants (mirrors SealiftState.validate's role): well-formed pool entries
## with a known lift class, and no negative or unknown-class caps. Returns false + push_error on the
## first violation.
func validate() -> bool:
	for entry_value in pool:
		var entry: Dictionary = entry_value
		if not entry.has("brigade_id") or not entry.has("bns") or not entry.has("lift_class"):
			push_error("AirInsertionState: malformed pool entry %s" % entry)
			return false
		if not LiftClass.is_known(String(entry["lift_class"])):
			push_error("AirInsertionState: pool entry %s has unknown lift_class %s" % [
				entry["brigade_id"], entry["lift_class"]])
			return false

	for lift_class in caps.keys():
		if not LiftClass.is_known(String(lift_class)):
			push_error("AirInsertionState: cap for unknown lift_class %s" % lift_class)
			return false
		if int(caps[lift_class]) < 0:
			push_error("AirInsertionState: negative cap for %s" % lift_class)
			return false

	return true
