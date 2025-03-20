extends Node2D

@export var missile_speed: float = 2.0
@export var pixel_size: int = 2  # Ensures pixel-perfect snapping

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var control_point: Vector2 = Vector2.ZERO
var progress: float = 0.0
var is_ready: bool = false  # Ensures missile starts only after target is set

@onready var sprite: Sprite2D = $Sprite2D  # Reference to the missile sprite
var line_renderer: Line2D  # Reference to global Line2D in scene

func _ready():
	visible = false  # Hide until `set_target()` is called
	progress = 0.0  # Ensure movement starts fresh

	# Find Line2D in the scene under the root node
	var root = get_tree().root.get_child(0)  # Assuming it's a direct child of the main scene
	line_renderer = root.find_child("Line2D", true, false)

	if line_renderer:
		line_renderer.clear_points()  # Reset line for new missile
		line_renderer.width = pixel_size  # Ensure line width fits pixel art scale
		# Apply a pixel texture
		line_renderer.texture = preload("res://Textures/missile.png")
		line_renderer.texture_mode = Line2D.LINE_TEXTURE_TILE  # Repeat texture for pixelated effect
	else:
		print("Error: Could not find Line2D in the scene. Missile trail will not render.")

func _process(delta):
	if is_ready and progress < 1.0:
		progress += missile_speed * delta
		var new_position = bezier_point(progress)  # Calculate new position
		position = new_position.snapped(Vector2(pixel_size, pixel_size))  # Snap to pixel grid
		update_rotation()  # Rotate missile towards movement direction

		# Ensure the existing `Line2D` updates properly
		if line_renderer:
			line_renderer.add_point(position.snapped(Vector2(pixel_size, pixel_size)))  # Snap to pixels

	else:
		if is_ready:
			queue_free()  # Remove missile when it reaches target

func bezier_point(t: float) -> Vector2:
	# Quadratic Bezier curve calculation
	var p0 = start_pos
	var p1 = control_point
	var p2 = end_pos
	return (1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * p1 + t * t * p2

func update_rotation():
	if progress < 1.0:
		var next_pos = bezier_point(min(progress + 0.05, 1.0))  # Look slightly ahead
		var direction = next_pos - position
		sprite.rotation = direction.angle()

func set_target(start: Vector2, target: Vector2):
	start_pos = start
	end_pos = target
	control_point = (start_pos + end_pos) / 2 + Vector2(0, -200)  # Arcing upwards

	position = start_pos  # Ensure it starts in the correct place
	visible = true  # Make the missile visible only after setup
	is_ready = true  # Now it's safe to move

	# Ensure `Line2D` updates with the missile movement
	if line_renderer:
		line_renderer.clear_points()  # Reset trail for new missile
	else:
		print("Error: Line2D not found in scene.")
