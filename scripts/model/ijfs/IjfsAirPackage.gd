class_name IjfsAirPackage
extends RefCounted

## The airframes flying ONE Organic strike, or the aircraft assigned to the day's SEAD effort.
##
## Plan 0060 R8 (USER ruling 2026-08-01) replaced "an Organic strike costs a sortie seat and nothing
## else" with "an Organic strike is a package of four real airframes drawn from real squadrons".
## That is what lets attrition be LOCAL: a SAM or a MANPADS team can only kill an aircraft that
## actually entered its envelope, and the loss lands on the squadron that supplied it rather than on
## a pooled tax spread over aircraft parked elsewhere.
##
## `members` holds ONE ENTRY PER AIRFRAME, so a squadron that supplied two of the four appears twice.
## That is deliberate: attributing a kill means naming which squadron loses an airframe, and a
## de-duplicated set could not say whether a squadron contributed one or three.
##
## Transient by design — a package exists for one engagement and is never serialized, which is why
## this extends RefCounted rather than Resource.

const STRIKE := "strike"
const SEAD := "sead"

## A target that belongs to no theatre. Distinct from "island-wide" on purpose: see `to_number`.
const NO_THEATRE := -1

## Which authored capacity row this package was drawn against, and what it is flying at. `munition_id`
## and `target_id` are empty for the SEAD package: it is assigned to the day, not to one target.
var kind: String = ""
var package_id: String = ""
var munition_id: String = ""
var target_id: String = ""

## The theatre the package flew into, or NO_THEATRE for a target that sits in none. A strike package
## is engaged only by SAMs in its TO, so NO_THEATRE means no SAM can reach it — which is right, and
## is NOT the same as the SEAD package, whose whole job is island-wide and which is engaged by every
## live SAM regardless. The two are told apart by `kind`, never by this sentinel.
var to_number: int = NO_THEATRE

## Airframes at assembly, before any ingress attrition. `survivor_fraction` divides by this, so a
## package that assembled short (never happens today — assembly is all-or-nothing) would still scale
## honestly.
var initial_size: int = 0

## For the SEAD package only (plan 0060 R11 stage C): how many of the leading members are DEDICATED
## SEAD airframes. `members` is built dedicated-first, so this is the index at which ordinary strike
## aircraft begin — and the two contribute different SEAD effect, which is the whole reason the split
## has to be recorded rather than re-derived from squadron roles.
##
## Read it BEFORE ingress attrition: `remove_member` shifts indices, and IjfsSeadStage computes the
## package's power at assignment time for exactly that reason.
var dedicated_size: int = 0

var members: Array[IjfsSquadron] = []


## Read one Organic munition's package configuration out of the scenario: which air classes it draws
## from, how many airframes fly, and whether MANPADS may engage it. Empty when the munition has no
## `attrition_link` — the normal case for every ground-launched munition, meaning "this costs no
## airframes". IjfsLoaders has already hard-validated the shape of any non-null link, so a non-empty
## return here is known-good.
static func link_config(scenario: Dictionary, munition_id: String) -> Dictionary:
	var entry: Dictionary = scenario.get("red_firing_capacity", {}).get(munition_id, {})
	var link: Variant = entry.get("attrition_link", null)
	if link == null:
		return {}
	return {
		"classes": link as Array,
		"package_size": int(entry["package_size"]),
		"manpads_eligible": bool(entry["manpads_eligible"]),
	}


## Reserve `size` distinct airframes from `candidates`, or return an empty array when the linked
## squadrons cannot field that many today.
##
## Selection is uniform over AIRFRAMES, not over squadrons: a 24-airframe squadron is six times more
## likely to supply a given slot than a 4-airframe one, which is what "the package comes from
## whatever is on the ramp" means. Drawing without replacement is done by shrinking the pool after
## each pick, so the same airframe cannot appear twice — one draw per member, on the caller's
## dedicated substream.
##
## Availability is `alive - rtb_today - sead_assigned_today` (IjfsSquadron.available_today): an
## airframe already home for the day, or already booked to the SEAD package, cannot also fly this.
static func reserve(candidates: Array, size: int, dice: Dice) -> Array[IjfsSquadron]:
	var pool: Array[IjfsSquadron] = []
	var remaining: Array[int] = []
	var total := 0
	for squadron: IjfsSquadron in candidates:
		var available := squadron.available_today()
		if available <= 0:
			continue
		pool.append(squadron)
		remaining.append(available)
		total += available

	var reserved: Array[IjfsSquadron] = []
	if total < size:
		return reserved
	for _slot in range(size):
		# `randf()` is [0, 1) for SeededDice, but a scripted 1.0 must not index past the end — hence
		# the clamp to the last eligible airframe rather than an out-of-range crash.
		var index := mini(int(floor(dice.randf() * float(total))), total - 1)
		for i in range(pool.size()):
			if index < remaining[i]:
				reserved.append(pool[i])
				remaining[i] -= 1
				break
			index -= remaining[i]
		total -= 1
	return reserved


static func build(kind_value: String, package_id_value: String, members_value: Array[IjfsSquadron]) -> IjfsAirPackage:
	var package := IjfsAirPackage.new()
	package.kind = kind_value
	package.package_id = package_id_value
	package.members = members_value
	package.initial_size = members_value.size()
	return package


func size() -> int:
	return members.size()


func is_empty() -> bool:
	return members.is_empty()


## Remove the airframe at `index` — the one an engagement just killed — and return the squadron that
## loses it, so the caller can book the loss against the right unit.
func remove_member(index: int) -> IjfsSquadron:
	var squadron := members[index]
	members.remove_at(index)
	# `dedicated_size` is an INDEX into `members`, so a removal below it has to move it or the
	# dedicated/ordinary split silently reclassifies an airframe. Production reads the split before
	# any removal today; this makes that a property of the object rather than of the call order.
	if index < dedicated_size:
		dedicated_size -= 1
	return squadron


## The share of the package that reached the target. IjfsStrikeContext multiplies both strike
## probabilities by it, so a package that lost half its airframes on ingress delivers half the effect.
func survivor_fraction() -> float:
	if initial_size <= 0:
		return 0.0
	return float(members.size()) / float(initial_size)


## Squadron id -> how many of the CURRENT members it supplied. Used by the ledger rows so a reader
## can see which units were exposed without the row carrying four object references.
func members_by_squadron() -> Dictionary:
	var counts: Dictionary = {}
	for squadron in members:
		counts[squadron.squadron_id] = int(counts.get(squadron.squadron_id, 0)) + 1
	return counts
