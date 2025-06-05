# GameData.gd
extends Node

var coins: int = 0
var xp: int = 0
var current_level: int = 1
var selected_upgrade: String = ""
var selected_special_ability: String = ""
var max_enemy_units: int = 2

var map_difficulty: int = 1

# Track unit upgrades by unit name.
var unit_upgrades: Dictionary = {}

# Flag to mark if the first enemy spawn for this level has been performed.
var first_enemy_spawn_done: bool = false

var current_zoom_index: int = 0
var available_abilities: Array[String] = [
	"Ground Slam",       # Hulk
	"Mark & Pounce",     # Panther
	"Guardian Halo",     # Angel
	"High Arcing Shot",  # Cannon
	"Suppressive Fire",  # Multi Turret
	"Fortify",           # Brute
	"Heavy Rain",    # Helicopter
	"Web Field"          # Spider
]

var multiplayer_mode = false

# Reset all persistent data to the defaults.
func reset_data() -> void:
	coins = 0
	xp = 0
	current_level = 1
	selected_upgrade = ""
	selected_special_ability = ""
	unit_upgrades.clear()
	available_abilities.clear()
	first_enemy_spawn_done = false

func add_coins(amount: int) -> void:
	coins += amount

func add_xp(amount: int) -> void:
	xp += amount

func advance_level() -> void:
	current_level += 1
	# Reset the first enemy spawn flag for the new level.
	first_enemy_spawn_done = false

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("Camera", "zoom_index", current_zoom_index)
	var err = cfg.save("user://settings.cfg")
	if err != OK:
		push_error("Failed to save settings: %s" % str(err))
	else:
		print("Settings saved successfully.")

func load_settings() -> void:
	print("Loading settings from user://settings.cfg...")
	var cfg = ConfigFile.new()
	var err = cfg.load("user://settings.cfg")
	if err == OK:
		if cfg.has_section_key("Camera", "zoom_index"):
			current_zoom_index = cfg.get_value("Camera", "zoom_index")
			print("Loaded zoom index:", current_zoom_index)
		else:
			print("Camera zoom_index not found in settings. Using default.")
			current_zoom_index = 0
	else:
		print("Failed to load settings; using default values.")
		current_zoom_index = 0

# -------------------------------------------------
# This RPC will be called on **every** peer (server + clients).
# Its job is to replicate “unit_to_upgrade = upgrade_name” onto local GameData.
# -------------------------------------------------
@rpc
func client_set_upgrade(unit_name: String, upgrade_name: String) -> void:
	GameData.unit_upgrades[unit_name] = upgrade_name

@rpc
func client_receive_all_upgrades(upgrades: Dictionary) -> void:
	print("[Client] ▶ client_receive_all_upgrades() called with: ", upgrades)
	unit_upgrades = upgrades.duplicate()
