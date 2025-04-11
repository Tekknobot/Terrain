extends ProgressBar

func _ready() -> void:
	# Duplicate the fill style (if it exists) so we have an instance-specific style.
	var style = get("theme_override_styles/fill")
	if style:
		style = style.duplicate()
		set("theme_override_styles/fill", style)

func _process(_delta: float) -> void:
	update_fill_color()

func update_fill_color() -> void:
	var percent := value / max_value
	
	if percent > 0.66:
		# High health = green
		set_fill_color(Color(0.2, 1, 0.2))
	elif percent > 0.33:
		# Medium health = yellow
		set_fill_color(Color(1, 1, 0.2))
	else:
		# Low health = red
		set_fill_color(Color(1, 0.2, 0.2))

func set_fill_color(color: Color) -> void:
	# Get the progress bar's unique fill style.
	var style = get("theme_override_styles/fill")
	if style:
		# We duplicate it before modifying it to ensure we're not modifying a shared resource.
		var new_style = style.duplicate()
		new_style.bg_color = color
		set("theme_override_styles/fill", new_style)
