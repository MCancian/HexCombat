class_name AirInsertionResolutionPlan
extends Resource

var state: AirInsertionState = null
var orders: Array = []
var turn_number: int = 0
var threat: Dictionary = {}
var config: Dictionary = {}
var hex_can_receive: Callable
var dice: Dice = null
var summary: AirInsertionSummary = null
var landings: Array = []
var budget: Dictionary = {}
var caps_after: Dictionary = {}
var pool_sent: Dictionary = {}
var substream: Dice = null
