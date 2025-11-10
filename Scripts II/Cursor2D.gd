# File: Cursor2D.gd
# Purpose: draws a texture cursor that snaps to a TileMap cell and renders above tiles
extends Node

@export_group("Target")
@export var tilemap_path: NodePath                       # assign your IsoGrid/TileMap here

@export_group("Cursor")
@export var cursor_texture: Texture2D                    # your PNG/WEBP/etc
@export var cursor_size_px: Vector2i = Vector2i(64, 64)  # final on-screen size (scaled to this)
@export var cursor_offset_px: Vector2 = Vector2(0, 0)    # extra pixel nudge after snapping
@export var cursor_modulate: Color = Color(1, 1, 1, 0.9) # translucency
@export var hide_when_outside: bool = true               # auto-hide off the board

@export_group("Snap")
@export var pixel_align: bool = true                     # round to whole pixels for crisp look
@export var use_tile_center: bool = true                 # center on tile, else top-left

# internal
var _tm: TileMap
var _layer: CanvasLayer
var _rect: TextureRect

func _ready() -> void:
	_tm = get_node_or_null(tilemap_path) as TileMap
	if _tm == null:
		push_error("Cursor2D: tilemap_path is not set or not a TileMap.")
		return

	# Top overlay layer
	_layer = CanvasLayer.new()
	_layer.name = "CursorLayer"
	add_child(_layer)

	# Draw the cursor as UI so it sits above tiles
	_rect = TextureRect.new()
	_rect.name = "Cursor"
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.texture = cursor_texture
	_rect.modulate = cursor_modulate
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.size = cursor_size_px
	_layer.add_child(_rect)

	# If no texture yet, hide
	_rect.visible = cursor_texture != null

func _process(_dt: float) -> void:
	if _tm == null or _rect == null:
		return

	# 1) Read mouse in screen space
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()

	# 2) Convert screen -> world(canvas) -> tilemap local (mirrors your TurnManager math)
	var canvas_xform: Transform2D = _tm.get_viewport().get_canvas_transform()
	var world: Vector2 = canvas_xform.affine_inverse() * mouse_screen
	var to_local: Transform2D = _tm.get_global_transform().affine_inverse()
	var local: Vector2 = to_local * world

	# compensate the same piece offset you use elsewhere so the tile math matches visuals
	var offset: Vector2 = Vector2.ZERO
	var off = _tm.get("piece_pixel_offset")
	if typeof(off) == TYPE_VECTOR2:
		offset = off as Vector2
	local -= offset

	# 3) Snap to a tile
	var tile_pos: Vector2i = _tm.local_to_map(local)

	var in_bounds := tile_pos.x >= 0 and tile_pos.x < 8 and tile_pos.y >= 0 and tile_pos.y < 8
	if hide_when_outside:
		_rect.visible = (cursor_texture != null) and in_bounds
	else:
		_rect.visible = (cursor_texture != null)

	if not in_bounds and hide_when_outside:
		return

	# 4) Compute the world position at that tile’s anchor (center or top-left)
	var local_anchor: Vector2 = _tm.map_to_local(tile_pos)
	if use_tile_center:
		# TileMap.map_to_local already returns the *center* when using square/iso;
		# if your tileset differs, adjust here.
		pass
	# convert to global (world/canvas) and then to screen for the UI node
	var world_anchor: Vector2 = _tm.to_global(local_anchor + offset)
	var screen_anchor: Vector2 = _tm.get_viewport().get_canvas_transform() * world_anchor

	# 5) Place the TextureRect
	var pos := screen_anchor + cursor_offset_px
	if pixel_align:
		pos = pos.round()
	_rect.position = pos - _rect.size * 0.5 if use_tile_center else pos

	# keep runtime style synced with exports
	_rect.modulate = cursor_modulate
	_rect.size = cursor_size_px
	if cursor_texture and _rect.texture != cursor_texture:
		_rect.texture = cursor_texture
