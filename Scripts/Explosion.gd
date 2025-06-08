extends Node2D

@export var duration := 0.5          # Duration before the explosion node frees, if needed.
@export var explosion_animation := "explode"  # Name of the explosion animation.
var tile_pos: Vector2i              # The tile position of the explosion.

func _ready():
	# Assume the explosion is spawned as a child of the TileMap.
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	# Calculate tile position from the explosion's global position.
	tile_pos = tilemap.local_to_map(tilemap.to_local(global_position))
	
	# Set z_index based on tile position (typically the y component).
	# This ensures objects are layered correctly.
	z_index = tile_pos.y + 1000

	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(5.0)  # Adjust intensity	

func _on_explosion_finished(anim_name):
	queue_free()
