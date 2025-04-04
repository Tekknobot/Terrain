# GameData.gd
extends Node

# Global variables for persistent game progress.
var coins: int = 0
var xp: int = 0
var current_level: int = 1
var selected_upgrade: String = ""
var max_enemy_units: int = 4

var map_difficulty: int = 1

# Optional: Additional persistent data you may want to track.
var player_stats: Dictionary = {
	"total_damage_dealt": 0,
	"units_lost": 0,
	"enemy_units_destroyed": 0
}

# Reset all persistent data to the defaults.
func reset_data() -> void:
	coins = 0
	xp = 0
	current_level = 1
	selected_upgrade = ""
	player_stats = {
		"total_damage_dealt": 0,
		"units_lost": 0,
		"enemy_units_destroyed": 0
	}

# Optionally, you can add functions to update the stats.
func add_coins(amount: int) -> void:
	coins += amount

func add_xp(amount: int) -> void:
	xp += amount

func advance_level() -> void:
	current_level += 1
