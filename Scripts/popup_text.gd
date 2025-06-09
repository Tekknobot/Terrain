extends Node2D

@export var duration := 1.2
@export var rise_distance := 32
@export var wiggle_amplitude := 6.0 # Degrees
@export var wiggle_speed := 6.0
@export var start_scale := 2

func _ready():
	var label = $Label

	# Set initial scale for pop
	scale = Vector2(start_scale, start_scale)

	# Main tween for scale, position, and fade
	var tween = create_tween()

	# Scale pop: shrink to normal size
	tween.tween_property(self, "scale", Vector2.ONE, 0.8)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Rise the popup text
	var target = position + Vector2(0, -rise_distance)
	tween.tween_property(self, "position", target, duration)\
		.set_trans(Tween.TRANS_SINE)

	# Fade out alpha
	tween.tween_property(self, "modulate:a", 0.0, duration)\
		.set_trans(Tween.TRANS_LINEAR)

	# Wiggle tween (looping back and forth)
	var angle_rad = deg_to_rad(wiggle_amplitude)
	var wiggle_tween = create_tween().set_loops()
	wiggle_tween.tween_property(self, "rotation", angle_rad, 1.0 / wiggle_speed)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wiggle_tween.tween_property(self, "rotation", -angle_rad, 1.0 / wiggle_speed)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Cleanup when done
	tween.tween_callback(Callable(self, "queue_free"))

func set_text(message: String, color: Color = Color.WHITE):
	var label = $Label
	#label.text = message
	#label.modulate = color
