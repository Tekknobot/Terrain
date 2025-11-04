# File: PlayerController.gd
# Attach to: your player prefab root (e.g., "S3")
extends Node2D

@export var tilemap_path: NodePath = ^"../../TileMap"  # optional direct path
@export var move_speed: float = 220.0
@export var stop_radius_px: float = 6.0
@export var y_offset: float = -8.0
@export var click_to_attack_distance_tiles: int = 1
@export var attack_cooldown: float = 0.55
@export var attack_damage: int = 10
@export var enemy_group_name: String = "Enemies"
@export var sprite_node_path: NodePath = ^"AnimatedSprite2D"
@export var attack_anim_name: String = "attack"
@export var idle_anim_name: String = "default"
@export var move_anim_name: String = "move"
@export var sfx_node_path: NodePath = ^"SFX"

# Z-order bias if your feet aren’t exactly at global_position.y
@export var z_bias: int = 0

var _tilemap: TileMap
var _sprite: AnimatedSprite2D
var _sfx: AudioStreamPlayer2D
var _astar := AStarGrid2D.new()
var _grid_w := 0
var _grid_h := 0
var _tile_size := Vector2i(32, 32)

var _path: Array[Vector2i] = []
var _have_target := false
var _attack_target: Node = null
var _cooldown_left: float = 0.0

# ─────────────────────────────────────────────────────────────
# RESOLVERS
# ─────────────────────────────────────────────────────────────
func _dfs_find_tilemap(n: Node) -> TileMap:
	if n is TileMap:
		return n
	for c in n.get_children():
		var r := _dfs_find_tilemap(c)
		if r != null:
			return r
	return null

func _resolve_tilemap() -> TileMap:
	# 1) Try the exported path
	if tilemap_path != NodePath():
		var t := get_node_or_null(tilemap_path) as TileMap
		if t != null:
			return t

	# 2) Try by name under the current scene
	var root := get_tree().current_scene
	if root != null:
		var by_name := root.find_child("TileMap", true, false)
		if by_name is TileMap:
			return by_name

		# 3) DFS under current scene
		var found := _dfs_find_tilemap(root)
		if found != null:
			return found

	# 4) Fallback: scan direct children of the tree root
	var tree_root := get_tree().get_root()
	for n in tree_root.get_children():
		if n is TileMap:
			return n

	return null

# ─────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────
func _ready() -> void:
	_tilemap = _resolve_tilemap()
	if _tilemap == null:
		push_error("PlayerDiabloController: TileMap not found (path and auto-discovery failed).")
		return

	_sprite = get_node_or_null(sprite_node_path) as AnimatedSprite2D
	_sfx    = get_node_or_null(sfx_node_path) as AudioStreamPlayer2D
	if _tilemap.tile_set and _tilemap.tile_set.tile_size != Vector2i.ZERO:
		_tile_size = _tilemap.tile_set.tile_size

	# world z-sorting so we layer correctly with structures/units
	z_as_relative = false
	_update_z()

	_build_astar_from_tilemap()
	_play_anim_safe(idle_anim_name)

func _unhandled_input(event: InputEvent) -> void:
	if _tilemap == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_world := get_global_mouse_position()
		var maybe_enemy := _pick_clicked_enemy(mouse_world)
		if maybe_enemy != null:
			_have_target = true
			_attack_target = maybe_enemy
			var target_tile := _world_to_tile(maybe_enemy.global_position)
			_issue_move_order(target_tile)
			return
		_have_target = false
		_attack_target = null
		var clicked_tile := _world_to_tile(mouse_world)
		var walkable := _find_nearest_walkable(clicked_tile)
		if walkable != Vector2i(-1, -1):
			_issue_move_order(walkable)

func _physics_process(delta: float) -> void:
	if _tilemap == null:
		return
	if _cooldown_left > 0.0:
		_cooldown_left = max(0.0, _cooldown_left - delta)
	if _have_target and is_instance_valid(_attack_target):
		var my_tile := _world_to_tile(global_position)
		var tgt_tile := _world_to_tile(_attack_target.global_position)
		if _manhattan(my_tile, tgt_tile) <= click_to_attack_distance_tiles:
			_path.clear()
			_do_attack(_attack_target)
			_update_z()
			return
		else:
			if _path.is_empty() or _path.back() != tgt_tile:
				_issue_move_order(tgt_tile)

	if not _path.is_empty():
		_move_along_path(delta)
	else:
		_play_anim_safe(idle_anim_name)

	_update_z()

# ─────────────────────────────────────────────────────────────
# INPUT HELPERS
# ─────────────────────────────────────────────────────────────
func _pick_clicked_enemy(mouse_world: Vector2) -> Node:
	if enemy_group_name == "" or not get_tree().has_group(enemy_group_name):
		return null
	var best: Node = null
	var best_d2 := INF
	for e in get_tree().get_nodes_in_group(enemy_group_name):
		if not is_instance_valid(e):
			continue
		var d2 = e.global_position.distance_squared_to(mouse_world)
		if d2 < best_d2 and d2 <= float(_tile_size.x * _tile_size.x) * 0.6:
			best = e
			best_d2 = d2
	return best

# ─────────────────────────────────────────────────────────────
# MOVEMENT
# ─────────────────────────────────────────────────────────────
func _issue_move_order(goal_tile: Vector2i) -> void:
	var start_tile := _world_to_tile(global_position)
	if start_tile == goal_tile:
		_path = []
		return
	_build_astar_from_tilemap()
	_path = _astar.get_id_path(start_tile, goal_tile)
	if _path.size() > 0 and typeof(_path[0]) != TYPE_VECTOR2I:
		var tmp: Array[Vector2i] = []
		for p in _path:
			tmp.append(Vector2i(p))
		_path = tmp
	if not _path.is_empty():
		_play_anim_safe(move_anim_name)

func _move_along_path(delta: float) -> void:
	if _path.is_empty():
		return
	var next_tile := _path[0]
	var next_world := _tile_to_world_center(next_tile)
	var dest := next_world + Vector2(0, y_offset)
	var dir := (dest - global_position)
	var dist := dir.length()
	if dist < stop_radius_px:
		_path.remove_at(0)
		if _path.is_empty():
			_play_anim_safe(idle_anim_name)
		_update_z()
		return
	# DEFAULT FACES LEFT → flip only when moving to the RIGHT
	if _sprite:
		_sprite.flip_h = dir.x > 0.0
	var step := dir.normalized() * move_speed * delta
	if step.length() > dist:
		step = dir
	global_position += step
	_update_z()

# ─────────────────────────────────────────────────────────────
# ATTACK
# ─────────────────────────────────────────────────────────────
func _do_attack(target: Node) -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = attack_cooldown
	if _sprite and is_instance_valid(target):
		_sprite.flip_h = target.global_position.x > global_position.x
	_play_anim_safe(attack_anim_name)
	if _sfx:
		_sfx.stop()
		_sfx.play()
	if is_instance_valid(target):
		if target.has_method("take_damage"):
			target.take_damage(attack_damage)
		elif target.has_method("apply_damage"):
			target.apply_damage(attack_damage)

# ─────────────────────────────────────────────────────────────
# PATHFINDING GRID
# ─────────────────────────────────────────────────────────────
func _build_astar_from_tilemap() -> void:
	_grid_w = int(_tilemap.get("grid_width") if _tilemap.has_method("get") else 0)
	_grid_h = int(_tilemap.get("grid_height") if _tilemap.has_method("get") else 0)
	if _grid_w <= 0 or _grid_h <= 0:
		var used := _tilemap.get_used_rect()
		_grid_w = max(1, used.size.x)
		_grid_h = max(1, used.size.y)
	_astar.clear()
	_astar.size = Vector2i(_grid_w, _grid_h)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	for x in range(_grid_w):
		for y in range(_grid_h):
			var t := Vector2i(x, y)
			var blocked := _is_blocked_tile(t)
			_astar.set_point_solid(t, blocked)
	_astar.update()

func _is_blocked_tile(t: Vector2i) -> bool:
	var within := t.x >= 0 and t.x < _grid_w and t.y >= 0 and t.y < _grid_h
	if not within:
		return true
	if _tilemap.has_method("is_water_tile") and _tilemap.is_water_tile(t):
		return true
	if _tilemap.has_method("get_structure_at_tile") and _tilemap.get_structure_at_tile(t) != null:
		return true
	var water_id := int(_tilemap.get("water_tile_id") if _tilemap.has_method("get") else -9999)
	if water_id != -9999 and _tilemap.get_cell_source_id(0, t) == water_id:
		return true
	return false

# ─────────────────────────────────────────────────────────────
# TILE/WORLD & UTILS
# ─────────────────────────────────────────────────────────────
func _world_to_tile(world_pos: Vector2) -> Vector2i:
	var local := _tilemap.to_local(world_pos)
	return _tilemap.local_to_map(local)

func _tile_to_world_center(t: Vector2i) -> Vector2:
	return _tilemap.to_global(_tilemap.map_to_local(t))

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func _find_nearest_walkable(start: Vector2i) -> Vector2i:
	if start.x < 0 or start.y < 0 or start.x >= _grid_w or start.y >= _grid_h:
		start = Vector2i(clamp(start.x, 0, _grid_w - 1), clamp(start.y, 0, _grid_h - 1))
	if not _is_blocked_tile(start):
		return start
	var q := [start]
	var seen := { start: true }
	while q.size() > 0:
		var cur: Vector2i = q.pop_front()
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n = cur + d
			if n.x < 0 or n.x >= _grid_w or n.y < 0 or n.y >= _grid_h:
				continue
			if seen.has(n):
				continue
			seen[n] = true
			if not _is_blocked_tile(n):
				return n
			q.append(n)
	return Vector2i(-1, -1)

func _play_anim_safe(name: String) -> void:
	if _sprite == null:
		return
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(name):
		if _sprite.animation != name:
			_sprite.play(name)

# Z-ORDER helper
func _update_z() -> void:
	z_as_relative = false
	z_index = int(global_position.y) + z_bias
