extends Camera2D

var zoom_levels = [Vector2(3,3), Vector2(4,4), Vector2(5,5), Vector2(6,6), Vector2(8,8)]
var current_zoom_index := 0
var dragging := false
var drag_start := Vector2.ZERO
var camera_start := Vector2.ZERO

# For pinch zooming
var active_touches := {}
var pinch_initial_distance := 0.0
var pinch_initial_zoom_index := 0

func _ready():
	zoom = zoom_levels[current_zoom_index]
	set_process_unhandled_input(true)  

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var grid_width = 12
	var grid_height = 12
	var center_tile = Vector2(grid_width / 2, grid_height / 2)
	global_position = tilemap.to_global(tilemap.map_to_local(center_tile))

func _unhandled_input(event):
	# Desktop zooming via mouse wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			current_zoom_index = max(current_zoom_index - 1, 0)
			_zoom_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			current_zoom_index = min(current_zoom_index + 1, zoom_levels.size() - 1)
			_zoom_camera()
		
		# Desktop dragging via left click
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_click_on_empty_tile():
					dragging = true
					drag_start = get_global_mouse_position()
					camera_start = global_position
			else:
				dragging = false

	# Desktop dragging motion
	elif event is InputEventMouseMotion and dragging:
		global_position = camera_start - (get_global_mouse_position() - drag_start) * 0.6

	# Touch events for pinch zoom (Android)
	elif event is InputEventScreenTouch:
		if event.pressed:
			# Register touch with its index
			active_touches[event.index] = event.position
			# If exactly two touches are active, start pinch gesture
			if active_touches.size() == 2:
				var touches = active_touches.values()
				pinch_initial_distance = touches[0].distance_to(touches[1])
				pinch_initial_zoom_index = current_zoom_index
		else:
			# Touch released – remove from dictionary
			active_touches.erase(event.index)
			# Reset pinch state if less than 2 touches remain
			if active_touches.size() < 2:
				pinch_initial_distance = 0.0

	elif event is InputEventScreenDrag:
		# Update the position of the dragging touch
		active_touches[event.index] = event.position
		# If two touches are active, process pinch zoom
		if active_touches.size() == 2 and pinch_initial_distance > 0.0:
			var touches = active_touches.values()
			var current_distance = touches[0].distance_to(touches[1])
			# Calculate ratio: >1 means fingers moved apart (zoom out), <1 means pinch (zoom in)
			var ratio = current_distance / pinch_initial_distance
			# Determine an offset based on the ratio. The multiplier (here 5) controls sensitivity.
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
	var tween = create_tween()
	tween.tween_property(self, "zoom", zoom_levels[current_zoom_index], 0.2).set_trans(Tween.TRANS_CUBIC)

func is_click_on_empty_tile() -> bool:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var mouse_pos = tilemap.get_global_mouse_position()
	var clicked_tile = tilemap.local_to_map(tilemap.to_local(mouse_pos))
	return tilemap.get_unit_at_tile(clicked_tile) == null
