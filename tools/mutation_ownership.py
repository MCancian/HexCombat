#!/usr/bin/env python3
"""Read-only views of tools/mutation_authority_manifest.json.

WHY THIS EXISTS. The manifest is ~65 KB of JSON and is the single home for mutation ownership, so
nothing may be copied out of it into a doc. But every question an agent actually asks it — "who owns
this field", "what does my plan still owe", "which exclusions die when I archive" — needs a handful of
lines, and every plan in the 0042-0050 campaign has answered them by writing the same throwaway
`python3 -c "import json..."` extraction. This is that extraction, once, committed.

It is NOT an ownership record and never becomes one: it prints what the manifest says, so it cannot
drift from it. It is also deliberately NOT part of `tools/validate_mutation_authority.gd` — that file
is the gate, this is a reading aid, and a reading aid must not be able to break a gate. Python also
means no Godot boot, which is the whole point.

    python3 tools/mutation_ownership.py                 # aggregates, authorities, field counts
    python3 tools/mutation_ownership.py --fields        # every protected Class.field -> aggregate
    python3 tools/mutation_ownership.py --fields Supply # ... filtered by substring
    python3 tools/mutation_ownership.py --exclusions    # unprotected fields + why
    python3 tools/mutation_ownership.py --plan 0050     # what a plan still owes, and what blocks its archive
    python3 tools/mutation_ownership.py --writers       # construction/legacy allowances
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "tools", "mutation_authority_manifest.json")
PIN = os.path.join(ROOT, "tools", "fixtures", "mutation_authority", "real_claims_pin.json")


def load():
    with open(MANIFEST, encoding="utf-8") as handle:
        return json.load(handle)


def claims(manifest):
    """Every protected (aggregate, section, Class.field), in the pin's identity format."""
    rows = []
    for aggregate in manifest["aggregates"]:
        for section in ("owned_models", "hosted_fields"):
            for model in aggregate.get(section, []):
                for field in model.get("fields", {}):
                    rows.append((aggregate["id"], section, "%s.%s" % (model["class"], field)))
    return sorted(rows)


def print_aggregates(manifest):
    print("%-26s %-10s %-28s %s" % ("AGGREGATE", "STATUS", "AUTHORITY", "PROTECTED FIELDS"))
    for aggregate in manifest["aggregates"]:
        counts = []
        for section, label in (("owned_models", "owned"), ("hosted_fields", "hosted")):
            total = sum(len(m.get("fields", {})) for m in aggregate.get(section, []))
            if total:
                counts.append("%d %s" % (total, label))
        print("%-26s %-10s %-28s %s" % (
            aggregate["id"], aggregate["status"], aggregate["authority_class"],
            ", ".join(counts) or "-"))
    print("\n%d aggregates, %d protected fields." % (len(manifest["aggregates"]), len(claims(manifest))))


def print_fields(manifest, needle):
    for aggregate_id, section, field in claims(manifest):
        if needle and needle.lower() not in field.lower() and needle.lower() not in aggregate_id.lower():
            continue
        print("%-42s %-26s %s" % (field, aggregate_id, section))


def print_exclusions(manifest, plan_filter):
    """Fields on a hosted class that are deliberately NOT protected, and the reason."""
    for policy in manifest["shared_model_policies"]:
        rows = []
        for field, entry in policy["non_authority_fields"].items():
            plan = os.path.basename(entry.get("plan", ""))
            if plan_filter and plan_filter not in plan:
                continue
            rows.append((field, entry["classification"], plan))
        if not rows:
            continue
        print("== %s (%d shown)" % (policy["class"], len(rows)))
        for field, classification, plan in rows:
            print("   %-38s %-26s %s" % (field, classification, plan or ""))


def print_plan(manifest, plan_number):
    """What a plan still owes — and therefore what its archive step would break.

    A promise classification names a plan file under the manifest's `plan_dir`. Archiving that plan
    while an exclusion still points at it turns the gate red ON PURPOSE, so this is the check to run
    before moving a plan to docs/archive/.
    """
    owed = []
    for policy in manifest["shared_model_policies"]:
        for field, entry in policy["non_authority_fields"].items():
            if plan_number in os.path.basename(entry.get("plan", "")):
                owed.append((policy["class"], field, entry["classification"], entry["why"]))

    shipped = [a for a in manifest["aggregates"]
               if plan_number in json.dumps(a.get("summary", ""))]
    if shipped:
        print("Aggregates whose summary names plan %s:" % plan_number)
        for aggregate in shipped:
            print("   %-24s -> %s" % (aggregate["id"], aggregate["authority_class"]))
        print()

    if not owed:
        print("Plan %s has NO outstanding exclusions — archiving it cannot turn the gate red." % plan_number)
        return
    print("Plan %s still owes %d field(s). Archiving it before these are resolved FAILS the gate:"
          % (plan_number, len(owed)))
    for cls, field, classification, why in owed:
        print("\n   %s.%s  [%s]" % (cls, field, classification))
        print("      %s" % why)


def print_writers(manifest):
    for aggregate in manifest["aggregates"]:
        for section in ("construction_writers", "legacy_writers"):
            for entry in aggregate.get(section, []):
                print("%-26s %-22s %s" % (aggregate["id"], section, entry["path"]))
                print("%50s %s" % ("", entry.get("why", entry.get("removal_plan", ""))))


def check_pin(manifest):
    """The pin is an expected-output artifact, never an ownership input. This only REPORTS drift;
    the gate is what fails on it."""
    with open(PIN, encoding="utf-8") as handle:
        pinned = set(json.load(handle)["claims"])
    live = set("%s|%s|%s" % row for row in claims(manifest))
    for missing in sorted(pinned - live):
        print("PIN ONLY (claim deleted or renamed): %s" % missing)
    for added in sorted(live - pinned):
        print("MANIFEST ONLY (pin not updated):     %s" % added)
    if pinned == live:
        print("Pin matches the manifest exactly (%d claims)." % len(live))
        return 0
    return 1


def main(argv):
    manifest = load()
    if "--fields" in argv:
        index = argv.index("--fields")
        needle = argv[index + 1] if len(argv) > index + 1 and not argv[index + 1].startswith("-") else ""
        print_fields(manifest, needle)
    elif "--exclusions" in argv:
        index = argv.index("--exclusions")
        plan = argv[index + 1] if len(argv) > index + 1 and not argv[index + 1].startswith("-") else ""
        print_exclusions(manifest, plan)
    elif "--plan" in argv:
        print_plan(manifest, argv[argv.index("--plan") + 1])
    elif "--writers" in argv:
        print_writers(manifest)
    elif "--check-pin" in argv:
        return check_pin(manifest)
    else:
        print_aggregates(manifest)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
