# TileMap.gd
extends TileMap

# ———————————————————————————————————————————————————————————————
# CONSTANTS
# ———————————————————————————————————————————————————————————————
const INTERSECTION = 12
const DOWN_RIGHT_ROAD = 14
const DOWN_LEFT_ROAD = 13

const MOVE_SPEED := 100.0  # pixels/sec

# ———————————————————————————————————————————————————————————————
# EXPORTS
# ———————————————————————————————————————————————————————————————
@export var grid_width: int = 10
@export var grid_height: int = 20

@export var water_threshold := -0.65
@export var sandstone_threshold := -0.2
@export var dirt_threshold := 0.1
@export var grass_threshold := 0.4
@export var snow_threshold := 0.7

@export var water_tile_id := 6
@export var sandstone_tile_id := 10
@export var dirt_tile_id := 7
@export var grass_tile_id := 8
@export var snow_tile_id := 9
@export var ice_tile_id := 11

@export var player_units: Array[PackedScene]
@export var enemy_units: Array[PackedScene]

@export var map_details: Label
@export var highlight_tile_id := 5
@export var attack_tile_id := 3

@export var structure_scenes: Array[PackedScene]
@export var max_structures: int = 10

@export var reset_button: Button
@export var menu_button: Button
@export var endturn_button: Button
@export var ability_button: Button

# ———————————————————————————————————————————————————————————————
# SIGNALS
# ———————————————————————————————————————————————————————————————
signal unit_selected(selected_unit)
signal units_spawned

# ———————————————————————————————————————————————————————————————
# MEMBER VARIABLES
# ———————————————————————————————————————————————————————————————
var noise := FastNoiseLite.new()
var tile_size: Vector2

var selected_unit: Node2D = null
var highlighted_tiles := []
var showing_attack := false

var astar := AStarGrid2D.new()
var grid_actual_width: int
var grid_actual_height: int

var current_path := []
var moving := false

var attack_sound = preload("res://Audio/SFX/attack_default.wav")
var beep_sound = preload("res://Audio/SFX/Retro Beeep 06.wav")
var splash_sound = preload("res://Audio/SFX/water-splash-199583.mp3")

var all_units: Array[Node2D]
var current_unit_index := 0
var planning_phase := true
var planned_units := 0
var completed_units

var hold_time: float = 0.0
var borders_visible := false

var next_structure_id: int = 1
var next_unit_id: int = 1

var critical_strike_mode: bool = false
var rapid_fire_mode: bool = false
var healing_wave_mode: bool = false
var overcharge_attack_mode: bool = false
var explosive_rounds_mode: bool = false
var spider_blast_mode: bool = false
var thread_attack_mode: bool = false
var lightning_surge_mode: bool = false

var ground_slam_mode: bool = false
var mark_and_pounce_mode: bool = false
var guardian_halo_mode: bool = false
var high_arcing_shot_mode: bool = false
var suppressive_fire_mode: bool = false
var fortify_mode: bool = false
var heavy_rain_mode: bool = false
var web_field_mode: bool = false

var suppressive_fire_dir: Vector2i = Vector2i.ZERO

var helicopter_phase: int = 0
var chosen_airlift_unit: Node = null
var chosen_airlift_dest: Vector2i = Vector2i(-1, -1)
var helicopter_bomb_tile: Vector2i = Vector2i(-1, -1)

var stored_map_data: Dictionary = {}
var stored_unit_data: Array = []
var stored_structure_data: Array = []

var all_player_units: Array[Node2D] = []
var finished_player_units: Array[Node2D] = []

var difficulty_tiers: Dictionary = {
	1: "Novice", 2: "Apprentice", 3: "Adept", 4: "Expert",
	5: "Master", 6: "Grandmaster", 7: "Legendary", 8: "Mythic",
	9: "Transcendent", 10: "Celestial", 11: "Divine", 12: "Omnipotent",
	13: "Ascendant", 14: "Ethereal", 15: "Supreme", 16: "Sovereign",
	17: "Infallible", 18: "Immortal", 19: "Omniscient", 20: "Absolute",
	21: "Unstoppable", 22: "Cosmic", 23: "Infinite", 24: "Ultimate"
}

var ability_ranges: Dictionary = {
	"Critical Strike":     2,
	"Rapid Fire":          3,
	"Healing Wave":        2,
	"Overcharge Attack":   3,
	"Explosive Rounds":    4,
	"Spider Blast":        3,
	"Thread Attack":       2,
	"Lightning Surge":     4,
	"Ground Slam":         1,
	"Mark & Pounce":       3,
	"Guardian Halo":       5,
	"High Arcing Shot":    5,
	"Suppressive Fire":    0,
	"Fortify":             0,  # “Fortify” might not highlight anything; adjust as needed
	"Heavy Rain":          5,
	"Web Field":           0
}

var next_spawn_index := 0   # Tracks which index of `units[]` to take next.

# ———————————————————————————————————————————————————————————————
# LIFECYCLE CALLBACKS
# ———————————————————————————————————————————————————————————————
func _ready():
	if is_multiplayer_authority():
		get_tree().get_multiplayer().connect("peer_connected", Callable(self, "_on_peer_connected"))
			
	tile_size = get_tileset().tile_size
	_setup_noise()

	# Connect to HUD
	var hud = get_node("/root/BattleGrid/HUDLayer/Control")
	connect("unit_selected", Callable(hud, "_on_unit_selected"))

	# Listen globally for Units that die:
	get_tree().connect("node_removed", Callable(self, "_on_node_removed"))
	

	if is_multiplayer_authority():
		_generate_map()
		call_deferred("_post_map_generation")
	else:
		clear_map()

	print("My peer ID is: ", get_tree().get_multiplayer().get_unique_id())
	if is_multiplayer_authority():
		print("→ I am the server")
	else:
		print("→ I am a client")
		
	# If I’m a client (not the authority), “force‐assign” ability names here:
	if not is_multiplayer_authority():
		# Wait one frame so that all Units have spawned
		await get_tree().process_frame

		var units = get_tree().get_nodes_in_group("Units")
		for i in range(units.size()):
			var unit = units[i]
			var uid = unit.unit_id

			# Cycle through the 8 abilities repeatedly:
			var ability_name = GameData.available_abilities[i % GameData.available_abilities.size()]
			GameData.unit_upgrades[uid] = ability_name

		print("[Client] → seeded unit_upgrades:", GameData.unit_upgrades)


func _process(delta):
	if selected_unit and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		hold_time += delta
		if hold_time >= 1.0:
			showing_attack = not showing_attack
			_update_highlight_display()
			hold_time = 0.0
	else:
		hold_time = 0.0

	if GameData.multiplayer_mode:
		map_details.text = "Multiplayer Mode"

func _physics_process(delta):
	if moving and selected_unit:
		var next_tile = current_path[0]
		var world_pos = to_global(map_to_local(next_tile)) + Vector2(0, selected_unit.Y_OFFSET)

		var sprite = selected_unit.get_node("AnimatedSprite2D")
		sprite.play("move")
		sprite.flip_h = world_pos.x > selected_unit.global_position.x

		var dir = (world_pos - selected_unit.global_position).normalized()
		selected_unit.global_position += dir * MOVE_SPEED * delta

		if selected_unit.global_position.distance_to(world_pos) < 2:
			selected_unit.global_position = world_pos
			selected_unit.tile_pos = next_tile
			
			update_astar_grid()
			
			current_path.remove_at(0)
			if current_path.is_empty():
				moving = false
				sprite.play("default")
				selected_unit.has_moved = true

# ———————————————————————————————————————————————————————————————
# MAP INITIALIZATION & IMPORT/EXPORT
# ———————————————————————————————————————————————————————————————
func clear_map() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			set_cell(0, Vector2i(x, y), -1)
	print("Map cleared – waiting for host data.")

func _generate_map():
	for x in range(grid_width):
		for y in range(grid_height):
			var n = noise.get_noise_2d(x, y)
			var tile_id = _get_tile_id_from_noise(n)
			set_cell(0, Vector2i(x, y), tile_id, Vector2i.ZERO)
	_generate_roads()
	map_details.text = difficulty_tiers[GameData.map_difficulty]

func _get_tile_id_from_noise(n: float) -> int:
	if n < water_threshold:
		return water_tile_id
	elif n < sandstone_threshold:
		return sandstone_tile_id
	elif n < dirt_threshold:
		return dirt_tile_id
	elif n < grass_threshold:
		return grass_tile_id
	elif n < snow_threshold:
		return snow_tile_id
	return ice_tile_id

func _generate_roads():
	var used_h := []
	var used_v := []
	for i in range(2):
		var hy = _get_unique_random_odd(grid_height, used_h)
		draw_road(Vector2i(0, hy), Vector2i(1, 0), DOWN_RIGHT_ROAD)
		var vx = _get_unique_random_odd(grid_width, used_v)
		draw_road(Vector2i(vx, 0), Vector2i(0, 1), DOWN_LEFT_ROAD)

func draw_road(start: Vector2i, direction: Vector2i, road_id: int):
	var pos = start
	while pos.x in range(grid_width) and pos.y in range(grid_height):
		var current = get_cell_source_id(0, pos)
		if current == DOWN_LEFT_ROAD or current == DOWN_RIGHT_ROAD:
			set_cell(0, pos, INTERSECTION, Vector2i.ZERO)
		else:
			set_cell(0, pos, road_id, Vector2i.ZERO)
		pos += direction

func _get_unique_random_odd(limit: int, used: Array) -> int:
	for i in range(20):
		var v = randi_range(1, limit - 2)
		if v % 2 == 1 and not used.has(v):
			used.append(v)
			return v
	return 1

func export_map_data() -> Dictionary:
	var data = {
		"grid_width": grid_width,
		"grid_height": grid_height
	}
	var tiles = []
	for x in range(grid_width):
		var col = []
		for y in range(grid_height):
			col.append(get_cell_source_id(0, Vector2i(x, y)))
		tiles.append(col)
	data["tiles"] = tiles
	return data

func import_map_data(data: Dictionary) -> void:
	grid_width  = data.get("grid_width", grid_width)
	grid_height = data.get("grid_height", grid_height)

	var tiles = data.get("tiles", [])
	if tiles.size() != grid_width:
		push_error("Tile data width mismatch! Expected %d columns but got %d." % [grid_width, tiles.size()])
		return

	for x in range(grid_width):
		for y in range(grid_height):
			set_cell(0, Vector2i(x, y), -1)

	for x in range(grid_width):
		var column = tiles[x]
		if column.size() != grid_height:
			push_error("Tile data height mismatch at column %d! Expected %d rows but got %d." % [x, grid_height, column.size()])
			continue
		for y in range(grid_height):
			var tile_id = column[y]
			set_cell(0, Vector2i(x, y), tile_id, Vector2i.ZERO)

	print("Map successfully imported: %d×%d" % [grid_width, grid_height])

# ———————————————————————————————————————————————————————————————
# Rebuild the A* grid so that any walkability changes (e.g. moved units/structures)
# are taken into account. Call this whenever tiles or unit/structure positions change.
# ———————————————————————————————————————————————————————————————
func update_astar_grid() -> void:
	grid_actual_width = grid_width
	grid_actual_height = grid_height
	astar.clear()
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.size = Vector2i(grid_actual_width, grid_actual_height)

	for x in range(grid_actual_width):
		for y in range(grid_actual_height):
			var pos = Vector2i(x, y)
			var blocked = (not _is_tile_walkable(pos)) or is_tile_occupied(pos)
			astar.set_point_solid(pos, blocked)

	astar.update()
	print("✅ AStar grid rebuilt — occupied tiles excluded.")

# ———————————————————————————————————————————————————————————————
# TEAM & UNIT SPAWNING
# ———————————————————————————————————————————————————————————————
func _post_map_generation():
	_spawn_teams()
	spawn_structures()
	_setup_camera()
	update_astar_grid()

	# ─── PRINT EVERY UNIT’S ID & ASSIGN LOOPED ABILITIES ───────────────────
	var num_abilities = GameData.available_abilities.size()
	var all_units = get_tree().get_nodes_in_group("Units")
	for i in range(all_units.size()):
		var that_unit = all_units[i]
		var id = that_unit.unit_id
		# wrap i around 0…num_abilities-1
		var ability_index = i % num_abilities
		var ability = GameData.available_abilities[ability_index]
		GameData.unit_upgrades[id] = ability
		print("[Server]  mapping ability:", ability, "→ unit_id:", id)
	# ────────────────────────────────────────────────────────

	TurnManager.start_turn()
	TurnManager.transition_to_level()

	if is_multiplayer_authority():
		GameState.stored_map_data = export_map_data()
		GameState.stored_unit_data = export_unit_data()
		GameState.stored_structure_data = export_structure_data()
		broadcast_game_state()

@rpc
func receive_game_state(map_data: Dictionary, unit_data: Array, structure_data: Array) -> void:
	# 1) Reconstruct exactly as the host did:
	_generate_client_map(map_data, unit_data, structure_data)
	print("Client map and state rebuilt.")
	
	# 2) Override peer_id for every enemy unit so the client truly owns them:
	var my_id = get_tree().get_multiplayer().get_unique_id()
	for u in get_tree().get_nodes_in_group("Units"):
		if not u.is_player:
			u.peer_id = my_id
			u.set_meta("peer_id", my_id)
	
	# 3) Mirror the host’s ability assignment (unchanged):
	var all_units = get_tree().get_nodes_in_group("Units")
	for i in range(all_units.size()):
		var unit = all_units[i]
		var uid = unit.unit_id
		var ability_name = ""
		if i < GameData.available_abilities.size():
			ability_name = GameData.available_abilities[i]
		GameData.unit_upgrades[uid] = ability_name
	print("[Client] forced GameData.unit_upgrades =", GameData.unit_upgrades)
	
	# 4) Finally switch to the Main scene:
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")


func _spawn_teams():
	var used_tiles: Array[Vector2i] = []
	_spawn_side(player_units, grid_height - 1, true, used_tiles)
	next_spawn_index = 0
	_spawn_side(enemy_units, 0, false, used_tiles)

func _spawn_side(units: Array[PackedScene], row: int, is_player: bool, used_tiles: Array[Vector2i]) -> void:
	# 1) Decide how many to spawn: 4 at level 1, +1 per extra level.
	var base := 4
	var raw_spawn = base + max(GameData.current_level - 1, 0)

	# Cap player spawns at 8 without using a ternary
	var total_to_spawn = raw_spawn
	if is_player:
		total_to_spawn = min(raw_spawn, 8)
		
	var count := units.size()
	if count == 0:
		return  # nothing to spawn

	# 2) Build chosen_scenes[] by cycling through `units[]` in order:
	var chosen_scenes := []
	for i in range(total_to_spawn):
		var idx := (next_spawn_index + i) % count
		chosen_scenes.append(units[idx])
	# After picking them, advance next_spawn_index by total_to_spawn (wrapped):
	next_spawn_index = (next_spawn_index + total_to_spawn) % count

	# 3) Compute horizontal offsets so they’re centered in a block:
	var spawn_count := chosen_scenes.size()
	var start_x := int((grid_width - spawn_count) / 2)

	for i in range(spawn_count):
		var scene_to_spawn = chosen_scenes[i]
		var x = clamp(start_x + i, 0, grid_width - 1)
		var spawn_tile := Vector2i(x, row)

		# 4) If that tile is invalid (out of bounds / water / occupied), find nearest land:
		spawn_tile = _find_nearest_land(spawn_tile, used_tiles)
		if spawn_tile == Vector2i(-1, -1):
			# Could not find a valid spot → skip.
			continue

		# 5) Instantiate and configure the unit:
		var unit_instance = scene_to_spawn.instantiate()
		unit_instance.global_position = to_global(map_to_local(spawn_tile)) + Vector2(0, unit_instance.Y_OFFSET)
		unit_instance.set_team(is_player)
		unit_instance.add_to_group("Units")
		unit_instance.tile_pos = spawn_tile

		unit_instance.unit_id = next_unit_id
		unit_instance.set_meta("unit_id", next_unit_id)
		next_unit_id += 1

		unit_instance.peer_id = get_tree().get_multiplayer().get_unique_id()
		unit_instance.set_meta("peer_id", unit_instance.peer_id)

		unit_instance.set_meta("scene_path", scene_to_spawn.resource_path)
		add_child(unit_instance)
		if is_player:
			var sprite = unit_instance.get_node_or_null("AnimatedSprite2D")
			if sprite:
				sprite.flip_h = true

		used_tiles.append(spawn_tile)
		print("Spawned unit ", unit_instance.name,
			  " at tile: ", spawn_tile,
			  " (team=", is_player, "), unit_id=", unit_instance.unit_id)
	# end for
	
func _spawn_unit(scene: PackedScene, tile: Vector2i, is_player: bool, used_tiles: Array[Vector2i]) -> void:
	var spawn_tile = _find_nearest_land(tile, used_tiles)
	if spawn_tile == Vector2i(-1, -1):
		print("⚠ No valid land tile found for unit near ", tile)
		return

	var unit_instance = scene.instantiate()
	unit_instance.global_position = to_global(map_to_local(spawn_tile)) + Vector2(0, unit_instance.Y_OFFSET)
	unit_instance.set_team(is_player)
	unit_instance.add_to_group("Units")
	unit_instance.tile_pos = spawn_tile

	unit_instance.unit_id = next_unit_id
	unit_instance.set_meta("unit_id", next_unit_id)
	next_unit_id += 1

	unit_instance.peer_id = get_tree().get_multiplayer().get_unique_id()
	unit_instance.set_meta("peer_id", unit_instance.peer_id)

	unit_instance.set_meta("scene_path", scene.resource_path)
	add_child(unit_instance)
	if is_player:
		var sprite = unit_instance.get_node_or_null("AnimatedSprite2D")
		if sprite:
			sprite.flip_h = true

	used_tiles.append(spawn_tile)
	print("Spawned unit ", unit_instance.name, " at tile: ", spawn_tile, " with unique ID: ", unit_instance.unit_id, " and peer id: ", unit_instance.peer_id)

func _find_nearest_land(start: Vector2i, used_tiles: Array[Vector2i]) -> Vector2i:
	var visited = {}
	var queue = [start]
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		if not is_within_bounds(current):
			continue
		if not is_water_tile(current) and not used_tiles.has(current) and not is_tile_occupied(current):
			return current
		visited[current] = true
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor = current + dir
			if is_within_bounds(neighbor) and not visited.has(neighbor):
				queue.append(neighbor)
				visited[neighbor] = true

	push_warning("⚠ No valid land tile found near %s" % str(start))
	return start

func spawn_structures():
	if structure_scenes.size() == 0:
		push_error("No structure scenes available to spawn!")
		return

	var count = 0
	var attempts = 0
	var max_attempts = grid_width * grid_height * 5

	while count < max_structures and attempts < max_attempts:
		attempts += 1
		var x = randi() % grid_width
		var y = randi() % grid_height
		var pos = Vector2i(x, y)
		var tile_id = get_cell_source_id(0, pos)

		if tile_id in [water_tile_id, INTERSECTION, DOWN_RIGHT_ROAD, DOWN_LEFT_ROAD]:
			continue
		if is_tile_occupied(pos):
			continue

		var random_index = randi() % structure_scenes.size()
		var structure_scene = structure_scenes[random_index]
		var structure = structure_scene.instantiate()

		structure.structure_id = next_structure_id
		structure.set_meta("structure_id", next_structure_id)
		next_structure_id += 1

		structure.set_meta("scene_path", structure_scene.resource_path)

		structure.global_position = to_global(map_to_local(pos))
		if structure.has_method("set_tile_pos"):
			structure.set_tile_pos(pos)
		elif structure.has_variable("tile_pos"):
			structure.tile_pos = pos

		var r_val = randf_range(0.4, 0.8)
		var g_val = randf_range(0.4, 0.8)
		var b_val = randf_range(0.4, 0.8)
		structure.modulate = Color(r_val, g_val, b_val, 1)

		structure.add_to_group("Structures")
		add_child(structure)
		astar.set_point_solid(pos, true)

		count += 1

	if count < max_structures:
		print("Spawned only", count, "structures after", attempts, "attempts.")
	else:
		print("Spawned", count, "structures.")

func spawn_new_enemy_units():
	# 1) How many enemies are already on the board?
	var enemy_units_on_board = get_tree().get_nodes_in_group("Units").filter(func(u): return not u.is_player)
	var current_count = enemy_units_on_board.size()
	
	# 2) If we've already reached (or exceeded) the cap, bail out.
	if current_count >= GameData.max_enemy_units:
		print("Max enemy units reached:", current_count)
		return
	
	# 3) Compute “raw” spawn based on current_level, but much slower than (level - 1).
	#    ‣ spawn_rate of 0.5 means “half a unit per level,” floored.
	#    ‣ Guarantee at least 1 spawn until you hit the cap.
	var level = GameData.current_level
	var spawn_rate := 0.5
	var base_spawn := int(floor(level * spawn_rate))
	base_spawn = max(base_spawn, 1)  # always spawn at least 1 enemy, early on
	
	# 4) But do not exceed the remaining slots (max_enemy_units – current_count)
	var slots_left = GameData.max_enemy_units - current_count
	var units_to_spawn = min(base_spawn, slots_left)
	
	# Debug print for clarity:
	print("🆕 Level", level, "→ trying to spawn", base_spawn,
		  "(capped to", units_to_spawn, "by max_enemy_units).")
	
	# 5) Center them along the top row (row = 0) in contiguous X positions
	var used_tiles: Array[Vector2i] = []
	var spawn_row = 0
	var start_x = int((grid_width - units_to_spawn) / 2)
	
	for i in range(units_to_spawn):
		var x = clamp(start_x + i, 0, grid_width - 1)
		var spawn_tile = Vector2i(x, spawn_row)
		
		# If that tile is invalid (off‐map / water / occupied), find nearest valid land
		if not is_within_bounds(spawn_tile) \
		   or is_tile_occupied(spawn_tile) \
		   or is_water_tile(spawn_tile):
		   
			spawn_tile = _find_nearest_land(spawn_tile, used_tiles)
			if spawn_tile == Vector2i(-1, -1):
				# No valid tile found—skip this spawn slot
				print("⚠ Couldn’t find valid land for spawn at X =", x)
				continue
		used_tiles.append(spawn_tile)
		
		# 6) Choose one random PackedScene from your enemy_units array:
		var random_index = randi() % enemy_units.size()
		var enemy_scene = enemy_units[random_index]
		var enemy_unit = enemy_scene.instantiate()
		
		# 7) Mark it as “enemy,” assign tile, group, etc.
		enemy_unit.set_team(false)
		enemy_unit.tile_pos = spawn_tile
		enemy_unit.add_to_group("Units")
		add_child(enemy_unit)
		
		# 8) Drop it in from above (same as before)
		var target_pos = to_global(map_to_local(spawn_tile)) + Vector2(0, enemy_unit.Y_OFFSET)
		var drop_offset = 100.0
		enemy_unit.global_position = target_pos - Vector2(0, drop_offset)
		
		var tween = enemy_unit.create_tween()
		tween.tween_property(enemy_unit, "global_position", target_pos, 0.5) \
			 .set_trans(Tween.TRANS_SINE) \
			 .set_ease(Tween.EASE_OUT)
	# end for
	
	# 9) Rebuild A⋆ so these new enemies act as blockers
	update_astar_grid()

# ———————————————————————————————————————————————————————————————
# CAMERA SETUP
# ———————————————————————————————————————————————————————————————
func _setup_camera():
	await get_tree().process_frame

	var camera_scene = preload("res://Scripts/Camera2D.gd")
	var camera = Camera2D.new()
	camera.set_script(camera_scene)
	get_tree().get_current_scene().add_child(camera)
	camera.make_current()

	var center_tile = Vector2(grid_width * 0.5, grid_height * 0.5)
	camera.global_position = to_global(map_to_local(center_tile))
	print("Camera centered at grid midpoint:", center_tile, "world:", camera.global_position)

# Add these helper functions somewhere above _input(event):
func _peek_show_range_for(unit: Node2D):
	var old_selected = selected_unit
	var old_showing_attack = showing_attack
	
	# Show movement range when peeking
	showing_attack = false
	selected_unit = unit
	_show_range_for_selected_unit()
	_update_hud_with(unit)
	play_beep_sound(unit.tile_pos)

	# Restore previous state
	selected_unit = old_selected
	showing_attack = old_showing_attack


func _peek_show_attack_range_for(unit: Node2D):
	var old_selected = selected_unit
	var old_showing_attack = showing_attack

	# Show attack range when peeking
	showing_attack = true
	selected_unit = unit
	_show_range_for_selected_unit()

	# Restore previous state
	selected_unit = old_selected
	showing_attack = old_showing_attack


func _input(event):
	if moving:
		return

	var turn_team = TurnManager.turn_order[TurnManager.current_turn_index]
	if GameData.multiplayer_mode and turn_team != TurnManager.Team.PLAYER:
		return
				
	# ──────────────────────────────────────────────────────────────────────────
	# If multiplayer, immediately ignore any client‐side clicks
	# when it’s not this peer’s turn. Only allow “peeking” (right‐click) below.
	# ──────────────────────────────────────────────────────────────────────────
	if GameData.multiplayer_mode and event is InputEventMouseButton:
		if is_multiplayer_authority():
			# server only acts on PLAYER’s turn
			if turn_team != TurnManager.Team.PLAYER:
				# Not player’s turn on the server → ignore all LEFT‐clicks/specials.
				# But still let right‐click peeks happen (handled later).
				if event.button_index == MOUSE_BUTTON_LEFT:
					return
		else:
			# client only acts on ENEMY’s turn
			if turn_team != TurnManager.Team.ENEMY:
				if event.button_index == MOUSE_BUTTON_LEFT:
					return

	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_global_mouse_position()
		var mouse_tile = local_to_map(to_local(Vector2(mouse_pos.x, mouse_pos.y + 16)))
		if mouse_tile.x < 0 or mouse_tile.x >= grid_width or mouse_tile.y < 0 or mouse_tile.y >= grid_height:
			return

		if moving:
			return

		# Precompute distance (only if we have a selected_unit)
		var dist := -1
		if selected_unit != null:
			dist = manhattan_distance(selected_unit.tile_pos, mouse_tile)
			
		#
		# === SPECIAL-ABILITY HANDLERS ===
		#
		# First, determine whether it’s “my turn” for the already-selected unit:
		var is_my_turn = false
		if selected_unit != null:
			if selected_unit.is_player:
				is_my_turn = (turn_team == TurnManager.Team.PLAYER)
			else:
				is_my_turn = (turn_team == TurnManager.Team.ENEMY)
		# If selected_unit is still null, is_my_turn remains false.

		if critical_strike_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1) \
			and dist <= selected_unit.attack_range:
				_clear_highlights()
				selected_unit.critical_strike(mouse_tile)
				print("Critical Strike activated by unit:", selected_unit.name)
				critical_strike_mode = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Critical Strike now.")
			return

		if rapid_fire_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.rapid_fire(mouse_tile)
				print("Rapid Fire activated by unit:", selected_unit.name)
				rapid_fire_mode = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Rapid Fire now.")
			return

		if healing_wave_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.healing_wave(mouse_tile)
				print("Healing Wave activated by unit:", selected_unit.name)
				healing_wave_mode = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Healing Wave now.")
			return

		if overcharge_attack_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.overcharge_attack(mouse_tile)
				print("Overcharge attack activated by unit:", selected_unit.name)
				overcharge_attack_mode = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Overcharge Attack now.")
			return

		if explosive_rounds_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.explosive_rounds(mouse_tile)
				print("Explosive Rounds activated by unit:", selected_unit.name)
				explosive_rounds_mode = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Explosive Rounds now.")
			return

		if spider_blast_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.spider_blast(mouse_tile)
				print("Spider Blast activated by unit:", selected_unit.name)
				spider_blast_mode = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Spider Blast now.")
			return

		if thread_attack_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.thread_attack(mouse_tile)
				print("Thread Attack activated by unit:", selected_unit.name)
				thread_attack_mode = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Thread Attack now.")
			return

		if lightning_surge_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.lightning_surge(mouse_tile)
				print("Lightning Surge activated by unit:", selected_unit.name)
				lightning_surge_mode = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Lightning Surge now.")
			return

		if ground_slam_mode:
			if selected_unit and is_my_turn and not selected_unit.has_attacked:
				_clear_highlights()
				if GameData.multiplayer_mode:
					var authority_id = get_multiplayer_authority()
					if get_tree().get_multiplayer().get_unique_id() == authority_id:
						request_ground_slam(selected_unit.unit_id, mouse_tile)
					else:
						rpc_id(authority_id, "request_ground_slam", selected_unit.unit_id, mouse_tile)
				else:
					selected_unit.ground_slam(mouse_tile)
				ground_slam_mode = false
				ability_button.button_pressed = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Ground Slam now.")
				ground_slam_mode = false
				ability_button.button_pressed = false
			return

		if mark_and_pounce_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				var target_unit = get_unit_at_tile(mouse_tile)
				if target_unit and not target_unit.is_player:
					_clear_highlights()
					if GameData.multiplayer_mode:
						var authority_id = get_multiplayer_authority()
						if get_tree().get_multiplayer().get_unique_id() == authority_id:
							request_mark_and_pounce(selected_unit.unit_id, target_unit.unit_id)
						else:
							rpc_id(authority_id, "request_mark_and_pounce", selected_unit.unit_id, target_unit.unit_id)
					else:
						selected_unit.mark_and_pounce(target_unit)
					print("Mark & Pounce activated by unit:", selected_unit.name, "on target:", target_unit.name)
					mark_and_pounce_mode = false
					ability_button.button_pressed = false
					GameData.selected_special_ability = ""
				else:
					print("No valid enemy at that tile for Mark & Pounce.")
					mark_and_pounce_mode = false
					ability_button.button_pressed = false
			else:
				print("Cannot perform Mark & Pounce now.")
				mark_and_pounce_mode = false
				ability_button.button_pressed = false
			return

		if guardian_halo_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				if GameData.multiplayer_mode:
					var authority_id = get_multiplayer_authority()
					if get_tree().get_multiplayer().get_unique_id() == authority_id:
						request_guardian_halo(selected_unit.unit_id, mouse_tile)
					else:
						rpc_id(authority_id, "request_guardian_halo", selected_unit.unit_id, mouse_tile)
				else:
					selected_unit.guardian_halo(mouse_tile)
				print("Guardian Halo activated by unit:", selected_unit.name)
				guardian_halo_mode = false
				ability_button.button_pressed = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Guardian Halo now.")
				guardian_halo_mode = false
				ability_button.button_pressed = false
			return

		if high_arcing_shot_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				if GameData.multiplayer_mode:
					var authority_id = get_multiplayer_authority()
					if get_tree().get_multiplayer().get_unique_id() == authority_id:
						request_high_arcing_shot(selected_unit.unit_id, mouse_tile)
					else:
						rpc_id(authority_id, "request_high_arcing_shot", selected_unit.unit_id, mouse_tile)
				else:
					selected_unit.high_arcing_shot(mouse_tile)
				print("High Arcing Shot activated by unit:", selected_unit.name)
				high_arcing_shot_mode = false
				ability_button.button_pressed = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform High Arcing Shot now.")
				high_arcing_shot_mode = false
				ability_button.button_pressed = false
			return

		if suppressive_fire_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				var dir = mouse_tile - selected_unit.tile_pos
				dir.x = sign(dir.x)
				dir.y = sign(dir.y)
				if GameData.multiplayer_mode:
					var authority_id = get_multiplayer_authority()
					if get_tree().get_multiplayer().get_unique_id() == authority_id:
						request_suppressive_fire(selected_unit.unit_id, dir)
					else:
						rpc_id(authority_id, "request_suppressive_fire", selected_unit.unit_id, dir)
				else:
					selected_unit.suppressive_fire(dir)
				print("Suppressive Fire activated by unit:", selected_unit.name, "dir:", dir)
				suppressive_fire_mode = false
				ability_button.button_pressed = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Suppressive Fire now.")
				suppressive_fire_mode = false
				ability_button.button_pressed = false
			return

		if fortify_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				if GameData.multiplayer_mode:
					var authority_id = get_multiplayer_authority()
					if get_tree().get_multiplayer().get_unique_id() == authority_id:
						request_fortify(selected_unit.unit_id)
					else:
						rpc_id(authority_id, "request_fortify", selected_unit.unit_id)
				else:
					selected_unit.fortify(mouse_tile)
				print("Fortify activated by unit:", selected_unit.name)
				fortify_mode = false
				ability_button.button_pressed = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Fortify now.")
				fortify_mode = false
				ability_button.button_pressed = false
			return

		if heavy_rain_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				if GameData.multiplayer_mode:
					var authority_id = get_multiplayer_authority()
					if get_tree().get_multiplayer().get_unique_id() == authority_id:
						request_heavy_rain(selected_unit.unit_id, mouse_tile)
					else:
						rpc_id(authority_id, "request_heavy_rain", selected_unit.unit_id, mouse_tile)
				else:
					selected_unit.spider_blast(mouse_tile)
				print("Spider Blast (formerly Web Field) activated by unit:", selected_unit.name)
				heavy_rain_mode = false
				ability_button.button_pressed = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Spider Blast (Heavy Rain) now.")
				heavy_rain_mode = false
				ability_button.button_pressed = false
			return

		if web_field_mode:
			if selected_unit and is_my_turn \
			and not selected_unit.has_attacked \
			and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				if GameData.multiplayer_mode:
					var authority_id = get_multiplayer_authority()
					if get_tree().get_multiplayer().get_unique_id() == authority_id:
						request_thread_attack(selected_unit.unit_id, mouse_tile)
					else:
						rpc_id(authority_id, "request_thread_attack", selected_unit.unit_id, mouse_tile)
				else:
					selected_unit.thread_attack(mouse_tile)
				print("Web Field (Thread Attack) activated by unit:", selected_unit.name)
				web_field_mode = false
				ability_button.button_pressed = false
				GameData.selected_special_ability = ""
			else:
				print("Cannot perform Web Field (Thread Attack) now.")
				web_field_mode = false
				ability_button.button_pressed = false
			return

		#
		# === NORMAL MOVEMENT / ATTACK / SELECTION ===
		#
		if event.button_index == MOUSE_BUTTON_LEFT:
			if selected_unit and is_instance_valid(selected_unit):
				# 1) compute “is it actually this unit’s turn?”
				var is_player_turn = (turn_team == TurnManager.Team.PLAYER)
				var is_enemy_turn  = (turn_team == TurnManager.Team.ENEMY)
				var can_act    = (is_player_turn and selected_unit.is_player) \
							   or (is_enemy_turn  and not selected_unit.is_player)

				# ── NEW “unit_owner vs. my_id” check ──
				var unit_owner = selected_unit.peer_id
				var my_id      = get_tree().get_multiplayer().get_unique_id()
				if unit_owner != my_id:
					can_act = false

				var not_tinted  = (selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1))

				# 2) attack logic (only if can_act AND showing_attack)
				if not_tinted and can_act and showing_attack:
					var enemy     = get_unit_at_tile(mouse_tile)
					var structure = get_structure_at_tile(mouse_tile)

					# ─────────── RANGED LOGIC ───────────
					if selected_unit.unit_type in ["Ranged", "Support"]:
						if enemy \
						and manhattan_distance(selected_unit.tile_pos, enemy.tile_pos) <= selected_unit.attack_range:
							var server = get_multiplayer_authority()
							request_auto_attack_ranged_unit(selected_unit.unit_id, enemy.unit_id)
							selected_unit.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)
							showing_attack = false
							_clear_highlights()
							return
						elif structure and manhattan_distance(selected_unit.tile_pos, structure.tile_pos) <= selected_unit.attack_range:
							var server = get_multiplayer_authority()
							var tpos = structure.tile_pos
							request_auto_attack_ranged_structure(selected_unit.unit_id, tpos)
							selected_unit.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)
							showing_attack = false
							_clear_highlights()
							return
						elif not enemy and not structure \
							 and manhattan_distance(selected_unit.tile_pos, mouse_tile) <= selected_unit.attack_range:
							var server = get_multiplayer_authority()
							request_auto_attack_ranged_empty(selected_unit.unit_id, mouse_tile)
							selected_unit.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)
							showing_attack = false
							_clear_highlights()
							return
					# ─────────── MELEE LOGIC ───────────
					else:
						if enemy and enemy.is_player != selected_unit.is_player \
						and manhattan_distance(selected_unit.tile_pos, enemy.tile_pos) == 1:
							if GameData.multiplayer_mode:
								var server_id = get_multiplayer_authority()
								rpc_id(server_id, "request_auto_attack_adjacent", selected_unit.unit_id, enemy.unit_id)
								if is_multiplayer_authority():
									request_auto_attack_adjacent(selected_unit.unit_id, enemy.unit_id)
								else:
									# client‐side prediction
									selected_unit.has_moved = true
									showing_attack = false
									_clear_highlights()
									var anim = selected_unit.get_node("AnimatedSprite2D")
									anim.play("attack")
									play_attack_sound(to_global(map_to_local(enemy.tile_pos)))
							else:
								selected_unit.auto_attack_adjacent()
								var anim = selected_unit.get_node("AnimatedSprite2D")
								anim.play("attack")
								selected_unit.has_moved = true
								showing_attack = false
								_clear_highlights()
								play_attack_sound(to_global(map_to_local(enemy.tile_pos)))
							return
					# end melee

				if selected_unit.being_pushed:
					return
					
				# 3) movement logic – only if we are in “movement‐range shown” mode
				if not showing_attack and not selected_unit.has_moved and can_act:
					if highlighted_tiles.size() > 0 \
					and highlighted_tiles.has(mouse_tile) \
					and dist <= selected_unit.movement_range:
						_move_selected_to(mouse_tile)
						var sprite = selected_unit.get_node("AnimatedSprite2D")
						sprite.self_modulate = Color(1, 0.6, 0.6, 1)
						return

				# 4) if it wasn’t a valid attack or move, but it’s still that unit’s turn, show range
				if not_tinted and can_act and showing_attack == false:
					# (nothing special here—just fall through to selection if they aren’t trying to move)
					pass
				# 5) if it’s not that unit’s turn, show its range anyway (peeking)
				elif not_tinted and can_act == false:
					_show_range_for_selected_unit()
					return
			# end if selected_unit

			# 6) if we didn’t attack or move, check for an enemy‐peek click
			var click_unit = get_unit_at_tile(mouse_tile)
			if click_unit and click_unit.is_player == false:
				_clear_highlights()
				_peek_show_range_for(click_unit)
				return

			# 7) otherwise, select a new unit (or clear selection)
			_select_unit_at_mouse()


		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# If we have a selected_unit, behave as before (show its attack range)
			if selected_unit:
				showing_attack = true
				_clear_highlights()
				_show_range_for_selected_unit()
				return

			# If no selected_unit, but right-clicked on an enemy, peek its attack range
			var click_unit = get_unit_at_tile(mouse_tile)
			if click_unit and click_unit.is_player == false:
				_clear_highlights()
				_peek_show_attack_range_for(click_unit)
				return

			# Otherwise, ignore (no change in selection)

# ———————————————————————————————————————————————————————————————
# AUTO-ATTACK RPCS
# ———————————————————————————————————————————————————————————————
@rpc("any_peer", "reliable")
func request_auto_attack_ranged_unit(attacker_id: int, target_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	var tgt = get_unit_by_id(target_id)
	if not atk or not tgt:
		return

	atk.auto_attack_ranged(tgt, atk)
	var died = tgt.health <= 0
	atk.gain_xp(25)
	if died:
		atk.gain_xp(25)

	rpc("sync_auto_attack_ranged_unit", attacker_id, target_id, died)

@rpc("any_peer", "reliable")
func sync_auto_attack_ranged_unit(attacker_id: int, target_id: int, died: bool) -> void:
	var atk = get_unit_by_id(attacker_id)
	var tgt = get_unit_by_id(target_id)
	if not atk or not tgt:
		return
	if not is_multiplayer_authority():
		atk.auto_attack_ranged(tgt, atk)
		atk.gain_xp(25)
		if died:
			atk.gain_xp(25)

@rpc("any_peer","reliable")
func request_auto_attack_ranged_structure(attacker_id: int, tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	var st  = get_structure_at_tile(tile)
	if not atk or not st:
		return

	sync_auto_attack_ranged_structure(attacker_id, tile, 25, false)
	rpc("sync_auto_attack_ranged_structure", attacker_id, tile, 25, false)

@rpc("any_peer","reliable")
func sync_auto_attack_ranged_structure(attacker_id: int, tile: Vector2i, damage: int, died: bool) -> void:
	var atk = get_unit_by_id(attacker_id)
	var st  = get_structure_at_tile(tile)
	if not atk or not st:
		return

	atk.auto_attack_ranged(st, atk)
	atk.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)
	atk.gain_xp(25)

@rpc("any_peer","reliable")
func request_auto_attack_ranged_empty(attacker_id: int, target_pos: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	sync_auto_attack_ranged_empty(attacker_id, target_pos)
	rpc("sync_auto_attack_ranged_empty", attacker_id, target_pos)

@rpc("any_peer","reliable")
func sync_auto_attack_ranged_empty(attacker_id: int, target_pos: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.auto_attack_ranged_empty(target_pos, atk)

func _compute_push_direction(attacker, target) -> Vector2i:
	var delta = target.tile_pos - attacker.tile_pos
	delta.x = sign(delta.x)
	delta.y = sign(delta.y)
	return delta

@rpc("any_peer", "reliable")
func request_auto_attack_adjacent(attacker_id: int, target_id: int) -> void:
	if not is_multiplayer_authority():
		return

	var atk = get_unit_by_id(attacker_id)
	var tgt = get_unit_by_id(target_id)
	if not atk or not tgt:
		return

	var damage = atk.damage
	var push_dir = _compute_push_direction(atk, tgt)
	var died = tgt.take_damage(damage)
	var new_tile = tgt.tile_pos + push_dir
	tgt.tile_pos = new_tile
	update_astar_grid()

	sync_melee_push(attacker_id, target_id, damage, new_tile, died)
	rpc("sync_melee_push", attacker_id, target_id, damage, new_tile, died)

@rpc("any_peer", "reliable")
func sync_melee_push(attacker_id: int, target_id: int, damage: int, new_tile: Vector2i, died: bool) -> void:
	var atk = get_unit_by_id(attacker_id)
	var tgt = get_unit_by_id(target_id)
	if not atk or not tgt:
		return

	# If this is a client, apply damage locally; otherwise, the server already applied it.
	var actually_died = died
	if not is_multiplayer_authority():
		actually_died = tgt.take_damage(damage)

	# Play the attack animation & sound on the attacker
	var atk_sprite = atk.get_node("AnimatedSprite2D")
	if atk_sprite:
		atk_sprite.play("attack")
	play_attack_sound(atk.global_position)

	# Grant XP for the hit (and extra if it died)
	atk.gain_xp(25)
	if actually_died:
		atk.gain_xp(25)

	# Flash the target briefly to show it was hit
	tgt.flash_white()
	tgt.being_pushed = true
	
	# Compute the world‐space position corresponding to new_tile (after push)
	var world_dest = to_global(map_to_local(new_tile)) + Vector2(0, tgt.Y_OFFSET)

	# Create a Tween to animate the target from its current position to world_dest
	var tw = tgt.create_tween()
	tw.tween_property(tgt, "global_position", world_dest, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# If the target died, queue it for freeing once the animation is done
	if actually_died:
		tw.tween_callback(func():
			if is_instance_valid(tgt):
				tgt.being_pushed = false
				tgt.queue_free()
		)

	# Only after the visual Tween completes do we update the logical tile_pos and rebuild A⋆
	tw.tween_callback(func():
		if is_instance_valid(tgt):
			tgt.tile_pos = new_tile
			tgt.being_pushed = false
			update_astar_grid()
		# If it died, it's already freed above, so nothing more is needed here.
	)

# ———————————————————————————————————————————————————————————————
# NEW RPCS FOR THE “EIGHT NEW SPECIAL ABILITIES”
# Place this block directly after sync_melee_push, before toggle_borders()
# ———————————————————————————————————————————————————————————————

# 1) Ground Slam
@rpc("any_peer", "reliable")
func request_ground_slam(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.ground_slam(target_tile)
	rpc("sync_ground_slam", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_ground_slam(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.ground_slam(target_tile)

# 2) Mark & Pounce
@rpc("any_peer", "reliable")
func request_mark_and_pounce(attacker_id: int, target_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	var tgt = get_unit_by_id(target_id)
	if not atk or not tgt:
		return
	atk.mark_and_pounce(tgt)
	rpc("sync_mark_and_pounce", attacker_id, target_id)

@rpc("any_peer", "reliable")
func sync_mark_and_pounce(attacker_id: int, target_id: int) -> void:
	var atk = get_unit_by_id(attacker_id)
	var tgt = get_unit_by_id(target_id)
	if not atk or not tgt:
		return
	if not is_multiplayer_authority():
		atk.mark_and_pounce(tgt)

# 3) Guardian Halo
@rpc("any_peer", "reliable")
func request_guardian_halo(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.guardian_halo(target_tile)
	rpc("sync_guardian_halo", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_guardian_halo(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.guardian_halo(target_tile)

# 4) High Arcing Shot
@rpc("any_peer", "reliable")
func request_high_arcing_shot(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.high_arcing_shot(target_tile)
	rpc("sync_high_arcing_shot", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_high_arcing_shot(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.high_arcing_shot(target_tile)

# 5) Suppressive Fire
@rpc("any_peer", "reliable")
func request_suppressive_fire(attacker_id: int, dir: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.suppressive_fire(dir)
	rpc("sync_suppressive_fire", attacker_id, dir)

@rpc("any_peer", "reliable")
func sync_suppressive_fire(attacker_id: int, dir: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.suppressive_fire(dir)

# 6) Fortify
@rpc("any_peer", "reliable")
func request_fortify(attacker_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.fortify()
	rpc("sync_fortify", attacker_id)

@rpc("any_peer", "reliable")
func sync_fortify(attacker_id: int) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.fortify()

# ─────────────────────────────────────────────────────────────────────────────
# 7a) Airlift — PICK UP an ally
# ─────────────────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func request_airlift_pick(attacker_id: int, ally_id: int) -> void:
	if not is_multiplayer_authority():
		return

	var heli = get_unit_by_id(attacker_id)
	var ally = get_unit_by_id(ally_id)
	if heli == null or ally == null:
		return

	var tilemap = get_node("/root/BattleGrid/TileMap")

	# Find one valid neighbor of the ally’s tile
	var adjacent_tile := Vector2i(-1, -1)
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var candidate = ally.tile_pos + dir
		if tilemap.is_within_bounds(candidate) and tilemap._is_tile_walkable(candidate) and not tilemap.is_tile_occupied(candidate):
			adjacent_tile = candidate
			break

	if adjacent_tile == Vector2i(-1, -1):
		push_warning("❗ Helicopter cannot find any adjacent tile to pick up the ally.")
		return

	# Teleport the ally onto the helicopter’s tile and hide it
	var heli_tile = heli.tile_pos
	ally.tile_pos = heli_tile
	ally.global_position = tilemap.to_global(tilemap.map_to_local(heli_tile)) + Vector2(0, ally.Y_OFFSET)
	ally.visible = false
	heli.queued_airlift_unit = ally

	# Broadcast to clients
	rpc("sync_airlift_pick", attacker_id, ally_id, heli_tile)


@rpc("any_peer", "reliable")
func sync_airlift_pick(attacker_id: int, ally_id: int, heli_tile: Vector2i) -> void:
	# Clients mirror exactly what the server did above.
	if is_multiplayer_authority():
		return

	var heli = get_unit_by_id(attacker_id)
	var ally = get_unit_by_id(ally_id)
	if heli == null or ally == null:
		return

	var tilemap = get_node("/root/BattleGrid/TileMap")
	ally.tile_pos = heli_tile
	ally.global_position = tilemap.to_global(tilemap.map_to_local(heli_tile)) + Vector2(0, ally.Y_OFFSET)
	ally.visible = false
	heli.queued_airlift_unit = ally


# ─────────────────────────────────────────────────────────────────────────────
# 7b) Airlift — DROP the carried ally at a target tile
# ─────────────────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func request_airlift_drop(attacker_id: int, ally_id: int, click_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return

	var heli = get_unit_by_id(attacker_id)
	if heli == null or heli.queued_airlift_unit == null:
		return

	var carried = heli.queued_airlift_unit
	var tilemap = get_node("/root/BattleGrid/TileMap")

	# 1) If the clicked tile is invalid, find a valid neighbor
	var final_drop = _get_adjacent_tile(click_tile)
	if final_drop == Vector2i(-1, -1):
		push_warning("❗ No valid adjacent tile to drop the ally.")
		return

	# 2) Teleport & unhide the ally
	carried.tile_pos = final_drop
	carried.global_position = tilemap.to_global(tilemap.map_to_local(final_drop)) + Vector2(0, carried.Y_OFFSET)
	carried.visible = true

	# 3) Clear the helicopter’s carry pointer
	heli.queued_airlift_unit = null

	# 4) Play a small landing VFX
	var explosion = preload("res://Scenes/VFX/Explosion.tscn").instantiate()
	explosion.global_position = tilemap.to_global(tilemap.map_to_local(final_drop))
	get_tree().get_current_scene().add_child(explosion)

	# 5) Broadcast to clients
	rpc("sync_airlift_drop", attacker_id, ally_id, final_drop)

	# 6) Mark helicopter as used
	heli.has_attacked = true
	heli.has_moved = true
	heli.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)


@rpc("any_peer", "reliable")
func sync_airlift_drop(attacker_id: int, ally_id: int, final_drop: Vector2i) -> void:
	# Clients mirror the “teleport & unhide” step
	if is_multiplayer_authority():
		return

	var heli = get_unit_by_id(attacker_id)
	var carried = get_unit_by_id(ally_id)
	if heli == null or carried == null:
		return

	var tilemap = get_node("/root/BattleGrid/TileMap")
	carried.tile_pos = final_drop
	carried.global_position = tilemap.to_global(tilemap.map_to_local(final_drop)) + Vector2(0, carried.Y_OFFSET)
	carried.visible = true
	heli.queued_airlift_unit = null

	# Spawn the same landing VFX
	var explosion = preload("res://Scenes/VFX/Explosion.tscn").instantiate()
	explosion.global_position = tilemap.to_global(tilemap.map_to_local(final_drop))
	get_tree().get_current_scene().add_child(explosion)

	heli.has_attacked = true
	heli.has_moved = true
	heli.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)


# ─────────────────────────────────────────────────────────────────────────────
# Helper: find a nearby valid tile for dropping
# ─────────────────────────────────────────────────────────────────────────────

func _get_adjacent_tile(base: Vector2i) -> Vector2i:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor = base + dir
		if tilemap.is_within_bounds(neighbor) and tilemap._is_tile_walkable(neighbor) and not tilemap.is_tile_occupied(neighbor):
			return neighbor
	return Vector2i(-1, -1)


func get_unit_by_id(target_id: int) -> Node:
	for u in get_tree().get_nodes_in_group("Units"):
		if u.has_meta("unit_id") and u.get_meta("unit_id") == target_id:
			return u
	return null

# 8) Web Field
@rpc("any_peer", "reliable")
func request_web_field(attacker_id: int, center_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.web_field(center_tile)
	rpc("sync_web_field", attacker_id, center_tile)

@rpc("any_peer", "reliable")
func sync_web_field(attacker_id: int, center_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.web_field(center_tile)

# 9) Thread Attack
@rpc("any_peer", "reliable")
func request_thread_attack(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.thread_attack(target_tile)
	rpc("sync_thread_attack", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_thread_attack(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.thread_attack(target_tile)

# 10) Lightning Surge
@rpc("any_peer", "reliable")
func request_lightning_surge(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.lightning_surge(target_tile)
	rpc("sync_lightning_surge", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_lightning_surge(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.lightning_surge(target_tile)

# 11) Heavy Rain
@rpc("any_peer", "reliable")
func request_heavy_rain(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	atk.spider_blast(target_tile)
	rpc("sync_heavy_rain", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_heavy_rain(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if not atk:
		return
	if not is_multiplayer_authority():
		atk.spider_blast(target_tile)


# ———————————————————————————————————————————————————————————————
# VISUAL HELPERS
# ———————————————————————————————————————————————————————————————
func toggle_borders():
	borders_visible = not borders_visible
	for unit in get_tree().get_nodes_in_group("Units"):
		for name in ["HealthBorder", "XPBorder", "HealthUI", "XPUI"]:
			var node = unit.get_node_or_null(name)
			if node:
				node.visible = borders_visible

func play_attack_sound(pos: Vector2):
	var player := $AudioStreamPlayer2D
	if player:
		player.stop()
		player.stream = attack_sound
		player.global_position = pos
		player.play()

func play_beep_sound(pos: Vector2):
	var player := $AudioStreamPlayer2D
	if player:
		player.stop()
		player.stream = beep_sound
		player.global_position = pos
		player.play()

func play_splash_sound(pos: Vector2):
	var player := $AudioStreamPlayer2D
	if player:
		player.stop()
		player.stream = splash_sound
		player.global_position = pos
		player.play()

# ———————————————————————————————————————————————————————————————
# SELECTION & HIGHLIGHTING
# ———————————————————————————————————————————————————————————————
func _select_unit_at_mouse():
	_clear_highlights()
	_clear_ability_modes()
	if ability_button:
		ability_button.button_pressed = false

	var hud = get_node("/root/BattleGrid/HUDLayer/Control")
	hud.visible = true

	var mouse_pos = get_global_mouse_position()
	mouse_pos.y += 16
	var tile = local_to_map(to_local(mouse_pos))
	var unit = get_unit_at_tile(tile)

	if unit == null:
		selected_unit = null
		showing_attack = false
		hud.visible = false
		return

	_update_hud_with(unit)
	play_beep_sound(tile)
	emit_signal("unit_selected", unit)
	selected_unit = unit
	showing_attack = false
	_show_range_for_selected_unit()

# ———————————————————————————————————————————————————————————————
# Turn off every “mode” flag before selecting a new ability or a new unit.
# Call this whenever you switch out of any special‐ability mode.
# ———————————————————————————————————————————————————————————————
func _clear_ability_modes() -> void:
	critical_strike_mode = false
	rapid_fire_mode = false
	healing_wave_mode = false
	overcharge_attack_mode = false
	explosive_rounds_mode = false
	spider_blast_mode = false
	thread_attack_mode = false
	lightning_surge_mode = false
	ground_slam_mode = false
	mark_and_pounce_mode = false
	guardian_halo_mode = false
	high_arcing_shot_mode = false
	suppressive_fire_mode = false
	fortify_mode = false
	heavy_rain_mode = false
	web_field_mode = false

	# Also clear any “in‐flight” helper state:
	chosen_airlift_unit = null
	GameData.selected_special_ability = ""

func _update_hud_with(unit):
	var hud = get_node("/root/BattleGrid/HUDLayer/Control")
	var hud_data = {
		"name":           unit.unit_name,
		"portrait":       unit.portrait,
		"current_hp":     unit.health,
		"max_hp":         unit.max_health,
		"current_xp":     unit.xp,
		"max_xp":         unit.max_xp,
		"level":          unit.level,
		"movement_range": unit.movement_range,
		"attack_range":   unit.attack_range,
		"damage":         unit.damage
	}
	hud.update_hud(hud_data)
	hud.visible = true

func _show_only_hud(unit, tile):
	selected_unit = null
	showing_attack = false
	play_beep_sound(tile)
	_update_hud_with(unit)

func _show_range_for_selected_unit():
	if selected_unit == null:
		return
	_clear_highlights()

	var range: int
	var tile_id: int
	if showing_attack:
		range = _get_active_attack_range()
		tile_id = attack_tile_id
	else:
		range = selected_unit.movement_range
		tile_id = highlight_tile_id

	_highlight_range(selected_unit.tile_pos, range, tile_id)

func _update_highlight_display():
	for tile in highlighted_tiles:
		set_cell(1, tile, _get_tile_id_from_noise(noise.get_noise_2d(tile.x, tile.y)))
	highlighted_tiles.clear()

	var range: int
	if showing_attack:
		range = _get_active_attack_range()
	else:
		range = selected_unit.movement_range

	var tile_id: int
	if showing_attack:
		tile_id = attack_tile_id
	else:
		tile_id = highlight_tile_id

	_highlight_range(selected_unit.tile_pos, range, tile_id)

func _highlight_range(start: Vector2i, max_dist: int, tile_id: int):
	var allow_occupied = (tile_id == attack_tile_id)
	var frontier = [start]
	var distances = { start: 0 }

	while frontier.size() > 0:
		var current = frontier.pop_front()
		var dist = distances[current]

		if dist > 0:
			if allow_occupied:
				set_cell(1, current, tile_id, Vector2i.ZERO)
				highlighted_tiles.append(current)
			else:
				if not is_water_tile(current) and not is_tile_occupied(current) and get_structure_at_tile(current) == null:
					set_cell(1, current, tile_id, Vector2i.ZERO)
					highlighted_tiles.append(current)

		if dist == max_dist:
			continue

		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor = current + dir
			if is_within_bounds(neighbor) and not distances.has(neighbor):
				if allow_occupied:
					distances[neighbor] = dist + 1
					frontier.append(neighbor)
				else:
					if _is_tile_walkable(neighbor) and not is_tile_occupied(neighbor) and get_structure_at_tile(neighbor) == null:
						distances[neighbor] = dist + 1
						frontier.append(neighbor)

func _clear_highlights():
	for pos in highlighted_tiles:
		set_cell(1, pos, _get_tile_id_from_noise(noise.get_noise_2d(pos.x, pos.y)))
	highlighted_tiles.clear()

# ———————————————————————————————————————————————————————————————
# MOVEMENT RPCS
# ———————————————————————————————————————————————————————————————
func _move_selected_to(target: Vector2i) -> void:
	update_astar_grid()
	current_path = get_weighted_path(selected_unit.tile_pos, target)
	if current_path.is_empty():
		return

	moving = true
	print("DEBUG: Moving unit", selected_unit.unit_id, "→", target)

	if is_multiplayer_authority():
		server_request_move(selected_unit.unit_id, target.x, target.y)
	else:
		var auth_id = get_multiplayer_authority()
		print("Client → server_request_move → authority peer", auth_id)
		rpc_id(auth_id, "server_request_move", selected_unit.unit_id, target.x, target.y)

@rpc("any_peer", "reliable")
func server_request_move(unit_id: int, tx: int, ty: int) -> void:
	if not is_multiplayer_authority():
		return

	var to = Vector2i(tx, ty)
	print("🏠 Server got move request for unit", unit_id, "→", to)
	rpc("remote_start_move", unit_id, tx, ty)
	remote_start_move(unit_id, tx, ty)

@rpc("any_peer", "unreliable")
func remote_start_move(unit_id: int, tx: int, ty: int) -> void:
	var to = Vector2i(tx, ty)
	var unit = get_unit_by_id(unit_id)
	if not unit:
		print("⚠ remote_start_move: no unit", unit_id)
		return

	selected_unit = unit
	update_astar_grid()
	current_path = get_weighted_path(unit.tile_pos, to)
	if current_path.is_empty():
		return

	moving = true
	print("🔔 Peer", get_tree().get_multiplayer().get_unique_id(), "syncing move of unit", unit_id, "→", to)

# ———————————————————————————————————————————————————————————————
# TURN MANAGEMENT
# ———————————————————————————————————————————————————————————————
func start_player_turn():
	set_end_turn_button_enabled(true)
	all_player_units = get_tree().get_nodes_in_group("Units").filter(func(u): return u.is_player)
	finished_player_units.clear()
	print("🎮 Player turn started. Units:", all_player_units.size())

func allow_player_to_plan_next():
	if current_unit_index >= all_units.size():
		print("✅ All moves planned. Waiting for End Turn.")
		return
	var unit = all_units[current_unit_index]
	selected_unit = unit

func confirm_unit_plan(move_tile: Vector2i, attack_target: Node2D):
	var unit = all_units[current_unit_index]
	unit.plan_move(move_tile)
	unit.plan_attack(attack_target)
	planned_units += 1
	current_unit_index += 1
	allow_player_to_plan_next()

	if planned_units >= all_units.size():
		await _execute_all_player_units()

func on_player_unit_done(unit: Node2D):
	if finished_player_units.has(unit):
		return

	finished_player_units.append(unit)
	print("✅ Player finished with:", unit.name)

	if finished_player_units.size() == all_player_units.size():
		print("🏁 All player units done! Ending turn...")
		var turn_manager = get_node("/root/TurnManager")
		if turn_manager:
			turn_manager.end_turn()
			set_end_turn_button_enabled(false)

func _execute_all_player_units():
	for unit in all_units:
		await unit.execute_all_player_actions()

	var turn_manager = get_tree().get_current_scene().get_node("TurnManager")
	if turn_manager:
		turn_manager.end_turn()

func _on_end_turn_button_pressed() -> void:
	if GameData.multiplayer_mode:
		rpc("request_end_turn")
	else:
		_do_end_turn()

func _do_end_turn() -> void:
	print("🛑 Ending turn locally")
	for u in get_tree().get_nodes_in_group("Units"):
		if u.has_method("is_moving") and u.is_moving():
			print("⏳ Cannot end turn — unit is still moving:", u.name)
			return

	for u in get_tree().get_nodes_in_group("Units"):
		u.has_moved = false
		u.has_attacked = false
		var sprite = u.get_node("AnimatedSprite2D")
		if sprite:
			sprite.self_modulate = Color(1, 1, 1, 1)

	var tm = get_node("/root/TurnManager")
	if tm:
		tm.end_turn()

	selected_unit = null
	showing_attack = false
	_clear_highlights()
	var hud = get_node("/root/BattleGrid/HUDLayer/Control")
	hud.visible = false

@rpc("any_peer", "reliable")
func request_end_turn() -> void:
	if not is_multiplayer_authority():
		_on_end_turn_button_pressed()
		return
	_do_end_turn()
	rpc("sync_end_turn")

@rpc("any_peer", "reliable")
func sync_end_turn() -> void:
	if is_multiplayer_authority():
		return
	_do_end_turn()

func set_end_turn_button_enabled(enabled: bool):
	var btn = get_node("CanvasLayer/Control/EndTurnButton")
	if btn:
		btn.disabled = not enabled

# ———————————————————————————————————————————————————————————————
# UTILITY FUNCTIONS
# ———————————————————————————————————————————————————————————————
func set_unit_position(unit: Node2D, pos: Vector2):
	unit.global_position = pos + Vector2(0, -8)

func is_tile_occupied(tile: Vector2i) -> bool:
	return get_unit_at_tile(tile) != null or get_structure_at_tile(tile) != null

func get_structure_at_tile(tile: Vector2i) -> Node:
	for structure in get_tree().get_nodes_in_group("Structures"):
		if structure.tile_pos == tile:
			return structure
	return null

func get_structure_by_id(target_id: int) -> Node:
	for s in get_tree().get_nodes_in_group("Structures"):
		if s.has_meta("structure_id") and s.get_meta("structure_id") == target_id:
			return s
	return null

func get_unit_at_tile(tile: Vector2i) -> Node:
	for unit in get_tree().get_nodes_in_group("Units"):
		if local_to_map(to_local(unit.global_position)) == tile:
			return unit
	return null

func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < grid_width and tile.y >= 0 and tile.y < grid_height

func is_water_tile(tile: Vector2i) -> bool:
	return get_cell_source_id(0, tile) == water_tile_id

func _is_tile_walkable(tile: Vector2i) -> bool:
	return get_cell_source_id(0, tile) != water_tile_id

func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func get_weighted_path(start: Vector2i, goal: Vector2i) -> Array:
	var INF = 1e9
	var open_set = [start]
	var came_from = {}
	var g_score = { start: 0.0 }
	var f_score = { start: heuristic(start, goal) }

	while open_set.size() > 0:
		var current = get_lowest_f_score(open_set, f_score)
		if current == goal:
			return reconstruct_path(came_from, current)

		open_set.erase(current)
		for neighbor in get_neighbors(current):
			if not _is_tile_walkable(neighbor) or is_tile_occupied(neighbor):
				continue

			var tentative_g = g_score[current] + get_cell_cost(neighbor)
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + heuristic(neighbor, goal)
				if not neighbor in open_set:
					open_set.append(neighbor)

	return []

func get_neighbors(tile: Vector2i) -> Array:
	var neighbors = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor = tile + d
		if is_within_bounds(neighbor):
			neighbors.append(neighbor)
	return neighbors

func heuristic(a: Vector2i, b: Vector2i) -> float:
	return abs(a.x - b.x) + abs(a.y - b.y)

func reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array:
	var total_path = [current]
	while came_from.has(current):
		current = came_from[current]
		total_path.insert(0, current)
	return total_path

func get_cell_cost(tile: Vector2i) -> float:
	var cost = 1.0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor = tile + d
		if is_within_bounds(neighbor) and get_cell_source_id(0, neighbor) == water_tile_id:
			cost += 0.5
			break
	return cost

func get_lowest_f_score(open_set: Array, f_score: Dictionary) -> Vector2i:
	var lowest = open_set[0]
	for tile in open_set:
		if f_score.has(tile) and f_score[tile] < f_score.get(lowest, 1e9):
			lowest = tile
	return lowest

# ———————————————————————————————————————————————————————————————
# IMPORT / EXPORT UNIT & STRUCTURE DATA
# ———————————————————————————————————————————————————————————————
func export_unit_data() -> Array:
	var data = []
	for unit in get_tree().get_nodes_in_group("Units"):
		var scene_path = ""
		if unit.has_meta("scene_path"):
			scene_path = unit.get_meta("scene_path")
		else:
			print("Warning: Unit ", unit.name, " does not have a scene path stored!")

		data.append({
			"scene_path": scene_path,
			"tile_pos":   unit.tile_pos,
			"is_player":  unit.is_player,
			"health":     unit.health,
			"unit_id":    unit.unit_id,
			"peer_id":    unit.peer_id
		})
	return data

func import_unit_data(unit_data: Array) -> void:
	for old in get_tree().get_nodes_in_group("Units"):
		old.queue_free()

	for info in unit_data:
		var scene_path = info.get("scene_path", "")
		if scene_path == "":
			continue
		var packed = load(scene_path)
		if not packed:
			print("Error loading unit scene at:", scene_path)
			continue

		var unit_instance = packed.instantiate()

		var uid = info.get("unit_id", -1)
		var pid = info.get("peer_id", 0)
		unit_instance.unit_id = uid
		unit_instance.peer_id = pid
		unit_instance.set_meta("unit_id", uid)
		unit_instance.set_meta("peer_id", pid)

		add_child(unit_instance)
		unit_instance.add_to_group("Units")

		var tile = info.get("tile_pos", Vector2i.ZERO)
		unit_instance.tile_pos = tile
		unit_instance.global_position = to_global(map_to_local(tile))
		unit_instance.global_position.y -= 8
		unit_instance.is_player = info.get("is_player", true)
		unit_instance.health = info.get("health", 100)

		if unit_instance.is_player:
			var sp = unit_instance.get_node_or_null("AnimatedSprite2D")
			if sp:
				sp.flip_h = true
		else:
			unit_instance.get_child(0).modulate = Color8(255, 110, 255)

		print("Imported unit", unit_instance.name, "with unit_id =", uid)

func export_structure_data() -> Array:
	var data = []
	for structure in get_tree().get_nodes_in_group("Structures"):
		var scene_path: String = ""
		if structure.has_meta("scene_path"):
			scene_path = structure.get_meta("scene_path")
		else:
			print("Warning: Structure ", structure.name, " does not have a scene path stored!")
		data.append({
			"scene_path": scene_path,
			"tile_pos":   structure.tile_pos
		})
	return data

func import_structure_data(structure_data: Array) -> void:
	for structure in get_tree().get_nodes_in_group("Structures"):
		structure.queue_free()

	for info in structure_data:
		var scene_path: String = info.get("scene_path", "")
		if scene_path == "":
			print("Skipping structure import; scene path missing.")
			continue
		var scene = load(scene_path)
		if scene == null:
			print("Error loading structure scene at:", scene_path)
			continue
		var structure_instance = scene.instantiate()
		add_child(structure_instance)
		structure_instance.tile_pos = info.get("tile_pos", Vector2i.ZERO)
		structure_instance.set_meta("scene_path", scene_path)
		structure_instance.position = map_to_local(structure_instance.tile_pos)
		structure_instance.position.y -= 8
		structure_instance.add_to_group("Structures")
		structure_instance.z_index = int(structure_instance.global_position.y)

		astar.set_point_solid(structure_instance.tile_pos, true)

		var r_val = randf_range(0.4, 0.8)
		var g_val = randf_range(0.4, 0.8)
		var b_val = randf_range(0.4, 0.8)
		structure_instance.modulate = Color(r_val, g_val, b_val, 1)

# ———————————————————————————————————————————————————————————————
# GAME STATE BROADCAST
# ———————————————————————————————————————————————————————————————
func broadcast_game_state() -> void:
	var map_data = export_map_data()
	var unit_data = export_unit_data()
	var structure_data = export_structure_data()
	rpc("receive_game_state", map_data, unit_data, structure_data)
	print("Game state broadcasted to all peers.")

func _generate_client_map(map_data: Dictionary, unit_data: Array, structure_data: Array) -> void:
	import_map_data(map_data)
	import_unit_data(unit_data)
	import_structure_data(structure_data)
	_setup_camera()
	update_astar_grid()
	print("Client map generated from host data.")

# ———————————————————————————————————————————————————————————————
# UTILITY, CAMERA, & AUDIO HELPERS
# ———————————————————————————————————————————————————————————————
func _setup_noise():
	noise.seed = randi()
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.4
	noise.fractal_lacunarity = 2.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM

func set_abilities_off() -> void:
	critical_strike_mode = false
	rapid_fire_mode = false
	healing_wave_mode = false
	overcharge_attack_mode = false
	explosive_rounds_mode = false
	spider_blast_mode = false
	thread_attack_mode = false
	lightning_surge_mode = false
	ground_slam_mode = false
	mark_and_pounce_mode = false
	guardian_halo_mode = false
	high_arcing_shot_mode = false
	suppressive_fire_mode = false
	fortify_mode = false
	heavy_rain_mode = false
	web_field_mode = false
	chosen_airlift_unit = null
	GameData.selected_special_ability = ""

# ———————————————————————————————————————————————————————————————
# BUTTON CALLBACKS
# ———————————————————————————————————————————————————————————————
func _on_GroundSlamButton_pressed() -> void:
	_clear_ability_modes()
	ground_slam_mode = true
	GameData.selected_special_ability = "Ground Slam"
	print("Mode set → Ground Slam.")

func _on_MarkAndPounceButton_pressed() -> void:
	_clear_ability_modes()
	mark_and_pounce_mode = true
	GameData.selected_special_ability = "Mark & Pounce"
	print("Mode set → Mark & Pounce.")

func _on_GuardianHaloButton_pressed() -> void:
	_clear_ability_modes()
	guardian_halo_mode = true
	GameData.selected_special_ability = "Guardian Halo"
	print("Mode set → Guardian Halo.")

func _on_HighArcingShotButton_pressed() -> void:
	_clear_ability_modes()
	high_arcing_shot_mode = true
	GameData.selected_special_ability = "High Arcing Shot"
	print("Mode set → High Arcing Shot.")

func _on_SuppressiveFireButton_pressed() -> void:
	_clear_ability_modes()
	suppressive_fire_mode = true
	GameData.selected_special_ability = "Suppressive Fire"
	print("Mode set → Suppressive Fire.")

func _on_FortifyButton_pressed() -> void:
	_clear_ability_modes()
	fortify_mode = true
	GameData.selected_special_ability = "Fortify"
	print("Mode set → Fortify.")

func _on_AirliftAndBombButton_pressed() -> void:
	_clear_ability_modes()
	heavy_rain_mode = true
	GameData.selected_special_ability = "Healing Wave"
	print("Mode set → Airlift & Drop. Step 1: pick a friendly unit to move.")

func _on_WebFieldButton_pressed() -> void:
	_clear_ability_modes()
	web_field_mode = true
	GameData.selected_special_ability = "Web Field"
	print("Mode set → Web Field.")

func _on_ability_pressed() -> void:
	# What button‐text did we just click?
	var ability_name = ability_button.text
	print("[AbilityPressed] Clicked button: ", ability_name)

	# --- 1) Decide if this same ability is already active by checking its mode boolean ---
	var same_as_current := false
	match ability_name:
		"Ground Slam":
			same_as_current = ground_slam_mode
		"Mark & Pounce":
			same_as_current = mark_and_pounce_mode
		"Guardian Halo":
			same_as_current = guardian_halo_mode
		"High Arcing Shot":
			same_as_current = high_arcing_shot_mode
		"Suppressive Fire":
			same_as_current = suppressive_fire_mode
		"Fortify":
			same_as_current = fortify_mode
		"Heavy Rain":
			same_as_current = heavy_rain_mode
		"Web Field":
			same_as_current = web_field_mode
		"Lightning Surge":
			same_as_current = lightning_surge_mode
		_:
			print("[AbilityPressed] ! Unknown ability text: ", ability_name)

	# --- 2) If it’s the same mode that’s already true, just clear highlights and redraw the grid. ---
	if same_as_current:
		print("[AbilityPressed] Same ability clicked → just refreshing highlights")
		_clear_highlights()
		_clear_ability_modes()
		selected_unit = null
		return

	# --- 3) Otherwise, we clicked a different ability. Clear all modes, clear highlights, and switch on the new one. ---
	print("[AbilityPressed] Switching to a new ability → clearing old modes")
	_clear_ability_modes()
	_clear_highlights()

	match ability_name:
		"Ground Slam":
			ground_slam_mode = true
		"Mark & Pounce":
			mark_and_pounce_mode = true
		"Guardian Halo":
			guardian_halo_mode = true
		"High Arcing Shot":
			high_arcing_shot_mode = true
		"Suppressive Fire":
			suppressive_fire_mode = true
		"Fortify":
			fortify_mode = true
		"Heavy Rain":
			heavy_rain_mode = true
		"Web Field":
			web_field_mode = true
		"Lightning Surge":
			lightning_surge_mode = true
		_:
			# Shouldn’t hit this if your button‐text is valid.
			print("[AbilityPressed] ! Unexpected ability name in match: ", ability_name)

	# Remember which special ability is now “selected.”
	GameData.selected_special_ability = ability_name
	print("[AbilityPressed] Mode set → ", ability_name)

	# Finally, show that ability’s range grid (if we have a unit selected).
	if selected_unit != null:
		showing_attack = true
		_update_highlight_display()
	else:
		print("[AbilityPressed] No selected_unit, so highlight refresh was skipped.")


# ———————————————————————————————————————————————————————————————
# HELPER FUNCTIONS FOR TURN FLOW
# ———————————————————————————————————————————————————————————————
func _on_reset_pressed() -> void:
	TurnManager.reset_match_stats()
	TurnManager.transition_to_next_level()

func _on_continue_pressed() -> void:
	TurnManager.reset_match_stats()
	GameData.current_level += 1
	GameData.max_enemy_units += 1
	self.visible = false
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_back_pressed() -> void:
	GameData.multiplayer_mode = false
	GameData.save_settings()
	get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")

func _on_peer_connected(id: int) -> void:
	# Send the current map/state first (this might already be happening in receive_game_state),
	# then immediately send the upgrades dictionary so the late‐joiner can populate their HUD.
	rpc_id(id, "client_receive_all_upgrades", GameData.unit_upgrades)

func _get_active_attack_range() -> int:
	# If the player has clicked “show attack range” for a special ability,
	# GameData.selected_special_ability is set (via _on_ability_pressed()).
	var ability_name: String = GameData.selected_special_ability
	if ability_name != "" and ability_ranges.has(ability_name):
		return ability_ranges[ability_name]
	# Otherwise, default to the unit’s normal attack_range:
	if selected_unit:
		return selected_unit.attack_range
	return 0

func _on_node_removed(node):
	# Whenever any node is removed from the scene tree:
	if node is Node2D and node.is_in_group("Units"):
		# If it was our selected_unit, clear it
		if node == selected_unit:
			_on_selected_unit_died()

func _on_selected_unit_died():
	# If our selected_unit was just removed from the scene, clear everything
	selected_unit = null
	showing_attack = false
	_clear_highlights()
