# File: Camera.gd
# Attach to: IsoGrid/Camera2D
extends Camera2D

@export var tilemap_path: NodePath = ^"../TileMap"
@export var player_group: String = "Player"   # ← follow whoever is in this group
@export var smoothing: bool = true
@export var smooth_speed: float = 6.0
@export var recenter_on_ready: bool = true
@export var recenter_on_first_player: bool = true
@export var clamp_only_when_ready: bool = true

var _tilemap: TileMap
var _player: Node2D = null
var _player_seen_once := false
var _last_used_rect := Rect2i(0, 0, -1, -1)

func _ready() -> void:
	make_current()

	_tilemap = get_node_or_null(tilemap_path) as TileMap
	if _tilemap == null:
		push_error("Camera: TileMap not found at tilemap_path.")
		return

	if recenter_on_ready:
		_center_on_tilemap(_tilemap)

	_refresh_limits_if_needed(true)

	# Try now, and also latch on as soon as one appears.
	_resolve_player_from_group()
	get_tree().node_added.connect(_on_node_added)

func _process(delta: float) -> void:
	_refresh_limits_if_needed()

	# Keep trying until we have a player.
	if _player == null or not is_instance_valid(_player) or _player.get_tree() == null:
		_player = null
		_player_seen_once = false
		_resolve_player_from_group()
		if _player == null:
			return

	# One-time snap when first found
	if recenter_on_first_player and not _player_seen_once:
		global_position = _player.global_position
		_player_seen_once = true

	# Follow
	var target := _player.global_position
	if smoothing:
		var t = clamp(delta * smooth_speed, 0.0, 1.0)
		global_position = global_position.lerp(target, t)
	else:
		global_position = target

# ——— player discovery (group-only) ———
func _on_node_added(node: Node) -> void:
	if _player != null:
		return
	if node is Node2D and node.is_in_group(player_group):
		_player = node as Node2D
		_player_seen_once = false

func _resolve_player_from_group() -> void:
	var players := get_tree().get_nodes_in_group(player_group)
	for p in players:
		if p is Node2D:
			_player = p
			_player_seen_once = false
			return

# ——— limits & centering ———
func _center_on_tilemap(tilemap: TileMap) -> void:
	var grid_w := int(tilemap.get("grid_width") if tilemap.has_method("get") else 0)
	var grid_h := int(tilemap.get("grid_height") if tilemap.has_method("get") else 0)
	if grid_w <= 0 or grid_h <= 0:
		var used := tilemap.get_used_rect()
		if used.size == Vector2i.ZERO:
			return
		grid_w = max(used.size.x, 1)
		grid_h = max(used.size.y, 1)
	var top_left_local := tilemap.map_to_local(Vector2i(0, 0))
	var bottom_right_local := tilemap.map_to_local(Vector2i(grid_w, grid_h))
	var center_local := (top_left_local + bottom_right_local) * 0.5
	global_position = tilemap.to_global(center_local)

func _refresh_limits_if_needed(force: bool=false) -> void:
	if _tilemap == null: return
	var used := _tilemap.get_used_rect()
	if not force and used == _last_used_rect:
		return
	_last_used_rect = used
	if clamp_only_when_ready and used.size == Vector2i.ZERO:
		# disable limits until content exists
		limit_left = -1000000; limit_top = -1000000
		limit_right = 1000000; limit_bottom = 1000000
		return
	_update_limits_from_tilemap(_tilemap)

func _update_limits_from_tilemap(tilemap: TileMap) -> void:
	var used := tilemap.get_used_rect()
	if used.size == Vector2i.ZERO:
		limit_left = -1000000; limit_top = -1000000
		limit_right = 1000000; limit_bottom = 1000000
		return
	var top_left_world := tilemap.to_global(tilemap.map_to_local(used.position))
	var bottom_right_world := tilemap.to_global(tilemap.map_to_local(used.position + used.size))
	var vp_size := get_viewport_rect().size
	var half := (vp_size * 0.5) / zoom
	var left := int(floor(top_left_world.x + half.x))
	var right := int(ceil(bottom_right_world.x - half.x))
	var top := int(floor(top_left_world.y + half.y))
	var bottom := int(ceil(bottom_right_world.y - half.y))
	if right < left:
		var cx := int(round((left + right) * 0.5))
		left = cx; right = cx
	if bottom < top:
		var cy := int(round((top + bottom) * 0.5))
		top = cy; bottom = cy
	limit_left = left
	limit_right = right
	limit_top = top
	limit_bottom = bottom
	limit_smoothed = true
