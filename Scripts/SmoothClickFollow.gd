extends Camera2D

@export var smoothing_speed: float = 5.0  # higher = faster follow

var target_position: Vector2

func _ready() -> void:
	target_position = position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# get_global_mouse_position() already gives you world coords
		target_position = get_global_mouse_position()

func _process(delta: float) -> void:
	# ease the camera toward the last-clicked world position
	position = position.lerp(target_position, smoothing_speed * delta)
