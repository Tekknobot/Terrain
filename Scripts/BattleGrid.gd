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
const UnitAction = preload("res://Scripts/UnitAction.gd")
var skip_increment: bool = false

const MISSILE_SCENE := preload("res://Prefabs/Missile.tscn")
const EXPLOSION_SCENE := preload("res://Scenes/VFX/Explosion.tscn")

var attack_source_unit = null
var attack_range_tiles: Array[Vector2i] = []

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
	camera.zoom = Vector2(7, 7)
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

func advance_turn() -> void:
	var units = all_units.filter(func(u): return u.is_player == player_turn)

	if active_unit_index < units.size():
		var unit = units[active_unit_index]
		if player_turn:
			selected_unit = unit
			clear_movement_highlight()
			return
		await handle_enemy_action(unit)

		# Only bump index here if move_unit DIDN’T already do it
		if not skip_increment:
			active_unit_index += 1
		skip_increment = false
		return

	# 🔁 All units have moved → End turn here
	end_turn()


func handle_enemy_action(unit) -> void:
	var action = decide_enemy_action(unit)
	if action:
		if action.type == "move":
			update_astar_grid_ignore(unit)
			var path = astar.get_point_path(unit.tile_pos, action.target)
			if path.size() > 1:
				highlight_path(path)
				await move_unit(unit, action.target)

		elif action.type == "ranged":
			highlight_attack_range(unit.tile_pos, unit.attack_range, 3)  # ✅ show range

			var missile = MISSILE_SCENE.instantiate()
			get_tree().root.get_child(0).add_child(missile)

			var start_local = map_to_local(unit.tile_pos) + tile_size * 0.5
			var end_local   = map_to_local(action.target) + tile_size * 0.5
			missile.set_target(start_local, end_local)
			await missile.finished
			
			clear_attack_highlight()  # ✅ clear attack range
			
			var explosion = EXPLOSION_SCENE.instantiate()
			explosion.global_position = to_global(end_local)
			add_child(explosion)

			var victim = get_unit_at_tile(action.target)
			if victim:
				victim.take_damage(40)
				victim.flash_white()

			if is_instance_valid(unit):
				active_unit_index += 1
				skip_increment = true

			await get_tree().create_timer(0.1).timeout
			clear_movement_highlight()  # remove attack highlights after launch
			advance_turn()
			return

		elif action.type == "attack":
			highlight_attack_range(unit.tile_pos, 1, 3)  # ✅ Melee range
			await try_attack_tile(unit, action.target)
			clear_attack_highlight()  # ✅ Clean up

	
func nearest_player_tile(unit) -> Vector2i:
	var best_tile = Vector2i(-1, -1)
	var best_dist = INF
	for other in all_units:
		if other.is_player:
			var dist = manhattan_distance(unit.tile_pos, other.tile_pos)
			if dist < best_dist:
				best_dist = dist
				best_tile = other.tile_pos
	return best_tile

func try_attack_tile(unit, tile: Vector2i) -> void:
	var enemy = get_unit_at_tile(tile)
	if enemy:	
		# ✅ Play attack sound
		$AudioStreamPlayer2D.stream = ATTACK_SOUND
		$AudioStreamPlayer2D.play()	
				
		unit._set_facing(unit.tile_pos, tile)
		enemy.take_damage(25)
		enemy.flash_white()

func decide_enemy_action(unit) -> UnitAction:
	var start = unit.tile_pos
	var best_action: UnitAction = null

	var reachable = unit.get_reachable_tiles()
	reachable.append(start)

	for target in reachable:
		update_astar_grid_ignore(unit)
		var path = astar.get_point_path(start, target)
		if path.size() == 0:
			continue

		var score = -manhattan_distance(target, nearest_player_tile(unit)) * 10

		# Ranged
		for other in all_units:
			if other.is_player:
				var dist = manhattan_distance(other.tile_pos, unit.tile_pos)

				if dist >= 2 and dist <= unit.attack_range:
					var ranged_action = UnitAction.new("ranged", other.tile_pos)
					ranged_action.score = score + 60 + (100 - other.health)
					if best_action == null or ranged_action.score > best_action.score:
						best_action = ranged_action

		# Movement
		var move_action = UnitAction.new("move", target, path)
		move_action.score = score
		if best_action == null or move_action.score > best_action.score:
			best_action = move_action

	return best_action

func highlight_path(path: Array[Vector2i]):
	clear_movement_highlight()
	for tile in path:
		set_cell(1, tile, highlight_tile_id, Vector2i(0, 0))
	highlighted_tiles = path.duplicate()

func move_unit(unit, target_tile: Vector2i):
	update_astar_grid_ignore(unit)
	var start_tile: Vector2i = unit.tile_pos

	if not is_within_bounds(start_tile):
		print("⚠ Start out of bounds:", start_tile)
		active_unit_index += 1
		skip_increment = true
		advance_turn()
		return

	var path = astar.get_point_path(start_tile, target_tile)
	if path.size() <= 1:
		print("⚠ No path found from", start_tile, "→", target_tile)
		active_unit_index += 1
		skip_increment = true
		advance_turn()
		return
	else:
		print("Path:", path)
		await unit.move_along_path(path)

	var attacked := await try_attack_adjacent(unit)
	await get_tree().create_timer(0.1).timeout

	if is_instance_valid(unit):
		active_unit_index += 1
		skip_increment = true

	advance_turn()

func try_attack_adjacent(unit) -> bool:
	var directions = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	for dir in directions:
		var neighbor = unit.tile_pos + dir
		for target in all_units:
			if target != unit and target.is_player != unit.is_player and target.tile_pos == neighbor:
				if unit.has_method("_set_facing"):
					unit._set_facing(unit.tile_pos, neighbor)

				var sprite = unit.get_node("AnimatedSprite2D")
				if sprite:
					sprite.play("attack")
					
					# ✅ Play attack sound
					$AudioStreamPlayer2D.stream = ATTACK_SOUND
					$AudioStreamPlayer2D.play()						

				target.take_damage(25)
				target.flash_white()

				var push_tile = target.tile_pos + dir
				if is_within_bounds(push_tile) and not is_water_tile(push_tile):
					var other = get_unit_at_tile(push_tile)
					var tween = create_tween()
					tween.tween_property(target, "global_position", map_to_local(push_tile), 0.2)
					await tween.finished

					if is_instance_valid(target):
						if other and is_instance_valid(other):
							target.die()
							other.die()
						else:
							target.tile_pos = push_tile

				await get_tree().create_timer(0.5).timeout

				if sprite:
					sprite.play("default")

				return true
	return false


func get_unit_at_tile(tile: Vector2i) -> Node:
	for unit in all_units:
		if unit.tile_pos == tile:
			return unit
	return null

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
	if event is InputEventMouseButton and event.pressed:
		var local_mouse_pos: Vector2 = to_local(get_global_mouse_position())
		local_mouse_pos.y += 8
		var clicked_tile: Vector2i = local_to_map(local_mouse_pos)

		if not is_within_bounds(clicked_tile):
			return

		# 🔴 Right Click = Toggle Attack Mode
		if event.button_index == MOUSE_BUTTON_RIGHT:
			for unit in all_units:
				if unit.is_player == player_turn and unit.tile_pos == clicked_tile and not unit.has_moved:
					
					# If same unit is already in attack mode → cancel
					if attack_source_unit == unit:
						print("Cancelled attack mode.")
						clear_attack_highlight()
						attack_range_tiles.clear()
						attack_source_unit = null
						return

					# Otherwise, enter attack mode
					print("Entered attack mode for:", unit.unit_type)
					selected_unit = null  # cancel movement mode
					clear_movement_highlight()
					clear_attack_highlight()

					highlight_attack_range(unit.tile_pos, unit.attack_range, 3)
					attack_range_tiles = attack_highlighted_tiles.duplicate()
					attack_source_unit = unit
					return

		# 🟡 Left Click = Confirm Attack / Movement Mode / Deselect
		elif event.button_index == MOUSE_BUTTON_LEFT:
			
			# If in attack mode
			if attack_source_unit:

				# Left-click same unit to switch to movement mode
				if clicked_tile == attack_source_unit.tile_pos:
					print("Switching from attack to movement mode for:", attack_source_unit.unit_type)
					selected_unit = attack_source_unit
					attack_source_unit = null
					attack_range_tiles.clear()
					clear_attack_highlight()
					highlight_movement_range(selected_unit)
					return

				# Left-click valid target in range → attack
				if clicked_tile in attack_range_tiles:
					var enemy = get_unit_at_tile(clicked_tile)
					if enemy and not enemy.is_player:
						print("Attacking enemy at:", clicked_tile)
						await launch_player_missile_attack(attack_source_unit, enemy)
						attack_source_unit = null
						attack_range_tiles.clear()
						clear_attack_highlight()
						return

				# Left-clicked outside range → cancel attack mode
				print("Clicked outside attack range. Cancelled attack mode.")
				attack_source_unit = null
				attack_range_tiles.clear()
				clear_attack_highlight()
				return

			# Else: handle regular selection/movement
			handle_tile_selection(clicked_tile)

func launch_player_missile_attack(source, target):
	var missile = MISSILE_SCENE.instantiate()
	get_tree().root.get_child(0).add_child(missile)

	var start_local = map_to_local(source.tile_pos) + tile_size * 0.5
	var end_local = map_to_local(target.tile_pos) + tile_size * 0.5
	missile.set_target(start_local, end_local)
	await missile.finished

	var explosion = EXPLOSION_SCENE.instantiate()
	explosion.global_position = to_global(end_local)
	add_child(explosion)

	if is_instance_valid(target):
		target.take_damage(40)
		target.flash_white()

	await get_tree().create_timer(0.1).timeout

func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < grid_actual_width and tile.y >= 0 and tile.y < grid_actual_height

func handle_tile_selection(clicked_tile: Vector2i):
	print("Handling tile selection for tile: ", clicked_tile)
	
	if selected_unit and tile_to_map(selected_unit.global_position) == clicked_tile:
		print("Reselecting unit:", selected_unit.unit_type)
		return  
	
	for unit in all_units:
		if unit.tile_pos == clicked_tile and unit.is_player == player_turn:
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

var attack_highlighted_tiles: Array[Vector2i] = []

func highlight_attack_range(origin: Vector2i, range: int, tile_id: int):
	clear_attack_highlight()

	for x in range(origin.x - range, origin.x + range + 1):
		for y in range(origin.y - range, origin.y + range + 1):
			var tile = Vector2i(x, y)
			if manhattan_distance(origin, tile) <= range and is_within_bounds(tile):
				set_cell(1, tile, tile_id, Vector2i(0, 0))
				attack_highlighted_tiles.append(tile)


func clear_attack_highlight(tile_id: int = 3):
	for x in range(grid_actual_width):
		for y in range(grid_actual_height):
			var tile = Vector2i(x, y)
			if get_cell_source_id(1, tile) == tile_id:
				set_cell(1, tile, -1, Vector2i(0, 0))

### **Highlight Movement Range**
func highlight_movement_range(unit):
	if unit.has_moved:
		print(unit.unit_type, "already moved this turn.")
		return	
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

func end_turn():
	print("Ending turn. Switching teams...")

	# Flip turn first
	player_turn = !player_turn

	# Reset has_moved only for units on the new team
	for unit in all_units:
		if unit.is_player == player_turn:
			unit.has_moved = false

	active_unit_index = 0
	await advance_turn()
