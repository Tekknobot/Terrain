# File: MapGen.gd
# Attach to: IsoGrid/TileMap
extends TileMap

# ------------------------------------------------------------
# CONSTANTS (tile sources used for special road/overlay IDs)
# ------------------------------------------------------------
const INTERSECTION     := 12
const DOWN_RIGHT_ROAD  := 14
const DOWN_LEFT_ROAD   := 13

# ------------------------------------------------------------
# EXPORTS — grid, noise thresholds, tile sources
# ------------------------------------------------------------
@export var grid_width:  int = 10
@export var grid_height: int = 20

# Noise thresholds → controls biome bands
@export var water_threshold     := -0.6
@export var sandstone_threshold :=  0.0
@export var dirt_threshold      :=  0.2
@export var grass_threshold     :=  0.4
@export var snow_threshold      :=  0.6
@export var ice_fraction: float = 0.5   # 0..1 → how much of the snow band becomes ice

# Source IDs in your TileSet
@export var water_tile_id     := 6
@export var sandstone_tile_id := 10
@export var dirt_tile_id      := 7
@export var grass_tile_id     := 8
@export var snow_tile_id      := 9
@export var ice_tile_id       := 11

# Road generation toggles
@export var generate_roads: bool = true
@export var min_road_pairs: int = 1     # each "pair" = 1 horizontal + 1 vertical
@export var max_road_pairs: int = 3
@export var road_gap:       int = 1     # spacing between parallel roads

# Structures
@export var structure_scenes: Array[PackedScene] = []
@export var max_structures: int = 10   # will be recalculated (base + per-road bonus)

# Optional: quick regenerate on scene run
@export var clear_before_gen: bool = true

# ------------------------------------------------------------
# INTERNALS
# ------------------------------------------------------------
var noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _road_count := 0

func _ready() -> void:
	# ✅ Force full opacity on this TileMap
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)

	_setup_noise()
	if clear_before_gen:
		clear_map()
	_generate_map()

# ------------------------------------------------------------
# PUBLIC: regenerate the map (call from buttons, etc.)
# ------------------------------------------------------------
func regenerate(seed: int = -1) -> void:
	if seed != -1:
		noise.seed = seed
	else:
		noise.seed = randi()
	clear_map()
	_generate_map()

# ------------------------------------------------------------
# CORE GENERATION
# ------------------------------------------------------------
func clear_map() -> void:
	for x in range(grid_width):
		for y in range(grid_height):
			set_cell(0, Vector2i(x, y), -1)
	# also remove any existing structures
	for s in get_tree().get_nodes_in_group("Structures"):
		if is_instance_valid(s):
			s.queue_free()

func _generate_map() -> void:
	# Paint terrain instantly
	for x in range(grid_width):
		for y in range(grid_height):
			var n := noise.get_noise_2d(x, y)
			var tile_id := _pick_tile_from_noise(n)
			set_cell(0, Vector2i(x, y), tile_id, Vector2i.ZERO)

	if generate_roads:
		_generate_roads()

	# Spawn structures last so placement respects terrain/roads
	spawn_structures()

	# keep fully opaque just in case
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)
	visible = true

# ------------------------------------------------------------
# NOISE
# ------------------------------------------------------------
func _setup_noise() -> void:
	noise.seed = randi()
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.4
	noise.fractal_lacunarity = 2.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM

func _pick_tile_from_noise(n: float) -> int:
	if n < water_threshold:
		return water_tile_id
	elif n < sandstone_threshold:
		return sandstone_tile_id
	elif n < dirt_threshold:
		return dirt_tile_id
	elif n < grass_threshold:
		return grass_tile_id

	# shrink the snow band by ice_fraction
	var effective_snow_threshold := 1.0 - ice_fraction * (1.0 - snow_threshold)
	if n < effective_snow_threshold:
		return snow_tile_id
	return ice_tile_id

# ------------------------------------------------------------
# ROADS
# ------------------------------------------------------------
func _generate_roads() -> void:
	_road_count = 0
	var used_h: Array[int] = []
	var used_v: Array[int] = []
	var pairs = clamp(_rng.randi_range(min_road_pairs, max_road_pairs), 0, 64)

	for i in range(pairs):
		# Horizontal road (→) at random row with spacing
		var hy := _unique_index_with_gap(grid_height, used_h, road_gap)
		_draw_road(Vector2i(0, hy), Vector2i(1, 0), DOWN_RIGHT_ROAD)
		_road_count += 1

		# Vertical road (↓) at random column with spacing
		var vx := _unique_index_with_gap(grid_width, used_v, road_gap)
		_draw_road(Vector2i(vx, 0), Vector2i(0, 1), DOWN_LEFT_ROAD)
		_road_count += 1

func _draw_road(start: Vector2i, dir: Vector2i, road_id: int) -> void:
	var p := start
	while p.x >= 0 and p.x < grid_width and p.y >= 0 and p.y < grid_height:
		var current := get_cell_source_id(0, p)
		if current == DOWN_LEFT_ROAD or current == DOWN_RIGHT_ROAD:
			set_cell(0, p, INTERSECTION, Vector2i.ZERO)
		else:
			set_cell(0, p, road_id, Vector2i.ZERO)
		p += dir

func _unique_index_with_gap(limit: int, used: Array, gap: int) -> int:
	# Try random picks first
	for i in range(100):
		var v := _rng.randi_range(0, limit - 1)
		var ok := true
		for u in used:
			if abs(v - int(u)) <= gap:
				ok = false; break
		if ok:
			used.append(v)
			return v

	# Deterministic fallback scan
	for v in range(limit):
		var ok := true
		for u in used:
			if abs(v - int(u)) <= gap:
				ok = false; break
		if ok:
			used.append(v)
			return v

	# If we truly can't fit another with the gap, relax to unique-only
	return _unique_index(limit, used)

func _unique_index(limit: int, used: Array) -> int:
	for i in range(50):
		var v := _rng.randi_range(0, limit - 1)
		if not used.has(v):
			used.append(v)
			return v
	for v in range(limit):
		if not used.has(v):
			used.append(v)
			return v
	return 0

# ------------------------------------------------------------
# STRUCTURES — placement rules & helpers
# ------------------------------------------------------------
func spawn_structures() -> void:
	if structure_scenes.is_empty():
		return

	var count := 0
	var attempts := 0
	var max_attempts := grid_width * grid_height * 5

	# Base + bonus per road (same spirit as your original)
	var base := 3
	var bonus_per_road := 2
	max_structures = clamp(base + int(_road_count * bonus_per_road), 3, 12)

	while count < max_structures and attempts < max_attempts:
		attempts += 1
		var x := _rng.randi_range(0, grid_width - 1)
		var y := _rng.randi_range(0, grid_height - 1)
		var pos := Vector2i(x, y)
		var tile_id := get_cell_source_id(0, pos)

		# --- Terrain / road rules ---
		if tile_id == water_tile_id \
		or tile_id == INTERSECTION \
		or tile_id == DOWN_RIGHT_ROAD \
		or tile_id == DOWN_LEFT_ROAD:
			continue

		# --- Keep a clear perimeter ring (no edge spawns) ---
		if _is_edge(pos, 1):
			continue

		# --- Keep at least 1 tile spacing between structures (no diagonal touching) ---
		if _has_nearby_structure(pos, 1):
			continue

		# --- No stacking ---
		if is_tile_occupied(pos):
			continue

		# Strong connectivity: pretend we block pos and its 4-neighbors (fat structure)
		var fat_blocks: Array[Vector2i] = [
			pos,
			pos + Vector2i(1, 0),
			pos + Vector2i(-1, 0),
			pos + Vector2i(0, 1),
			pos + Vector2i(0, -1),
		]

		# 1) still globally connected?
		if not _zones_connected_with_block_area(fat_blocks):
			continue
		# 2) won’t produce a full wall across a row/column?
		if _would_create_wall(pos):
			continue

		# Place the structure
		var scene_idx := _rng.randi_range(0, structure_scenes.size() - 1)
		var structure := structure_scenes[scene_idx].instantiate()

		# Track tile pos in meta so our helpers can always read it
		structure.set_meta("tile_pos", pos)
		# try to set property if it exists (safe fallback via meta above)
		if structure.has_method("set_tile_pos"):
			structure.set_tile_pos(pos)
		else:
			# avoid structure.set("tile_pos", pos) because it errors if property doesn't exist
			pass

		# place in world
		structure.global_position = to_global(map_to_local(pos))
		structure.add_to_group("Structures")

		# random tint (fully opaque; no fades)
		var r_val := randf_range(0.4, 0.8)
		var g_val := randf_range(0.4, 0.8)
		var b_val := randf_range(0.4, 0.8)
		structure.modulate = Color(r_val, g_val, b_val, 1.0)

		add_child(structure)
		count += 1

# --- utility used by structure logic ---
func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < grid_width and tile.y >= 0 and tile.y < grid_height

func is_water_tile(tile: Vector2i) -> bool:
	return get_cell_source_id(0, tile) == water_tile_id

func is_tile_occupied(tile: Vector2i) -> bool:
	# occupied = any structure sits on the tile
	return get_structure_at_tile(tile) != null

func _get_structure_tile_pos(s: Node) -> Vector2i:
	# Prefer property if present, otherwise meta
	var p = s.get("tile_pos")
	if typeof(p) == TYPE_VECTOR2I:
		return p
	if s.has_meta("tile_pos"):
		return s.get_meta("tile_pos")
	return Vector2i(-9999, -9999)

func get_structure_at_tile(tile: Vector2i) -> Node:
	for s in get_tree().get_nodes_in_group("Structures"):
		if not is_instance_valid(s): continue
		if _get_structure_tile_pos(s) == tile:
			return s
	return null

func _is_walkable_for_path(tile: Vector2i) -> bool:
	# Used by connectivity checks: walkable if inside, not water, no structures
	return is_within_bounds(tile) \
		and not is_water_tile(tile) \
		and get_structure_at_tile(tile) == null

func get_neighbors(tile: Vector2i) -> Array[Vector2i]:
	return [
		tile + Vector2i(1, 0),
		tile + Vector2i(-1, 0),
		tile + Vector2i(0, 1),
		tile + Vector2i(0, -1),
	]

func _is_edge(t: Vector2i, margin: int = 1) -> bool:
	return t.x < margin or t.y < margin or t.x >= grid_width - margin or t.y >= grid_height - margin

func _has_nearby_structure(center: Vector2i, radius: int = 1) -> bool:
	for s in get_tree().get_nodes_in_group("Structures"):
		if not is_instance_valid(s): continue
		var st := _get_structure_tile_pos(s)
		# Chebyshev distance ≤ radius (blocks diagonal touching)
		var dx = abs(center.x - st.x)
		var dy = abs(center.y - st.y)
		if max(dx, dy) <= radius:
			return true
	return false

# Treat an arbitrary set of tiles as extra blocked when validating connectivity.
func _zones_connected_with_block_area(extra_blocks: Array[Vector2i]) -> bool:
	var extra := {}
	for b in extra_blocks:
		extra[b] = true

	var start := Vector2i(-1, -1)
	var player_zone := Rect2i(0, grid_height - int(grid_height / 3), grid_width, int(grid_height / 3))
	var enemy_zone  := Rect2i(0, 0, grid_width, int(grid_height / 3))

	var enemy_targets: Array[Vector2i] = []
	for y in range(enemy_zone.position.y, enemy_zone.position.y + enemy_zone.size.y):
		for x in range(enemy_zone.position.x, enemy_zone.position.x + enemy_zone.size.x):
			var t := Vector2i(x, y)
			if extra.has(t): continue
			if _is_walkable_for_path(t):
				enemy_targets.append(t)

	for y in range(player_zone.position.y, player_zone.position.y + player_zone.size.y):
		for x in range(player_zone.position.x, player_zone.position.x + player_zone.size.x):
			var t2 := Vector2i(x, y)
			if extra.has(t2): continue
			if _is_walkable_for_path(t2):
				start = t2
				break
		if start != Vector2i(-1, -1):
			break

	if start == Vector2i(-1, -1) or enemy_targets.is_empty():
		return true  # nothing meaningful to connect → treat as okay

	# BFS from start to any enemy target, avoiding extra-blocked tiles
	var q := [start]
	var seen := { start: true }
	while q.size() > 0:
		var cur: Vector2i = q.pop_front()
		if enemy_targets.has(cur):
			return true
		for n in get_neighbors(cur):
			if extra.has(n): continue
			if not seen.has(n) and _is_walkable_for_path(n):
				seen[n] = true
				q.append(n)

	return false

# Does adding a block at pos complete a full wall across a row/column?
func _would_create_wall(pos: Vector2i) -> bool:
	# Row check
	var row_blocked := true
	for x in range(grid_width):
		var t := Vector2i(x, pos.y)
		if t == pos:
			continue
		if _is_walkable_for_path(t):
			row_blocked = false
			break
	# Column check
	var col_blocked := true
	for y in range(grid_height):
		var t2 := Vector2i(pos.x, y)
		if t2 == pos:
			continue
		if _is_walkable_for_path(t2):
			col_blocked = false
			break
	return row_blocked or col_blocked
