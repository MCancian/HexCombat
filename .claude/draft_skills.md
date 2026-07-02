
<project></project>-change-control — how changes are classified, gated, reviewed here; the project's non-negotiables with the *rationale* and the historical incident behind each.

<project></project>-debugging-playbook — symptom→triage table for this project's failure modes; the traps that cost real time (each with its story); discriminating experiments.

<project></project>-failure-archaeology — the chronicle: every major investigation, dead end, rejected fix, and revert, as symptom → root cause → evidence → status, so no one re-fights a settled battle. Mine git history and docs hard for this.

<project></project>-architecture-contract — the system's load-bearing design decisions and WHY; the invariants that must hold; the open known-weak points, stated plainly.

<domain></domain>-reference — the domain-theory knowledge pack a mid-level person lacks (the field's math/protocols/standards as they apply HERE, not a textbook).

<project></project>-config-and-flags — catalog of every configuration axis: options, defaults, which are production vs experimental, guards; how to add one (checklist); with re-verification commands since flags drift.

<project></project>-build-and-env — recreate the environment from scratch; known traps.

<project></project>-run-and-operate — running/deploying the thing: command anatomy, data or artifact conventions, what output lands where.

<project></project>-diagnostics-and-tooling — how to MEASURE instead of eyeball: the project's diagnostic tools with interpretation guides; ship actual scripts inside the skill's scripts/ dir where they exist or where you can write them.

<project></project>-validation-and-qa — what counts as evidence here; acceptance-threshold discipline; the certified/golden inventory; how to add tests.

<project></project>-docs-and-writing — maintaining the docs of record; templates; house style.

<project></project>-<hardest-problem></hardest>-campaign — an EXECUTABLE, decision-gated campaign for the hardest live problem from Phase 1: numbered phases, exact commands, EXPECTED observations/numbers at every gate ("if you see X instead → branch to Y"), the solution menu ranked with theory/derivation obligations for each, known wrong paths explicitly fenced off, and a validation-and-promotion protocol that routes through the project's change control — success must be measurable, never judged by eye.
