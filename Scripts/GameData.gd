extends Node

var coins: int = 0
var xp: int = 0
var current_level: int = 1
var selected_upgrade: String = ""
var selected_special_ability: String = ""
var max_enemy_units: int = 4
var map_difficulty: int = 1

# Store special ability upgrades for units.
# Use a key that identifies the unit type (e.g., unit.unit_name)
var unit_upgrades: Dictionary = {}

# Optional additional stats…
var player_stats: Dictionary = {
	"total_damage_dealt": 0,
	"units_lost": 0,
	"enemy_units_destroyed": 0
}

func reset_data() -> void:
	coins = 0
	xp = 0
	current_level = 1
	selected_upgrade = ""
	selected_special_ability = ""
	unit_upgrades = {}
	player_stats = {
		"total_damage_dealt": 0,
		"units_lost": 0,
		"enemy_units_destroyed": 0
	}
	
func add_coins(amount: int) -> void:
	coins += amount

func add_xp(amount: int) -> void:
	xp += amount

func advance_level() -> void:
	current_level += 1
