extends Node2D

signal reached_target

@export var speed: float = 200.0  # pixels per second
var target_position: Vector2 = Vector2.ZERO

# We'll use a Line2D node as a trail visualizer.
@onready var line_renderer: Line2D = null

func _ready() -> void:
	# Try to get an existing Line2D node; if not, create one.
	line_renderer = get_node_or_null("Line2D")
	if line_renderer == null:
		line_renderer = Line2D.new()
		# Set the line's width and default color.
		line_renderer.width = 2
		line_renderer.default_color = Color(1.0, 1.0, 0.0, 1.0)  # yellow for a lightning effect
		# Set a high z_index to ensure it draws on top.
		line_renderer.z_index = 4096
		add_child(line_renderer)
	line_renderer.clear_points()
	line_renderer.add_point(global_position)
	print("Missile _ready(): global_position =", global_position)

func set_target(start: Vector2, target: Vector2) -> void:
	# Set starting position and target.
	global_position = start
	target_position = target
	if line_renderer:
		line_renderer.clear_points()
		line_renderer.add_point(global_position)
	print("set_target(): start =", start, ", target =", target)

func _process(delta: float) -> void:
	# Check if target_position is different than the current global_position.
	if global_position == target_position:
		return

	# Calculate movement.
	var direction: Vector2 = (target_position - global_position).normalized()
	global_position += direction * speed * delta

	# Debug output: print current position and distance to target.
	print_debug("Missile position:", global_position, "Distance to target:", global_position.distance_to(target_position))

	# Update the trail.
	if line_renderer:
		var points: Array = line_renderer.points.duplicate()
		if points.size() > 0:
			points[points.size() - 1] = global_position
		else:
			points.append(global_position)
		line_renderer.points = points

	# When close enough to the target, emit the signal and remove the missile.
	if global_position.distance_to(target_position) < 5.0:
		print("Missile reached the target. Emitting 'reached_target' signal and freeing missile.")
		emit_signal("reached_target")
		queue_free()

# Helper function to print debug information
func print_debug(varargs):
	var debug_string = ""
	for arg in varargs:
		debug_string += str(arg) + " "
	print(debug_string)
