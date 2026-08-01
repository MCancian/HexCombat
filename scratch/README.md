# scratch/ — throwaway probes live here, not in `tools/`

Everything in this directory except this README is gitignored. Write measurement probes,
one-off sweeps and experiment scripts here, run them, and delete them when done. Nothing
here is ever collected by the gate.

## Why not `tools/`

`tools/*.gd` **seeds the compile closure** that `tools/validate_tool_script_purity.gd` walks:
every class any tool names, plus everything those name, transitively. A scratch script there
drags whatever it touches into that closure, so a stray `preload` or a syntax error fails gate
phases that have nothing to do with your experiment — and the failure points nowhere near the
edit. This directory is outside the seed.

It has to be inside the project because the flatpak Godot sandbox cannot read scripts outside
the project dir, so `/tmp` is not an option for a `-s` script on the Linux box.

```bash
godot --headless --path . -s res://scratch/my_probe.gd
```

## The rule that makes a probe trustworthy

**A probe must print the input it believes it is measuring, not just the result.**

Measured cost of skipping it (2026-08-01): a sweep meant to compare Red's air force at three
J-16D counts edited the wrong JSON key, threw a `KeyError` into filtered-out stderr, and printed
three identical result blocks. It read as "this parameter changes nothing" and was one step from
being reported that way. It was caught only because the probe also printed the order of battle it
had actually loaded — 584 every time, when two runs should have shown 556 and 546.

So: echo the loaded parameter, and assert the edit applied.

## Do NOT hand-edit tracked data files to measure something

`DataOverrides` already exists for this and already fails loud, which hand-editing does not:

- `DataOverrides.set_map({...})` injects the override map programmatically, for in-process sweeps.
- `DataOverrides.load_error()` returns non-empty when the map failed to load. Its own header:
  *"an unoverridden game recorded as an overridden one is worse than no game at all."*
- `DataOverrides.unapplied()` names every override key that matched **nothing**. A key is marked
  applied only on success, so a wrong dot-path is reported rather than silently ignored.

`IjfsLoaders` runs every JSON it loads through `DataOverrides.apply(path, parsed)`, so
`ijfs_scenario.json` and `red_air_oob.json` are both reachable this way.

A probe that overrides data MUST assert both before trusting a number:

```gdscript
DataOverrides.set_map({"data/ijfs/red_air_oob.json": {"red_air_oob.0.aircraft_per_sqn": 10}})
assert(DataOverrides.load_error() == "", DataOverrides.load_error())
# ... run ...
assert(DataOverrides.unapplied().is_empty(), "override keys matched nothing: %s" % [DataOverrides.unapplied()])
```

That is the mechanical version of the echo rule above: `unapplied()` would have named the wrong
key in the J-16D incident instead of leaving it to be noticed by eye. Nothing is written to the
tree, so there is no restore step and no window where a crash leaves a silent balance change behind.

If you genuinely must edit a tracked file, restore it and confirm with `git status --short` before
trusting any number.

## Related

- `hexcombat-validation-and-qa` — what counts as evidence here
- `hexcombat-build-and-env` — flatpak sandbox traps
