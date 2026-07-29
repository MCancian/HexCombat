# Mutation-authority validator fixtures

Deliberately illegal source, kept here so `tools/validate_mutation_authority.gd` can prove — on
every gate run — that it detects each write form its header claims. A claim no fixture exercises is
a claim nobody has checked.

**Why `.gdfixture` and not `.gd`:** these files must never be compiled. Godot's importer and
GdUnit4's suite discovery both walk the project for `.gd`, and a fixture whose whole purpose is to
break a rule would either fail to compile or be run as a test suite. The validator reads them as
text, which is all a source gate ever needed.

## How a fixture declares what it expects

- `#@expect <rule>` trailing a line means the scan MUST report exactly that rule on that line.
  A line with no marker MUST produce nothing. The validator compares the two sets exactly, so a
  missed detection fails as a false negative and an over-eager one as a false positive.
- One violation per line — the comparison is keyed by `path:line`.
- `bad_manifest_*.json` each declare `_expect_error`: the single manifest-check code that manifest
  must provoke. These cover the failures no source file can reach (dead paths, unclassified fields,
  duplicate claims, a missing authority).

## Files

| File | Role |
|---|---|
| `fixture_manifest.json` | The healthy manifest the source fixtures are scanned against |
| `model.gdfixture` | `FixtureRow` — the owned protected model, including a sanctioned mutator |
| `host.gdfixture` | `FixtureHost` — a shared model carrying two hosted protected fields |
| `facade.gdfixture` | `FixtureGameStateFacade` — stand-in for a GameState façade setter bypass |
| `other_model.gdfixture` | `FixtureOtherModel` — an owned model for a second aggregate |
| `authority.gdfixture` | `FixtureTransitions` — the authority for the first aggregate |
| `transitions_dir/other_authority.gdfixture` | `FixtureOtherTransitions` — authority for second aggregate; proves wrong-authority detection |
| `construction.gdfixture` | A construction writer initialising fresh, unpublished rows |
| `legacy.gdfixture` | A declared temporary legacy writer |
| `violations.gdfixture` | One line per detected write form, each marked `#@expect` |
| `bad_manifest_*.json` | One broken manifest per manifest-check error code |
