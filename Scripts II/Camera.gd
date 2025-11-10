# CameraFollowPlayers.gd (Godot 4, warnings-as-errors safe)
extends Camera2D

# ── What to follow ───────────────────────────────────────────
enum TargetMode { FIRST, NEAREST, CENTROID }
@export var target_mode: TargetMode = TargetMode.CENTROID
@export var y_offset: float = -8.0           # keep consistent with Spawner.gd

# ── Smoothing ────────────────────────────────────────────────
@export var smooth_speed: float = 7.5        # higher = snappier
@export var deadzone: float = 4.0            # pixels before camera starts moving

# ── Zoom to fit multiple players (optional) ─────────────────
@export var zoom_to_fit: bool = false
@export var fit_padding: Vector2 = Vector2(120, 80)   # px padding around players
@export var min_zoom: float = 0.75                    # smaller = zoom out more
@export var max_zoom: float = 1.5

# ── World limits from a TileMap (optional but recommended) ──
@export var tilemap_path: NodePath = ^"../TileMap"

var _tilemap: TileMap
var _retarget_timer: float = 0.0
@export var retarget_interval: float = 0.2

func _ready() -> void:
	# Godot 4: use make_current() (no 'current' property)
	make_current()
	_tilemap = get_node_or_null(tilemap_path) as TileMap
	_update_camera_limits_from_tilemap()

func _process(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_update_camera_limits_from_tilemap()  # in case map changes

	var target: Vector2 = _compute_target_position()
	# Deadzone: move only if we’re outside a small radius
	if global_position.distance_to(target) > deadzone:
		var t: float = clamp(smooth_speed * delta, 0.0, 1.0)
		global_position = global_position.lerp(target, t)

	if zoom_to_fit:
		_update_zoom_to_fit()

# Always returns a Vector2 (no nulls/Variants)
func _compute_target_position() -> Vector2:
	var players: Array = get_tree().get_nodes_in_group("Player")
	if players.is_empty():
		return global_position

	match target_mode:
		TargetMode.FIRST:
			var n: Node = players[0]
			if n is Node2D:
				return (n as Node2D).global_position + Vector2(0.0, y_offset)

		TargetMode.NEAREST:
			var best: Node2D = null
			var best_d2: float = INF
			for p in players:
				if p is Node2D:
					var pos: Vector2 = (p as Node2D).global_position + Vector2(0.0, y_offset)
					var d2: float = global_position.distance_squared_to(pos)
					if d2 < best_d2:
						best_d2 = d2
						best = p
			if best != null:
				return best.global_position + Vector2(0.0, y_offset)

		TargetMode.CENTROID:
			var sum: Vector2 = Vector2.ZERO
			var count: int = 0
			for p in players:
				if p is Node2D:
					sum += (p as Node2D).global_position + Vector2(0.0, y_offset)
					count += 1
			if count > 0:
				return sum / float(count)

	# Fallback
	return global_position

func _players_bounds() -> Rect2:
	var rect_set: bool = false
	var r: Rect2 = Rect2()
	for p in get_tree().get_nodes_in_group("Player"):
		if not (p is Node2D):
			continue
		var pos: Vector2 = (p as Node2D).global_position + Vector2(0.0, y_offset)
		if not rect_set:
			r = Rect2(pos, Vector2.ZERO)
			rect_set = true
		else:
			r = r.expand(pos)
	return r

func _update_zoom_to_fit() -> void:
	var r: Rect2 = _players_bounds()
	if r.size == Vector2.ZERO:
		return

	var screen_size: Vector2 = get_viewport_rect().size
	var pad: Vector2 = fit_padding
	var desired: Vector2 = r.size + pad * 2.0
	if desired.x <= 1.0 or desired.y <= 1.0:
		return

	var zx: float = desired.x / screen_size.x
	var zy: float = desired.y / screen_size.y
	var target_zoom: float = max(zx, zy)
	target_zoom = clamp(target_zoom, min_zoom, max_zoom)

	# Smooth zoom a bit
	var z: float = lerp(zoom.x, target_zoom, 0.1)
	zoom = Vector2(z, z)

func _update_camera_limits_from_tilemap() -> void:
	if _tilemap == null:
		limit_left = -1000000
		limit_right = 1000000
		limit_top = -1000000
		limit_bottom = 1000000
		return

	var used: Rect2i = _tilemap.get_used_rect()
	if used.size == Vector2i.ZERO:
		return

	var top_left_world: Vector2 = _tilemap.to_global(_tilemap.map_to_local(used.position))
	var bottom_right_world: Vector2 = _tilemap.to_global(_tilemap.map_to_local(used.position + used.size))

	limit_left = int(floor(min(top_left_world.x, bottom_right_world.x)))
	limit_right = int(ceil(max(top_left_world.x, bottom_right_world.x)))
	limit_top = int(floor(min(top_left_world.y, bottom_right_world.y)))
	limit_bottom = int(ceil(max(top_left_world.y, bottom_right_world.y)))
