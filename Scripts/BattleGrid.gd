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

func _ready():
	tile_size = get_tileset().tile_size
	_setup_noise()
	_generate_map()
	_spawn_teams()
	_setup_camera()

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
	_spawn_side(player_units, grid_height - 1, true)
	_spawn_side(enemy_units, 0, false)

func _spawn_side(units: Array[PackedScene], row: int, is_player: bool):
	var count = units.size()
	if count == 0:
		return
	var spacing = float(grid_width) / float(count + 1)
	for i in range(count):
		var x = clamp(int(round(spacing * (i + 1))) - 1, 0, grid_width - 1)
		_spawn_unit(units[i], Vector2i(x, row), is_player)

func _spawn_unit(scene: PackedScene, tile: Vector2i, is_player: bool):
	var spawn_tile = _find_nearest_land(tile)
	if spawn_tile == null:
		print("⚠ No valid spawn tile found near ", tile)
		return

	var unit = scene.instantiate()
	unit.global_position = to_global(map_to_local(spawn_tile)) + tile_size * 0.5
	unit.set_team(is_player)
	add_child(unit)

func _find_nearest_land(start: Vector2i) -> Vector2i:
	if not is_water_tile(start):
		return start

	var max_radius = max(grid_width, grid_height)
	for r in range(1, max_radius):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var pos = start + Vector2i(dx, dy)
				if is_within_bounds(pos) and not is_water_tile(pos):
					return pos

	return Vector2i(-1, -1)  # sentinel meaning “no valid tile”

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
	for unit in get_tree().get_nodes_in_group("Unit"):
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
