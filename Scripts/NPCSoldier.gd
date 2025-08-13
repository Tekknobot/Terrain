# res://Scripts/SoldierNPC.gd
extends Area2D

@export var panic_steps: int = 4
@export var panic_speed: float = 4.0
@export var despawn_at_edge: bool = true

const Y_OFFSET := -8.0

var tile_pos: Vector2i
var _tilemap: TileMap
var _sprite: AnimatedSprite2D

func _ready() -> void:
	_tilemap = get_tree().get_current_scene().get_node("TileMap")
	_sprite = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
	# Set initial tile if placed directly in editor
	if _tilemap:
		tile_pos = _tilemap.local_to_map(_tilemap.to_local(global_position))

func place_on_tile(t: Vector2i) -> void:
	tile_pos = t
	var wp := _tilemap.to_global(_tilemap.map_to_local(t)) + Vector2(0, Y_OFFSET)
	global_position = wp

func start_scatter(threat_tile: Vector2i) -> void:
	visible = true
	if _sprite: _sprite.play("move")
	var target := _pick_flee_target(threat_tile, panic_steps)
	await _walk_path_to(target, panic_speed)
	if _sprite: _sprite.play("default")
	if despawn_at_edge and not _tilemap.is_within_bounds(tile_pos):
		queue_free()

func _pick_flee_target(threat_tile: Vector2i, steps: int) -> Vector2i:
	var frontier := [tile_pos]
	var visited := { tile_pos: null }
	for _i in range(steps):
		var nxt := []
		for t in frontier:
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n = t + d
				if visited.has(n): continue
				if not _tilemap.is_within_bounds(n):
					visited[n] = t
					nxt.append(n)
					continue
				if _tilemap._is_tile_walkable(n) and not _tilemap.is_tile_occupied(n):
					visited[n] = t
					nxt.append(n)
		frontier = nxt
	var best := tile_pos
	var best_cost := -INF
	for k in visited.keys():
		var c = abs(k.x - threat_tile.x) + abs(k.y - threat_tile.y)
		if c > best_cost:
			best_cost = c
			best = k
	return best

func _walk_path_to(dest: Vector2i, speed: float) -> void:
	var path: Array = []
	if _tilemap.is_within_bounds(tile_pos) and _tilemap.is_within_bounds(dest):
		path = _tilemap.get_weighted_path(tile_pos, dest)
	else:
		path = [dest]
	for step in path:
		await _move_one(step, speed)
	_tilemap.update_astar_grid()
	await get_tree().process_frame

func _move_one(dest: Vector2i, speed: float) -> void:
	var target := _tilemap.to_global(_tilemap.map_to_local(dest)) + Vector2(0, Y_OFFSET)
	
	# Flip based on movement direction (default facing left)
	if _sprite:
		# If target is to the right of current pos, flip_h = true
		_sprite.flip_h = target.x > global_position.x
	
	while global_position.distance_to(target) > 1.0:
		var dt := get_process_delta_time()
		global_position = global_position.move_toward(target, speed * dt)
		await Engine.get_main_loop().process_frame
	
	global_position = target
	tile_pos = dest
