extends Camera2D

# List of available zoom levels.
var zoom_levels = [
	Vector2(1, 1),
	Vector2(2, 2),
]

var current_zoom_index := 0

# Camera drag
var dragging := false
var drag_start := Vector2.ZERO
var camera_start := Vector2.ZERO
var base_position := Vector2.ZERO  # position controlled by drag and centering logic

# For pinch zooming
var active_touches := {}
var pinch_initial_distance := 0.0
var pinch_initial_zoom_index := 0

# Camera shake
var shake_amount := 0.0
var shake_decay := 5.0

var valid_drag := false

func _ready():
	GameData.load_settings()
	current_zoom_index = GameData.current_zoom_index

	zoom = zoom_levels[current_zoom_index]
	
	set_process_unhandled_input(true)
	set_process(true)

	# Center camera on TileMap
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var grid_width = 8
	var grid_height = 8
	var center_tile = Vector2(grid_width / 2, grid_height / 2)
	var world_pos = tilemap.to_global(tilemap.map_to_local(center_tile))
	global_position = world_pos
	base_position = world_pos


func _unhandled_input(event):
	# Near the top of _unhandled_input
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap.selected_unit != null:
		return  # disable all dragging/zoom logic while unit is selected
	
	# Zooming
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			current_zoom_index = max(current_zoom_index - 1, 0)
			_zoom_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			current_zoom_index = min(current_zoom_index + 1, zoom_levels.size() - 1)
			_zoom_camera()

		# Start drag only if clicking empty tile
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_click_on_empty_tile():
					dragging = true
					valid_drag = true
					drag_start = get_global_mouse_position()
					camera_start = base_position
				else:
					valid_drag = false
			else:
				dragging = false
				valid_drag = false

	elif event is InputEventMouseMotion and dragging and valid_drag:
		base_position = camera_start - (get_global_mouse_position() - drag_start) * 0.6


	# Pinch zoom (mobile)
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
			if ratio > 1:
				offset = int((ratio - 1) * 5)
			elif ratio < 1:
				offset = -int((1 - ratio) * 5)
			var new_index = clamp(pinch_initial_zoom_index + offset, 0, zoom_levels.size() - 1)
			if new_index != current_zoom_index:
				current_zoom_index = new_index
				_zoom_camera()


func _zoom_camera():
	var target_zoom = zoom_levels[current_zoom_index]
	var tween = create_tween()
	tween.tween_property(self, "zoom", target_zoom, 0.2).set_trans(Tween.TRANS_CUBIC)
	print("→ Camera zoom changed: index=", current_zoom_index, ", zoom=", target_zoom)
	GameData.current_zoom_index = current_zoom_index
	GameData.save_settings()


func is_click_on_empty_tile() -> bool:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")

	# If a unit is selected, don't allow drag
	if tilemap.has_node("selected_unit") and tilemap.selected_unit != null:
		return false

	var local_pos = tilemap.to_local(get_viewport().get_mouse_position())
	var clicked_tile = tilemap.local_to_map(local_pos)

	var has_unit := tilemap.get_unit_at_tile(clicked_tile) != null
	var has_structure := tilemap.get_structure_at_tile(clicked_tile) != null

	return not has_unit and not has_structure


func _process(delta):
	if shake_amount > 0:
		var shake_offset = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * shake_amount
		global_position = base_position + shake_offset
		shake_amount = max(shake_amount - shake_decay * delta, 0.0)
	else:
		global_position = base_position


func shake(amount: float) -> void:
	shake_amount = amount
