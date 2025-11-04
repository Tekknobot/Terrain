# File: Spawner.gd
# Attach to: IsoGrid/Spawner (Node or Node2D)
extends Node

# --- references ---
@export var tilemap_path: NodePath = ^"../TileMap"

# --- prefabs ---
@export var player_prefabs: Array[PackedScene] = []
@export var enemy_prefabs: Array[PackedScene] = []

# --- counts (defaults; you can call spawn_* with explicit numbers too) ---
@export var player_count: int = 1
@export var enemy_count: int = 5

# --- placement rules ---
@export var avoid_roads: bool = true
@export var edge_margin: int = 1                 # keep N tiles from the outer border
@export var max_attempts_per_unit: int = 300

# y offset used by your sprites (so feet sit on the tile nicely)
@export var y_offset: float = -8.0

# Road IDs (match MapGen.gd constants)
@export var road_ids: PackedInt32Array = [13, 14, 12]  # DOWN_LEFT_ROAD, DOWN_RIGHT_ROAD, INTERSECTION

var _tilemap: TileMap

func _ready() -> void:
	_tilemap = get_node_or_null(tilemap_path) as TileMap
	if _tilemap == null:
		push_error("Spawner: TileMap not found at tilemap_path.")
		return
	# Example auto-spawn (comment out if you want manual control):
	# spawn_players(player_count)
	# spawn_enemies(enemy_count)

# ─────────────────────────────────────────────────────────────
# Public API (spawns ANYWHERE open; no zones)
# ─────────────────────────────────────────────────────────────
func spawn_players(count: int = -1) -> void:
	if count <= 0: count = max(1, player_count)
	if player_prefabs.is_empty(): return

	var idx := 0
	for i in range(count):
		var tile := _find_open_tile_anywhere()
		if tile == Vector2i(-1, -1): break
		var scene := player_prefabs[idx % player_prefabs.size()]
		idx += 1
		_spawn_unit(scene, tile, true)

func spawn_enemies(count: int = -1) -> void:
	if count <= 0: count = max(1, enemy_count)
	if enemy_prefabs.is_empty(): return

	var idx := 0
	for i in range(count):
		var tile := _find_open_tile_anywhere()
		if tile == Vector2i(-1, -1): break
		var scene := enemy_prefabs[idx % enemy_prefabs.size()]
		idx += 1
		_spawn_unit(scene, tile, false)

func spawn_wave(players: int, enemies: int) -> void:
	spawn_players(players)
	spawn_enemies(enemies)

# ─────────────────────────────────────────────────────────────
# Core spawn
# ─────────────────────────────────────────────────────────────
func _spawn_unit(scene: PackedScene, tile: Vector2i, is_player: bool) -> void:
	var u := scene.instantiate() as Node2D
	if u == null:
		return

	var world_center := _tile_to_world_center(tile)
	u.global_position = world_center + Vector2(0, y_offset)

	u.add_to_group("Units")
	if is_player:
		u.add_to_group("Player")
	else:
		u.add_to_group("Enemies")

	u.set_meta("tile_pos", tile)

	# World-space z sort
	if u.has_method("set"):
		u.set("z_as_relative", false)
		u.set("z_index", int(u.global_position.y))

	add_child(u)

# ─────────────────────────────────────────────────────────────
# Tile selection (ANYWHERE)
# ─────────────────────────────────────────────────────────────
func _find_open_tile_anywhere() -> Vector2i:
	var gw := _grid_w()
	var gh := _grid_h()

	# Random attempts first
	for _i in range(max_attempts_per_unit):
		var rx := randi_range(edge_margin, gw - 1 - edge_margin)
		var ry := randi_range(edge_margin, gh - 1 - edge_margin)
		var t := Vector2i(rx, ry)
		if _is_open_tile(t):
			return t

	# Deterministic scan fallback
	for y in range(edge_margin, gh - edge_margin):
		for x in range(edge_margin, gw - edge_margin):
			var t := Vector2i(x, y)
			if _is_open_tile(t):
				return t

	return Vector2i(-1, -1)

func _is_open_tile(t: Vector2i) -> bool:
	if not _within_bounds(t): return false
	if _is_water(t): return false

	if avoid_roads:
		var id := _tile_id(t)
		if road_ids.has(id): return false

	if _get_structure_at(t) != null: return false

	# Check units already placed
	for u in get_tree().get_nodes_in_group("Units"):
		if not (u is Node2D): continue
		var utile := _world_to_tile((u as Node2D).global_position - Vector2(0, y_offset))
		if utile == t:
			return false

	return true

# ─────────────────────────────────────────────────────────────
# Map helpers
# ─────────────────────────────────────────────────────────────
func _grid_w() -> int:
	var gw: int = 0
	if _tilemap.has_method("get"):
		var v = _tilemap.get("grid_width")
		if typeof(v) == TYPE_INT: gw = v
	if gw <= 0:
		var used := _tilemap.get_used_rect()
		gw = max(used.size.x, 1)
	return gw

func _grid_h() -> int:
	var gh: int = 0
	if _tilemap.has_method("get"):
		var v = _tilemap.get("grid_height")
		if typeof(v) == TYPE_INT: gh = v
	if gh <= 0:
		var used := _tilemap.get_used_rect()
		gh = max(used.size.y, 1)
	return gh

func _within_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < _grid_w() and t.y >= 0 and t.y < _grid_h()

func _tile_id(t: Vector2i) -> int:
	return _tilemap.get_cell_source_id(0, t)

func _is_water(t: Vector2i) -> bool:
	if _tilemap.has_method("is_water_tile"):
		return _tilemap.is_water_tile(t)
	var wid := int(_tilemap.get("water_tile_id") if _tilemap.has_method("get") else -9999)
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
