#!/usr/bin/env python3
"""Find the largest connected component of hexes in taiwan_hex_grid.json using
odd-r pointy-top adjacency (matching HexMath.gd). Print sorted hex IDs to stdout
as a JSON array, and a one-line summary to stderr."""

import json
import sys
from collections import deque
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

ODDR_NEIGHBORS_EVEN = [(-1, -1), (-1, 0), (0, -1), (0, 1), (1, -1), (1, 0)]
ODDR_NEIGHBORS_ODD  = [(-1, 0), (-1, 1), (0, -1), (0, 1), (1, 0), (1, 1)]


def neighbor_offsets(row: int) -> list[tuple[int, int]]:
    return ODDR_NEIGHBORS_ODD if (row & 1) == 1 else ODDR_NEIGHBORS_EVEN


def main() -> None:
    grid_path = REPO_ROOT / "data" / "taiwan_hex_grid.json"
    with open(grid_path) as f:
        raw = json.load(f)
    entries = raw["hexes"] if isinstance(raw, dict) and "hexes" in raw else raw

    coords: dict[str, tuple[int, int]] = {}
    for h in entries:
        coords[h["id"]] = (h["row"], h["col"])

    # Build adjacency: each id -> set of neighbor ids
    coord_to_id = {(r, c): i for i, (r, c) in coords.items()}
    all_ids_set = set(coords.keys())

    adj: dict[str, set[str]] = {i: set() for i in all_ids_set}
    for i, (r, c) in coords.items():
        for dr, dc in neighbor_offsets(r):
            nid = coord_to_id.get((r + dr, c + dc))
            if nid is not None:
                adj[i].add(nid)

    # BFS to find all connected components
    unvisited = set(all_ids_set)
    components: list[list[str]] = []
    while unvisited:
        start = unvisited.pop()
        queue: deque[str] = deque([start])
        component: list[str] = []
        while queue:
            h = queue.popleft()
            component.append(h)
            for nb in list(adj[h]):
                if nb in unvisited:
                    unvisited.remove(nb)
                    queue.append(nb)
        components.append(sorted(component, key=lambda x: (coords[x][0], coords[x][1])))

    # Largest component = main island
    components.sort(key=len, reverse=True)
    main_island = components[0]
    offshore_ids = sorted(
        set(all_ids_set) - set(main_island),
        key=lambda x: (coords[x][0], coords[x][1]),
    )

    print(json.dumps(main_island, indent=2))
    sizes = [len(c) for c in components]
    print(
        f"total={len(entries)}  components={sizes}  offshore_ids={offshore_ids}",
        file=sys.stderr,
    )
    sys.exit(0)


if __name__ == "__main__":
    main()