# Terrain Pipeline — HexCombat

## Purpose

Derive per-hex terrain classes for `data/taiwan_hex_grid.json` from open geodata:

- **DEM** — Copernicus GLO-90 (90 m elevation)
- **Land cover** — ESA WorldCover 2021 (10 m)
- **Coastline** — GSHHG (GSHHS hi-res)

Only derived JSON under `data/terrain/` is committed. Raster cache lives outside the repo at `~/geodata/hexcombat/`.

## Setup

```bash
cd tools/terrain
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Fetch sources

```bash
python3 fetch_sources.py
```

Stdlib only, idempotent. Downloads ~1–2 GB of raster tiles to `~/geodata/hexcombat/`.

## Files

| File | Role |
|---|---|
| `fetch_sources.py` | Downloader — stdlib only, idempotent |
| `classify_hexes.py` | Classifier — reads hex grid + rasters, writes terrain JSON (coming) |
| `overrides.json` | Manual per-hex class overrides, applied last |
