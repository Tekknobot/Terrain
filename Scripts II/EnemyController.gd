# File: EnemyController.gd
# Attach to: your enemy prefab root (Node2D)
extends Node2D

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────
@export var tilemap_path: NodePath = ^"../../TileMap"   # optional direct path
@export var player_group: String = "Player"
@export var move_speed: float = 180.0
@export var y_offset: float = -8.0
@export var stop_radius_px: float = 6.0

@export var aggro_radius_px: float = 220.0
@export var give_up_radius_px: float = 360.0
@export var melee_range_tiles: int = 1
@export var attack_damage: int = 6
@export var attack_cooldown: float = 0.7

@export var max_health: int = 30

# Anim/sfx (optional)
@export var sprite_node_path: NodePath = ^"AnimatedSprite2D"
@export var idle_anim: String = "default"
@export var move_anim: String = "move"
@export var attack_anim: String = "attack"
@export var sfx_attack_path: NodePath = ^"SFX2"        # optional
@export var sfx_hurt_path: NodePath = ^"SFX"           # optional

# ─────────────────────────────────────────────────────────────
# RUNTIME
# ─────────────────────────────────────────────────────────────
var _tilemap: TileMap
var _sprite: AnimatedSprite2D
var _sfx_attack: AudioStreamPlayer2D
var _sfx_hurt: AudioStreamPlayer2D

var _astar := AStarGrid2D.new()
var _grid_w := 0
var _grid_h := 0
var _tile_size := Vector2i(32, 32)

var _health: int
var _cooldown_left: float = 0.0

var _target: Node = null
var _path: Array[Vector2i] = []

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
	# Auto-tag as "Enemies" for the player's click-to-attack
	add_to_group("Enemies")

	_tilemap = _resolve_tilemap()
	if _tilemap == null:
		push_error("EnemyDiabloAI: TileMap not found (path and auto-discovery failed).")
		return

	_sprite = get_node_or_null(sprite_node_path) as AnimatedSprite2D
	_sfx_attack = get_node_or_null(sfx_attack_path) as AudioStreamPlayer2D
	_sfx_hurt   = get_node_or_null(sfx_hurt_path) as AudioStreamPlayer2D

	if _tilemap.tile_set and _tilemap.tile_set.tile_size != Vector2i.ZERO:
		_tile_size = _tilemap.tile_set.tile_size

	_health = max_health
	_build_astar_from_tilemap()

	_play_anim(idle_anim)

func _physics_process(delta: float) -> void:
	if _tilemap == null:
		return

	# cooldown
	if _cooldown_left > 0.0:
		_cooldown_left = max(0.0, _cooldown_left - delta)

	# Acquire / validate target
	_update_target()

	# If in melee range, attack; else chase; else idle/wander.
	if _target and is_instance_valid(_target):
		var my_tile := _world_to_tile(global_position)
		var tgt_tile := _world_to_tile(_target.global_position)

		if _manhattan(my_tile, tgt_tile) <= melee_range_tiles:
			_path.clear()
			_do_attack(_target)
			return
		else:
			# chase
			if _path.is_empty() or _path.back() != tgt_tile:
				_issue_path_to(tgt_tile)

	# Move along path (if any)
	if not _path.is_empty():
		_move_along_path(delta)
	else:
		_play_anim(idle_anim)

# ─────────────────────────────────────────────────────────────
# TARGETING / AGGRO
# ─────────────────────────────────────────────────────────────
func _update_target() -> void:
	# Drop target if too far away
	if _target and (not is_instance_valid(_target) or _target.global_position.distance_to(global_position) > give_up_radius_px):
		_target = null

	# Find nearest player within aggro radius if we don't have one
	if _target == null:
		var best: Node = null
		var best_d2: float = aggro_radius_px * aggro_radius_px
		for p in get_tree().get_nodes_in_group(player_group):
			if not is_instance_valid(p):
				continue
			var d2: float = p.global_position.distance_squared_to(global_position)
			if d2 <= best_d2:
				best = p
				best_d2 = d2
		_target = best

# ─────────────────────────────────────────────────────────────
# MOVEMENT / PATH
# ─────────────────────────────────────────────────────────────
func _issue_path_to(goal_tile: Vector2i) -> void:
	var start_tile := _world_to_tile(global_position)
	if start_tile == goal_tile:
		_path.clear()
		return

	_build_astar_from_tilemap() # rebuild solids in case structures changed
	_path = _astar.get_id_path(start_tile, goal_tile)
	if _path.size() > 0 and typeof(_path[0]) != TYPE_VECTOR2I:
		var conv: Array[Vector2i] = []
		for p in _path:
			conv.append(Vector2i(p))
		_path = conv

	if not _path.is_empty():
		_play_anim(move_anim)

func _move_along_path(delta: float) -> void:
	var next_tile := _path[0]
	var target_world := _tile_to_world_center(next_tile)
	var dest := target_world + Vector2(0, y_offset)

	var vec := dest - global_position
	var dist := vec.length()

	# face (default face left → flip only when moving right)
	if _sprite:
		_sprite.flip_h = vec.x > 0.0

	if dist < stop_radius_px:
		_path.remove_at(0)
		if _path.is_empty():
			_play_anim(idle_anim)
		return

	var step := vec.normalized() * move_speed * delta
	if step.length() > dist:
		step = vec
	global_position += step

# ─────────────────────────────────────────────────────────────
# ATTACK / DAMAGE
# ─────────────────────────────────────────────────────────────
func _do_attack(target: Node) -> void:
	if _cooldown_left > 0.0 or not is_instance_valid(target):
		return
	_cooldown_left = attack_cooldown

	# face target (default face left → flip when target is to the right)
	if _sprite:
		_sprite.flip_h = target.global_position.x > global_position.x
	_play_anim(attack_anim)

	if _sfx_attack:
		_sfx_attack.stop()
		_sfx_attack.play()

	# Call typical damage methods if present
	if target.has_method("take_damage"):
		target.take_damage(attack_damage)
	elif target.has_method("apply_damage"):
		target.apply_damage(attack_damage)

# Allow player to damage us
func take_damage(amount: int) -> void:
	_health -= int(amount)
	if _sfx_hurt:
		_sfx_hurt.stop()
		_sfx_hurt.play()
	_flash()
	if _health <= 0:
		queue_free()

# quick white flash for hit feedback (if sprite exists)
func _flash() -> void:
	if _sprite == null:
		return
	var old := _sprite.modulate
	_sprite.modulate = Color(1, 1, 1)
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate", old, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ─────────────────────────────────────────────────────────────
# ANIMATION HELPER
# ─────────────────────────────────────────────────────────────
func _play_anim(name: String) -> void:
	if _sprite == null:
		return
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(name):
		if _sprite.animation != name:
			_sprite.play(name)

# ─────────────────────────────────────────────────────────────
# PATHFINDING GRID (mirrors MapGen walkability)
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
			_astar.set_point_solid(t, _is_blocked_tile(t))
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
# TILE/WORLD HELPERS
# ─────────────────────────────────────────────────────────────
func _world_to_tile(world_pos: Vector2) -> Vector2i:
	var local := _tilemap.to_local(world_pos)
	return _tilemap.local_to_map(local)

func _tile_to_world_center(t: Vector2i) -> Vector2:
	return _tilemap.to_global(_tilemap.map_to_local(t))

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
