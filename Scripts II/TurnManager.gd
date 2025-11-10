# TurnManager.gd
extends Node

@export var board_map_path: NodePath          # assign your TileMap (with MapGen.gd) in the Inspector
@export var show_highlights: bool = true
@export var allow_select_any_color: bool = false   # DEBUG: let you pick black on white's turn, etc.

var board_map: TileMap
var board: Array                               # 8x8 of Nodes or null
var current_turn: String = "white"
var selected_piece: Node = null
var legal_for_selected: Array[Vector2i] = []
var move_history: Array = []

# --- simple highlight overlay ---
var highlight_nodes: Array = []  # Node2D dots

func _ready() -> void:
	if board_map_path == NodePath(""):
		push_error("TurnManager: board_map_path is not set.")
		return
	board_map = get_node(board_map_path) as TileMap
	await get_tree().process_frame
	rebuild_board()

# ---------------------------------------------------------------------
# BOARD BUILD / SYNC
# ---------------------------------------------------------------------
func rebuild_board() -> void:
	board = []
	for y in range(8):
		var row: Array = []
		for x in range(8):
			row.append(null)
		board.append(row)

	for p in get_tree().get_nodes_in_group("Pieces"):
		if not is_instance_valid(p):
			continue
		var t := _get_piece_tile_pos(p)
		if _in_bounds(t):
			board[t.y][t.x] = p

# ---------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if board_map == null:
		return

	rebuild_board()

	var tile := _mouse_to_tile(mb.position)
	if not _in_bounds(tile):
		_clear_selection()
		return

	# --- debug: show what lives on that tile ---
	var there = board[tile.y][tile.x]
	if show_highlights:
		if there == null:
			print("Clicked tile: ", tile, " -> (empty)")
		else:
			print("Clicked tile: ", tile, " -> ", _get_piece_color(there), " ", _get_piece_type(there))

	# selection flow
	var clicked_piece = there

	if selected_piece == null:
		if clicked_piece != null and _can_select(clicked_piece):
			selected_piece = clicked_piece
			legal_for_selected = legal_moves_for(selected_piece)
			_redraw_highlights()
		else:
			_clear_selection()
		return

	# clicking own piece switches selection (or any color if debug-allowed)
	if clicked_piece != null and _can_select(clicked_piece):
		selected_piece = clicked_piece
		legal_for_selected = legal_moves_for(selected_piece)
		_redraw_highlights()
		return

	# attempt move
	for m in legal_for_selected:
		if m == tile:
			_perform_move(selected_piece, tile)
			_clear_selection()
			return

	_clear_selection()

func _can_select(p: Node) -> bool:
	if allow_select_any_color:
		return true
	return _get_piece_color(p) == current_turn

func _clear_selection() -> void:
	selected_piece = null
	legal_for_selected = []
	_redraw_highlights()

# ---------------------------------------------------------------------
# COORDINATES & CONVERSIONS
# ---------------------------------------------------------------------
# screen (viewport) -> world (canvas) -> local (TileMap) -> tile (map)
func _mouse_to_tile(screen_pos: Vector2) -> Vector2i:
	# 1) Screen → World using the canvas transform
	var canvas_xform: Transform2D = board_map.get_viewport().get_canvas_transform()
	var world: Vector2 = canvas_xform.affine_inverse() * screen_pos
	# 2) World → TileMap local using the node's global transform (no canvas)
	var to_local: Transform2D = board_map.get_global_transform().affine_inverse()
	var local: Vector2 = to_local * world
	# 3) Local → Tile (map coords)
	return board_map.local_to_map(local)

func _tile_to_global_center(tile: Vector2i) -> Vector2:
	var local_center: Vector2 = board_map.map_to_local(tile)
	return board_map.to_global(local_center)

func _in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < 8 and t.y >= 0 and t.y < 8

# ---------------------------------------------------------------------
# PIECE META HELPERS
# ---------------------------------------------------------------------
func _get_piece_tile_pos(p: Node) -> Vector2i:
	var v = p.get("tile_pos")
	if typeof(v) == TYPE_VECTOR2I:
		return v
	if p.has_meta("tile_pos"):
		return p.get_meta("tile_pos")
	return Vector2i(-9999, -9999)

func _set_piece_tile_pos(p: Node, t: Vector2i) -> void:
	p.set_meta("tile_pos", t)
	if p.has_method("set_tile_pos"):
		p.set_tile_pos(t)

func _get_piece_color(p: Node) -> String:
	if p.has_method("get"):
		var c = p.get("piece_color")
		if typeof(c) == TYPE_STRING:
			return c
	if p.has_meta("piece_color"):
		var cm = p.get_meta("piece_color")
		if typeof(cm) == TYPE_STRING:
			return cm
	return ""

func _get_piece_type(p: Node) -> String:
	if p.has_method("get"):
		var t = p.get("piece_type")
		if typeof(t) == TYPE_STRING:
			return t.to_lower()
	if p.has_meta("piece_type"):
		var tm = p.get_meta("piece_type")
		if typeof(tm) == TYPE_STRING:
			return tm.to_lower()
	return ""

# ---------------------------------------------------------------------
# MOVE GENERATION (pseudo-legal)
# ---------------------------------------------------------------------
func pseudo_moves_for(p: Node) -> Array[Vector2i]:
	var t := _get_piece_type(p)
	var pos := _get_piece_tile_pos(p)
	var col := _get_piece_color(p)
	var out: Array[Vector2i] = []

	if t == "rook":
		_line(out, pos, Vector2i(1,0), col); _line(out, pos, Vector2i(-1,0), col)
		_line(out, pos, Vector2i(0,1), col); _line(out, pos, Vector2i(0,-1), col)
	elif t == "bishop":
		_line(out, pos, Vector2i(1,1), col); _line(out, pos, Vector2i(-1,1), col)
		_line(out, pos, Vector2i(1,-1), col); _line(out, pos, Vector2i(-1,-1), col)
	elif t == "queen":
		_line(out, pos, Vector2i(1,0), col); _line(out, pos, Vector2i(-1,0), col)
		_line(out, pos, Vector2i(0,1), col); _line(out, pos, Vector2i(0,-1), col)
		_line(out, pos, Vector2i(1,1), col); _line(out, pos, Vector2i(-1,1), col)
		_line(out, pos, Vector2i(1,-1), col); _line(out, pos, Vector2i(-1,-1), col)
	elif t == "knight":
		var js := [Vector2i(1,2), Vector2i(2,1), Vector2i(-1,2), Vector2i(-2,1),
				   Vector2i(1,-2), Vector2i(2,-1), Vector2i(-1,-2), Vector2i(-2,-1)]
		for j in js:
			var q = pos + j
			if _in_bounds(q):
				var occ = board[q.y][q.x]
				if occ == null or _get_piece_color(occ) != col:
					out.append(q)
	elif t == "king":
		for dx in [-1,0,1]:
			for dy in [-1,0,1]:
				if dx == 0 and dy == 0:
					continue
				var q := pos + Vector2i(dx, dy)
				if _in_bounds(q):
					var occ2 = board[q.y][q.x]
					if occ2 == null or _get_piece_color(occ2) != col:
						out.append(q)
	elif t == "pawn":
		var dir := 1
		if col == "white":
			dir = -1
		var one := pos + Vector2i(0, dir)
		if _in_bounds(one) and board[one.y][one.x] == null:
			out.append(one)
			var start_y := 1
			if col == "white":
				start_y = 6
			if pos.y == start_y:
				var two := pos + Vector2i(0, dir * 2)
				if _in_bounds(two) and board[two.y][two.x] == null:
					out.append(two)
		for dx in [-1, 1]:
			var c := pos + Vector2i(dx, dir)
			if _in_bounds(c):
				var occ3 = board[c.y][c.x]
				if occ3 != null and _get_piece_color(occ3) != col:
					out.append(c)
	return out

func _line(out: Array, start: Vector2i, d: Vector2i, my_color: String) -> void:
	var p := start + d
	while _in_bounds(p):
		var occ = board[p.y][p.x]
		if occ == null:
			out.append(p)
		else:
			if _get_piece_color(occ) != my_color:
				out.append(p) # capture square
			break
		p += d

# ---------------------------------------------------------------------
# ATTACKS & KING SAFETY
# ---------------------------------------------------------------------
func square_attacked_by(square: Vector2i, attacker_color: String) -> bool:
	var kjs := [
		Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
		Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)
	]
	for j in kjs:
		var p = square + j
		if _in_bounds(p):
			var n = board[p.y][p.x]
			if n != null and _get_piece_color(n) == attacker_color and _get_piece_type(n) == "knight":
				return true

	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var k := square + Vector2i(dx, dy)
			if _in_bounds(k):
				var n2 = board[k.y][k.x]
				if n2 != null and _get_piece_color(n2) == attacker_color and _get_piece_type(n2) == "king":
					return true

	var pawn_dir := 1
	if attacker_color == "white":
		pawn_dir = -1
	for dx2 in [-1, 1]:
		var pc := square + Vector2i(dx2, -pawn_dir)
		if _in_bounds(pc):
			var n3 = board[pc.y][pc.x]
			if n3 != null and _get_piece_color(n3) == attacker_color and _get_piece_type(n3) == "pawn":
				return true

	var orth := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in orth:
		var p2 = square + d
		while _in_bounds(p2):
			var occ = board[p2.y][p2.x]
			if occ != null:
				if _get_piece_color(occ) == attacker_color:
					var typ := _get_piece_type(occ)
					if typ == "rook" or typ == "queen":
						return true
				break
			p2 += d

	var diag := [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	for d2 in diag:
		var p3 = square + d2
		while _in_bounds(p3):
			var occ2 = board[p3.y][p3.x]
			if occ2 != null:
				if _get_piece_color(occ2) == attacker_color:
					var typ2 := _get_piece_type(occ2)
					if typ2 == "bishop" or typ2 == "queen":
						return true
				break
			p3 += d2

	return false

func _find_king(color: String) -> Vector2i:
	for y in range(8):
		for x in range(8):
			var n = board[y][x]
			if n != null and _get_piece_color(n) == color and _get_piece_type(n) == "king":
				return Vector2i(x,y)
	return Vector2i(-1,-1)

func legal_moves_for(p: Node) -> Array[Vector2i]:
	var pseudo := pseudo_moves_for(p)
	var legal: Array[Vector2i] = []
	var from := _get_piece_tile_pos(p)
	for to in pseudo:
		var captured = board[to.y][to.x]
		_apply_board_move(from, to)
		var kpos := _find_king(_get_piece_color(p))
		var in_check := square_attacked_by(kpos, _opponent(_get_piece_color(p)))
		_revert_board_move(from, to, captured)
		if not in_check:
			legal.append(to)
	return legal

# ---------------------------------------------------------------------
# APPLY / REVERT MOVES ON THE BOARD ARRAY
# ---------------------------------------------------------------------
func _apply_board_move(from: Vector2i, to: Vector2i) -> void:
	var piece = board[from.y][from.x]
	board[to.y][to.x] = piece
	board[from.y][from.x] = null

func _revert_board_move(from: Vector2i, to: Vector2i, captured: Node) -> void:
	var piece = board[to.y][to.x]
	board[from.y][from.x] = piece
	board[to.y][to.x] = captured

# ---------------------------------------------------------------------
# PERFORM MOVE (SCENE + STATE)
# ---------------------------------------------------------------------
func _perform_move(p: Node, to: Vector2i) -> void:
	var from := _get_piece_tile_pos(p)

	var captured = board[to.y][to.x]
	_apply_board_move(from, to)
	if captured != null and is_instance_valid(captured):
		captured.queue_free()

	_set_piece_tile_pos(p, to)

	var world_center := _tile_to_global_center(to)
	var pixel_offset := Vector2.ZERO
	var off = board_map.get("piece_pixel_offset")
	if typeof(off) == TYPE_VECTOR2:
		pixel_offset = off
	p.global_position = world_center + pixel_offset

	var typ := _get_piece_type(p)
	var col := _get_piece_color(p)
	var promote_row := 0
	if col == "white":
		promote_row = 0
	else:
		promote_row = 7
	if typ == "pawn" and to.y == promote_row:
		if p.has_method("set"):
			p.set("piece_type", "queen")
		else:
			p.set_meta("piece_type", "queen")

	move_history.append({"from": from, "to": to})
	current_turn = _opponent(current_turn)

	rebuild_board()
	var opp := current_turn
	if _no_legal_moves(opp):
		var king_pos := _find_king(opp)
		var is_check := square_attacked_by(king_pos, _opponent(opp))
		if is_check:
			print("Checkmate! ", _opponent(opp), " wins.")
		else:
			print("Stalemate.")

func _no_legal_moves(color: String) -> bool:
	for y in range(8):
		for x in range(8):
			var n = board[y][x]
			if n != null and _get_piece_color(n) == color:
				var ms := legal_moves_for(n)
				if ms.size() > 0:
					return false
	return true

func _opponent(color: String) -> String:
	if color == "white":
		return "black"
	return "white"

# ---------------------------------------------------------------------
# DEBUG HIGHLIGHTS
# ---------------------------------------------------------------------
func _redraw_highlights() -> void:
	# clear old dots
	for n in highlight_nodes:
		if is_instance_valid(n):
			n.queue_free()
	highlight_nodes.clear()

	if not show_highlights or selected_piece == null:
		return

	# small dots at legal targets
	for t in legal_for_selected:
		var dot := Node2D.new()
		dot.position = _tile_to_global_center(t)
		add_child(dot)
		highlight_nodes.append(dot)
		dot.draw.connect(func():
			dot.draw_circle(Vector2.ZERO, 6.0, Color(1, 1, 0, 0.6)))
