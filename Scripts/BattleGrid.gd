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

const MOVE_SPEED := 75.0  # pixels/sec
var current_path := []
var moving := false

func _ready():
	tile_size = get_tileset().tile_size
	_setup_noise()
	_generate_map()

	call_deferred("_post_map_generation")  # Wait until the next frame

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_tile = local_to_map(to_local(Vector2(get_global_mouse_position().x, get_global_mouse_position().y + 8)))
		if selected_unit and highlighted_tiles.has(mouse_tile) and not showing_attack:
			_move_selected_to(mouse_tile)
		else:
			_select_unit_at_mouse()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		get_tree().reload_current_scene()

func _select_unit_at_mouse():
	# Clear previous highlights
	for tile in highlighted_tiles:
		set_cell(1, tile, _get_tile_id_from_noise(noise.get_noise_2d(tile.x, tile.y)))
	highlighted_tiles.clear()

	var mouse_pos = get_global_mouse_position()
	mouse_pos.y += 8
	var tile = local_to_map(to_local(mouse_pos))
	var unit = get_unit_at_tile(tile)

	if unit:
		if unit == selected_unit:
			showing_attack = not showing_attack
		else:
			selected_unit = unit
			showing_attack = false

		var range = 0
		var tile_id = 0
		if showing_attack:
			range = selected_unit.attack_range
			tile_id = attack_tile_id
		else:
			range = selected_unit.movement_range
			tile_id = highlight_tile_id

		_highlight_range(tile, range, tile_id)
	else:
		selected_unit = null
		showing_attack = false

func _highlight_range(start: Vector2i, max_dist: int, tile_id: int):
	var frontier = [start]
	var distances = { start: 0 }

	while frontier.size() > 0:
		var current = frontier.pop_front()
		var dist = distances[current]

		if dist > 0:
			set_cell(1, current, tile_id, Vector2i.ZERO)
			highlighted_tiles.append(current)
		if dist == max_dist:
			continue

		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor = current + dir
			if is_within_bounds(neighbor) and not distances.has(neighbor) and _is_tile_walkable(neighbor):
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
	current_path = astar.get_point_path(selected_unit.tile_pos, target)
	if current_path.is_empty():
		return
	moving = true

func _physics_process(delta):
	if moving:
		var next_tile = current_path[0]
		var world_pos = to_global(map_to_local(next_tile))
		
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
			selected_unit.global_position = world_pos
			selected_unit.tile_pos = next_tile
			current_path.remove_at(0)

			if current_path.is_empty():
				moving = false
				update_astar_grid()   # Refresh walkability now that the unit moved
				_clear_highlights()   # Remove any leftover range tiles
				sprite.play("default")


func _clear_highlights():
	# Restore all movement highlights
	for pos in highlighted_tiles:
		set_cell(1, pos, _get_tile_id_from_noise(noise.get_noise_2d(pos.x, pos.y)))
	highlighted_tiles.clear()

func _post_map_generation():
	_spawn_teams()
	_setup_camera()
	update_astar_grid()

func update_astar_grid() -> void:
	var tilemap = self
	var used_rect = tilemap.get_used_rect()
	grid_actual_width = used_rect.size.x
	grid_actual_height = used_rect.size.y

	astar.clear()
	astar.cell_size = Vector2(1, 1)
	astar.default_compute_heuristic = 1
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER

	# IMPORTANT: set grid size so neighbors get connected
	astar.size = Vector2i(grid_actual_width, grid_actual_height)

	# Create all walkable points
	for x in range(grid_actual_width):
		for y in range(grid_actual_height):
			var pos = Vector2i(x, y)
			var tile_id = tilemap.get_cell_source_id(0, pos)
			if tile_id != -1 and tile_id != water_tile_id:
				astar.set_point_solid(pos, false)

	# Build neighbor links
	astar.update()

	# Block occupied tiles
	for unit in get_tree().get_nodes_in_group("Units"):
		astar.set_point_solid(unit.tile_pos, true)

	print("AStar grid updated:", grid_actual_width, "x", grid_actual_height)
	
func is_tile_occupied(tile: Vector2i) -> bool:
	return get_unit_at_tile(tile) != null

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

	var spacing = float(grid_width) / float(count + 1)

	for i in range(count):
		var x = clamp(int(round(spacing * (i + 1))) - 1, 0, grid_width - 1)
		_spawn_unit(units[i], Vector2i(x, row), is_player, used_tiles)

func _spawn_unit(scene: PackedScene, tile: Vector2i, is_player: bool, used_tiles: Array[Vector2i]):
	var spawn_tile = _find_nearest_land(tile, used_tiles)

	if spawn_tile == Vector2i(-1, -1):
		print("⚠ No valid land tile found for unit near ", tile)
		return

	var unit = scene.instantiate()
	unit.global_position = to_global(map_to_local(spawn_tile))
	unit.set_team(is_player)
	unit.add_to_group("Units")
	unit.tile_pos = spawn_tile  # optional tracking on unit
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
	var camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	var center_tile = Vector2(grid_width * 0.5, grid_height * 0.5)
	camera.position = to_global(map_to_local(center_tile))
	camera.zoom = Vector2(6, 6)
	print("Camera centered at grid midpoint:", center_tile, "world:", camera.position)

func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < grid_width and tile.y >= 0 and tile.y < grid_height
 
