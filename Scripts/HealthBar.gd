extends ProgressBar

func _process(_delta):
	update_fill_color()

func update_fill_color():
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

func set_fill_color(color: Color):
	var style = get("theme_override_styles/fill")
	if style:
		style.bg_color = color
