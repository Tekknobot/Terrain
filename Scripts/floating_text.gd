extends Node2D

@export var duration := 1.0
@export var rise_distance := 40
@export var float_speed := 50

func _ready():
	var tween = create_tween()
	var target_pos = position + Vector2(0, -rise_distance)
	tween.tween_property(self, "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(Callable(self, "queue_free"))


func set_damage(amount: int, is_crit: bool = false):
	var label = $Label
	label.text = str(amount)
	if is_crit:
		label.modulate = Color(1, 0.2, 0.2)  # Red for critical hit
	else:
		label.modulate = Color(1, 1, 1)
