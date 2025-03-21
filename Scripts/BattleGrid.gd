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

func _ready():
	generate_grid()
	setup_camera()
	spawn_units()
	setup_astar()  # Setup AStar grid using update_astar_grid()
	start_turn()


### **Generate Grid with Water Division**
func generate_grid():
	# Use exported grid_width and grid_height for initial layout.
	var water_start = grid_height / 2 - water_rows / 2  
	var water_end = water_start + water_rows  
	tile_size = Vector2(get_tileset().tile_size)
	
	print("Tile size: ", tile_size, " water_start: ", water_start, " water_end: ", water_end)
	
	for x in range(grid_width):
		for y in range(grid_height):
			if y >= water_start and y < water_end:
				set_cell(0, Vector2i(x, y), water_tile_id, Vector2i(0, 0))
			else:
				set_cell(0, Vector2i(x, y), land_tile_id, Vector2i(0, 0))


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
	if active_unit_index >= all_units.size():
		player_turn = !player_turn
		active_unit_index = 0
		print("Turn changed! Player Turn:", player_turn)

		# If it’s now the enemy’s turn, let them all move immediately
		if not player_turn:
			for unit in all_units:
				if not unit.is_player:
					# Highlight AI unit’s movement range
					highlight_movement_range(unit)
					
					await get_tree().create_timer(1).timeout

					# Command the unit to move
					unit.start_turn()

					# Clear highlights so next unit can show theirs
					clear_movement_highlight()
					await get_tree().create_timer(2).timeout
			player_turn = true
			print("AI finished. Back to player turn.")

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
		unit.move_along_path(path)
	selected_unit = null
	active_unit_index += 1
	advance_turn()

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
				set_cell(0, target_tile, highlight_tile_id, Vector2i(0, 0))
	print("Highlighted tiles: ", highlighted_tiles)

func clear_movement_highlight():
	for tile in highlighted_tiles:
		set_cell(0, tile, land_tile_id, Vector2i(0, 0))
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
