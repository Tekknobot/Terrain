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
var unit_special: Dictionary = {}      # unit_id -> String
var unit_upgrades: Dictionary = {}     # unit_id -> Array[String]

# ─────────────────────────────────────────────────────────────────────────────
# UI / settings
# ─────────────────────────────────────────────────────────────────────────────
var selected_special_ability: String = ""
var current_zoom_index: int = 0
var first_enemy_spawn_done: bool = false
var next_unit_id := 1

var in_upgrade_phase: bool = false
var enemy_upgraded : bool = false

#-------------------------------------
var next_region_scene: PackedScene = null
var title_scene := "res://Scenes/TitleScreen.tscn"
var map_scene   := "res://Scenes/Main.tscn"

# Roster & squad
var roster_units: Array = []      # (not used by loader; kept if you want to cache)
var selected_squad: Array = []
const max_squad_size := 3

# Add this near the top of your script
var roster_portraits: Array = [
	"res://Sprites/Portraits/pilots/mek_portraits/m1.png", # Vanguard
	"res://Sprites/Portraits/pilots/mek_portraits/m2.png", # Aegis
	"res://Sprites/Portraits/pilots/mek_portraits/r1.png", # Tempest
	"res://Sprites/Portraits/pilots/mek_portraits/r2.png", # Titan
	"res://Sprites/Portraits/pilots/mek_portraits/r3.png", # Specter
	"res://Sprites/Portraits/pilots/mek_portraits/r4.png", # Nova
	"res://Sprites/Portraits/pilots/mek_portraits/s2.png", # Raptor
	"res://Sprites/Portraits/pilots/mek_portraits/s3.png", # Valkyrie
]
# ▶ NEW: exact prefabs chosen on SquadSelect, stored as scene paths
var selected_squad_paths: Array[String] = []

func set_selected_squad_from_prefabs(prefabs: Array[PackedScene]) -> void:
	selected_squad_paths.clear()
	for p in prefabs:
		if p and p.resource_path != "":
			selected_squad_paths.append(p.resource_path)

func clear_selected_squad_paths() -> void:
	selected_squad_paths.clear()


func get_roster() -> Array:
	var roster: Array = []

	var roots := [
		"res://Scenes/Meks_Scenes/PLAYER",
		"res://Prefabs/Units",
	]

	var scene_paths: Array[String] = []
	for root in roots:
		if DirAccess.dir_exists_absolute(root):
			_collect_scene_files_recursive(root, scene_paths)
		else:
			print("⚠️ Folder not found:", root)

	print("🔎 Found scene files:", scene_paths.size())
	for p in scene_paths:
		print(" •", p)

	var idx := 0
	for scene_path in scene_paths:
		var packed: PackedScene = load(scene_path)
		if packed == null:
			print("❌ Could not load:", scene_path)
			continue

		var inst := packed.instantiate()
		if inst == null:
			print("❌ Could not instantiate:", scene_path)
			continue

		var name_val = inst.get("unit_name")
		if name_val == null:
			name_val = scene_path.get_file().get_basename()

		var level_val = inst.get("level"); if level_val == null: level_val = 1
		var hp_val = inst.get("health"); if hp_val == null: hp_val = 100
		var max_hp_val = inst.get("max_health"); if max_hp_val == null: max_hp_val = hp_val

		# Get portrait from your array (if within range)
		var portrait_path: String = ""
		if idx < roster_portraits.size():
			portrait_path = roster_portraits[idx]
		idx += 1

		roster.append({
			"unit_name": String(name_val),
			"level": int(level_val),
			"health": int(hp_val),
			"max_health": int(max_hp_val),
			"portrait": portrait_path,
			"scene_path": scene_path
		})

		inst.queue_free()

	print("✅ Roster size:", roster.size())
	return roster

func _collect_scene_files_recursive(path: String, out_paths: Array) -> void:
	var files := DirAccess.get_files_at(path)
	for f in files:
		if f.ends_with(".tscn") or f.ends_with(".scn"):
			out_paths.append(path.path_join(f))

	var dirs := DirAccess.get_directories_at(path)
	for d in dirs:
		if d == "." or d == "..":
			continue
		_collect_scene_files_recursive(path.path_join(d), out_paths)

# ─────────────────────────────────────────────────────────────────────────────
# Run / map flow helpers
# ─────────────────────────────────────────────────────────────────────────────
func set_selected_squad(squad: Array) -> void:
	selected_squad = squad

func start_new_run(initial_squad: Array) -> void:
	play_reset()
	carryover_units = initial_squad.duplicate(true)
	get_tree().change_scene_to_file(map_scene)

func on_map_won() -> void:
	advance_level()
	get_tree().change_scene_to_file(map_scene)

# ─────────────────────────────────────────────────────────────────────────────
# Resets / settings
# ─────────────────────────────────────────────────────────────────────────────
func full_reset() -> void:
	pass

func play_reset() -> void:
	current_level = 1
	max_enemy_units = 1
	map_difficulty = 1
	unit_upgrades.clear()
	first_enemy_spawn_done = false
	next_unit_id = 1

func advance_level() -> void:
	current_level += 1
	max_enemy_units += 1
	first_enemy_spawn_done = false

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
# Specials / upgrades
# ─────────────────────────────────────────────────────────────────────────────
func set_unit_special(unit_id: int, ability_name: String) -> void:
	unit_special[unit_id] = ability_name

func get_unit_special(unit_id: int) -> String:
	return unit_special.get(unit_id, "")

func clear_unit_special(unit_id: int) -> void:
	unit_special.erase(unit_id)

func add_upgrade(unit_id: int, upgrade_name: String) -> void:
	if not unit_upgrades.has(unit_id) or typeof(unit_upgrades[unit_id]) != TYPE_ARRAY:
		unit_upgrades[unit_id] = []
	unit_upgrades[unit_id].append(upgrade_name)

func get_upgrades(unit_id: int) -> Array:
	var ups = unit_upgrades.get(unit_id, [])
	if typeof(ups) == TYPE_ARRAY:
		return ups
	return [str(ups)]

func clear_unit_upgrades(unit_id: int) -> void:
	unit_upgrades.erase(unit_id)

func clear_all_upgrades() -> void:
	unit_upgrades.clear()

func clear_enemy_upgrades() -> void:
	for u in get_tree().get_nodes_in_group("Units"):
		if not u.is_player and u.has_meta("unit_id"):
			clear_unit_upgrades(u.get_meta("unit_id"))

func mark_map_completed(map_id: int) -> void:
	if map_id in completed_maps:
		return
	completed_maps.append(map_id)

func is_map_completed(map_id: int) -> bool:
	return map_id in completed_maps
