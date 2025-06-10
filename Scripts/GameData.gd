extends Node

# Global currency and progression
var coins: int = 0
var xp: int = 0
var current_level: int = 1
var max_enemy_units: int = 1

# Map settings
var map_difficulty: int = 1

# Track which upgrades each unit (by ID) has received
# Key: unit_id (int) → Value: Array of upgrade names (String)
var unit_upgrades: Dictionary = {}

# Persist currently-selected special ability
var selected_special_ability: String = ""

# Available special abilities (for UI and ability cycling)
var available_abilities: Array[String] = [
	"Ground Slam",
	"Mark & Pounce",
	"Guardian Halo",
	"High Arcing Shot",
	"Suppressive Fire",
	"Fortify",
	"Heavy Rain",
	"Web Field"
]

# Persistent UI/settings
var current_zoom_index: int
var first_enemy_spawn_done: bool

# Reset all memory between matches
func reset_data() -> void:
	coins = 0
	xp = 0
	current_level = 1
	unit_upgrades.clear()
	selected_special_ability = ""

# Configuration persistence
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

# Manage unit upgrades
func add_upgrade(unit_id: int, upgrade_name: String) -> void:
	# Ensure an array exists for this unit_id
	if not unit_upgrades.has(unit_id) or typeof(unit_upgrades[unit_id]) != TYPE_ARRAY:
		unit_upgrades[unit_id] = []
	unit_upgrades[unit_id].append(upgrade_name)

func get_upgrades(unit_id: int) -> Array:
	return unit_upgrades.get(unit_id, [])

func clear_unit_upgrades(unit_id: int) -> void:
	unit_upgrades.erase(unit_id)

func clear_all_upgrades() -> void:
	unit_upgrades.clear()
