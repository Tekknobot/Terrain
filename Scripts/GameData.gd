# File: res://Scripts/GameData.gd
extends Node

# ─────────────────────────────────────────────────────────────────────────────
# Global currency and progression
# ─────────────────────────────────────────────────────────────────────────────
var coins: int = 0
var xp: int = 0
var current_level: int = 1
var max_enemy_units: int = 2

var last_enemy_upgrade_level: int = 1

var completed_maps: Array[int] = []

var carryover_units: Array = []  # cleared after being consumed

# ─────────────────────────────────────────────────────────────────────────────
# Map settings
# ─────────────────────────────────────────────────────────────────────────────
var map_difficulty: int = 1

# ─────────────────────────────────────────────────────────────────────────────
# Track which upgrades and special ability each unit has received
# ─────────────────────────────────────────────────────────────────────────────
# unit_special: unit_id → String (the one‐time special ability assignment)
var unit_special: Dictionary = {}
# unit_upgrades: unit_id → Array[String] (the post‐battle upgrades list)
var unit_upgrades: Dictionary = {}

# ─────────────────────────────────────────────────────────────────────────────
# Persist currently-selected special ability (for HUD toggling, etc.)
# ─────────────────────────────────────────────────────────────────────────────
var selected_special_ability: String = ""

# ─────────────────────────────────────────────────────────────────────────────
# Available special abilities (for cycling, client seeding, UI list, etc.)
# ─────────────────────────────────────────────────────────────────────────────
var available_abilities: Array[String] = [
	"Ground Slam",
	"Mark & Pounce",
	"Guardian Halo",
	"High Arching Shot",
	"Suppressive Fire",
	"Fortify",
	"Heavy Rain",
	"Web Field"
]

# ─────────────────────────────────────────────────────────────────────────────
# Persistent UI/settings
# ─────────────────────────────────────────────────────────────────────────────
var current_zoom_index: int = 0
var first_enemy_spawn_done: bool = false

# reset your ID counter
var	next_unit_id = 1

var in_upgrade_phase: bool = false
var enemy_upgraded : bool = false


#-------------------------------------
var next_region_scene: PackedScene = null


# ─────────────────────────────────────────────────────────────────────────────
# Reset all memory between matches
# ─────────────────────────────────────────────────────────────────────────────
# Called only once at the start of a new match / new save slot
func full_reset() -> void:
	pass

func play_reset() -> void:
	#coins = 0
	#xp = 0
	current_level = 1
	max_enemy_units = 1
	map_difficulty = 1
	#selected_special_ability = ""
	#unit_special.clear()
	unit_upgrades.clear()
	first_enemy_spawn_done = false

	# **Reset your ID counter here:**
	next_unit_id = 1
	pass
	
# Called at the end of each level to prepare for the next level
func advance_level() -> void:
	current_level += 1
	max_enemy_units += 1
	first_enemy_spawn_done = false
	# ✂–– don’t clear unit_special or unit_upgrades here ––✂
	
# ─────────────────────────────────────────────────────────────────────────────
# Configuration persistence
# ─────────────────────────────────────────────────────────────────────────────
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("Camera", "zoom_index", current_zoom_index)
	var err = cfg.save("user://settings.cfg")
	if err != OK:
		push_error("Failed to save settings: %s" % str(err))

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		if cfg.has_section_key("Camera", "zoom_index"):
			current_zoom_index = cfg.get_value("Camera", "zoom_index")

# ─────────────────────────────────────────────────────────────────────────────
# Special‐ability assignment
# ─────────────────────────────────────────────────────────────────────────────
func set_unit_special(unit_id: int, ability_name: String) -> void:
	unit_special[unit_id] = ability_name

func get_unit_special(unit_id: int) -> String:
	return unit_special.get(unit_id, "")

func clear_unit_special(unit_id: int) -> void:
	unit_special.erase(unit_id)

# ─────────────────────────────────────────────────────────────────────────────
# Post-battle upgrades management
# ─────────────────────────────────────────────────────────────────────────────
func add_upgrade(unit_id: int, upgrade_name: String) -> void:
	if not unit_upgrades.has(unit_id) or typeof(unit_upgrades[unit_id]) != TYPE_ARRAY:
		unit_upgrades[unit_id] = []
	unit_upgrades[unit_id].append(upgrade_name)

# Safely return an Array of upgrades (never a String)
func get_upgrades(unit_id: int) -> Array:
	var ups = unit_upgrades.get(unit_id, [])
	if typeof(ups) == TYPE_ARRAY:
		return ups
	# if somehow a String got in there, wrap it
	return [str(ups)]

func clear_unit_upgrades(unit_id: int) -> void:
	unit_upgrades.erase(unit_id)

func clear_all_upgrades() -> void:
	unit_upgrades.clear()

func clear_enemy_upgrades() -> void:
	# look at every Unit in the scene
	for u in get_tree().get_nodes_in_group("Units"):
		# if it’s an enemy, erase its entry
		if not u.is_player and u.has_meta("unit_id"):
			clear_unit_upgrades(u.get_meta("unit_id"))

func mark_map_completed(map_id: int) -> void:
	if map_id in completed_maps:
		return
	completed_maps.append(map_id)

func is_map_completed(map_id: int) -> bool:
	return map_id in completed_maps
	
	
