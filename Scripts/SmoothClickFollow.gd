extends Camera2D

@export var smoothing_speed: float = 5.0  # higher = snappier follow

var target_position: Vector2
var dragging := false
var last_mouse_screen: Vector2
var smoothing_enabled: bool = false

func _ready() -> void:
	# start with camera where it is
	target_position = position
	# turn on built-in smoothing if you like, but we'll lerp ourselves
	smoothing_enabled = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# begin or end drag
		dragging = event.pressed
		if dragging:
			last_mouse_screen = event.position
	elif dragging and event is InputEventMouseMotion:
		# calculate how much the mouse moved on screen
		var delta_screen = last_mouse_screen - event.position
		# translate that into world-space pan (account for zoom)
		target_position += delta_screen * zoom
		last_mouse_screen = event.position

func _process(delta: float) -> void:
	# smoothly move toward the dragged target position
	position = position.lerp(target_position, smoothing_speed * delta)
