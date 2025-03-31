extends Node2D

signal finished

@export var missile_speed: float = 2.0
@export var pixel_size: int = 2  # Ensures pixel-perfect snapping

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var control_point: Vector2 = Vector2.ZERO
var progress: float = 0.0
var is_ready: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var line_renderer: Line2D = $Line2D

func _ready():
	visible = false
	progress = 0.0

	var scene = get_tree().get_current_scene()
	line_renderer = scene.get_node("MissileTrail")

	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = true

		# Use the average Y of start and end to sort depth
		var avg_y = (start_pos.y + end_pos.y) / 2
		line_renderer.z_index = int(avg_y)
		line_renderer.z_as_relative = false  # Use global z, not relative to parent

		line_renderer.clear_points()
		line_renderer.visible = false
		line_renderer.width = pixel_size  # Match pixel size

		line_renderer.texture = preload("res://Textures/missile.png")
		line_renderer.texture_mode = Line2D.LINE_TEXTURE_TILE
		line_renderer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		
		# Optional visual tuning:
		line_renderer.joint_mode = Line2D.LINE_JOINT_BEVEL
		line_renderer.begin_cap_mode = Line2D.LINE_CAP_NONE
		line_renderer.end_cap_mode = Line2D.LINE_CAP_NONE

	else:
		print("❌ Could not find Line2D in scene. No trail will render.")


func _process(delta):
	if is_ready and progress < 1.0:
		progress += missile_speed * delta
		var new_position = bezier_point(progress)
		global_position = new_position.snapped(Vector2(pixel_size, pixel_size))
		update_rotation()

		if line_renderer:
			line_renderer.add_point(global_position)
	elif is_ready and progress >= 1.0:
		is_ready = false
		if line_renderer:
			line_renderer.visible = false

		# Instantiate explosion effect at the missile's final position.
		var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().get_current_scene().add_child(explosion)
		
		# Damage any unit on this tile.
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		var tile = tilemap.local_to_map(tilemap.to_local(global_position))
		var target_unit = tilemap.get_unit_at_tile(tile)
		if target_unit:
			target_unit.take_damage(40)  # Adjust damage as needed.
			target_unit.flash_white()
			
		emit_signal("finished")
		queue_free()

	z_index = int(global_position.y)
	z_as_relative = false

func bezier_point(t: float) -> Vector2:
	var p0 = start_pos
	var p1 = control_point
	var p2 = end_pos
	return (1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * p1 + t * t * p2

func update_rotation():
	var next_pos = bezier_point(min(progress + 0.05, 1.0))
	var direction = next_pos - global_position
	sprite.rotation = direction.angle()

func set_target(start: Vector2, target: Vector2):
	start_pos = start
	end_pos = target
	control_point = (start + target) / 2 + Vector2(0, -200)

	global_position = start_pos
	visible = true
	is_ready = true

	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = true  # ✅ show trail
