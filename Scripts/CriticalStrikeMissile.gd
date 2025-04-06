extends Node2D

signal finished

@export var missile_speed: float = 0.5
@export var pixel_size: int = 2  # Ensures pixel-perfect snapping

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var control_point: Vector2 = Vector2.ZERO
var progress: float = 0.0
var is_ready: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var line_renderer: Line2D = $Line2D

func _ready() -> void:
	visible = false
	progress = 0.0
	is_ready = false
	
	# Configure the local Line2D node (missile trail)
	if line_renderer:
		line_renderer.clear_points()
		line_renderer.width = pixel_size
		line_renderer.texture = preload("res://Textures/missile.png")
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
	elif is_ready and progress >= 1.0:
		is_ready = false
		if line_renderer:
			line_renderer.visible = false
		# Call our asynchronous explosion sequence.
		await spawn_explosions()
		emit_signal("finished")
		queue_free()

# Calculate a quadratic Bezier point.
func bezier_point(t: float) -> Vector2:
	# B(t) = (1-t)^2 * p0 + 2(1-t)t * p1 + t^2 * p2
	return (1 - t) * (1 - t) * start_pos + 2 * (1 - t) * t * control_point + t * t * end_pos

# Update the missile's rotation to face its direction of travel.
func update_rotation() -> void:
	var next_pos = bezier_point(min(progress + 0.05, 1.0))
	var dir = next_pos - global_position
	sprite.rotation = dir.angle()

# Call this function to set the missile's path.
func set_target(start: Vector2, target: Vector2) -> void:
	start_pos = start
	end_pos = target
	# Set a control point for an arcing trajectory (offset upward by 200 pixels).
	control_point = (start + target) / 2 + Vector2(0, -200)
	global_position = start_pos
	visible = true
	is_ready = true
	progress = 0.0
	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = true

# Asynchronous explosion sequence.
func spawn_explosions() -> void:
	# Preload the explosion effect once.
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		print("No TileMap found!")
		return
	var impact_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	
	# Iterate over the 3x3 grid around the impact tile.
	for x in range(-1, 2):
		for y in range(-1, 2):
			var tile = impact_tile + Vector2i(x, y)
			
			# Instantiate an explosion effect on each tile.
			var explosion = explosion_scene.instantiate()
			# Position the explosion at the center of the tile.
			explosion.global_position = tilemap.to_global(tilemap.map_to_local(tile))
			get_tree().get_current_scene().add_child(explosion)
			
			# Determine damage for this tile.
			var damage: int = 0
			if x == 0 and y == 0:
				damage = 40
			else:
				damage = 25

			# Damage any unit on this tile.
			var unit = tilemap.get_unit_at_tile(tile)
			if unit:
				unit.take_damage(damage)
				unit.flash_white()
				
			# Optionally, damage structures on this tile.
			var structure = tilemap.get_structure_at_tile(tile)
			if structure:
				var anim_sprite = structure.get_node_or_null("AnimatedSprite2D")
				if anim_sprite:
					anim_sprite.play("demolished")
					structure.modulate = Color(1, 1, 1, 1)
			
			# Wait a short delay before processing the next explosion.
			await get_tree().create_timer(0.1).timeout
	
	print("Missile exploded at tile: ", impact_tile)
	
	# Optionally, update z-index for proper layering.
	z_index = int(global_position.y)
	z_as_relative = false
