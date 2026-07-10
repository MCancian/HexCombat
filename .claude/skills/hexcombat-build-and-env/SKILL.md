---
name: hexcombat-build-and-env
description: Recreate or repair the HexCombat working environment — Godot binary, class-cache import, GdUnit4, MCP, opencode — and the known environment traps on both the Windows and Linux boxes. Use on a fresh checkout, after adding scripts, when imports/tests fail mysteriously, or when a tool won't launch.
---

# HexCombat build & environment

Two boxes are real and both current — check which one you're on before following a recipe.

## Windows box

- **OS:** Windows 11; shell for gates is `pwsh` (PowerShell 7+). Git Bash exists for POSIX needs.
- **Godot:** `C:\Godot_v4.7-stable_win64.exe` (4.7-stable, Win64). Overridable via `$env:GODOT_BIN`
  or `-GodotBin` on the gate script.
- **Project root:** `C:\Users\mdogg\Desktop\HexCombat` (git repo, branch `main`).
- **Test framework:** GdUnit4, vendored in `addons/gdUnit4/` (committed).
- **Source oracles (read-only reference repos):**
  - `C:\Users\mdogg\TaiwanInvasionViewer` — the original Python/Flask sim. **Path gotcha:** the
    real source tree is NESTED — `C:\Users\mdogg\TaiwanInvasionViewer\TaiwanInvasionViewer\src\…`.
    Agents that look in the outer dir wrongly report "source not found"; use the nested path.
  - `C:\Users\mdogg\My Drive\Projects\TaiwanDefenseRefactor` — later Python wargame (mine model source).

## Linux box

- **OS:** Fedora; shell for gates is `bash`. No `pwsh` here — don't reach for the `.ps1` scripts.
- **Godot:** installed as a flatpak, invoked simply as `godot` on `PATH` (4.7-stable). A real
  display exists, so windowed screenshot capture (`tools/capture_screenshot.gd`) works.
- **Canonical gate:** `bash tools/run_all_tests.sh` — same four-phase verdict logic as the
  Windows `.ps1` (ported 2026-07-08). Linux teardown-flake exit codes are 139/134/138/132
  (POSIX signal-based) rather than the Windows access-violation codes.
- **Flatpak sandbox trap:** the sandboxed Godot process cannot read or write outside the project
  directory — a `-s res://tools/foo.gd` script living in `/tmp` or the scratchpad fails with
  "File not found", and any tool writing output must use a repo-relative path. Copy scratch
  scripts into the repo, run them, then delete them; don't point `--path`/`-s` at anything
  outside the checkout.
- **Class cache after adding a script:** same rule as Windows — after adding or renaming any
  `class_name` script, run `godot --headless --path . --import` before trusting test output,
  or the new class fails to resolve (stale class cache, looks like an unrelated failure).

## From scratch (fresh checkout, Windows)

```powershell
# 1. Build the class cache (REQUIRED after checkout and after adding/renaming any script)
& "C:\Godot_v4.7-stable_win64.exe" --headless --path "C:\Users\mdogg\Desktop\HexCombat" --import

# 2. Prove the environment with the canonical gate
pwsh -File tools/run_all_tests.ps1
```

Expect **ALL PHASES GREEN** (possibly with teardown-flake warnings — those are OK).

## From scratch (fresh checkout, Linux)

```bash
# 1. Build the class cache (REQUIRED after checkout and after adding/renaming any script)
godot --headless --path . --import

# 2. Prove the environment with the canonical gate
bash tools/run_all_tests.sh
```

Expect **ALL PHASES GREEN** (possibly with teardown-flake warnings, exit 139/134/138/132 — those
are OK).

## Known traps

- **Stale class cache** — `.godot/` is git-ignored and rebuilt by `--import`. Editing/adding
  scripts and then running validators **without re-importing** produces phantom failures,
  including non-deterministic-looking results (a past incident produced a flaky victory census
  that looked like a state-bleed bug). Rule: any script change → `--import` before judging test
  output.
- **`.gd.uid` files are committed** alongside their scripts. Godot generates them on import; if
  you create a script, commit its `.uid` too (the import step creates it).
- **Godot 4.7 headless teardown crash** — after scripts/tests finish and PASS, the engine
  intermittently segfaults during shutdown (exit codes -1073741819 access violation, -1073740940
  heap corruption, -1073741571 stack overflow, -1073740791 buffer overrun). The gate already
  classifies these: clean output + crash exit = warning, not failure. Never "fix" this by
  swallowing real nonzero exits; judge by output markers.
- **`.mcp.json` is locally modified on purpose** (machine-specific Godot path) — never commit it.
- **`pi` CLI is broken on this box** (spawns `opencode` via `spawn('opencode')`, can't resolve the
  `.cmd` shim → ENOENT). Call `opencode` directly.
- **Windows line endings:** some files trigger LF→CRLF warnings; harmless, don't churn files to
  "fix" it. The fixture byte-compare gate normalizes line endings already.

## Godot MCP (visual/runtime inspection)

`.mcp.json` configures the Godot MCP server (launch editor, run project, read debug output,
screenshots). Available as `mcp__godot__*` tools when enabled. Headless gates never need it;
visual verification does.

## opencode (auxiliary implementer)

```bash
opencode run -m opencode/deepseek-v4-flash-free "task"            # read/write build agent
opencode run -m opencode/deepseek-v4-flash-free --agent explore "task"  # read-only (may fall back)
opencode run -m opencode/deepseek-v4-flash-free -s <session> "step"     # continue a session
```

Small free model: use only for mechanical/exploratory chores; verify everything it reports.
