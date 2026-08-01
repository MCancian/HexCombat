class_name OffloadRates
extends RefCounted

# Throughput rates ported from TaiwanInvasionViewer defaults/offload_rates.json.
# All values in short tons/day. Source of truth: data/offload_rates.json.

# Weight of one battalion in short tons.
# Source: TaiwanInvasionViewer src/contracts/units.py TONS_PER_BN.
const TONS_PER_BN := 2200.0

# Beach throughput rates
const BEACH_BASE := 4400.0
const JACKUP_BARGE := 4400.0
const FLOATING_PIER := 2200.0

# Port throughput rates. The SEIZED_* constants exist to mirror data/offload_rates.json
# (REQUIRED_RATE_KEYS); no code reads them — a seized node contributes zero by EXCLUSION in
# InfrastructureResolver.red_offload_nodes, not by rating it 0.
const OPERATIONAL_PORT := 11000.0
const DEGRADED_PORT := 2200.0
const SEIZED_PORT := 0.0

# Airbridge throughput rates
const OPERATIONAL_AIRBRIDGE := 2200.0
const DEGRADED_AIRBRIDGE := 1100.0
const SEIZED_AIRBRIDGE := 0.0

# Required key names for data/offload_rates.json validation.
const REQUIRED_RATE_KEYS: Array[String] = [
	"beach_base",
	"jackup_barge",
	"floating_pier",
	"operational_port",
	"degraded_port",
	"seized_port",
	"operational_airbridge",
	"degraded_airbridge",
	"seized_airbridge",
]
