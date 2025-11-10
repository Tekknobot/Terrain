# File: MapGen.gd
# Attach to: IsoGrid/TileMap
extends TileMap

# ------------------------------------------------------------
# CHESS PIECE SLOTS (assign your PackedScenes in the Inspector)
# ------------------------------------------------------------
@export_group("Chess — White")
@export var white_piece_slots: Array[PackedScene] = []  # size 16: [R,N,B,Q,K,B,N,R, 8x Pawns a..h]

@export_group("Chess — Black")
@export var black_piece_slots: Array[PackedScene] = []  # size 16: [R,N,B,Q,K,B,N,R, 8x Pawns a..h]

@export_group("") # close group

# Slot order per side:
# 0..7  -> back rank a..h = [R, N, B, Q, K, B, N, R]
# 8..15 -> pawns a..h
const CHESS_BACK_ORDER := ["R","N","B","Q","K","B","N","R"]
const SLOT_LABELS := [
	"Back a (Rook)",    # 0
	"Back b (Knight)",  # 1
	"Back c (Bishop)",  # 2
	"Back d (Queen)",   # 3
	"Back e (King)",    # 4
	"Back f (Bishop)",  # 5
	"Back g (Knight)",  # 6
	"Back h (Rook)",    # 7
	"Pawn a",           # 8
	"Pawn b",           # 9
	"Pawn c",           # 10
	"Pawn d",           # 11
	"Pawn e",           # 12
	"Pawn f",           # 13
	"Pawn g",           # 14
	"Pawn h"            # 15
]

# ------------------------------------------------------------
# BOARD CONFIG
# ------------------------------------------------------------
@export var grid_width:  int = 8   # chessboard is 8x8
@export var grid_height: int = 8

# Assign these to your TileSet’s light/dark square source IDs
@export var light_square_tile_id: int = 7
@export var dark_square_tile_id: int = 10

# Piece visuals/orientation & positioning
@export var piece_pixel_offset: Vector2 = Vector2(0, -8)     # adjust if your art baseline shifts
@export var black_piece_tint: Color = Color8(255, 110, 255, 255)
@export var tint_black_pieces: bool = true                   # toggle tinting

# ------------------------------------------------------------
# CURSOR (Tile overlay that is over tiles but below piece nodes)
# ------------------------------------------------------------
@export_group("Cursor")
@export var cursor_enabled: bool = true
@export var cursor_layer: int = 4           # must be > the board's base layer (0) and < any piece nodes (children draw above)
@export var cursor_tile_id: int = 12        # choose a tile from your TileSet to use as the cursor texture
@export var hide_cursor_when_outside: bool = true

var _cursor_last: Vector2i = Vector2i(-9999, -9999)

# ------------------------------------------------------------
# LIFECYCLE
# ------------------------------------------------------------
func _ready() -> void:
	# Ensure full opacity
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)

	clear_map()
	_generate_map()

func _process(_dt: float) -> void:
	if not cursor_enabled:
		_clear_cursor()
		return
	_update_cursor_tile()

# Quick regenerate (e.g., from a button)
func regenerate() -> void:
	clear_map()
	_generate_map()

# ------------------------------------------------------------
# CORE GENERATION
# ------------------------------------------------------------
func clear_map() -> void:
	# Clear all tiles (board + any overlays you might have placed previously)
	for x in range(grid_width):
		for y in range(grid_height):
			set_cell(0, Vector2i(x, y), -1)
			# also clear the cursor layer if it's within range
			set_cell(cursor_layer, Vector2i(x, y), -1)
	_cursor_last = Vector2i(-9999, -9999)

	# Remove existing pieces
	for p in get_tree().get_nodes_in_group("Pieces"):
		if is_instance_valid(p):
			p.queue_free()

func _generate_map() -> void:
	_paint_chess_board()
	_spawn_chess_pieces()

	# visuals/camera
	modulate = Color(1, 1, 1, 1)
	self_modulate = Color(1, 1, 1, 1)
	visible = true
	_center_main_camera()

# ------------------------------------------------------------
# BOARD PAINTER
# ------------------------------------------------------------
func _paint_chess_board() -> void:
	# Enforce 8x8 for chess
	grid_width = 8
	grid_height = 8

	# Clear first
	for x in range(grid_width):
		for y in range(grid_height):
			set_cell(0, Vector2i(x, y), -1)

	# Checker pattern: (x+y) even = light, odd = dark
	for x in range(8):
		for y in range(8):
			var is_light := ((x + y) % 2) == 0
			var tid := light_square_tile_id
			if not is_light:
				tid = dark_square_tile_id
			set_cell(0, Vector2i(x, y), tid, Vector2i.ZERO)

# ------------------------------------------------------------
# PIECE SPAWNING
# ------------------------------------------------------------
func _spawn_chess_pieces() -> void:
	# Define starting ranks each time (in case grid values changed)
	var white_back_y := grid_height - 1  # 7
	var white_pawn_y := grid_height - 2  # 6
	var black_back_y := 0
	var black_pawn_y := 1

	# --- WHITE back rank ---
	for i in range(8):
		var s: PackedScene = null
		if i < white_piece_slots.size():
			s = white_piece_slots[i]
		_place_piece_with_type(s, Vector2i(i, white_back_y), "white", _type_from_back_file(i))

	# --- WHITE pawns ---
	for i in range(8):
		var s2: PackedScene = null
		var idx := i + 8
		if idx < white_piece_slots.size():
			s2 = white_piece_slots[idx]
		_place_piece_with_type(s2, Vector2i(i, white_pawn_y), "white", "pawn")

	# --- BLACK back rank ---
	for i in range(8):
		var sb: PackedScene = null
		if i < black_piece_slots.size():
			sb = black_piece_slots[i]
		_place_piece_with_type(sb, Vector2i(i, black_back_y), "black", _type_from_back_file(i))

	# --- BLACK pawns ---
	for i in range(8):
		var sb2: PackedScene = null
		var idx2 := i + 8
		if idx2 < black_piece_slots.size():
			sb2 = black_piece_slots[idx2]
		_place_piece_with_type(sb2, Vector2i(i, black_pawn_y), "black", "pawn")

func _place_piece_with_type(scene: PackedScene, tile: Vector2i, color: String, piece_type: String) -> void:
	if scene == null:
		return
	if is_tile_occupied(tile):
		return

	var node := scene.instantiate()

	# --- ALWAYS set tile_pos meta + optional property ---
	node.set_meta("tile_pos", tile)
	if node.has_method("set_tile_pos"):
		node.set_tile_pos(tile)

	# --- ALWAYS set color/type metadata (so TurnManager can read them) ---
	node.set_meta("piece_color", color)
	node.set_meta("piece_type", piece_type)
	# Optionally set script properties if your piece scenes expose them
	if node.has_method("set"):
		node.set("piece_color", color)
		node.set("piece_type", piece_type)

	# --- Orientation: white faces right; black faces left (default) ---
	if node is Node2D:
		var n2d := node as Node2D
		var sx := n2d.scale.x
		if color == "white":
			if sx > 0:
				n2d.scale.x = -sx
		else:
			if sx < 0:
				n2d.scale.x = -sx

	# --- Tint black pieces if desired ---
	if tint_black_pieces and node is CanvasItem and color == "black":
		(node as CanvasItem).modulate = black_piece_tint

	# --- Center on tile + pixel offset (matches TurnManager selection math) ---
	var local_center := map_to_local(tile)
	node.global_position = to_global(local_center + piece_pixel_offset)

	node.add_to_group("Pieces")
	add_child(node)

# ------------------------------------------------------------
# CAMERA
# ------------------------------------------------------------
func _center_main_camera() -> void:
	var cam: Camera2D = get_viewport().get_camera_2d()

	# Try some common fallbacks (no boolean `or` chaining)
	if cam == null:
		var node := get_node_or_null("../Camera2D")
		if node == null:
			node = get_node_or_null("../../Camera2D")
		if node == null:
			node = get_node_or_null("%Camera2D")
		cam = node as Camera2D

	if cam == null:
		return  # No camera found

	# Center on the middle tile
	var center_tile := Vector2i(grid_width >> 1, grid_height >> 1)
	var center_world := to_global(map_to_local(center_tile))
	cam.global_position = center_world
	cam.global_position.y -= 24

# ------------------------------------------------------------
# BOARD QUERIES (for interaction / movement later)
# ------------------------------------------------------------
func is_within_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < grid_width and tile.y >= 0 and tile.y < grid_height

func is_tile_occupied(tile: Vector2i) -> bool:
	return get_piece_at_tile(tile) != null

func get_piece_at_tile(tile: Vector2i) -> Node:
	for p in get_tree().get_nodes_in_group("Pieces"):
		if not is_instance_valid(p):
			continue
		var tp := _get_piece_tile_pos(p)
		if tp == tile:
			return p
	return null

func _get_piece_tile_pos(p: Node) -> Vector2i:
	var v = p.get("tile_pos")
	if typeof(v) == TYPE_VECTOR2I:
		return v
	if p.has_meta("tile_pos"):
		return p.get_meta("tile_pos")
	return Vector2i(-9999, -9999)

# ------------------------------------------------------------
# DEBUG (optional)
# ------------------------------------------------------------
func debug_print_piece_slot_mapping() -> void:
	print("WHITE SLOTS:")
	for i in range(16):
		var name := "(empty)"
		if i < white_piece_slots.size() and white_piece_slots[i] != null:
			name = white_piece_slots[i].resource_path
		print("  [", i, "] ", SLOT_LABELS[i], " -> ", name)

	print("BLACK SLOTS:")
	for i in range(16):
		var name_b := "(empty)"
		if i < black_piece_slots.size() and black_piece_slots[i] != null:
			name_b = black_piece_slots[i].resource_path
		print("  [", i, "] ", SLOT_LABELS[i], " -> ", name_b)

# ------------------------------------------------------------
# PIECE TYPE MAPPER
# ------------------------------------------------------------
func _type_from_back_file(i: int) -> String:
	if i == 0 or i == 7:
		return "rook"
	if i == 1 or i == 6:
		return "knight"
	if i == 2 or i == 5:
		return "bishop"
	if i == 3:
		return "queen"
	return "king"  # i == 4

# ------------------------------------------------------------
# CURSOR HELPERS
# ------------------------------------------------------------
func _clear_cursor() -> void:
	if _cursor_last.x >= 0:
		set_cell(cursor_layer, _cursor_last, -1)
		_cursor_last = Vector2i(-9999, -9999)

func _update_cursor_tile() -> void:
	# 1) Mouse in screen space
	var mouse_screen := get_viewport().get_mouse_position()

	# 2) Screen -> world(canvas) -> this TileMap's local
	var canvas_xform: Transform2D = get_viewport().get_canvas_transform()
	var world: Vector2 = canvas_xform.affine_inverse() * mouse_screen
	var local: Vector2 = get_global_transform().affine_inverse() * world

	# 3) Compensate your piece_pixel_offset (to match selection math)
	var off = get("piece_pixel_offset")
	if typeof(off) == TYPE_VECTOR2:
		local -= (off as Vector2)

	# 4) Snap to tile
	var t: Vector2i = local_to_map(local)
	var in_bounds := t.x >= 0 and t.x < grid_width and t.y >= 0 and t.y < grid_height

	# 5) Clear previous
	if _cursor_last.x >= 0:
		set_cell(cursor_layer, _cursor_last, -1)

	# 6) Paint if inside (or keep hidden if outside and hiding is enabled)
	if in_bounds:
		set_cell(cursor_layer, t, cursor_tile_id, Vector2i.ZERO)
		_cursor_last = t
	else:
		_cursor_last = Vector2i(-9999, -9999)
		if not hide_cursor_when_outside:
			# Optional: keep the last tile visible (do nothing)
			pass
