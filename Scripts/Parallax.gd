extends ParallaxBackground

@export var amplitude: Vector2 = Vector2(20, 10)   # Maximum offset from the center.
@export var period: float = 5.0                     # Duration (in seconds) of one full oscillation cycle.

var elapsed_time: float = 0.0

func _process(delta: float) -> void:
	elapsed_time += delta
	# Calculate oscillation using sine (for X) and cosine (for Y).
	var offset_x = amplitude.x * sin(elapsed_time * TAU / period)
	var offset_y = amplitude.y * cos(elapsed_time * TAU / period)
	# Set the global scroll_offset for the parallax layers.
	scroll_offset = Vector2(offset_x, offset_y)
