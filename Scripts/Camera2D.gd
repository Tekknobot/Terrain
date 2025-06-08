extends Camera2D

# List of available zoom levels.
var zoom_levels = [
	Vector2(1, 1),
	Vector2(2, 2),
]

var current_zoom_index := 0

var dragging := false
var drag_start := Vector2.ZERO
var camera_start := Vector2.ZERO

# For pinch zooming.
var active_touches := {}
var pinch_initial_distance := 0.0
var pinch_initial_zoom_index := 0

# Camera shake variables
var shake_amount := 0.0
var shake_decay := 5.0
var original_position := Vector2.ZERO


func _ready():
	# Load the saved zoom index from GameData.
	GameData.load_settings()
	current_zoom_index = GameData.current_zoom_index

	# Set the camera's initial zoom.
	zoom = zoom_levels[current_zoom_index]
	
	set_process_unhandled_input(true)
	set_process(true)

	# Center the camera over the TileMap.
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var grid_width = 8
	var grid_height = 8
	var center_tile = Vector2(grid_width / 2, grid_height / 2)
	global_position = tilemap.to_global(tilemap.map_to_local(center_tile))

	# Store original position for shake
	original_position = global_position


func _unhandled_input(event):
	# Desktop zooming via mouse wheel.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			current_zoom_index = max(current_zoom_index - 1, 0)
			_zoom_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			current_zoom_index = min(current_zoom_index + 1, zoom_levels.size() - 1)
			_zoom_camera()
		# Desktop dragging via left click.
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_click_on_empty_tile():
					dragging = true
					drag_start = get_global_mouse_position()
					camera_start = global_position
			else:
				dragging = false

	# Desktop dragging motion.
	elif event is InputEventMouseMotion and dragging:
		global_position = camera_start - (get_global_mouse_position() - drag_start) * 0.6

	# Touch events for pinch zoom (Android).
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
	# Tween the camera's zoom from its current value to the target value.
	var target_zoom = zoom_levels[current_zoom_index]
	var tween = create_tween()
	tween.tween_property(self, "zoom", target_zoom, 0.2).set_trans(Tween.TRANS_CUBIC)
	
	print("→ Camera zoom changed: index=", current_zoom_index, ", zoom=", target_zoom)
	
	# Save the new zoom index in GameData.
	GameData.current_zoom_index = current_zoom_index
	GameData.save_settings()


func is_click_on_empty_tile() -> bool:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var mouse_pos = tilemap.get_global_mouse_position()
	var clicked_tile = tilemap.local_to_map(tilemap.to_local(mouse_pos))
	return tilemap.get_unit_at_tile(clicked_tile) == null


func _process(delta):
	# Camera shake effect
	if shake_amount > 0:
		var shake_offset = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * shake_amount
		global_position = original_position + shake_offset
		shake_amount = max(shake_amount - shake_decay * delta, 0.0)
	else:
		global_position = original_position


func shake(amount: float) -> void:
	shake_amount = amount
