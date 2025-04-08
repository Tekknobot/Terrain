extends Node2D

signal reached_target

# Array of Vector2 positions defining the missile’s travel path (global coordinates).
var path: Array = []
var current_index: int = 0

@export var speed: float = 200.0  # Speed in pixels per second.

@onready var line_renderer: Line2D = null
@onready var particles: CPUParticles2D = $CPUParticles2D  # adjust the node path

func _ready() -> void:
	# Try to get an existing Line2D node.
	line_renderer = get_node_or_null("Line2D")
	# If none is found, create one and add it as a child.
	if line_renderer == null:
		line_renderer = Line2D.new()
		# Set the line's width to 1 pixel.
		line_renderer.width = 1
		# Optionally set its default color.
		line_renderer.default_color = Color(1, 1, 1, 1)
		add_child(line_renderer)
	# Set up the line renderer with the final path points (static)
	line_renderer.clear_points()

func follow_path(new_path: Array) -> void:
	# Duplicate the input path to avoid modifying the original.
	path = new_path.duplicate()
	current_index = 0
	# Set the starting global position to the first point of the path.
	if path.size() > 0:
		global_position = path[0]
	# Initialize the line renderer's points (static path).
	#line_renderer.points = path.duplicate()

func _process(delta: float) -> void:
	if path.is_empty():
		return
	
	if current_index < path.size():
		var target_pos: Vector2 = path[current_index]
		var direction: Vector2 = (target_pos - global_position).normalized()
		global_position += direction * speed * delta

		# Optionally update the particle node's position if it needs to be offset.
		# For example, if you want the particles to trail 16 pixels behind:
		particles.position = Vector2(-48 * 2, 54)

		if global_position.distance_to(target_pos) < 5.0:
			current_index += 1
			var tilemap = get_tree().get_current_scene().get_node("TileMap")
			tilemap.play_attack_sound(global_position)

	if current_index >= path.size():
		emit_signal("reached_target")
		queue_free()
