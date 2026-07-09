#!/usr/bin/env python3
"""Fetch terrain source data for HexCombat — DEM, landcover, coastline.

Idempotent downloader.  Skip existing non-empty files.
"""

import argparse
import os
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path


def _download(url: str, dest: Path) -> str:
    """Download *url* to *dest*.

    Returns one of ``DONE``, ``FAIL``, ``SKIP``, ``SKIP-404``.
    """
    if dest.exists() and dest.stat().st_size > 0:
        print(url)
        return "SKIP"

    print(url)
    try:
        urllib.request.urlretrieve(url, dest)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return "SKIP-404"
        print(f"FAIL (HTTP {exc.code})", file=sys.stderr)
        raise
    except Exception as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        raise
    return "DONE"


def _fetch_dem(cache: Path) -> None:
    sub = cache / "dem"
    sub.mkdir(parents=True, exist_ok=True)

    for lat in range(21, 26):
        lat_s = f"N{lat:02d}"
        for lon in range(119, 123):
            lon_s = f"E{lon:03d}"
            fname = f"Copernicus_DSM_COG_30_{lat_s}_00_{lon_s}_00_DEM.tif"
            url = (
                "https://copernicus-dem-90m.s3.amazonaws.com/"
                f"Copernicus_DSM_COG_30_{lat_s}_00_{lon_s}_00_DEM/{fname}"
            )
            status = _download(url, sub / fname)
            print(status)


def _fetch_landcover(cache: Path) -> None:
    sub = cache / "landcover"
    sub.mkdir(parents=True, exist_ok=True)

    for tile in ("N21E120", "N24E120"):
        fname = f"ESA_WorldCover_10m_2021_v200_{tile}_Map.tif"
        url = (
            "https://esa-worldcover.s3.eu-central-1.amazonaws.com/"
            f"v200/2021/map/{fname}"
        )
        status = _download(url, sub / fname)
        print(status)


def _fetch_coastline(cache: Path) -> None:
    sub = cache / "coastline"
    sub.mkdir(parents=True, exist_ok=True)

    marker = sub / "GSHHS_shp" / "f" / "GSHHS_f_L1.shp"
    if marker.exists() and marker.stat().st_size > 0:
        print("SKIP")
        return

    zip_path = sub / "gshhg-shp-2.3.7.zip"
    url = (
        "https://github.com/GenericMappingTools/gshhg-gmt/releases/download/"
        "2.3.7/gshhg-shp-2.3.7.zip"
    )
    status = _download(url, zip_path)
    print(status)
    if status in ("FAIL", "SKIP-404"):
        return

    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(sub)
    print("UNZIPPED")


def main() -> None:
    default = str(Path.home() / "geodata" / "hexcombat")
    parser = argparse.ArgumentParser(
        description="Fetch terrain source data for HexCombat"
    )
    parser.add_argument(
        "--cache-dir",
        default=default,
        help=f"Cache directory (default: {default})",
    )
    args = parser.parse_args()

    cache = Path(args.cache_dir)
    cache.mkdir(parents=True, exist_ok=True)

    _fetch_dem(cache)
    _fetch_landcover(cache)
    _fetch_coastline(cache)


if __name__ == "__main__":
    main()
