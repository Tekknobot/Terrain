extends Sprite2D

@export var tilemap: TileMap            # Reference to the battle grid TileMap
@export var highlight_texture: Texture  # Texture for the highlight sprite

# The current local hovered tile.
var current_tile: Vector2i = Vector2i(-1, -1)
# Get this client's unique ID.
var local_peer_id: int = 0
# Dictionary to hold remote hover highlights (peer_id: highlight Sprite2D)
var remote_hover_highlights := {}

func _ready():
	local_peer_id = get_tree().get_multiplayer().get_unique_id()
	if highlight_texture:
		texture = highlight_texture
	z_index = 0
	set_process(true)

func _process(delta):
	if tilemap == null:
		return
	var mouse_pos = get_global_mouse_position()
	mouse_pos.y += 16  # Adjust for UI offset if necessary
	var tile_pos = tilemap.local_to_map(tilemap.to_local(mouse_pos))
	
	# Only update if the hovered tile changed.
	if is_within_bounds(tile_pos) and tile_pos != current_tile:
		current_tile = tile_pos
		position = tilemap.map_to_local(current_tile)
		z_index = calculate_z_index(current_tile)
		# Send the new hover tile along with our peer ID
		rpc("update_hover_tile", local_peer_id, current_tile)

func calculate_z_index(tile_pos: Vector2i) -> int:
	# In isometric view, a higher tile.y generally means a lower z-index.
	return tile_pos.y

func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < tilemap.grid_width and tile.y >= 0 and tile.y < tilemap.grid_height

@rpc("unreliable")
func update_hover_tile(peer_id: int, new_tile: Vector2i) -> void:
	# If this update came from us, ignore it.
	if peer_id == local_peer_id:
		return

	# Check if we already have a highlight sprite for that peer; if not, create one.
	if not remote_hover_highlights.has(peer_id):
		var new_highlight = Sprite2D.new()
		if highlight_texture:
			new_highlight.texture = highlight_texture
		# Optionally, modify the color so remote highlights look different.
		new_highlight.modulate = Color(1, 0.8, 0.8, 1)
		new_highlight.z_index = 0
		# Add the new highlight as a sibling (or to a dedicated parent).
		get_parent().add_child(new_highlight)
		remote_hover_highlights[peer_id] = new_highlight

	# Update the remote highlight's position.
	var remote_sprite: Sprite2D = remote_hover_highlights[peer_id]
	remote_sprite.position = tilemap.map_to_local(new_tile)
	remote_sprite.z_index = calculate_z_index(new_tile)
