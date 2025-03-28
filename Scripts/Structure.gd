extends Node2D

@export var tile_pos: Vector2i = Vector2i.ZERO
@export var y_offset: int = 8  # Y offset in pixels

func _ready():
	# Set the node's z_index based on its global Y position.
	z_index = int(global_position.y)
	print("Structure placed at tile:", tile_pos, "with z_index:", z_index)

func set_tile_pos(new_tile_pos: Vector2i) -> void:
	tile_pos = new_tile_pos
	var tree = get_tree()
	if tree:
		var current_scene = tree.get_current_scene()
		if current_scene:
			var tilemap = current_scene.get_node("TileMap")
			if tilemap:
				# Convert the tile position to world position and apply the y offset.
				global_position = tilemap.map_to_local(new_tile_pos) + Vector2(0, y_offset)
				# Update the z_index based on the new global Y.
				z_index = int(global_position.y)
			else:
				push_warning("TileMap node not found!")
		else:
			push_warning("Current scene not available!")
	else:
		push_warning("No SceneTree available!")
	print("Tile position set to:", tile_pos)
	
	global_position.y -= 8
