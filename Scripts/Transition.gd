extends ColorRect

@export var fade_duration: float = 1.0

func _ready() -> void:
	# Start fully transparent.
	modulate.a = 0.0
	# Set the minimum size to cover the entire viewport.
	custom_minimum_size = get_viewport_rect().size

func fade_out() -> Tween:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	return tween

func fade_in() -> Tween:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween
