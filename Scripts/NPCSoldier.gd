extends Area2D

@export var panic_steps: int = 0
@export var panic_speed: float = 4.0
@export var despawn_at_edge: bool = true

const Y_OFFSET := -8.0

var tile_pos: Vector2i
var _tilemap: TileMap
var _sprite: AnimatedSprite2D

@export var auto_fade_after_scatter: bool = true
@export var fade_delay_range: Vector2 = Vector2(0.25, 0.9)   # seconds to wait before fading
@export var fade_duration_range: Vector2 = Vector2(0.7, 1.4) # seconds to fade to 0 alpha

# --- crowd visual occupancy (so multiple can share a tile) ---
var _crowd_offset: Vector2 = Vector2.ZERO
var _claimed_tile: Vector2i = Vector2i(-999, -999)

func _ready() -> void:
	_tilemap = get_tree().get_current_scene().get_node("TileMap")
	_sprite = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
	z_as_relative = false

	if _tilemap:
		# compute our tile from current world position
		tile_pos = _tilemap.local_to_map(_tilemap.to_local(global_position))
		# claim a small visual offset so several NPCs can share this tile without overlapping
		if _tilemap.has_method("crowd_claim"):
			_crowd_offset = _tilemap.crowd_claim(tile_pos)
			_claimed_tile = tile_pos
		# snap to center + offset
		global_position = _tilemap.to_global(_tilemap.map_to_local(tile_pos)) + Vector2(0, Y_OFFSET) + _crowd_offset

	_update_z()

func _update_z() -> void:
	# draw-order = y-sort by world position
	z_as_relative = false
	z_index = int(global_position.y)

func place_on_tile(t: Vector2i) -> void:
	tile_pos = t
	# claim a visual crowd slot if available
	if _tilemap and _tilemap.has_method("crowd_claim"):
		_crowd_offset = _tilemap.crowd_claim(t)
		_claimed_tile = t
	else:
		_crowd_offset = Vector2.ZERO

	var wp: Vector2 = _tilemap.to_global(_tilemap.map_to_local(t)) + Vector2(0, Y_OFFSET) + _crowd_offset
	global_position = wp
	_update_z()

func start_scatter(threat_tile: Vector2i) -> void:
	visible = true
	if _sprite: _sprite.play("move")

	var target: Vector2i = _pick_flee_target(threat_tile, panic_steps)
	await _walk_path_to(target, panic_speed)

	if _sprite: _sprite.play("default")

	# If we left the grid → release slot and despawn immediately
	if despawn_at_edge and not _tilemap.is_within_bounds(tile_pos):
		if _claimed_tile.x != -999 and _tilemap and _tilemap.has_method("crowd_release"):
			_tilemap.crowd_release(_claimed_tile)
		queue_free()
		return

	# Otherwise: brief delay, fade out, then free (effect-only NPC)
	if auto_fade_after_scatter:
		await _fade_and_free()

func _fade_and_free() -> void:
	var wait := randf_range(fade_delay_range.x, fade_delay_range.y)
	await get_tree().create_timer(wait).timeout

	var dur := randf_range(fade_duration_range.x, fade_duration_range.y)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# fade the sprite if present, otherwise the whole node
	if _sprite:
		tw.tween_property(_sprite, "modulate:a", 0.0, dur)
	else:
		tw.tween_property(self, "modulate:a", 0.0, dur)

	await tw.finished

	# release visual crowd slot if we had one
	if _claimed_tile.x != -999 and _tilemap and _tilemap.has_method("crowd_release"):
		_tilemap.crowd_release(_claimed_tile)

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
	# If we’re leaving this tile, release its crowd slot
	if dest != tile_pos and _claimed_tile == tile_pos and _tilemap and _tilemap.has_method("crowd_release"):
		_tilemap.crowd_release(_claimed_tile)
		_claimed_tile = Vector2i(-999, -999)

	# claim a slot on the destination tile (so several can land there)
	var dest_offset: Vector2 = Vector2.ZERO
	if _tilemap and _tilemap.has_method("crowd_claim"):
		dest_offset = _tilemap.crowd_claim(dest)

	var target: Vector2 = _tilemap.to_global(_tilemap.map_to_local(dest)) + Vector2(0, Y_OFFSET) + dest_offset

	# Flip based on movement direction (default facing left)
	if _sprite:
		_sprite.flip_h = target.x > global_position.x

	while global_position.distance_to(target) > 1.0:
		var dt := get_process_delta_time()
		global_position = global_position.move_toward(target, speed * dt)
		_update_z()  # keep layer order correct as we run
		await Engine.get_main_loop().process_frame

	global_position = target
	tile_pos = dest
	_crowd_offset = dest_offset
	_claimed_tile = dest
	_update_z()
