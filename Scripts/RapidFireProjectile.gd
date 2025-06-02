# RapidFireProjectile.gd
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
		var tilemap = get_node("/root/BattleGrid/TileMap")
		if tilemap:
			var current_tile = tilemap.local_to_map(tilemap.to_local(global_position))
			var base_z = 1000
			z_index = base_z + current_tile.y * 10
	elif is_ready and progress >= 1.0:
		is_ready = false
		if line_renderer:
			line_renderer.visible = false
		explode()
		emit_signal("finished")
		queue_free()

func bezier_point(t: float) -> Vector2:
	return (1 - t) * (1 - t) * start_pos \
		   + 2 * (1 - t) * t * control_point \
		   + t * t * end_pos

func update_rotation() -> void:
	var next_pos = bezier_point(min(progress + 0.05, 1.0))
	var dir = next_pos - global_position
	# If you want the sprite to rotate to face direction, uncomment:
	# sprite.rotation = dir.angle()

# ————————————— Call this to configure the projectile —————————————
func set_target(start: Vector2, target: Vector2) -> void:
	start_pos = start
	end_pos = target
	# For a flat shot, control_point is simply the midpoint:
	control_point = (start + target) / 2
	global_position = start_pos
	visible = true
	is_ready = true
	progress = 0.0
	if line_renderer:
		line_renderer.clear_points()
		line_renderer.visible = true

func explode() -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		print("No TileMap found!")
		return
	var impact_tile = tilemap.local_to_map(tilemap.to_local(global_position))
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	explosion.global_position = tilemap.to_global(tilemap.map_to_local(impact_tile))
	get_tree().get_current_scene().add_child(explosion)

	var unit = tilemap.get_unit_at_tile(impact_tile)
	if unit:
		unit.take_damage(primary_damage)
		unit.flash_white()
		unit.shake()

	print("Rapid Fire missile exploded at tile: ", impact_tile)
	z_index = int(global_position.y)
	z_as_relative = false
