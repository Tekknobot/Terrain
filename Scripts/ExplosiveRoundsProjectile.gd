extends Node2D

signal finished

@export var missile_speed: float = 0.5
@export var pixel_size: int = 2  # For pixel-perfect snapping

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var control_point: Vector2 = Vector2.ZERO
var progress: float = 0.0
var is_ready: bool = false

@export var primary_damage: int = 30   # Damage at center tile.
@export var splash_damage: int = 20    # Damage for cardinal adjacent tiles.
@export var diagonal_damage: int = 15  # Damage for diagonal tiles.
@export var knockback_distance: int = 1  # How many tiles to push (optional).

@onready var sprite: Sprite2D = $Sprite2D
@onready var line_renderer: Line2D = $Line2D

func _ready() -> void:
	visible = false
	progress = 0.0
	is_ready = false
	
	# Configure the local Line2D (missile trail).
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
	return (1 - t) * (1 - t) * start_pos + 2 * (1 - t) * t * control_point + t * t * end_pos

# Update the missile's rotation to face its direction of travel.
func update_rotation() -> void:
	var next_pos = bezier_point(min(progress + 0.05, 1.0))
	var dir = next_pos - global_position

# Call this function to set the missile's path.
func set_target(start: Vector2, target: Vector2) -> void:
	start_pos = start
	end_pos = target
	# Set a control point for an arcing trajectory (adjust offset as desired).
	control_point = (start + target) / 2 + Vector2(0, -200)
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
	
	# Instantiate an explosion effect at the center.
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	explosion.global_position = tilemap.to_global(tilemap.map_to_local(impact_tile))
	get_tree().get_current_scene().add_child(explosion)
	
	# Loop over the 3x3 grid around the impact tile.
	for x in range(-1, 2):
		for y in range(-1, 2):
			var tile = impact_tile + Vector2i(x, y)
			var damage: int = 0
			# Determine damage based on distance:
			if x == 0 and y == 0:
				damage = primary_damage
			elif abs(x) + abs(y) == 1:
				damage = splash_damage
			else:
				damage = diagonal_damage
			
			# Damage any enemy unit on this tile.
			var enemy_unit = tilemap.get_unit_at_tile(tile)
			if enemy_unit and not enemy_unit.is_player:
				enemy_unit.take_damage(damage)
				enemy_unit.flash_white()
				enemy_unit.shake()
				print("Explosive Rounds: ", enemy_unit.name, " took ", damage, " damage at tile ", tile)
		
	
	print("Explosive Rounds missile exploded at tile: ", impact_tile)
	# Update z-index based on current position.
	z_index = int(global_position.y)
	z_as_relative = false
