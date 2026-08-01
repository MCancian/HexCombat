# IJFS — Retrospectives

Lessons from IJFS work, newest first. Symptom → cause → what to do differently.

## 2026-07-30 — plan 0046, the IJFS mutation authority

**A protected field NAME is claimed across the whole repo, not within its class.** Registering
`IjfsMunition.name` turned 22 untouched lines in `scripts/ui/HexMap.gd` and `scripts/ui/SymbolPreview.gd`
into `E_UNRESOLVED_WRITE` gate failures, because `name` is a Godot `Node` property and the gate's
name-backstop fires on any unresolvable receiver writing a protected name. The fix was to rename the
field (`munition_name`, JSON key unchanged). The manifest's `_schema_rules` already ask for
distinctive names; this is what ignoring that line costs. **Before registering a field, grep the tree
for its name** — `name`, `id`, `state`, `type`, `active` are mines. Note the plan review predicted
this class of failure for `metadata` and was wrong there (measurement: one declaring class, all
writes type-resolvable) while nobody looked at `name`. Predicting the category is not the same as
finding the instance; run the gate.

**An authority does not have to apply at the end.** The first three aggregates all follow
"calculator returns a typed outcome, coordinator hands it to the authority once". IJFS cannot: its
stages consume dice CONDITIONALLY on state an earlier stage just wrote, and later stages choose which
targets to iterate by reading it, so deferring application would change the draw count and move the
golden pins. The authority is therefore called from inside the stages, at the exact point the old
assignment sat. What it buys is a named, checked, single-file writer — not a deferred one. That
forced a new directory claim for `scripts/ijfs/` rather than widening `scripts/calc/`'s "writes
nothing" claim to accommodate one subsystem. (2026-07-31, plan 0055: the claim held, the name did
not — it is now `scripts/interleaved/`, named for the property rather than the subsystem.)

**Monotonic invariants are best enforced by absence, not by a guard.** Nothing in `IjfsTransitions`
can clear `destroyed`. There is no guard to argue with or bypass, because there is no way to express
the operation.

**Two things in this subsystem look like bugs and are not** — check before "fixing":
`IjfsSquadron.rtb_today` has no runtime writer at all (the mechanic that would give it one is plan
0059 — until then a writer appearing is a bug, not a fix); and `IjfsEngine`'s `will_fly` inventory
pre-check is defensive redundancy rather than an RNG gate,
because `IjfsTargeting._rule_affordable` already refuses an unaffordable pairing on every selection
path. The first is pinned as-is by `tests/ijfs/ijfs_authority_characterization_test.gd`;
the second means the insufficiency contract has to be tested
directly against the authority, since an engine-level test of it would pass while exercising nothing.
