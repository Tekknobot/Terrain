extends Sprite2D

@export var tilemap: TileMap  # Reference to the battle grid TileMap
@export var highlight_texture: Texture  # Texture for the highlight sprite

var current_tile: Vector2i = Vector2i(-1, -1)  # Stores the currently hovered tile

func _ready():
	if highlight_texture:
		texture = highlight_texture  # Set the highlight sprite
	z_index = 0  # Default z-index
	set_process(true)  # Ensure it updates every frame

func _process(delta):
	if tilemap == null:
		return  # Prevent errors if tilemap isn't assigned

	var mouse_pos = get_global_mouse_position()
	mouse_pos.y += 16
	var tile_pos = tilemap.local_to_map(tilemap.to_local(mouse_pos))  # Convert to tile coordinates

	# Ensure the highlight follows the tile properly without flickering
	if is_within_bounds(tile_pos) and tile_pos != current_tile:
		current_tile = tile_pos
		position = tilemap.map_to_local(current_tile)  # No isometric offset applied
		z_index = calculate_z_index(current_tile) # Adjust layering

func calculate_z_index(tile_pos: Vector2i) -> int:
	# Ensures tiles stack properly in isometric view (higher Y = lower Z index)
	return tile_pos.y # Invert Y to ensure proper layering

func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < tilemap.grid_width and tile.y >= 0 and tile.y < tilemap.grid_height
