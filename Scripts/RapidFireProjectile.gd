extends Node2D

signal finished

@export var missile_speed: float = 0.5
@export var pixel_size: int = 2  # For pixel-perfect snapping

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var control_point: Vector2 = Vector2.ZERO
var progress: float = 0.0
var is_ready: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var line_renderer: Line2D = $Line2D

# Damage parameters (you can tweak these)
@export var primary_damage: int = 40
@export var secondary_damage: int = 25

func _ready() -> void:
	visible = false
	progress = 0.0
	is_ready = false
	# Use the local Line2D node (if available) for a missile trail.
	if line_renderer:
		line_renderer.clear_points()
		line_renderer.width = pixel_size
		line_renderer.texture_mode = Line2D.LINE_TEXTURE_TILE
		line_renderer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line_renderer.joint_mode = Line2D.LINE_JOINT_BEVEL
		line_renderer.begin_cap_mode = Line2D.LINE_CAP_NONE
		line_renderer.end_cap_mode = Line2D.LINE_CAP_NONE
	else:
		print("❌ No Line2D found; missile trail will not render.")

func _process(delta: float) -> void:
	if is_ready and progress < 1.0:
		progress += missile_speed * delta
		var new_position = bezier_point(progress)
		global_position = new_position.snapped(Vector2(pixel_size, pixel_size))
		update_rotation()
		if line_renderer:
			line_renderer.add_point(global_position)
		
		# Update the projectile's z-index based on its current tile position.
		var tilemap = get_node("/root/BattleGrid/TileMap")
		if tilemap:
			var current_tile = tilemap.local_to_map(tilemap.to_local(global_position))
			# Example: use a base z-index and add a multiple of the tile's y coordinate.
			var base_z = 1000  # Adjust as needed.
			z_index = base_z + current_tile.y * 10
	elif is_ready and progress >= 1.0:
		is_ready = false
		if line_renderer:
			line_renderer.visible = false
		explode()
		emit_signal("finished")
		queue_free()


# Calculate a quadratic Bezier point.
func bezier_point(t: float) -> Vector2:
	# B(t) = (1-t)^2 * p0 + 2(1-t)t * p1 + t^2 * p2
	return (1 - t) * (1 - t) * start_pos + 2 * (1 - t) * t * control_point + t * t * end_pos

# Update the missile's rotation to face its direction.
func update_rotation() -> void:
	var next_pos = bezier_point(min(progress + 0.05, 1.0))
	var dir = next_pos - global_position
	#sprite.rotation = dir.angle()

# Call this function to set the missile's path.
# For Rapid Fire, the first projectile uses set_target as normal.
func set_target(start: Vector2, target: Vector2) -> void:
	start_pos = start
	end_pos = target
	# Set a control point for an arcing trajectory (offset upward by 200 pixels).
	control_point = (start + target) / 2 + Vector2(0, 0)
	global_position = start_pos
	visible = true
	is_ready = true
	progress = 0.0
	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = true

# When the missile reaches its destination, explode.
func explode() -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		print("No TileMap found!")
		return
	var impact_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	
	# Spawn a primary explosion at the impact tile.
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	explosion.global_position = tilemap.to_global(tilemap.map_to_local(impact_tile))
	get_tree().get_current_scene().add_child(explosion)
	
	# Damage the impact tile.
	var unit = tilemap.get_unit_at_tile(impact_tile)
	if unit:
		unit.take_damage(primary_damage)
		unit.flash_white()
		unit.shake()

	print("Rapid Fire missile exploded at tile: ", impact_tile)
	z_index = int(global_position.y)
	z_as_relative = false
