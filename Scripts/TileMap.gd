#TileMap.gd
extends TileMap

const INTERSECTION = 12
const DOWN_RIGHT_ROAD = 14
const DOWN_LEFT_ROAD = 13

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

var noise := FastNoiseLite.new()
var tile_size: Vector2

@export var highlight_tile_id := 5
var selected_unit: Node2D = null
var highlighted_tiles := []

@export var attack_tile_id := 3
var showing_attack := false

var astar := AStarGrid2D.new()
var grid_actual_width: int
var grid_actual_height: int

const MOVE_SPEED := 100.0  # pixels/sec
var current_path := []
var moving := false

var attack_sound = preload("res://Audio/SFX/attack_default.wav")  # Replace with your actual path
var beep_sound = preload("res://Audio/SFX/Retro Beeep 06.wav")  # Replace with your actual path
var splash_sound = preload("res://Audio/SFX/water-splash-199583.mp3")  # Replace with your actual path

var all_units: Array[Node2D]
var current_unit_index := 0
var planning_phase := true
var planned_units := 0
var completed_units

@export var structure_scenes: Array[PackedScene]  # Add 6 structure scenes here
@export var max_structures: int = 10

# Add a new variable at the top of your script.
var hold_time: float = 0.0
var borders_visible := false

signal unit_selected(selected_unit)
signal units_spawned

@export var reset_button: Button
@export var menu_button: Button

var difficulty_tiers: Dictionary = {
	1: "Novice",
	2: "Apprentice",
	3: "Adept",
	4: "Expert",
	5: "Master",
	6: "Grandmaster",
	7: "Legendary",
	8: "Mythic",
	9: "Transcendent",
	10: "Celestial",
	11: "Divine",
	12: "Omnipotent",
	13: "Ascendant",
	14: "Ethereal",
	15: "Supreme",
	16: "Sovereign",
	17: "Infallible",
	18: "Immortal",
	19: "Omniscient",
	20: "Absolute",
	21: "Unstoppable",
	22: "Cosmic",
	23: "Infinite",
	24: "Ultimate"
}

var critical_strike_mode: bool = false
var rapid_fire_mode: bool = false
var healing_wave_mode: bool = false
var overcharge_attack_mode: bool = false
var explosive_rounds_mode: bool = false
var spider_blast_mode: bool = false
var thread_attack_mode: bool = false
var lightning_surge_mode: bool = false   # New lightning surge mode

var stored_map_data: Dictionary = {}
var stored_unit_data: Array = []
var stored_structure_data: Array = []

func _ready():
	tile_size = get_tileset().tile_size
	_setup_noise()
	
	if is_multiplayer_authority():
		# Host: generate the map and then postprocess it.
		_generate_map()
		call_deferred("_post_map_generation")
	else:
		# Client: clear any pre-existing map (or simply do nothing) and wait for the game state.
		clear_map()

func clear_map() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			set_cell(0, Vector2i(x, y), -1)  # Remove any tile.
	print("Map cleared – waiting for host data.")

# New _process function to check for a continuous press.
func _process(delta):
	# Only accumulate hold time if the left mouse button is pressed and a unit is selected.
	if selected_unit and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		hold_time += delta
		if hold_time >= 1.0:
			# Toggle attack mode on every 2 seconds of holding.
			showing_attack = not showing_attack
			_update_highlight_display()  # update highlights to reflect the new mode.
			hold_time = 0.0  # reset the timer so holding continues to toggle every 2 seconds.
	else:
		hold_time = 0.0  # reset if the mouse button is released.

	if GameData.multiplayer_mode:
		reset_button.visible = false
		menu_button.visible = false	


func _post_map_generation():
	_spawn_teams()
	spawn_structures()  # Spawn structures after the map is generated.
	_setup_camera()
	update_astar_grid()
	TurnManager.start_turn()
	TurnManager.transition_to_level()

	# If you are the host, store the game state for later broadcasting.
	if is_multiplayer_authority():
		GameState.stored_map_data = export_map_data()
		GameState.stored_unit_data = export_unit_data()
		GameState.stored_structure_data = export_structure_data()
		# Optionally, if peers are already connected:
		broadcast_game_state()

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_global_mouse_position()
		
		# Convert the mouse position to a tile coordinate.
		var tile = local_to_map(to_local(Vector2(mouse_pos.x, mouse_pos.y + 16)))
		
		# If the click is off the map, return.
		if tile.x < 0 or tile.x >= grid_width or tile.y < 0 or tile.y >= grid_height:
			return

		var mouse_tile = local_to_map(to_local(Vector2(mouse_pos.x, mouse_pos.y + 16)))
		if moving:
			return

		# If Critical Strike mode is active and the click is not on the toggle:
		if critical_strike_mode:
			if selected_unit and selected_unit.is_player and !selected_unit.has_attacked and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.critical_strike(mouse_tile)
				print("Critical Strike activated by unit: ", selected_unit.name)
				critical_strike_mode = false
				GameData.selected_special_ability = ""
			else:
				print("No player unit selected for Critical Strike.")
			return  # Exit input processing for this click.
		
		# If Rapid Fire mode is active...
		if rapid_fire_mode:
			if selected_unit and selected_unit.is_player and !selected_unit.has_attacked and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.rapid_fire(mouse_tile)
				print("Rapid Fire activated by unit: ", selected_unit.name)
				rapid_fire_mode = false
				GameData.selected_special_ability = ""
			else:
				print("No player unit selected for Rapid Fire.")
			return

		# If Healing Wave mode is active...
		if healing_wave_mode:
			if selected_unit and selected_unit.is_player and !selected_unit.has_attacked and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.healing_wave(mouse_tile)
				print("Healing Wave activated by unit: ", selected_unit.name)
				healing_wave_mode = false
				GameData.selected_special_ability = ""
			else:
				print("No player unit selected for Healing Wave.")
			return

		# If Overcharge attack mode is active...
		if overcharge_attack_mode:
			if selected_unit and selected_unit.is_player and !selected_unit.has_attacked and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.overcharge_attack(mouse_tile)
				print("Overcharge attack activated by unit: ", selected_unit.name)
				overcharge_attack_mode = false
				GameData.selected_special_ability = ""
			else:
				print("No player unit selected for Overcharge.")
			return

		# If Explosive Rounds mode is active...
		if explosive_rounds_mode:
			if selected_unit and selected_unit.is_player and !selected_unit.has_attacked and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.explosive_rounds(mouse_tile)
				print("Explosive Rounds activated by unit: ", selected_unit.name)
				explosive_rounds_mode = false
				GameData.selected_special_ability = ""
			else:
				print("No player unit selected for Explosive Rounds.")
			return

		# If Spider Blast mode is active...
		if spider_blast_mode:
			if selected_unit and selected_unit.is_player and !selected_unit.has_attacked and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.spider_blast(mouse_tile)
				print("Spider Blast activated by unit: ", selected_unit.name)
				spider_blast_mode = false
				GameData.selected_special_ability = ""
			else:
				print("No player unit selected for Spider Blast.")
			return

		# If Thread Attack mode is active and the click is not on the toggle:
		if thread_attack_mode:
			if selected_unit and selected_unit.is_player and !selected_unit.has_attacked and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.thread_attack(mouse_tile)
				print("Thread Attack activated by unit: ", selected_unit.name)
				# Clear the mode so it fires only once.
				thread_attack_mode = false
				GameData.selected_special_ability = ""
			else:
				print("No player unit selected for Thread Attack.")
			return  # Exit input processing for this click.
			
		# NEW: If Lightning Surge mode is active and the click is not on the toggle:
		if lightning_surge_mode:
			if selected_unit and selected_unit.is_player and !selected_unit.has_attacked and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
				_clear_highlights()
				selected_unit.lightning_surge(mouse_tile)
				print("Lightning Surge activated by unit: ", selected_unit.name)
				lightning_surge_mode = false
				GameData.selected_special_ability = ""
			else:
				print("No player unit selected for Lightning Surge.")
			return  # Exit input processing for this click.
		
		# ... continue with your normal input processing ...
		if event.button_index == MOUSE_BUTTON_LEFT:
			if selected_unit and is_instance_valid(selected_unit):
				if selected_unit.is_player and selected_unit.get_child(0).self_modulate != Color(0.4, 0.4, 0.4, 1):
					if showing_attack:
						var enemy = get_unit_at_tile(mouse_tile)
						var structure = get_structure_at_tile(mouse_tile)
						if (enemy and not enemy.is_player) or structure or (enemy == null and structure == null):
							if selected_unit.unit_type in ["Ranged", "Support"]:
								if enemy and manhattan_distance(selected_unit.tile_pos, enemy.tile_pos) <= selected_unit.attack_range:
									selected_unit.auto_attack_ranged(enemy, selected_unit)
									var sprite := selected_unit.get_node("AnimatedSprite2D")
									sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)
									showing_attack = false
									_clear_highlights()
									return
								elif structure and manhattan_distance(selected_unit.tile_pos, structure.tile_pos) <= selected_unit.attack_range:
									selected_unit.auto_attack_ranged(structure, selected_unit)
									var sprite := selected_unit.get_node("AnimatedSprite2D")
									sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)
									showing_attack = false
									_clear_highlights()
									return
								elif enemy == null and structure == null and manhattan_distance(selected_unit.tile_pos, mouse_tile) <= selected_unit.attack_range:
									selected_unit.auto_attack_ranged_empty(mouse_tile, selected_unit)
									var sprite := selected_unit.get_node("AnimatedSprite2D")
									sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)
									showing_attack = false
									_clear_highlights()
									return
							else:
								if enemy and manhattan_distance(selected_unit.tile_pos, enemy.tile_pos) == 1:
									selected_unit.auto_attack_adjacent()
									selected_unit.has_moved = true
									var sprite := selected_unit.get_node("AnimatedSprite2D")
									sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)
									showing_attack = false
									_clear_highlights()
									play_attack_sound(to_global(map_to_local(enemy.tile_pos)))
									return
					if not showing_attack:
						if highlighted_tiles.has(mouse_tile):
							if selected_unit.has_moved:
								return
							_move_selected_to(mouse_tile)
							var sprite = selected_unit.get_node("AnimatedSprite2D")
							sprite.self_modulate = Color(1, 0.6, 0.6, 1)
							return
				else:
					_show_range_for_selected_unit()
			_select_unit_at_mouse()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if selected_unit:
				showing_attack = true
				_clear_highlights()
				_show_range_for_selected_unit()		
										
func toggle_borders():
	borders_visible = not borders_visible

	for unit in get_tree().get_nodes_in_group("Units"):
		for name in ["HealthBorder","XPBorder","HealthUI","XPUI"]:
			var node = unit.get_node_or_null(name)
			if node:
				node.visible = borders_visible
				
func _select_unit_at_mouse():
	_clear_highlights()
	var hud = get_node("/root/BattleGrid/HUDLayer/Control")
	hud.visible = true
	
	var mouse_pos = get_global_mouse_position()
	mouse_pos.y += 16  # Adjust for any offset
	var tile = local_to_map(to_local(mouse_pos))
	var unit = get_unit_at_tile(tile)
	
	# If no unit is found, clear selection and update HUD accordingly.
	if unit == null:
		selected_unit = null
		showing_attack = false
		hud.visible = false
		return

	# Build the dictionary from the unit's properties.
	var hud_data = {
		"name": unit.unit_name,           # Adjust this to unit.name if you use that.
		"portrait": unit.portrait,          # Must be a Texture
		"current_hp": unit.health,
		"max_hp": unit.max_health,
		"current_xp": unit.xp,
		"max_xp": unit.max_xp,
		"level": unit.level,
		"movement_range": unit.movement_range,
		"attack_range": unit.attack_range,
		"damage": unit.damage
	}
	
	# Prevent selecting a unit that has already moved and attacked (if needed).
	if unit.is_player and unit.has_moved and unit.has_attacked:
		selected_unit = null
		showing_attack = false
		play_beep_sound(tile)
		hud.update_hud(hud_data)
		return
	
	# Set the selected unit and update highlights, etc.
	selected_unit = unit
	showing_attack = false
	_show_range_for_selected_unit()
	play_beep_sound(tile)
	
	# Update the HUD.
	hud.visible = true
	hud.update_hud(hud_data)

func _show_range_for_selected_unit():
	var range = 0
	var tile_id = 0

	if selected_unit == null:
		return

	if showing_attack:
		range = selected_unit.attack_range
		tile_id = attack_tile_id
	else:
		range = selected_unit.movement_range
		tile_id = highlight_tile_id

	_highlight_range(selected_unit.tile_pos, range, tile_id)

func _update_highlight_display():
	# Clear old highlights
	for tile in highlighted_tiles:
		set_cell(1, tile, _get_tile_id_from_noise(noise.get_noise_2d(tile.x, tile.y)))
	highlighted_tiles.clear()

	var range = 0
	var tile_id = 0

	if showing_attack:
		range = selected_unit.attack_range
		tile_id = attack_tile_id
	else:
		range = selected_unit.movement_range
		tile_id = highlight_tile_id

	_highlight_range(selected_unit.tile_pos, range, tile_id)

func _highlight_range(start: Vector2i, max_dist: int, tile_id: int):
	# In attack mode, allow highlighting even if tiles are water or occupied,
	# and now also allow tiles occupied by structures.
	var allow_occupied = (tile_id == attack_tile_id)
	
	var frontier = [start]
	var distances = { start: 0 }

	while frontier.size() > 0:
		var current = frontier.pop_front()
		var dist = distances[current]

		# For non-starting tiles...
		if dist > 0:
			if allow_occupied:
				# In attack mode, ignore water, occupancy, and structures.
				set_cell(1, current, tile_id, Vector2i.ZERO)
				highlighted_tiles.append(current)
			else:
				# In movement mode, only highlight if not water, not occupied,
				# and not occupied by a structure.
				if not is_water_tile(current) and not is_tile_occupied(current) and get_structure_at_tile(current) == null:
					set_cell(1, current, tile_id, Vector2i.ZERO)
					highlighted_tiles.append(current)

		if dist == max_dist:
			continue

		# Expand the search.
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor = current + dir
			if is_within_bounds(neighbor) and not distances.has(neighbor):
				if allow_occupied:
					# In attack mode, add neighbors regardless of occupancy or structures.
					distances[neighbor] = dist + 1
					frontier.append(neighbor)
				else:
					# Otherwise, add neighbor only if walkable, not occupied, and not occupied by a structure.
					if _is_tile_walkable(neighbor) and not is_tile_occupied(neighbor) and get_structure_at_tile(neighbor) == null:
						distances[neighbor] = dist + 1
						frontier.append(neighbor)

func _highlight_movement_range(start: Vector2i, max_dist: int):
	var frontier = [start]
	var distances = {start: 0}

	while frontier.size() > 0:
		var current = frontier.pop_front()
		var dist = distances[current]

		if dist > 0:
			set_cell(1, current, highlight_tile_id, Vector2i.ZERO)
			highlighted_tiles.append(current)
		if dist == max_dist:
			continue

		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor = current + dir
			if is_within_bounds(neighbor) and not distances.has(neighbor) and _is_tile_walkable(neighbor):
				distances[neighbor] = dist + 1
				frontier.append(neighbor)

func _move_selected_to(target: Vector2i):
	self.update_astar_grid()
	current_path = get_weighted_path(selected_unit.tile_pos, target)
	if current_path.is_empty():
		return
	moving = true

func _physics_process(delta):
	if moving:
		var next_tile = current_path[0]
		var world_pos = to_global(map_to_local(next_tile)) + Vector2(0, selected_unit.Y_OFFSET)

		# Flip sprite based on horizontal movement
		var sprite := selected_unit.get_node("AnimatedSprite2D")
		sprite.play("move")
		if world_pos.x > selected_unit.global_position.x:
			sprite.flip_h = true  # moving right → face right
		elif world_pos.x < selected_unit.global_position.x:
			sprite.flip_h = false   # moving left → face left
		
		var dir = (world_pos - selected_unit.global_position).normalized()
		selected_unit.global_position += dir * MOVE_SPEED * delta
		
		if selected_unit.global_position.distance_to(world_pos) < 2:
			# Set final position and update tile
			selected_unit.global_position = world_pos
			selected_unit.tile_pos = next_tile
			current_path.remove_at(0)

			if current_path.is_empty():
				moving = false
				update_astar_grid()
				_clear_highlights()
				sprite.play("default")
				
				# Mark the unit as having moved and tint it
				selected_unit.has_moved = true

				# Run adjacent enemy check if applicable
				if selected_unit and selected_unit.has_method("check_adjacent_and_attack"):
					selected_unit.check_adjacent_and_attack()
					

func _clear_highlights():
	# Restore all movement highlights
	for pos in highlighted_tiles:
		set_cell(1, pos, _get_tile_id_from_noise(noise.get_noise_2d(pos.x, pos.y)))
	highlighted_tiles.clear()

func update_astar_grid():
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
	
func is_tile_occupied(tile: Vector2i) -> bool:
	return get_unit_at_tile(tile) != null or get_structure_at_tile(tile) != null

func get_structure_at_tile(tile: Vector2i) -> Node:
	for structure in get_tree().get_nodes_in_group("Structures"):
		# Assuming each structure stores its tile_pos.
		if structure.tile_pos == tile:
			return structure
	return null

func _build_astar():
	astar.clear()
	astar.cell_size = tile_size
	for x in range(grid_width):
		for y in range(grid_height):
			var pos = Vector2i(x, y)
			if _is_tile_walkable(pos):
				astar.add_cell(pos)
	astar.connect_neighbors()


func _setup_noise():
	noise.seed = randi()
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.4
	noise.fractal_lacunarity = 2.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM

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
	while pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height:
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

func _spawn_teams():
	var used_tiles: Array[Vector2i] = []  # Shared for both teams
	_spawn_side(player_units, grid_height - 1, true, used_tiles)
	_spawn_side(enemy_units, 0, false, used_tiles)

func _spawn_side(units: Array[PackedScene], row: int, is_player: bool, used_tiles: Array[Vector2i]):
	var count = units.size()
	if count == 0:
		return

	# Calculate the starting x position so the units appear centered
	var start_x = int((grid_width - count) / 2)
	
	for i in range(count):
		var x = clamp(start_x + i, 0, grid_width - 1)
		_spawn_unit(units[i], Vector2i(x, row), is_player, used_tiles)

func _spawn_unit(scene: PackedScene, tile: Vector2i, is_player: bool, used_tiles: Array[Vector2i]) -> void:
	var spawn_tile = _find_nearest_land(tile, used_tiles)
	if spawn_tile == Vector2i(-1, -1):
		print("⚠ No valid land tile found for unit near ", tile)
		return
	var unit_instance = scene.instantiate()
	unit_instance.global_position = to_global(map_to_local(spawn_tile)) + Vector2(0, unit_instance.Y_OFFSET)
	unit_instance.set_team(is_player)
	unit_instance.add_to_group("Units")
	unit_instance.tile_pos = spawn_tile  # Make sure this is valid!
	# Store the scene path for later export.
	unit_instance.set_meta("scene_path", scene.resource_path)
	add_child(unit_instance)
	if is_player:
		var sprite = unit_instance.get_node_or_null("AnimatedSprite2D")
		if sprite:
			sprite.flip_h = true
	used_tiles.append(spawn_tile)
	print("Spawned unit ", unit_instance.name, " at tile: ", spawn_tile)


func _find_nearest_land(start: Vector2i, used_tiles: Array[Vector2i]) -> Vector2i:
	var visited = {}      # Dictionary to track visited tiles.
	var queue = [start]   # Start BFS from the given start tile.

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		
		# Skip if we're out of bounds (safety check).
		if not is_within_bounds(current):
			continue

		# If current is valid (not water, not in used_tiles, and not occupied), return it.
		if not is_water_tile(current) and not used_tiles.has(current) and not is_tile_occupied(current):
			return current

		# Mark current as visited.
		visited[current] = true

		# Check neighboring tiles in four cardinal directions.
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor = current + dir
			# If neighbor is within bounds and not visited, add it to the queue.
			if is_within_bounds(neighbor) and not visited.has(neighbor):
				queue.append(neighbor)
				visited[neighbor] = true
	# If no valid tile is found, warn and return a fallback.
	push_warning("⚠ No valid land tile found near %s" % str(start))
	return start  # Fallback: return the original position (or Vector2i(-1, -1)) depending on your design.

func is_water_tile(tile: Vector2i) -> bool:
	return get_cell_source_id(0, tile) == water_tile_id

func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func get_unique_random_odd(limit: int, used: Array) -> int:
	for i in range(20):
		var v = randi_range(1, limit - 2)
		if v % 2 == 1 and not used.has(v):
			used.append(v)
			return v
	return 1

func get_unit_at_tile(tile: Vector2i) -> Node:
	for unit in get_tree().get_nodes_in_group("Units"):  # ← plural!
		if local_to_map(to_local(unit.global_position)) == tile:
			return unit
	return null

func _is_tile_walkable(tile: Vector2i) -> bool:
	return get_cell_source_id(0, tile) != water_tile_id

func _setup_camera():
	await get_tree().process_frame
	
	var camera_scene = preload("res://Scripts/Camera2D.gd")
	var camera = Camera2D.new()
	camera.set_script(camera_scene)
	get_tree().get_current_scene().add_child(camera) # Camera at root scene now
	camera.make_current()
	
	var center_tile = Vector2(grid_width * 0.5, grid_height * 0.5)
	camera.global_position = to_global(map_to_local(center_tile))
	#camera.zoom = Vector2(4, 4)
	
	print("Camera centered at grid midpoint:", center_tile, "world:", camera.global_position)

func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < grid_width and tile.y >= 0 and tile.y < grid_height

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


var all_player_units: Array[Node2D] = []
var finished_player_units: Array[Node2D] = []

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
	# highlight movement/attack range, etc.

func confirm_unit_plan(move_tile: Vector2i, attack_target: Node2D):
	var unit = all_units[current_unit_index]
	unit.plan_move(move_tile)
	unit.plan_attack(attack_target)
	planned_units += 1
	current_unit_index += 1
	allow_player_to_plan_next()

	# ✅ If all are planned, trigger actions immediately
	if planned_units >= all_units.size():
		await _execute_all_player_units()

func end_turn():
	planning_phase = false
	for unit in all_units:
		await unit.execute_actions()
	# Switch to enemy turn next

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

	# 🔁 After all units are done, switch to enemy turn
	var turn_manager = get_tree().get_current_scene().get_node("TurnManager")
	if turn_manager:
		turn_manager.end_turn()


func _on_end_turn_button_pressed():
	print("🛑 Player clicked End Turn")

	# ⛔ Prevent end turn if any unit is still moving
	for u in get_tree().get_nodes_in_group("PlayerUnits"):
		if u.has_method("is_moving") and u.is_moving():
			print("⏳ Cannot end turn — unit is still moving:", u.name)
			return

	for u in get_tree().get_nodes_in_group("Units"):
		u.has_moved = false
		u.has_attacked = false

		var sprite = u.get_node("AnimatedSprite2D")
		if sprite:
			sprite.self_modulate = Color(1, 1, 1, 1)  # ✅ Reset the sprite’s tint

		on_player_unit_done(u)

	var turn_manager = get_node("/root/TurnManager")
	if turn_manager:
		turn_manager.end_turn()

func set_end_turn_button_enabled(enabled: bool):
	var btn = get_node("CanvasLayer/Control/EndTurnButton")
	if btn:
		btn.disabled = not enabled

func set_unit_position(unit: Node2D, pos: Vector2):
	unit.global_position = pos + Vector2(0, -8)

# Custom weighted A* pathfinding that penalizes tiles adjacent to water.
# Adjust penalty values as needed.

func get_weighted_path(start: Vector2i, goal: Vector2i) -> Array:
	var INF = 1e9
	var open_set = []
	open_set.append(start)
	
	var came_from = {}
	var g_score = {}
	g_score[start] = 0.0
	
	var f_score = {}
	f_score[start] = heuristic(start, goal)
	
	while open_set.size() > 0:
		var current = get_lowest_f_score(open_set, f_score)
		if current == goal:
			return reconstruct_path(came_from, current)
		
		open_set.erase(current)
		
		for neighbor in get_neighbors(current):
			# Skip non-walkable or occupied tiles
			if not _is_tile_walkable(neighbor) or is_tile_occupied(neighbor):
				continue
			
			# Calculate the cost to move into this neighbor
			var tentative_g = g_score[current] + get_cell_cost(neighbor)
			
			if (not g_score.has(neighbor)) or (tentative_g < g_score[neighbor]):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + heuristic(neighbor, goal)
				if not neighbor in open_set:
					open_set.append(neighbor)
					
	# Return an empty array if no valid path was found.
	return []

func get_neighbors(tile: Vector2i) -> Array:
	var neighbors = []
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in directions:
		var neighbor = tile + d
		if is_within_bounds(neighbor):
			neighbors.append(neighbor)
	return neighbors

func heuristic(a: Vector2i, b: Vector2i) -> float:
	# Manhattan distance heuristic
	return abs(a.x - b.x) + abs(a.y - b.y)

func reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array:
	var total_path = [current]
	while came_from.has(current):
		current = came_from[current]
		total_path.insert(0, current)
	return total_path

func get_cell_cost(tile: Vector2i) -> float:
	# Base cost for a normal move
	var cost = 1.0
	# Add a penalty if this tile is adjacent to water.
	# Adjust the penalty value as needed.
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor = tile + d
		if is_within_bounds(neighbor) and get_cell_source_id(0, neighbor) == water_tile_id:
			cost += 0.5
			break  # Only add penalty once per tile; remove break if you want cumulative penalties.
	return cost

func get_lowest_f_score(open_set: Array, f_score: Dictionary) -> Vector2i:
	var lowest = open_set[0]
	for tile in open_set:
		if f_score.has(tile) and f_score[tile] < f_score.get(lowest, 1e9):
			lowest = tile
	return lowest


func spawn_structures():
	# Check if there are any structure scenes available.
	if structure_scenes.size() == 0:
		push_error("No structure scenes available to spawn!")
		return

	var count = 0  # Counter for spawned structures.
	var attempts = 0
	var max_attempts = grid_width * grid_height * 5  # Limit to avoid infinite loops

	while count < max_structures and attempts < max_attempts:
		attempts += 1
		var x = randi() % grid_width
		var y = randi() % grid_height
		var pos = Vector2i(x, y)
		var tile_id = get_cell_source_id(0, pos)
		
		# Skip if the tile is water.
		if tile_id == water_tile_id:
			continue
		
		# Skip if the tile is a road (e.g., intersection or road tiles).
		if tile_id == INTERSECTION or tile_id == DOWN_RIGHT_ROAD or tile_id == DOWN_LEFT_ROAD:
			continue
		
		# Skip if the tile is occupied by a unit or structure.
		if is_tile_occupied(pos):
			continue
		
		# Valid tile found; spawn a structure.
		var random_index = randi() % structure_scenes.size()
		var structure_scene = structure_scenes[random_index]
		var structure = structure_scene.instantiate()
		
		# Store the scene's resource path in metadata so that you can export and import later.
		structure.set_meta("scene_path", structure_scene.resource_path)
		
		# Position the structure in world space.
		structure.global_position = to_global(map_to_local(pos))
		
		# Optionally, set the tile_pos property if available.
		if structure.has_method("set_tile_pos"):
			structure.set_tile_pos(pos)
		elif structure.has_variable("tile_pos"):
			structure.tile_pos = pos
		
		# Randomly modulate the structure's color within a mid-range.
		# This keeps the RGB values between 0.4 and 0.8.
		var r_val = randf_range(0.4, 0.8)
		var g_val = randf_range(0.4, 0.8)
		var b_val = randf_range(0.4, 0.8)
		structure.modulate = Color(r_val, g_val, b_val, 1)
		
		# Add the structure to the "Structures" group.
		structure.add_to_group("Structures")
		
		# Add the structure as a child to this TileMap (or your dedicated parent node).
		add_child(structure)
		
		# Mark this tile as occupied in the AStar grid.
		astar.set_point_solid(pos, true)
		
		count += 1

	if count < max_structures:
		print("Spawned only", count, "structures after", attempts, "attempts.")
	else:
		print("Spawned", count, "structures.")

func spawn_new_enemy_units():
	# Count current enemy units on the board.
	var enemy_units_on_board = get_tree().get_nodes_in_group("Units").filter(func(u): return not u.is_player)
	var current_count = enemy_units_on_board.size()
	
	if current_count >= GameData.max_enemy_units:
		print("Max enemy units reached:", current_count)
		return  # Do not spawn any new units if at or above limit.
	
	# Determine how many new enemy units to spawn.
	var units_to_spawn: int = GameData.current_level - 1  # Default: spawn 1 enemy per turn.
	
	# Limit spawn count to the maximum allowed.
	units_to_spawn = min(units_to_spawn, GameData.max_enemy_units - current_count)
	
	# Create an array to track occupied spawn tiles.
	var used_tiles: Array[Vector2i] = []
	
	# Define the spawn row for new enemy units (adjust as needed).
	var spawn_row = 0
	
	# Calculate a starting x position so that units appear centered.
	var start_x = int((grid_width - units_to_spawn) / 2)
	
	for i in range(units_to_spawn):
		# Calculate the spawn tile along the row.
		var x = clamp(start_x + i, 0, grid_width - 1)
		var spawn_tile = Vector2i(x, spawn_row)
		
		# Check if the spawn tile is valid, open, and not water.
		if !is_within_bounds(spawn_tile) or is_tile_occupied(spawn_tile) or is_water_tile(spawn_tile):
			# Try to find an alternative nearby open tile.
			spawn_tile = _find_nearest_land(spawn_tile, used_tiles)
			if spawn_tile == Vector2i(-1, -1):
				continue  # Skip if no valid tile is found.
		
		used_tiles.append(spawn_tile)
		
		# Instantiate a random enemy unit.
		var random_index = randi() % enemy_units.size()
		var enemy_scene = enemy_units[random_index]
		var enemy_unit = enemy_scene.instantiate()
		
		enemy_unit.set_team(false)  # Set unit as enemy
		enemy_unit.tile_pos = spawn_tile
		enemy_unit.add_to_group("Units")
		add_child(enemy_unit)
		
		# Determine the target position based on the tile.
		var target_pos = to_global(map_to_local(spawn_tile)) + Vector2(0, enemy_unit.Y_OFFSET)
		
		# Create a drop effect: start above the target position.
		var drop_offset = 100.0  # Adjust how high above the tile the enemy starts.
		enemy_unit.global_position = target_pos - Vector2(0, drop_offset)
		
		# Animate the enemy dropping into place using a tween.
		var tween = enemy_unit.create_tween()
		tween.tween_property(enemy_unit, "global_position", target_pos, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Optionally, update the AStar grid after spawning new units.
	update_astar_grid()

func _on_reset_pressed() -> void:
	TurnManager.reset_match_stats()  # Reset stats first.
	TurnManager.transition_to_next_level()

# When the player is ready to proceed.
func _on_continue_pressed() -> void:
	TurnManager.reset_match_stats()
	
	# Save the current level progress if needed.
	GameData.current_level += 1
	GameData.max_enemy_units += 1
	
	self.visible = false
	
	# Transition to the next mission/level.
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_back_pressed() -> void:
	GameData.multiplayer_mode = false
	GameData.save_settings()
	# Transition to the next mission/level.
	get_tree().change_scene_to_file("res://Scenes/TitleScreen.tscn")

func set_abilities_off() -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	critical_strike_mode = false
	rapid_fire_mode = false

# Export the complete map data as a Dictionary.
func export_map_data() -> Dictionary:
	var data = {}
	data["grid_width"] = grid_width
	data["grid_height"] = grid_height
	var tiles = []
	for x in range(grid_width):
		var col = []
		for y in range(grid_height):
			# Get the tile's source ID for the given cell.
			col.append(get_cell_source_id(0, Vector2i(x, y)))
		tiles.append(col)
	data["tiles"] = tiles
	return data

# Import map data and rebuild the tile map.
func import_map_data(data: Dictionary) -> void:
	grid_width = data.get("grid_width", grid_width)
	grid_height = data.get("grid_height", grid_height)
	var tiles = data.get("tiles", [])
	if tiles.size() != grid_width:
		push_error("Tile data width mismatch!")
		return
	# Clear the current map (if needed)
	for x in range(grid_width):
		for y in range(grid_height):
			set_cell(0, Vector2i(x, y), -1) # clear previous tile
	# Set the cells with the data provided.
	for x in range(grid_width):
		for y in range(grid_height):
			var tile_id = tiles[x][y]
			set_cell(0, Vector2i(x, y), tile_id, Vector2i.ZERO)
	print("Map successfully imported from host data.")

# Exports all unit data into an array.
func export_unit_data() -> Array:
	var data = []
	for unit in get_tree().get_nodes_in_group("Units"):
		var scene_path: String = ""
		if unit.has_meta("scene_path"):
			scene_path = unit.get_meta("scene_path")
		else:
			print("Warning: Unit ", unit.name, " does not have a scene path stored!")
		data.append({
			"scene_path": scene_path,
			"tile_pos": unit.tile_pos,
			"is_player": unit.is_player,
			"health": unit.health
			# Add additional properties as needed.
		})
	print("Exported unit data: ", data)
	return data


# Exports structure data similarly.
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
			"tile_pos": structure.tile_pos
			# Add additional properties if needed.
		})
	print("Exported structure data: ", data)
	return data


# On the client, use these functions to instantiate units and structures.
func import_unit_data(unit_data: Array) -> void:
	# Remove any existing units.
	for unit in get_tree().get_nodes_in_group("Units"):
		unit.queue_free()
	for info in unit_data:
		var scene_path: String = info.get("scene_path", "")
		if scene_path == "":
			print("Skipping unit import; scene path missing.")
			continue  # Skip if no valid scene path.
		var scene = load(scene_path)
		if scene == null:
			print("Error loading unit scene at: ", scene_path)
			continue
		var unit_instance = scene.instantiate()
		add_child(unit_instance)
		unit_instance.tile_pos = info.get("tile_pos", Vector2i.ZERO)
		unit_instance.is_player = info.get("is_player", true)
		unit_instance.health = info.get("health", 100)
		unit_instance.position = map_to_local(unit_instance.tile_pos)
		unit_instance.position.y -= 8
		unit_instance.add_to_group("Units")
		
		if unit_instance.is_player:
			var sprite = unit_instance.get_node_or_null("AnimatedSprite2D")
			if sprite:
				sprite.flip_h = true		
				
		if !unit_instance.is_player:
			unit_instance.get_child(0).modulate = Color8(255, 110, 255)
			
		# Save the scene path for potential future exports.
		unit_instance.set_meta("scene_path", scene_path)
	print("Imported unit data.")

func import_structure_data(structure_data: Array) -> void:
	# Remove any existing structures.
	for structure in get_tree().get_nodes_in_group("Structures"):
		structure.queue_free()
	for info in structure_data:
		var scene_path: String = info.get("scene_path", "")
		if scene_path == "":
			print("Skipping structure import; scene path missing.")
			continue
		var scene = load(scene_path)
		if scene == null:
			print("Error loading structure scene at: ", scene_path)
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
		
		# Randomly modulate the structure's color within a mid-range.
		# This keeps the RGB values between 0.4 and 0.8.
		var r_val = randf_range(0.4, 0.8)
		var g_val = randf_range(0.4, 0.8)
		var b_val = randf_range(0.4, 0.8)
		structure_instance.modulate = Color(r_val, g_val, b_val, 1)
		
	print("Imported structure data.")

func broadcast_game_state() -> void:
	var map_data = export_map_data()
	var unit_data = export_unit_data()
	var structure_data = export_structure_data()
	# Use an RPC so that every connected client receives the game state.
	rpc("receive_game_state", map_data, unit_data, structure_data)
	print("Game state broadcasted to all peers.")

@rpc
func receive_game_state(map_data: Dictionary, unit_data: Array, structure_data: Array) -> void:
	_generate_client_map(map_data, unit_data, structure_data)
	print("Game state successfully received and rebuilt on the client.")
	
	# Now switch to the main game scene.
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")


func _generate_client_map(map_data: Dictionary, unit_data: Array, structure_data: Array) -> void:
	# Rebuild the tile map from the host's map data.
	import_map_data(map_data)
	# Rebuild units and structures.
	import_unit_data(unit_data)
	import_structure_data(structure_data)
	_setup_camera()
	update_astar_grid()
	print("Client map generated from host data.")
