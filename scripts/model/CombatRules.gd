class_name CombatRules
extends Resource

var feba_base_km: float = 2.0
var red_supply_pool: float = 0.0
var red_out_of_supply_effectiveness: float = 1.0
var unscreened_support_strength: float = 0.5
var maneuver_casualty_weight: float = 4.0
var support_casualty_weight: float = 1.0
var defender_terrain_modifier: float = 1.0
var support_multipliers: Dictionary = {}
var combat_base_loss_rate: float = 0.20
var combat_attacker_ratio_slope: float = 0.08
var combat_defender_ratio_slope: float = 0.10
var combat_loss_roll_midpoint: float = 50.0
var combat_loss_roll_scale: float = 1000.0
var combat_min_loss_rate: float = 0.05
var combat_max_attacker_loss_rate: float = 0.45
var combat_max_defender_loss_rate: float = 0.50
var feba_balance_gain: float = 2.0
var feba_balance_clamp: float = 2.0
var feba_roll_factor_min: float = 0.75
var feba_roll_factor_span: float = 0.5
var combat_min_effective_strength: float = 0.1
var combat_attacker_advantage_ratio: float = 1.2
var combat_defender_advantage_ratio: float = 0.85
var default_combat_strength: float = 1.0
