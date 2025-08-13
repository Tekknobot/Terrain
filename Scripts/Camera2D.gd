# File: res://Scripts/Camera2D.gd
extends Camera2D

# Zoom levels to cycle through
var zoom_levels = [
	Vector2(1, 1),
	Vector2(2, 2),
]
var current_zoom_index := 0

# Drag state
var dragging := false
var drag_start := Vector2.ZERO
var camera_start := Vector2.ZERO
var base_position := Vector2.ZERO  # the “true” camera pos; shake adds on top
var valid_drag := false

# Touch pinch-zoom
var active_touches := {}
var pinch_initial_distance := 0.0
var pinch_initial_zoom_index := 0

# Shake
var shake_amount := 0.0
var shake_decay := 5.0

func _ready():
	# Restore zoom from settings
	GameData.load_settings()
	current_zoom_index = clamp(GameData.current_zoom_index, 0, zoom_levels.size() - 1)
	zoom = zoom_levels[current_zoom_index]

	set_process(true)
	set_process_unhandled_input(true)

	# Center on the map once at start
	_center_on_tilemap()
	# …and again after one frame in case tiles spawn async
	call_deferred("_center_on_tilemap")

func _unhandled_input(event):
	var tilemap: TileMap = get_tree().get_current_scene().get_node("TileMap")

	# If a unit is currently selected, skip camera interactions (matches your rule)
	if tilemap != null and tilemap.selected_unit != null:
		return

	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			current_zoom_index = max(current_zoom_index - 1, 0)
			_zoom_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			current_zoom_index = min(current_zoom_index + 1, zoom_levels.size() - 1)
			_zoom_camera()

		# Drag start/stop (only if clicking empty tile)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_click_on_empty_tile():
					dragging = true
					valid_drag = true
					drag_start = get_global_mouse_position()
					camera_start = base_position
				else:
					valid_drag = false
			else:
				dragging = false
				valid_drag = false

	# Dragging
	elif event is InputEventMouseMotion and dragging and valid_drag:
		base_position = camera_start - (get_global_mouse_position() - drag_start) * 0.6

	# Touch: pinch zoom
	elif event is InputEventScreenTouch:
		if event.pressed:
			active_touches[event.index] = event.position
			if active_touches.size() == 2:
				var touches = active_touches.values()
				pinch_initial_distance = touches[0].distance_to(touches[1])
				pinch_initial_zoom_index = current_zoom_index
		else:
			active_touches.erase(event.index)
			if active_touches.size() < 2:
				pinch_initial_distance = 0.0

	elif event is InputEventScreenDrag:
		active_touches[event.index] = event.position
		if active_touches.size() == 2 and pinch_initial_distance > 0.0:
			var touches = active_touches.values()
			var current_distance = touches[0].distance_to(touches[1])
			var ratio = current_distance / pinch_initial_distance

			var offset := 0
			if ratio > 1.0:
				offset = int((ratio - 1.0) * 5.0)
			elif ratio < 1.0:
				offset = -int((1.0 - ratio) * 5.0)

			var new_index = clamp(pinch_initial_zoom_index + offset, 0, zoom_levels.size() - 1)
			if new_index != current_zoom_index:
				current_zoom_index = new_index
				_zoom_camera()

func _process(delta):
	# Apply shake around the base_position (no difficulty-based vertical offset)
	if shake_amount > 0.0:
		var shake_offset = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * shake_amount
		global_position = base_position + shake_offset
		shake_amount = max(shake_amount - shake_decay * delta, 0.0)
	else:
		global_position = base_position

func _zoom_camera():
	var target_zoom = zoom_levels[current_zoom_index]
	var tween = create_tween()
	tween.tween_property(self, "zoom", target_zoom, 0.2).set_trans(Tween.TRANS_CUBIC)
	GameData.current_zoom_index = current_zoom_index
	GameData.save_settings()

func _is_click_on_empty_tile() -> bool:
	var tilemap: TileMap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return true

	var local_pos = tilemap.to_local(get_global_mouse_position())
	var clicked_tile: Vector2i = tilemap.local_to_map(local_pos)

	var has_unit := tilemap.get_unit_at_tile(clicked_tile) != null
	var has_structure := tilemap.get_structure_at_tile(clicked_tile) != null
	return not has_unit and not has_structure

func _center_on_tilemap() -> void:
	var tilemap: TileMap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return

	var used: Rect2i = tilemap.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		used = Rect2i(Vector2i.ZERO, Vector2i(tilemap.grid_width, tilemap.grid_height))

	# Map corners (top-left and bottom-right *boundary*)
	var tl_local: Vector2 = tilemap.map_to_local(used.position)
	var br_local: Vector2 = tilemap.map_to_local(used.position + used.size)

	# Geometric center (local)
	var center_local: Vector2 = (tl_local + br_local) * 0.5

	# Apply the same vertical visual bias you use for mouse/tile math
	var visual_bias := Vector2(0, 64)

	# Convert to world and set
	var center_world: Vector2 = tilemap.to_global(center_local + visual_bias)
	base_position = center_world
	global_position = center_world
	
func shake(amount: float) -> void:
	shake_amount = amount
