extends Sprite2D

@export var tilemap: TileMap            # Assign this in the Inspector.
@export var highlight_texture: Texture  # Assign this texture in the Inspector.

# The current tile (in tile coordinates) that the mouse is hovering over.
var current_tile: Vector2i = Vector2i(-1, -1)

func _ready():
	visible = false
	# If we have a texture assigned, set it.
	if highlight_texture:
		texture = highlight_texture
	# Set a base z-index.
	z_index = 0
	# Ensure _process runs every frame.
	set_process(true)
	await get_tree().create_timer(4).timeout
	visible = true

func _process(delta):
	# If the tilemap hasn't been assigned, there's nothing to do.
	if tilemap == null:
		return
	
	# Get the global mouse position; adjust Y if needed (for example, to account for UI offset).
	var mouse_pos = get_global_mouse_position()
	mouse_pos.y += 16  # Adjust this value as necessary
	
	# Convert the mouse position to a tile coordinate.
	var tile_pos = tilemap.local_to_map(tilemap.to_local(mouse_pos))
	
	# If the new tile is valid and different from our current tile, update.
	if is_within_bounds(tile_pos) and tile_pos != current_tile:
		current_tile = tile_pos
		# Update this sprite’s position to the upper‑left corner (or center) of the tile.
		position = tilemap.map_to_local(current_tile)
		# Update z-index so that the sprite layers properly (for isometric, you might use tile.y).
		z_index = calculate_z_index(current_tile)
		#print("Local hover tile updated to: ", current_tile)

func calculate_z_index(tile_pos: Vector2i) -> int:
	# For basic layering, we simply use tile_pos.y.
	return tile_pos.y

func is_within_bounds(tile: Vector2i) -> bool:
	# Check that the tile's x and y values are within the TileMap's grid.
	return tile.x >= 0 and tile.x < tilemap.grid_width and tile.y >= 0 and tile.y < tilemap.grid_height
