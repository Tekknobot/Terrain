extends TileMap

const INTERSECTION = 12
const DOWN_RIGHT_ROAD = 14
const DOWN_LEFT_ROAD = 13

@export var grid_width: int = 10
@export var grid_height: int = 20

@export var water_threshold := -0.6
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

var all_units: Array[Node2D]
var current_unit_index := 0
var planning_phase := true
var planned_units := 0
var completed_units

@export var structure_scenes: Array[PackedScene]  # Add 6 structure scenes here
@export var max_structures: int = 10

func _ready():
	tile_size = get_tileset().tile_size
	_setup_noise()
	_generate_map()

	call_deferred("_post_map_generation")  # Wait until the next frame

func _post_map_generation():
	_spawn_teams()
	spawn_structures()  # Spawn structures after the map is generated.		
	_setup_camera()
	update_astar_grid()

	print("✅ Map post-gen complete. All units:")
	for unit in get_tree().get_nodes_in_group("Units"):
		print("  -", unit.name, "at", unit.tile_pos, "is_player:", unit.is_player)
	
func _input(event):
	if event is InputEventMouseButton and event.pressed:
		var mouse_tile = local_to_map(to_local(Vector2(get_global_mouse_position().x, get_global_mouse_position().y + 16)))
		if moving == true:
			return
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Left click → select or move (movement only)
			if selected_unit and highlighted_tiles.has(mouse_tile) and showing_attack == false:
				_move_selected_to(mouse_tile)
			else:
				_select_unit_at_mouse()
		
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right click → show attack range only, don't change selected unit
			if selected_unit:
				showing_attack = true
				_clear_highlights()
				_show_range_for_selected_unit()

	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				get_tree().reload_current_scene()
			KEY_1:
				toggle_borders()	
						

var borders_visible := false

func toggle_borders():
	borders_visible = not borders_visible

	for unit in get_tree().get_nodes_in_group("Units"):
		for name in ["HealthBorder","XPBorder","HealthUI","XPUI"]:
			var node = unit.get_node_or_null(name)
			if node:
				node.visible = borders_visible
				
func _select_unit_at_mouse():
	_clear_highlights()

	var mouse_pos = get_global_mouse_position()
	mouse_pos.y += 16
	var tile = local_to_map(to_local(mouse_pos))
	var unit = get_unit_at_tile(tile)

	# Prevent any movement updates if the unit has already moved
	if unit == null:
		return
		
	if unit.has_moved:
		return
		
	if unit:
		selected_unit = unit
		showing_attack = false
		_show_range_for_selected_unit()
	else:
		selected_unit = null
		showing_attack = false
		
	play_beep_sound(tile)	

func _show_range_for_selected_unit():
	var range = 0
	var tile_id = 0

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
	# If we're in attack mode, allow highlighting occupied tiles.
	var allow_occupied = (tile_id == attack_tile_id)
	
	var frontier = [start]
	var distances = { start: 0 }

	while frontier.size() > 0:
		var current = frontier.pop_front()
		var dist = distances[current]

		# Only highlight if it's not water and (if not allowing occupied, ensure it's not occupied)
		if dist > 0:
			if not is_water_tile(current) and (allow_occupied or not is_tile_occupied(current)):
				set_cell(1, current, tile_id, Vector2i.ZERO)
				highlighted_tiles.append(current)

		if dist == max_dist:
			continue

		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor = current + dir
			# When exploring neighbors, only check for occupancy if we're not in attack mode.
			if is_within_bounds(neighbor) \
			and not distances.has(neighbor) \
			and _is_tile_walkable(neighbor) \
			and (allow_occupied or not is_tile_occupied(neighbor)):
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
				sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)  # Dark gray tint
				
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

func _spawn_unit(scene: PackedScene, tile: Vector2i, is_player: bool, used_tiles: Array[Vector2i]):
	var spawn_tile = _find_nearest_land(tile, used_tiles)

	if spawn_tile == Vector2i(-1, -1):
		print("⚠ No valid land tile found for unit near ", tile)
		return

	var unit = scene.instantiate()
	unit.global_position = to_global(map_to_local(spawn_tile)) + Vector2(0, unit.Y_OFFSET)
	unit.set_team(is_player)
	unit.add_to_group("Units")
	unit.tile_pos = spawn_tile
	add_child(unit)

	used_tiles.append(spawn_tile)

func _find_nearest_land(start: Vector2i, used_tiles: Array[Vector2i]) -> Vector2i:
	var direction := -1  # default = upward (for player units)

	# if enemy side, move downward
	if start.y == 0:
		direction = 1

	var pos := start
	while is_within_bounds(pos):
		if not is_water_tile(pos) and not used_tiles.has(pos):
			return pos
		pos.y += direction

	push_warning("⚠ No valid land tile found in straight path from %s" % start)
	return Vector2i(-1, -1)

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
	camera.zoom = Vector2(4, 4) 
	
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
	var max_attempts = grid_width * grid_height * 5  # Arbitrary limit to avoid infinite loops

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
		
		# Position the structure in world space.
		structure.global_position = to_global(map_to_local(pos))
		
		# Optionally, set the tile_pos property if available.
		if structure.has_method("set_tile_pos"):
			structure.set_tile_pos(pos)
		elif structure.has_variable("tile_pos"):
			structure.tile_pos = pos
		
		# Randomly modulate the structure's color within a mid-range.
		# This keeps the RGB values between 0.4 and 0.8.
		var r = randf_range(0.4, 0.8)
		var g = randf_range(0.4, 0.8)
		var b = randf_range(0.4, 0.8)
		structure.modulate = Color(r, g, b, 1)
		
		# Add the structure to the "Structures" group.
		structure.add_to_group("Structures")
		
		# Add the structure as a child to the TileMap (or your dedicated parent node).
		add_child(structure)
		
		# Mark this tile as occupied in the AStar grid.
		astar.set_point_solid(pos, true)
		
		count += 1

	if count < max_structures:
		print("Spawned only", count, "structures after", attempts, "attempts.")
	else:
		print("Spawned", count, "structures.")
