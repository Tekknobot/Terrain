extends Node2D

@export var duration := 1.2
@export var rise_distance := 60

func _ready():
	var label = $Label
	var tween = create_tween()

	# Flash red/white color 3 times before fading out
	for i in range(3):
		tween.tween_property(label, "modulate", Color(1, 1, 1), 0.1)  # White
		tween.tween_property(label, "modulate", Color(1, 0, 0), 0.1)  # Red

	# Rise the popup text
	var target = position + Vector2(0, -rise_distance)
	tween.tween_property(self, "position", target, duration).set_trans(Tween.TRANS_SINE)

	# Fade out
	tween.tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_LINEAR)
	
	# Cleanup
	tween.tween_callback(Callable(self, "queue_free"))

func set_text(message: String, color: Color = Color.WHITE):
	var label = $Label
	label.text = message
	label.modulate = color
