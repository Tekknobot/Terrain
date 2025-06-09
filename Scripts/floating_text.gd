extends Node2D

@export var duration := 1.0
@export var rise_distance := 40
@export var float_speed := 50
@export var start_scale := 2.0
@export var wiggle_amplitude := 6.0 # degrees
@export var wiggle_speed := 6.0

func _ready():
	global_position.y -= 32
	
	# Initial scale for pop-in effect
	scale = Vector2(start_scale, start_scale)

	# Main tween (scale, rise, fade)
	var tween = create_tween()

	# Scale down to normal
	tween.tween_property(self, "scale", Vector2.ONE, 0.6)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Rise movement
	var target_pos = position + Vector2(0, -rise_distance)
	tween.tween_property(self, "position", target_pos, duration)\
		.set_trans(Tween.TRANS_SINE)

	# Fade out alpha
	tween.tween_property(self, "modulate:a", 0.0, duration)\
		.set_trans(Tween.TRANS_LINEAR)

	# Wiggle rotation (looping)
	var wiggle_tween = create_tween().set_loops()
	var angle = deg_to_rad(wiggle_amplitude)
	wiggle_tween.tween_property(self, "rotation", angle, 1.0 / wiggle_speed)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wiggle_tween.tween_property(self, "rotation", -angle, 1.0 / wiggle_speed)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Cleanup
	tween.tween_callback(Callable(self, "queue_free"))

func set_damage(amount: int, is_crit: bool = false):
	var label = $Label
	label.text = str(amount)

	if is_crit:
		label.modulate = Color(1, 0.2, 0.2) # Red for crit
	else:
		label.modulate = Color(1, 1, 1) # White for normal hit
