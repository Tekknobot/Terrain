extends TileMap

@export var grid_width: int = 10  
@export var grid_height: int = 20  
@export var land_tile_id: int = 4  
@export var water_tile_id: int = 6  
@export var water_rows: int = 3  
@export var player_units: Array[PackedScene]  
@export var enemy_units: Array[PackedScene]  
@export var highlight_tile_id: int = 7  

var player_turn: bool = true  
var all_units: Array = []  
var active_unit_index: int = 0  
var astar := AStarGrid2D.new()  # Using AStarGrid2D  
var tile_size: Vector2  
var camera: Camera2D  
var selected_unit = null  
var highlighted_tiles: Array[Vector2i] = []  

# These will be updated from get_used_rect() to ensure consistency.
var grid_actual_width: int
var grid_actual_height: int

const TILE_WATER = 6
const TILE_SANDSTONE = 10
const TILE_DIRT = 7
const TILE_GRASS = 8
const TILE_SNOW = 9
const TILE_ICE = 11

const INTERSECTION = 12
const DOWN_RIGHT_ROAD = 14
const DOWN_LEFT_ROAD = 13

var base_tiles: Dictionary = {}
var noise := FastNoiseLite.new()

@export var day_duration := 10.0  # Seconds per full day-night cycle
var day_phase := 0.0  # Ranges from 0.0 to 1.0

@onready var ATTACK_SOUND = preload("res://Audio/SFX/attack_default.wav")  # Replace with your actual path

func _ready():
	noise.seed = randi()
	noise.frequency = 0.08  # Controls how large/small terrain patches are
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.4
	noise.fractal_lacunarity = 2.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	
	generate_grid()
	setup_camera()
	spawn_units()
	setup_astar()  # Setup AStar grid using update_astar_grid()
	start_turn()

func _process(delta):
	# Update day phase (0.0 to 1.0)
	day_phase += delta / day_duration
	if day_phase > 1.0:
		day_phase -= 1.0  # Loop

	update_day_night_tint()

func update_day_night_tint():
	# Simulate light intensity (min 0.4 at night, max 1.0 during the day)
	var brightness := 0.7 + 0.3 * sin(PI * 2 * day_phase)

	# Slight bluish tint at night (more subtle)
	var tint := Color(
		brightness,
		brightness,
		brightness + (1.0 - brightness) * 0.1
	)

	set_layer_modulate(0, tint)


### **Generate Grid with Water Division**
func generate_grid():
	var tile_size = Vector2(get_tileset().tile_size)

	for x in range(grid_width):
		for y in range(grid_height):
			var tile_pos = Vector2i(x, y)
			var n = noise.get_noise_2d(float(x), float(y))  # returns value from -1 to 1

			var tile_type := TILE_GRASS  # default fallback

			# Terrain thresholds based on noise value
			if n < -0.6:
				tile_type = TILE_WATER
			elif n < -0.2:
				tile_type = TILE_SANDSTONE
			elif n < 0.1:
				tile_type = TILE_DIRT
			elif n < 0.4:
				tile_type = TILE_GRASS
			elif n < 0.7:
				tile_type = TILE_SNOW
			else:
				tile_type = TILE_ICE

			set_cell(0, tile_pos, tile_type, Vector2i(0, 0))
			base_tiles[tile_pos] = tile_type
	
	# 🛣 Add roads after terrain
	generate_roads()
	
func generate_roads():
	var picked_horizontal_odd_y = []
	var picked_vertical_odd_x = []

	# Randomly pick 2-4 roads
	for i in range(2):
		var horizontal_y = get_unique_random_odd(grid_height, picked_horizontal_odd_y)
		var vertical_x = get_unique_random_odd(grid_width, picked_vertical_odd_x)

		draw_road(Vector2i(0, horizontal_y), Vector2i(1, 0), DOWN_RIGHT_ROAD)  # Horizontal
		draw_road(Vector2i(vertical_x, 0), Vector2i(0, 1), DOWN_LEFT_ROAD)     # Vertical

func draw_road(start: Vector2i, direction: Vector2i, road_tile_id: int):
	var pos = start
	while pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height:
		var tile_id = get_cell_source_id(0, pos)
		if tile_id == DOWN_LEFT_ROAD or tile_id == DOWN_RIGHT_ROAD:
			set_cell(0, pos, INTERSECTION, Vector2i(0, 0))
		else:
			set_cell(0, pos, road_tile_id, Vector2i(0, 0))
		pos += direction

func get_unique_random_odd(max_val: int, used: Array) -> int:
	var tries = 0
	while tries < 20:
		var val = randi_range(1, max_val - 2)
		if val % 2 == 1 and not used.has(val):
			used.append(val)
			return val
		tries += 1
	return 1  # fallback

### **Setup Camera**
func setup_camera():
	await get_tree().process_frame  
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	# Center camera on the grid.
	var grid_center: Vector2 = map_to_local(Vector2i(grid_width / 2, grid_height / 2)) + tile_size / 2.0
	camera.position = grid_center
	camera.zoom = Vector2(5, 5)
	print("Camera position: ", camera.position, " zoom: ", camera.zoom)


### **Update A* Grid Dynamically**
func update_astar_grid() -> void:
	var tilemap: TileMap = self
	var used_rect = tilemap.get_used_rect()
	grid_actual_width = used_rect.size.x
	grid_actual_height = used_rect.size.y
	print("Updating AStar grid using used_rect: ", used_rect)
	
	astar.size = Vector2i(grid_actual_width, grid_actual_height)
	astar.cell_size = Vector2(1, 1)
	astar.default_compute_heuristic = 1
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()  # Clear previous configuration
	
	for x in range(grid_actual_width):
		for y in range(grid_actual_height):
			var tile_position = Vector2i(x, y)
			var tile_id = tilemap.get_cell_source_id(0, tile_position)
			# Mark tile as solid if it's invalid, water, or occupied.
			var is_solid: bool = (tile_id == -1 or tile_id == water_tile_id or is_tile_occupied(tile_position))
			astar.set_point_solid(tile_position, is_solid)
	
	print("AStar grid updated with size:", grid_actual_width, "x", grid_actual_height)


### **Setup the AStar Grid**
func setup_astar() -> void:
	update_astar_grid()
	print("AStar grid setup completed.")


### **Turn Management**
func start_turn():
	active_unit_index = 0  
	advance_turn()

func advance_turn():
	var team_units = all_units.filter(func(u): return u.is_player != player_turn)

	if active_unit_index >= team_units.size():
		player_turn = !player_turn
		active_unit_index = 0
		print("Turn changed! Player Turn:", player_turn)

		if not player_turn:
			var enemy_units = all_units.filter(func(u): return not u.is_player)
			for unit in enemy_units:
				var start_tile = unit.tile_pos  # Current position
				var target_tile = unit.choose_target_tile()
				if target_tile == Vector2i(-1, -1):
					continue
				# Get and highlight the actual path
				update_astar_grid_ignore(unit)
				var path = astar.get_point_path(start_tile, target_tile)

				if path.size() > 1:
					highlight_path(path)
					await get_tree().create_timer(0.4).timeout
					move_unit(unit, target_tile)
					await unit.movement_finished
					clear_movement_highlight()
					await get_tree().create_timer(0.2).timeout
					
	selected_unit = null

func highlight_path(path: Array[Vector2i]):
	clear_movement_highlight()
	for tile in path:
		set_cell(1, tile, highlight_tile_id, Vector2i(0, 0))
	highlighted_tiles = path.duplicate()

func move_unit(unit, target_tile: Vector2i):
	# Force the grid to ignore the moving unit itself
	update_astar_grid_ignore(unit)

	# Use the unit’s stored tile_pos as the true start
	var start_tile: Vector2i = unit.tile_pos

	if not is_within_bounds(start_tile):
		print("⚠ Start out of bounds:", start_tile)
		return

	var path = astar.get_point_path(start_tile, target_tile)
	if path.size() <= 1:
		print("⚠ No path found from", start_tile, "→", target_tile)
	else:
		print("Path:", path)
		await unit.move_along_path(path)  # 🟢 Await move first!

	# ✅ After move, check for adjacent enemy to attack
	var attacked := await try_attack_adjacent(unit)

	await get_tree().create_timer(0.1).timeout  # Slight pause
	selected_unit = null
	active_unit_index += 1
	advance_turn()

func try_attack_adjacent(unit) -> bool:
	var directions = [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)
	]

	for dir in directions:
		var neighbor_tile = unit.tile_pos + dir
		for target in all_units:
			if target != unit and target.is_player != unit.is_player and target.tile_pos == neighbor_tile:
				print("⚔ Attack triggered between", unit.unit_type, "and", target.unit_type)

				# Flip the attacker to face the direction of attack
				if unit.has_method("_set_facing"):
					unit._set_facing(unit.tile_pos, neighbor_tile)

				var sprite = unit.get_node("AnimatedSprite2D")
				if sprite:
					sprite.play("attack")
					
					# 🔊 Play attack sound from existing AudioStreamPlayer2D
					var tilemap = get_tree().get_current_scene().get_node("TileMap")
					if tilemap.has_node("AudioStreamPlayer2D"):
						var sound = tilemap.get_node("AudioStreamPlayer2D")
						sound.stream = ATTACK_SOUND
						sound.global_position = unit.global_position  # Optional: position it at attacker
						sound.play()

				target.take_damage(25)
				target.flash_white()

				# Optional: push the target back
				var push_tile = target.tile_pos + dir
				if is_within_bounds(push_tile) and not is_tile_occupied(push_tile) and not is_water_tile(push_tile):
					var world_pos = map_to_local(push_tile)
					var tween = create_tween()
					tween.tween_property(target, "global_position", world_pos, 0.2)
					target.tile_pos = push_tile
				
				await get_tree().create_timer(0.5).timeout

				if sprite:
					sprite.play("default")
					
				return true
	return false

func update_astar_grid_ignore(selected: Node) -> void:
	var used_rect = get_used_rect()
	grid_actual_width = used_rect.size.x
	grid_actual_height = used_rect.size.y
	print("Updating AStar grid (ignoring selected) using used_rect: ", used_rect)
	
	astar.size = Vector2i(grid_actual_width, grid_actual_height)
	astar.cell_size = Vector2(1, 1)
	astar.default_compute_heuristic = 1
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()  # Clear previous configuration
	
	# Compute the tile for the selected unit (its center)
	var selected_tile: Vector2i = get_unit_tile(selected.global_position)
	
	for x in range(grid_actual_width):
		for y in range(grid_actual_height):
			var pos = Vector2i(x, y)
			# If this is the selected unit’s tile, mark it as free.
			if pos == selected_tile:
				astar.set_point_solid(pos, false)
			else:
				var tile_id = get_cell_source_id(0, pos)
				var solid = (tile_id == -1 or tile_id == water_tile_id or is_tile_occupied(pos))
				astar.set_point_solid(pos, solid)
	print("AStar grid (ignoring selected) updated with size:", grid_actual_width, "x", grid_actual_height)

### **Input Handling (Click Selection & Movement)**
func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Use to_local() to convert global mouse position to local space.
		var local_mouse_pos: Vector2 = to_local(get_global_mouse_position())
		# Apply the offset for selection.
		local_mouse_pos.y += 8
		print("Local mouse pos (with offset): ", local_mouse_pos)
		var clicked_tile: Vector2i = local_to_map(local_mouse_pos)
		print("Clicked tile (after conversion): ", clicked_tile)
		if is_within_bounds(clicked_tile):
			handle_tile_selection(clicked_tile)

func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < grid_actual_width and tile.y >= 0 and tile.y < grid_actual_height

func handle_tile_selection(clicked_tile: Vector2i):
	print("Handling tile selection for tile: ", clicked_tile)
	
	if selected_unit and tile_to_map(selected_unit.global_position) == clicked_tile:
		print("Reselecting unit:", selected_unit.unit_type)
		return  
	
	for unit in all_units:
		if tile_to_map(unit.global_position) == clicked_tile and unit.is_player == player_turn:
			selected_unit = unit
			clear_movement_highlight()
			highlight_movement_range(unit)
			print("Unit selected:", unit.unit_type)
			return  
	
	if selected_unit and clicked_tile in highlighted_tiles:
		print("Moving selected unit to: ", clicked_tile)
		# Note: Do not adjust the tile offset here—use the true tile coordinate.
		move_unit(selected_unit, clicked_tile)
		selected_unit = null
		clear_movement_highlight()
	
	if not is_tile_occupied(clicked_tile):
		selected_unit = null
		clear_movement_highlight()


### **Highlight Movement Range**
func highlight_movement_range(unit):
	clear_movement_highlight()
	var start_tile = tile_to_map(unit.global_position)
	for x in range(grid_actual_width):
		for y in range(grid_actual_height):
			var target_tile = Vector2i(x, y)
			var distance = manhattan_distance(start_tile, target_tile)
			# Use the ignore helper so the selected unit doesn't block its own path.
			if distance <= unit.movement_range and is_valid_spawn_ignore(unit, target_tile):
				highlighted_tiles.append(target_tile)
				set_cell(1, target_tile, highlight_tile_id, Vector2i(0, 0))
	print("Highlighted tiles: ", highlighted_tiles)

func clear_movement_highlight():
	for tile in highlighted_tiles:
		set_cell(1, tile, -1, Vector2i(0, 0))  # ❌ this is outdated
	highlighted_tiles.clear()

### **Utility Functions**
func is_water_tile(tile: Vector2i) -> bool:
	return get_cell_source_id(0, tile) == water_tile_id

func is_tile_occupied(tile: Vector2i) -> bool:
	for unit in all_units:
		if tile_to_map(unit.global_position) == tile:
			return true
	return false

func is_valid_spawn(tile: Vector2i) -> bool:
	return not is_water_tile(tile) and not is_tile_occupied(tile)

# New helper: Ignore occupancy for the selected unit.
func is_tile_occupied_ignore(selected: Node, tile: Vector2i) -> bool:
	for unit in all_units:
		if unit != selected and tile_to_map(unit.global_position) == tile:
			return true
	return false

func is_valid_spawn_ignore(selected: Node, tile: Vector2i) -> bool:
	return not is_water_tile(tile) and not is_tile_occupied_ignore(selected, tile)

func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# Convert a world position to tile coordinate by converting to local space first.
func tile_to_map(world_position: Vector2) -> Vector2i:
	return local_to_map(to_local(world_position))

### **Spawn Units (North/South Sides)**
func spawn_units():
	var land_start_south = grid_height - 2  
	var land_start_north = 1  
	var available_columns = grid_width - 2  
	var unit_spacing = available_columns / 3  
	
	for i in range(6):
		var spawn_x = (i % 3) * unit_spacing + 1  
		var spawn_y = land_start_south - (i / 3)
		var spawn_pos = Vector2i(spawn_x, spawn_y)
		if is_valid_spawn(spawn_pos):
			var unit_scene = player_units[i].instantiate()
			# Use to_global(map_to_local(...)) to convert tile coordinates to global.
			unit_scene.global_position = to_global(map_to_local(spawn_pos)) + tile_size / 2
			unit_scene.set_team(true)
			all_units.append(unit_scene)
			add_child(unit_scene)
			print("Spawned player unit at tile: ", spawn_pos)
	
	for i in range(6):
		var spawn_x = (i % 3) * unit_spacing + 1  
		var spawn_y = land_start_north + (i / 3)
		var spawn_pos = Vector2i(spawn_x, spawn_y)
		if is_valid_spawn(spawn_pos):
			var unit_scene = enemy_units[i].instantiate()
			unit_scene.global_position = to_global(map_to_local(spawn_pos)) + tile_size / 2
			unit_scene.set_team(false)
			unit_scene.modulate = Color(1, 110.0 / 255.0, 1)
			all_units.append(unit_scene)
			add_child(unit_scene)
			print("Spawned enemy unit at tile: ", spawn_pos)

# Converts a world position to the tile coordinate corresponding to its center.
func get_unit_tile(world_position: Vector2) -> Vector2i:
	var local_pos: Vector2 = to_local(world_position)
	# Divide by tile_size and round to the nearest integer.
	return Vector2i(round(local_pos.x / tile_size.x), round(local_pos.y / tile_size.y))
