# File: Spawner.gd
# Attach to: IsoGrid/Spawner (Node or Node2D)
extends Node

# --- references ---
@export var tilemap_path: NodePath = ^"../TileMap"

# --- prefabs ---
@export var player_prefabs: Array[PackedScene] = []
@export var enemy_prefabs: Array[PackedScene] = []

# --- counts ---
@export var player_count: int = 1
@export var enemy_count: int = 5

# --- placement rules ---
@export var avoid_roads: bool = true
@export var edge_margin: int = 1
@export var max_attempts_per_unit: int = 300

# y offset used by your sprites (so feet sit on the tile nicely)
@export var y_offset: float = -8.0

# Road IDs (match MapGen.gd constants)
@export var road_ids: PackedInt32Array = [13, 14, 12]  # DOWN_LEFT_ROAD, DOWN_RIGHT_ROAD, INTERSECTION

# Map ready gating
@export var wait_for_map_ready: bool = true           # wait for painted tiles
@export var require_structures_ready: bool = false    # also wait until at least one structure exists
@export var map_ready_timeout_sec: float = 5.0        # max time to wait before proceeding anyway

# Auto spawn
@export var auto_spawn_on_ready: bool = false
@export var auto_players: int = 1
@export var auto_enemies: int = 5

var _tilemap: TileMap

func _ready() -> void:
	randomize()
	_tilemap = get_node_or_null(tilemap_path) as TileMap
	if _tilemap == null:
		push_error("Spawner: TileMap not found at tilemap_path.")
		return

	# If auto-spawn is enabled, wait for the map then spawn.
	if auto_spawn_on_ready:
		await _ensure_map_ready()
		spawn_players(auto_players)
		spawn_enemies(auto_enemies)

# ─────────────────────────────────────────────────────────────
# Public API (ANYWHERE open; no zones)
# ─────────────────────────────────────────────────────────────
func spawn_players(count: int = -1) -> void:
	await _ensure_map_ready()

	if player_prefabs.is_empty():
		push_warning("Spawner: No player_prefabs assigned.")
		return
	if count <= 0:
		count = max(1, player_count)

	var idx := 0
	for i in range(count):
		var tile := _find_open_tile_anywhere_relaxed()
		if tile == Vector2i(-1, -1):
			push_warning("Spawner: Could not find open tile for player " + str(i))
			break
		var scene := player_prefabs[idx % player_prefabs.size()]
		idx += 1
		_spawn_unit(scene, tile, true)

func spawn_enemies(count: int = -1) -> void:
	await _ensure_map_ready()

	if enemy_prefabs.is_empty():
		push_warning("Spawner: No enemy_prefabs assigned.")
		return
	if count <= 0:
		count = max(1, enemy_count)

	var idx := 0
	for i in range(count):
		var tile := _find_open_tile_anywhere_relaxed()
		if tile == Vector2i(-1, -1):
			push_warning("Spawner: Could not find open tile for enemy " + str(i))
			break
		var scene := enemy_prefabs[idx % enemy_prefabs.size()]
		idx += 1
		_spawn_unit(scene, tile, false)

func spawn_wave(players: int, enemies: int) -> void:
	spawn_players(players)
	spawn_enemies(enemies)

# ─────────────────────────────────────────────────────────────
# Map readiness gating
# ─────────────────────────────────────────────────────────────
func _ensure_map_ready() -> bool:
	if not wait_for_map_ready:
		return true
	if _tilemap == null:
		return false

	var deadline_ms := int(map_ready_timeout_sec * 1000.0)
	var start_ms := Time.get_ticks_msec()

	while true:
		var used := _tilemap.get_used_rect()
		var painted := (used.size != Vector2i.ZERO)

		var structures_ok := true
		if require_structures_ready:
			structures_ok = get_tree().get_nodes_in_group("Structures").size() > 0

		if painted and structures_ok:
			return true

		if Time.get_ticks_msec() - start_ms >= deadline_ms:
			# Proceed anyway; log why
			if not painted:
				push_warning("Spawner: Map not painted (used_rect empty) before timeout; proceeding anyway.")
			elif require_structures_ready and not structures_ok:
				push_warning("Spawner: No structures found before timeout; proceeding anyway.")
			return painted

		await get_tree().process_frame

	# Safety: satisfy static analysis (should never reach here)
	return false

# ─────────────────────────────────────────────────────────────
# Core spawn
# ─────────────────────────────────────────────────────────────
func _spawn_unit(scene: PackedScene, tile: Vector2i, is_player: bool) -> void:
	var u := scene.instantiate() as Node2D
	if u == null:
		push_warning("Spawner: instantiate() returned null.")
		return

	var world_center := _tile_to_world_center(tile)
	u.global_position = world_center + Vector2(0, y_offset)

	u.add_to_group("Units")
	if is_player:
		u.add_to_group("Player")
	else:
		u.add_to_group("Enemies")

	u.set_meta("tile_pos", tile)

	# world-space z sort
	if u.has_method("set"):
		u.set("z_as_relative", false)
		u.set("z_index", int(u.global_position.y))

	add_child(u)

	var role := "Player"
	if not is_player:
		role = "Enemy"
	print("Spawner: spawned " + role + " at " + str(tile))

# ─────────────────────────────────────────────────────────────
# Tile selection (ANYWHERE) with progressive relaxation
# ─────────────────────────────────────────────────────────────
func _find_open_tile_anywhere_relaxed() -> Vector2i:
	var gw := _grid_w()
	var gh := _grid_h()
	if gw <= 0 or gh <= 0:
		push_warning("Spawner: Map has no painted tiles (used_rect empty).")
		return Vector2i(-1, -1)

	# Pass A: strict rules
	var t := _find_open_tile_anywhere(gw, gh, edge_margin, true)
	if t != Vector2i(-1, -1):
		return t

	# Pass B: ignore roads
	t = _find_open_tile_anywhere(gw, gh, edge_margin, false)
	if t != Vector2i(-1, -1):
		return t

	# Pass C: shrink edge margin to zero (last resort)
	t = _find_open_tile_anywhere(gw, gh, 0, false)
	return t

func _find_open_tile_anywhere(gw: int, gh: int, margin: int, respect_roads: bool) -> Vector2i:
	# Random attempts
	for _i in range(max_attempts_per_unit):
		var min_x := margin
		var max_x = max(margin, gw - 1 - margin)
		var min_y := margin
		var max_y = max(margin, gh - 1 - margin)
		var rx := randi_range(min_x, max_x)
		var ry := randi_range(min_y, max_y)
		var tt := Vector2i(rx, ry)
		if _is_open_tile(tt, respect_roads):
			return tt

	# Deterministic scan
	for y in range(margin, gh - margin):
		for x in range(margin, gw - margin):
			var tt := Vector2i(x, y)
			if _is_open_tile(tt, respect_roads):
				return tt

	return Vector2i(-1, -1)

func _is_open_tile(t: Vector2i, respect_roads: bool) -> bool:
	if not _within_bounds(t):
		return false
	if _is_water(t):
		return false

	if respect_roads:
		var tid := _tile_id(t)
		if road_ids.has(tid):
			return false

	# Block structures
	if _get_structure_at(t) != null:
		return false

	# Block existing units
	for u in get_tree().get_nodes_in_group("Units"):
		if not (u is Node2D):
			continue
		var utile := _world_to_tile((u as Node2D).global_position - Vector2(0, y_offset))
		if utile == t:
			return false

	return true

# ─────────────────────────────────────────────────────────────
# Map helpers
# ─────────────────────────────────────────────────────────────
func _grid_w() -> int:
	var used := _tilemap.get_used_rect()
	return max(used.size.x, 0)

func _grid_h() -> int:
	var used := _tilemap.get_used_rect()
	return max(used.size.y, 0)

func _within_bounds(t: Vector2i) -> bool:
	var used := _tilemap.get_used_rect()
	return t.x >= used.position.x and t.y >= used.position.y \
		and t.x < used.position.x + used.size.x and t.y < used.position.y + used.size.y

func _tile_id(t: Vector2i) -> int:
	return _tilemap.get_cell_source_id(0, t)

func _is_water(t: Vector2i) -> bool:
	# Prefer helper if present
	if _tilemap.has_method("is_water_tile"):
		return _tilemap.is_water_tile(t)
	# Fallback via source id
	var wid := -9999
	if _tilemap.has_method("get"):
		var v = _tilemap.get("water_tile_id")
		if typeof(v) == TYPE_INT:
			wid = v
	return (wid != -9999 and _tile_id(t) == wid)

func _get_structure_at(t: Vector2i) -> Node:
	if _tilemap.has_method("get_structure_at_tile"):
		return _tilemap.get_structure_at_tile(t)
	for s in get_tree().get_nodes_in_group("Structures"):
		if is_instance_valid(s) and s.has_meta("tile_pos") and s.get_meta("tile_pos") == t:
			return s
	return null

func _tile_to_world_center(t: Vector2i) -> Vector2:
	return _tilemap.to_global(_tilemap.map_to_local(t))

func _world_to_tile(world_pos: Vector2) -> Vector2i:
	var local := _tilemap.to_local(world_pos)
	return _tilemap.local_to_map(local)
