# HexCombat systems reference

One doc per subsystem — how it works in HexCombat today, the key functions/files, and how
faithfully it tracks its **TaiwanInvasionViewer** (TIV) oracle. Written for agents; human-readable
HTML mirrors live in `html/`. Audit status + open fidelity questions:
`../archive/AUDIT_PROGRESS.md` and `../archive/PORT_FIDELITY_DECISIONS.md` (both discharged).

| System | Doc | HTML |
|---|---|---|
| Hex grid & geometry | [hex-grid.md](hex-grid.md) | [html](html/hex-grid.html) |
| Ground combat (BOOTS) | [ground-combat.md](ground-combat.md) | [html](html/ground-combat.html) |
| Amphibious offload (D1) | [amphibious-offload.md](amphibious-offload.md) | [html](html/amphibious-offload.html) |
| Supply (D2 DOS) | [supply-dos.md](supply-dos.md) | [html](html/supply-dos.html) |
| Anti-ship & mine (D3) | [antiship-mine.md](antiship-mine.md) | [html](html/antiship-mine.html) |
| IJFS (D4) | [ijfs.md](ijfs.md) | [html](html/ijfs.html) |
| Front-line / cleanup / victory (D5) | [frontline-cleanup-victory.md](frontline-cleanup-victory.md) | [html](html/frontline-cleanup-victory.html) |
| ROC mobilization phase-in | [roc-mobilization.md](roc-mobilization.md) | — |
| PLAAF air insertion | [air-insertion.md](air-insertion.md) | — |
| Turn engine & data | [turn-engine.md](turn-engine.md) | [html](html/turn-engine.html) |
| LLM API & self-play | [llm-api-selfplay.md](llm-api-selfplay.md) | [html](html/llm-api-selfplay.html) |
| View layer | [view-layer.md](view-layer.md) | [html](html/view-layer.html) |

## The "State & authority" section

A doc whose subsystem owns a registered mutation aggregate carries one short **State & authority**
section (campaign 0042–0050). It names four things and no more: the aggregate, its authority class,
the operation-specific outcome/receipt types, and a link to
`tools/mutation_authority_manifest.json`. It then explains the RULES the authority enforces — what
they mean for the model, not which field which file may assign.

It must never restate the protected-field or writer lists. Those live in the manifest, are enforced
by `tools/validate_mutation_authority.gd`, and a copy of them rots silently. This index does not keep
an authority inventory either, for the same reason — the manifest is the inventory.
