class_name IjfsStrikePhaseContext
extends Resource

## Typed input bundle for IjfsEngine's two strike passes (plan 0046 commit 2). Built once per
## `run_daily` and threaded through both, which is what makes it a bundle rather than a parameter
## list: `attacked` and `skip_reasons` are shared ACCUMULATORS — the post-AD pass must see what the
## pre-AD pass already hit, and the final skip log reads both after they are done.
##
## `phase` and `dice` deliberately stay explicit at the call site. Phase differs between the two
## passes and reading it out of a mutable bundle is how a pass silently runs under the wrong label;
## Dice stays visible because draw order is the contract this whole subsystem is pinned on.
##
## `organic_budget` is the one field that changes between the passes: it is null for pre-AD (organic
## munitions are filtered out there, see IjfsTargeting._filter_by_phase) and set before post-AD, once
## the surviving strike aircraft are known.

# Day identity for the log rows.
var current_day: int = 0

# Shared across both passes: target_id -> true once attacked, and target_id ->
# [reason, doctrine_name, doctrine_selection] for the ones that were not.
var attacked: Dictionary = {}
var skip_reasons: Dictionary = {}

# Ephemeral daily firing budgets (IjfsFiringCapacity.FiringCapacityBudget / OrganicStrikeBudget),
# or null when unbudgeted. Variant because both are inner classes.
var capacity_budget: Variant = null
var organic_budget: Variant = null

# Warmup release gating: z_day is the day relative to the landing, release_rules the scenario's
# target-release table. Both null outside the warmup.
var z_day: Variant = null
var release_rules: Variant = null

# Warmup munition restriction, or null when every munition is available.
var munition_filter: Variant = null

## Whether Taiwan's air defences may kill Red aircraft at all. False during a prelanding warmup that
## declares no AD attrition, and it gates the package's ingress engagements for the same reason it
## gates SAM return fire and the free shot. Only known after the warmup context is read, so the engine
## sets it after construction.
var ad_attrition_enabled: bool = true

# How survivable each airframe is today (IjfsAttritionProfile): RCS signature x role exposure,
# shared by every path that can kill an aircraft.
var attrition: IjfsAttritionProfile = null

## The day's ONE derived child stream for air-engagement rolls: package assembly, MANPADS, SAM
## return fire and the anti-radiation salvos (plan 0060). Derived once per day and RETAINED — a
## per-package `derive` of the same label would hand every package an identical sequence, which is
## the failure mode the plan calls out by name. Kept off the main phase stream so package geometry
## cannot shift the strike, detection or SEAD draws that surround it.
var air_engagement_dice: Dice = null

## How many Organic packages have launched today. Only makes package ids unique in the ledger, so a
## reader can tell two packages against the same target apart.
var packages_launched: int = 0
