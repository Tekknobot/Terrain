# GameData.gd
extends Node

var coins: int = 0
var xp: int = 0
var current_level: int = 1
var selected_upgrade: String = ""
var selected_special_ability: String = ""
var max_enemy_units: int = 8

var map_difficulty: int = 1

# Track unit upgrades by unit name.
var unit_upgrades: Dictionary = {}

# Flag to mark if the first enemy spawn for this level has been performed.
var first_enemy_spawn_done: bool = false

# Reset all persistent data to the defaults.
func reset_data() -> void:
	coins = 0
	xp = 0
	current_level = 1
	selected_upgrade = ""
	selected_special_ability = ""
	unit_upgrades.clear()
	first_enemy_spawn_done = false

func add_coins(amount: int) -> void:
	coins += amount

func add_xp(amount: int) -> void:
	xp += amount

func advance_level() -> void:
	current_level += 1
	# Reset the first enemy spawn flag for the new level.
	first_enemy_spawn_done = false
