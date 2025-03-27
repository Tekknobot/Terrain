extends Camera2D

var zoom_levels = [Vector2(4,4), Vector2(5,5), Vector2(6,6), Vector2(8,8)]
var current_zoom_index := 0
var dragging := false
var drag_start := Vector2.ZERO
var camera_start := Vector2.ZERO

func _ready():
	zoom = zoom_levels[current_zoom_index]
	set_process_unhandled_input(true)  

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var grid_width = 12
	var grid_height = 12
	var center_tile = Vector2(grid_width / 2, grid_height / 2)
	global_position = tilemap.to_global(tilemap.map_to_local(center_tile))

func _unhandled_input(event):
	# Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			current_zoom_index = max(current_zoom_index - 1, 0)
			_zoom_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			current_zoom_index = min(current_zoom_index + 1, zoom_levels.size() - 1)
			_zoom_camera()
		
		# Dragging
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if is_click_on_empty_tile():
					dragging = true
					drag_start = get_global_mouse_position()
					camera_start = global_position
			else:
				dragging = false

	elif event is InputEventMouseMotion and dragging:
		global_position = camera_start - (get_global_mouse_position() - drag_start) * 0.6

func _zoom_camera():
	var tween = create_tween()
	tween.tween_property(self, "zoom", zoom_levels[current_zoom_index], 0.2).set_trans(Tween.TRANS_CUBIC)

func is_click_on_empty_tile() -> bool:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var mouse_pos = tilemap.get_global_mouse_position()
	var clicked_tile = tilemap.local_to_map(tilemap.to_local(mouse_pos))
	return tilemap.get_unit_at_tile(clicked_tile) == null
