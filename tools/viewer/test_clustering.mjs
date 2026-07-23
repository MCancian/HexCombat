// Regression test for the Front-view clustering (plan 0023 P1). Loads the REAL
// connectedComponents/largestCluster source out of game_viewer.html's <clustering-pure> block
// (no duplicated algorithm — the shipped code IS the code under test) and asserts it on a known
// two-cluster fixture. Pure graph logic, so no browser is needed — run with: node
// tools/viewer/test_clustering.mjs (exit 0 = pass; the viewer's screenshot verification is
// separate, see docs/STATUS.md).
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(HERE, "game_viewer.html"), "utf8");

// Slice out the marked pure block and eval it to recover the two functions. The markers are load-
// bearing — keep them around exactly the clustering functions in game_viewer.html.
const START = "// <clustering-pure>";
const END = "// </clustering-pure>";
const from = html.indexOf(START);
const to = html.indexOf(END);
if (from === -1 || to === -1 || to < from) {
  throw new Error("clustering-pure markers not found in game_viewer.html — did the block move?");
}
// Start at the newline after the START marker line so the marker's own trailing comment text
// (which follows `//`) is not pulled into the evaluated source as bare tokens.
const source = html.slice(html.indexOf("\n", from) + 1, to);
const { connectedComponents, largestCluster } =
  new Function(source + "\nreturn { connectedComponents, largestCluster };")();

let failures = 0;
function check(name, cond) {
  if (cond) { console.log("  ok   " + name); }
  else { console.log("  FAIL " + name); failures++; }
}
function sortedSizes(comps) { return comps.map(c => c.length).sort((a, b) => b - a); }

// Fixture: two spatially-separated beachheads on an odd-r-ish grid, joined by nothing (the hex
// between them, B_gap, is NOT in the focus set, so it must not bridge the clusters).
//   Cluster A (3 hexes, 2 contested): A1-A2-A3
//   Cluster B (2 hexes, 0 contested): B1-B2
// Adjacency is a plain undirected map; only focus ids are traversed.
const adj = {
  A1: ["A2", "gap"],
  A2: ["A1", "A3"],
  A3: ["A2"],
  gap: ["A1", "B1"],   // the neutral hex between the beachheads
  B1: ["B2", "gap"],
  B2: ["B1"],
};
const neighborsOf = (id) => adj[id] || [];
const focus = new Set(["A1", "A2", "A3", "B1", "B2"]);   // gap deliberately excluded
const contested = new Set(["A2", "A3"]);
const isContested = (id) => contested.has(id);

const comps = connectedComponents(focus, neighborsOf);
check("finds exactly two components", comps.length === 2);
check("component sizes are [3, 2] (gap does not bridge)",
  JSON.stringify(sortedSizes(comps)) === JSON.stringify([3, 2]));

const big = largestCluster(comps, isContested);
check("frames the larger cluster (A, 3 hexes)",
  new Set(big).size === 3 && ["A1", "A2", "A3"].every(id => big.includes(id)));

// Tie-break: two equal-size clusters, the one with more contested hexes wins.
const tieComps = [["X1", "X2"], ["Y1", "Y2"]];
const tieContested = new Set(["Y1"]);          // Y has 1 contested, X has 0
const tieWinner = largestCluster(tieComps, (id) => tieContested.has(id));
check("tie on size -> most-contested cluster wins",
  JSON.stringify(tieWinner) === JSON.stringify(["Y1", "Y2"]));

// Degenerate inputs.
check("no components -> empty cluster", largestCluster([], () => false).length === 0);
const single = connectedComponents(new Set(["S1"]), () => []);
check("single hex -> one component of size 1",
  single.length === 1 && single[0].length === 1);

if (failures > 0) {
  console.log(`\nCLUSTERING TEST: ${failures} FAILURE(S)`);
  process.exit(1);
}
console.log("\nCLUSTERING TEST PASS");
