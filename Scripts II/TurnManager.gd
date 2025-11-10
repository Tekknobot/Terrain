# TurnManager.gd
extends Node

@export var board_map_path: NodePath
@export var show_highlights: bool = true            # controls move tile markers (on/off)
@export var allow_select_any_color: bool = false
@export var ai_plays_white: bool = false
@export var ai_plays_black: bool = true

# Move tile overlay settings
@export var move_layer: int = 1                     # overlay layer to paint legal moves on
@export var move_tile_id: int = 5                   # tile ID for "legal move" marker

# Check / Checkmate overlay settings
@export var check_layer: int = 2                    # overlay layer to paint check / mate indicators
@export var check_tile_id_check: int = 4            # white tile under king when in check
@export var check_tile_id_mate: int = 3             # red tile under king when checkmated

# Threat overlay (pieces that are currently capturable by the opponent)
@export var threat_layer: int = 3                   # layer to paint "under attack" indicators
@export var threat_tile_id: int = 3                 # typically a red tile; reuse your atlas as needed

# Motion / animation
@export var move_duration: float = 0.35             # seconds
@export var move_ease: String = "sine_in_out"       # "sine_in_out","cubic_in_out","quad_in_out", etc.

var board_map: TileMap
var board: Array                                    # 8x8 array (Variant for simplicity)
var current_turn: String = "white"
var selected_piece: Node = null
var legal_for_selected: Array[Vector2i] = []
var move_history: Array = []

var is_animating: bool = false

func _ready() -> void:
	if board_map_path == NodePath(""):
		push_error("TurnManager: board_map_path is not set.")
		return
	board_map = get_node(board_map_path) as TileMap
	await get_tree().process_frame
	rebuild_board()
	_update_all_indicators()
	_maybe_ai_move() # if AI starts as white

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
		# skip soft-captured pieces (parked in Graveyard)
		if p.get_meta("captured", false):
			continue
		var t: Vector2i = _get_piece_tile_pos(p)
		if _in_bounds(t):
			board[t.y][t.x] = p

# ---------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	# Block during animation or when AI controls this side
	if is_animating or _ai_controls(current_turn):
		return

	# Optional: simple undo keybind (Ctrl/Cmd + Z)
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_Z and (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
			undo_last_move()
			return

	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if board_map == null:
		return

	rebuild_board()
	_update_all_indicators()

	var tile: Vector2i = _mouse_to_tile(mb.position)
	if not _in_bounds(tile):
		_clear_selection()
		return

	var there: Node = board[tile.y][tile.x] as Node
	if show_highlights:
		if there == null:
			print("Clicked tile: ", tile, " -> (empty)")
		else:
			print("Clicked tile: ", tile, " -> ", _effective_color(there), " ", _effective_type(there))

	var clicked_piece: Node = there

	if selected_piece == null:
		if clicked_piece != null and _can_select(clicked_piece):
			selected_piece = clicked_piece
			legal_for_selected = legal_moves_for(selected_piece)
			_paint_move_tiles()
		else:
			_clear_selection()
		return

	# Switch selection to another selectable piece
	if clicked_piece != null and _can_select(clicked_piece):
		selected_piece = clicked_piece
		legal_for_selected = legal_moves_for(selected_piece)
		_paint_move_tiles()
		return

	# Attempt move
	for m in legal_for_selected:
		if m == tile:
			await _perform_move(selected_piece, tile)  # animated
			_clear_selection()
			await get_tree().process_frame
			_maybe_ai_move()
			return

	_clear_selection()

func _can_select(p: Node) -> bool:
	if allow_select_any_color:
		return true
	return _effective_color(p) == current_turn

func _clear_selection() -> void:
	selected_piece = null
	legal_for_selected = []
	_clear_move_tiles()
	# keep indicators; they reflect game state

# ---------------------------------------------------------------------
# COORDINATES & CONVERSIONS (offset-aware)
# ---------------------------------------------------------------------
func _mouse_to_tile(screen_pos: Vector2) -> Vector2i:
	# 1) Screen -> World (canvas)
	var canvas_xform: Transform2D = board_map.get_viewport().get_canvas_transform()
	var world: Vector2 = canvas_xform.affine_inverse() * screen_pos
	# 2) World -> TileMap local
	var to_local: Transform2D = board_map.get_global_transform().affine_inverse()
	var local: Vector2 = to_local * world
	# 3) Compensate the same offset used when placing sprites
	var offset: Vector2 = Vector2.ZERO
	var off = board_map.get("piece_pixel_offset")
	if typeof(off) == TYPE_VECTOR2:
		offset = off as Vector2
	local -= offset
	# 4) Local -> tile
	return board_map.local_to_map(local)

func _tile_to_global_center(tile: Vector2i) -> Vector2:
	var local_center: Vector2 = board_map.map_to_local(tile)
	return board_map.to_global(local_center)

func _in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < 8 and t.y >= 0 and t.y < 8

# ---------------------------------------------------------------------
# PIECE META HELPERS (+ robust fallbacks)
# ---------------------------------------------------------------------
func _get_piece_tile_pos(p: Node) -> Vector2i:
	var v = p.get("tile_pos")
	if typeof(v) == TYPE_VECTOR2I:
		return v as Vector2i
	if p.has_meta("tile_pos"):
		return p.get_meta("tile_pos") as Vector2i
	return Vector2i(-9999, -9999)

func _set_piece_tile_pos(p: Node, t: Vector2i) -> void:
	p.set_meta("tile_pos", t)
	if p.has_method("set_tile_pos"):
		p.set_tile_pos(t)

func _get_piece_color(p: Node) -> String:
	if p.has_method("get"):
		var c = p.get("piece_color")
		if typeof(c) == TYPE_STRING:
			return c as String
	if p.has_meta("piece_color"):
		var cm = p.get_meta("piece_color")
		if typeof(cm) == TYPE_STRING:
			return cm as String
	return ""

func _get_piece_type(p: Node) -> String:
	if p.has_method("get"):
		var t = p.get("piece_type")
		if typeof(t) == TYPE_STRING:
			return (t as String).to_lower()
	if p.has_meta("piece_type"):
		var tm = p.get_meta("piece_type")
		if typeof(tm) == TYPE_STRING:
			return (tm as String).to_lower()
	return ""

# Fallbacks if metadata is missing
func _effective_color(p: Node) -> String:
	var c: String = _get_piece_color(p)
	if c != "":
		return c
	var pos: Vector2i = _get_piece_tile_pos(p)
	if not _in_bounds(pos):
		return ""
	if pos.y >= 6:
		return "white"
	if pos.y <= 1:
		return "black"
	return ""

func _effective_type(p: Node) -> String:
	var t: String = _get_piece_type(p)
	if t != "":
		return t
	var pos: Vector2i = _get_piece_tile_pos(p)
	if not _in_bounds(pos):
		return ""
	if pos.y == 6 or pos.y == 1:
		return "pawn"
	return ""  # back rank unknown unless set by MapGen

# Track whether a piece has moved at least once (for castling + undo)
func _get_has_moved(p: Node) -> bool:
	if p.has_method("get"):
		var v = p.get("has_moved")
		if typeof(v) == TYPE_BOOL: return v
	if p.has_meta("has_moved"):
		return bool(p.get_meta("has_moved"))
	return false

func _set_has_moved(p: Node, v: bool) -> void:
	p.set_meta("has_moved", v)
	if p.has_method("set"):
		p.set("has_moved", v)

# ---------------------------------------------------------------------
# MOVE GENERATION (pseudo-legal -> legal)
# ---------------------------------------------------------------------
func pseudo_moves_for(p: Node) -> Array[Vector2i]:
	var t: String = _effective_type(p)
	var pos: Vector2i = _get_piece_tile_pos(p)
	var col: String = _effective_color(p)
	var out: Array[Vector2i] = []

	if t == "rook":
		_line(out, pos, Vector2i(1, 0), col); _line(out, pos, Vector2i(-1, 0), col)
		_line(out, pos, Vector2i(0, 1), col); _line(out, pos, Vector2i(0, -1), col)
	elif t == "bishop":
		_line(out, pos, Vector2i(1, 1), col); _line(out, pos, Vector2i(-1, 1), col)
		_line(out, pos, Vector2i(1, -1), col); _line(out, pos, Vector2i(-1, -1), col)
	elif t == "queen":
		_line(out, pos, Vector2i(1, 0), col); _line(out, pos, Vector2i(-1, 0), col)
		_line(out, pos, Vector2i(0, 1), col); _line(out, pos, Vector2i(0, -1), col)
		_line(out, pos, Vector2i(1, 1), col); _line(out, pos, Vector2i(-1, 1), col)
		_line(out, pos, Vector2i(1, -1), col); _line(out, pos, Vector2i(-1, -1), col)
	elif t == "knight":
		var js: Array[Vector2i] = [
			Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
			Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)
		]
		for j in js:
			var q: Vector2i = pos + j
			if _in_bounds(q):
				var occ: Node = board[q.y][q.x] as Node
				if occ == null or _effective_color(occ) != col:
					out.append(q)
	elif t == "king":
		# normal king steps
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0: continue
				var q: Vector2i = pos + Vector2i(dx, dy)
				if _in_bounds(q):
					var occ2: Node = board[q.y][q.x] as Node
					if occ2 == null or _effective_color(occ2) != col:
						out.append(q)

		# castling candidates (added as pseudo; filtered to legal later)
		# x: 0..7, home rank: y=7 for white, y=0 for black (white pawns at y=6)
		var home_y: int = 0
		if col == "white":
			home_y = 7

		var king_home := Vector2i(4, home_y)
		if pos == king_home and not _get_has_moved(p):
			# kingside: rook at x=7, squares 5 and 6 empty
			var rook_k := board[home_y][7] as Node
			if rook_k != null and _effective_type(rook_k) == "rook" and _effective_color(rook_k) == col and not _get_has_moved(rook_k):
				if board[home_y][5] == null and board[home_y][6] == null:
					out.append(Vector2i(6, home_y))
			# queenside: rook at x=0, squares 1..3 empty
			var rook_q := board[home_y][0] as Node
			if rook_q != null and _effective_type(rook_q) == "rook" and _effective_color(rook_q) == col and not _get_has_moved(rook_q):
				if board[home_y][1] == null and board[home_y][2] == null and board[home_y][3] == null:
					out.append(Vector2i(2, home_y))

	elif t == "pawn":
		var dir: int = 1
		if col == "white":
			dir = -1
		var one: Vector2i = pos + Vector2i(0, dir)
		if _in_bounds(one) and board[one.y][one.x] == null:
			out.append(one)
			var start_y: int = 1
			if col == "white":
				start_y = 6
			if pos.y == start_y:
				var two: Vector2i = pos + Vector2i(0, dir * 2)
				if _in_bounds(two) and board[two.y][two.x] == null:
					out.append(two)
		for dx in [-1, 1]:
			var c: Vector2i = pos + Vector2i(dx, dir)
			if _in_bounds(c):
				var occ3: Node = board[c.y][c.x] as Node
				if occ3 != null and _effective_color(occ3) != col:
					out.append(c)
	return out

func _line(out: Array[Vector2i], start: Vector2i, d: Vector2i, my_color: String) -> void:
	var p: Vector2i = start + d
	while _in_bounds(p):
		var occ: Node = board[p.y][p.x] as Node
		if occ == null:
			out.append(p)
		else:
			if _effective_color(occ) != my_color:
				out.append(p) # capture square
			break
		p += d

func square_attacked_by(square: Vector2i, attacker_color: String) -> bool:
	# knights
	var kjs: Array[Vector2i] = [
		Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
		Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)
	]
	for j in kjs:
		var p: Vector2i = square + j
		if _in_bounds(p):
			var n: Node = board[p.y][p.x] as Node
			if n != null and _effective_color(n) == attacker_color and _effective_type(n) == "knight":
				return true

	# king
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var k: Vector2i = square + Vector2i(dx, dy)
			if _in_bounds(k):
				var n2: Node = board[k.y][k.x] as Node
				if n2 != null and _effective_color(n2) == attacker_color and _effective_type(n2) == "king":
					return true

	# pawns (they attack forward-diagonally)
	var pawn_dir: int = 1
	if attacker_color == "white":
		pawn_dir = -1
	for dx2 in [-1, 1]:
		var pc: Vector2i = square + Vector2i(dx2, -pawn_dir)
		if _in_bounds(pc):
			var n3: Node = board[pc.y][pc.x] as Node
			if n3 != null and _effective_color(n3) == attacker_color and _effective_type(n3) == "pawn":
				return true

	# rooks/queens (orthogonal)
	var orth: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in orth:
		var p2: Vector2i = square + d
		while _in_bounds(p2):
			var occ: Node = board[p2.y][p2.x] as Node
			if occ != null:
				if _effective_color(occ) == attacker_color:
					var typ: String = _effective_type(occ)
					if typ == "rook" or typ == "queen":
						return true
				break
			p2 += d

	# bishops/queens (diagonals)
	var diag: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	for d2 in diag:
		var p3: Vector2i = square + d2
		while _in_bounds(p3):
			var occ2: Node = board[p3.y][p3.x] as Node
			if occ2 != null:
				if _effective_color(occ2) == attacker_color:
					var typ2: String = _effective_type(occ2)
					if typ2 == "bishop" or typ2 == "queen":
						return true
				break
			p3 += d2

	return false

func _find_king(color: String) -> Vector2i:
	for y in range(8):
		for x in range(8):
			var n: Node = board[y][x] as Node
			if n != null and _effective_color(n) == color and _effective_type(n) == "king":
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _is_castle_move(piece: Node, from: Vector2i, to: Vector2i) -> bool:
	return _effective_type(piece) == "king" and abs(to.x - from.x) == 2 and from.y == to.y

func _castle_path_safe(color: String, from: Vector2i, to: Vector2i) -> bool:
	var dir: int = -1
	if to.x > from.x:
		dir = 1

	# squares the king occupies or passes through (from, from+dir, to)
	var squares := [from, from + Vector2i(dir, 0), to]
	for s in squares:
		if square_attacked_by(s, _opponent(color)):
			return false
	return true

func legal_moves_for(p: Node) -> Array[Vector2i]:
	var pseudo: Array[Vector2i] = pseudo_moves_for(p)
	var legal: Array[Vector2i] = []
	var from: Vector2i = _get_piece_tile_pos(p)
	var my_col: String = _effective_color(p)
	for to in pseudo:
		# Special: castling path safety pre-check
		var is_castle := _is_castle_move(p, from, to)
		if is_castle:
			# king cannot castle out of/through/into check
			if square_attacked_by(from, _opponent(my_col)) or not _castle_path_safe(my_col, from, to):
				continue

		var captured: Node = board[to.y][to.x] as Node
		_apply_board_move(from, to)
		var kpos: Vector2i = _find_king(my_col)
		var in_check: bool = square_attacked_by(kpos, _opponent(my_col))
		_revert_board_move(from, to, captured)
		if not in_check:
			legal.append(to)
	return legal

# ---------------------------------------------------------------------
# APPLY / REVERT MOVES ON THE BOARD ARRAY
# ---------------------------------------------------------------------
func _apply_board_move(from: Vector2i, to: Vector2i) -> void:
	var piece: Node = board[from.y][from.x] as Node
	board[to.y][to.x] = piece
	board[from.y][from.x] = null

func _revert_board_move(from: Vector2i, to: Vector2i, captured: Node) -> void:
	var piece: Node = board[to.y][to.x] as Node
	board[from.y][from.x] = piece
	board[to.y][to.x] = captured

# ---------------------------------------------------------------------
# PERFORM MOVE (SCENE + STATE) — animated + plays "move"
# ---------------------------------------------------------------------
func _perform_move(p: Node, to: Vector2i) -> void:
	await _perform_move_impl(p, to)

func _perform_move_impl(p: Node, to: Vector2i) -> void:
	is_animating = true
	_clear_move_tiles()

	var from: Vector2i = _get_piece_tile_pos(p)
	var captured: Node = board[to.y][to.x] as Node

	# For history/undo
	var did_promote: bool = false
	var promoted_from: String = ""
	var was_castle: bool = false
	var rook_moved: Node = null
	var rook_from := Vector2i(-1, -1)
	var rook_to := Vector2i(-1, -1)
	var piece_had_moved := _get_has_moved(p)

	# Update board state first (rules remain correct during animation)
	_apply_board_move(from, to)

	# Detect castling and prepare rook move in board state (keeps logic consistent during tween)
	if _is_castle_move(p, from, to):
		was_castle = true
		var home_y := from.y
		if to.x == 6:
			# kingside: rook 7->5
			rook_from = Vector2i(7, home_y)
			rook_to = Vector2i(5, home_y)
		else:
			# queenside: rook 0->3
			rook_from = Vector2i(0, home_y)
			rook_to = Vector2i(3, home_y)
		rook_moved = board[rook_from.y][rook_from.x] as Node
		if rook_moved != null:
			_apply_board_move(rook_from, rook_to)

	# Compute destination position (+ pixel offset, same as spawn)
	var world_end: Vector2 = _tile_to_global_center(to)
	var pixel_offset: Vector2 = Vector2.ZERO
	var off = board_map.get("piece_pixel_offset")
	if typeof(off) == TYPE_VECTOR2:
		pixel_offset = off as Vector2
	world_end += pixel_offset

	# Play "move" animation if available
	_try_play_move_anim(p)
	if was_castle and rook_moved != null:
		_try_play_move_anim(rook_moved)

	# Tween the piece (and rook if castling)
	var tween := get_tree().create_tween()
	_configure_tween_ease(tween)
	tween.tween_property(p, "global_position", world_end, max(0.0, move_duration))

	if was_castle and rook_moved != null:
		var r_end := _tile_to_global_center(rook_to)
		var roff: Vector2 = Vector2.ZERO
		var ro = board_map.get("piece_pixel_offset")
		if typeof(ro) == TYPE_VECTOR2:
			roff = ro as Vector2
		r_end += roff
		tween.tween_property(rook_moved, "global_position", r_end, max(0.0, move_duration))

	await tween.finished

	# Now lock in the tile_pos & remove captured piece (if still alive)
	_set_piece_tile_pos(p, to)
	if was_castle and rook_moved != null:
		_set_piece_tile_pos(rook_moved, rook_to)
	if captured != null and is_instance_valid(captured):
		_capture_piece(captured)

	# Promotion (auto-queen)
	var typ: String = _effective_type(p)
	var col: String = _effective_color(p)
	var promote_row: int = (0 if col == "white" else 7)
	if typ == "pawn" and to.y == promote_row:
		did_promote = true
		promoted_from = "pawn"
		p.set_meta("piece_type", "queen")
		if p.has_method("set"):
			p.set("piece_type", "queen")

	# Update movement flags (for castling rules)
	_set_has_moved(p, true)
	if was_castle and rook_moved != null:
		_set_has_moved(rook_moved, true)

	# Rich history for undo
	move_history.append({
		"piece": p,
		"from": from,
		"to": to,
		"captured": captured,
		"was_castle": was_castle,
		"rook": rook_moved,
		"rook_from": rook_from,
		"rook_to": rook_to,
		"did_promote": did_promote,
		"promoted_from": promoted_from,
		"piece_had_moved": piece_had_moved
	})

	current_turn = _opponent(current_turn)

	rebuild_board()
	_update_all_indicators()
	is_animating = false

# Try to play a "move" animation on common node types
func _try_play_move_anim(p: Node) -> void:
	# AnimationPlayer child named "AnimationPlayer"
	var ap := p.get_node_or_null("AnimationPlayer")
	if ap is AnimationPlayer:
		var apc := ap as AnimationPlayer
		if apc.has_animation("move"):
			apc.play("move")
			return
	# AnimatedSprite2D or anything with play("move")
	if p.has_method("play"):
		if p.has_method("set_animation"):
			p.call("set_animation", "move")
		p.call("play", "move")

# Configure tween easing from string
func _configure_tween_ease(t: Tween) -> void:
	match move_ease.to_lower():
		"cubic_in_out":
			t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		"quad_in_out":
			t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		"expo_in_out":
			t.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		"back_in_out":
			t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
		_:
			t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------------------------------------------------------------------
# CHECK / THREAT INDICATORS
# ---------------------------------------------------------------------
func _update_all_indicators() -> void:
	_update_check_indicators()
	_update_threat_indicators()

func _update_check_indicators() -> void:
	_clear_check_tiles()

	# White status
	var w_king: Vector2i = _find_king("white")
	if _in_bounds(w_king):
		var w_in_check: bool = square_attacked_by(w_king, "black")
		if w_in_check:
			var w_mate: bool = _no_legal_moves("white")
			var w_tile_id := check_tile_id_check
			if w_mate:
				w_tile_id = check_tile_id_mate
			board_map.set_cell(check_layer, w_king, w_tile_id, Vector2i.ZERO)

	# Black status
	var b_king: Vector2i = _find_king("black")
	if _in_bounds(b_king):
		var b_in_check: bool = square_attacked_by(b_king, "white")
		if b_in_check:
			var b_mate: bool = _no_legal_moves("black")
			var b_tile_id := check_tile_id_check
			if b_mate:
				b_tile_id = check_tile_id_mate
			board_map.set_cell(check_layer, b_king, b_tile_id, Vector2i.ZERO)

func _update_threat_indicators() -> void:
	# Show red tile under any piece that is currently capturable by its opponent.
	# (This is independent from "in check".)
	_clear_threat_tiles()
	for y in range(8):
		for x in range(8):
			var n: Node = board[y][x] as Node
			if n == null:
				continue
			var col := _effective_color(n)
			if col == "":
				continue
			var here := Vector2i(x, y)
			if square_attacked_by(here, _opponent(col)):
				board_map.set_cell(threat_layer, here, threat_tile_id, Vector2i.ZERO)

func _no_legal_moves(color: String) -> bool:
	for y in range(8):
		for x in range(8):
			var n: Node = board[y][x] as Node
			if n != null and _effective_color(n) == color:
				var ms: Array[Vector2i] = legal_moves_for(n)
				if ms.size() > 0:
					return false
	return true

# ---------------------------------------------------------------------
# AI (simple greedy: prefer capture of highest value; else random legal)
# ---------------------------------------------------------------------
func _maybe_ai_move() -> void:
	# Only act if AI controls the side to play
	if not _ai_controls(current_turn):
		return
	# Wait if an animation is still going
	while is_animating:
		await get_tree().process_frame

	await get_tree().process_frame
	rebuild_board()
	_update_all_indicators()

	# Gather all legal moves for current_turn
	var moves: Array = [] # Array[Dictionary]
	for y in range(8):
		for x in range(8):
			var n: Node = board[y][x] as Node
			if n == null:
				continue
			if _effective_color(n) != current_turn:
				continue
			var from: Vector2i = Vector2i(x, y)
			var ms: Array[Vector2i] = legal_moves_for(n)
			for to in ms:
				var cap: Node = board[to.y][to.x] as Node
				var score: int = 0
				if cap != null:
					score = _piece_value(_effective_type(cap))
				moves.append({"piece": n, "from": from, "to": to, "captured": cap, "score": score})

	if moves.is_empty():
		return

	var best_score: int = -99999
	for m in moves:
		var s: int = m["score"]
		if s > best_score:
			best_score = s

	var best: Array = []
	for m in moves:
		if m["score"] == best_score:
			best.append(m)

	var idx: int = randi() % best.size()
	var choice: Dictionary = best[idx]

	# Perform the AI move (animated)
	var piece: Node = choice["piece"]
	var to: Vector2i = choice["to"]
	await _perform_move_impl(piece, to)

	# If both sides are AI, schedule the opponent's move next frame
	if _ai_controls(current_turn):
		await get_tree().process_frame
		_maybe_ai_move()

func _ai_controls(color: String) -> bool:
	if color == "white":
		return ai_plays_white
	return ai_plays_black

func _piece_value(t: String) -> int:
	match t:
		"king":
			return 10000
		"queen":
			return 900
		"rook":
			return 500
		"bishop":
			return 330
		"knight":
			return 320
		"pawn":
			return 100
		_:
			return 0

# ---------------------------------------------------------------------
# UTILS
# ---------------------------------------------------------------------
func _opponent(color: String) -> String:
	if color == "white":
		return "black"
	return "white"

# ---------------------------------------------------------------------
# OVERLAYS
# ---------------------------------------------------------------------
func _clear_move_tiles() -> void:
	for y in range(8):
		for x in range(8):
			board_map.set_cell(move_layer, Vector2i(x, y), -1)

func _paint_move_tiles() -> void:
	_clear_move_tiles()
	if not show_highlights or selected_piece == null:
		return
	for t in legal_for_selected:
		board_map.set_cell(move_layer, t, move_tile_id, Vector2i.ZERO)

func _clear_check_tiles() -> void:
	for y in range(8):
		for x in range(8):
			board_map.set_cell(check_layer, Vector2i(x, y), -1)

func _clear_threat_tiles() -> void:
	for y in range(8):
		for x in range(8):
			board_map.set_cell(threat_layer, Vector2i(x, y), -1)

# ---------------------------------------------------------------------
# CAPTURE / RESTORE (soft-capture to enable undo)
# ---------------------------------------------------------------------
func _capture_piece(p: Node) -> void:
	if p == null or not is_instance_valid(p): return
	p.visible = false
	p.remove_from_group("Pieces") # avoid being considered on rebuild_board
	# park it under us or a dedicated Graveyard
	var gy: Node = get_node_or_null("Graveyard")
	if gy == null: gy = self
	p.reparent(gy)
	# mark captured for clarity
	p.set_meta("captured", true)

func _restore_captured_piece(p: Node) -> void:
	if p == null: return
	# restore membership
	if not p.is_in_group("Pieces"):
		p.add_to_group("Pieces")
	p.visible = true
	p.set_meta("captured", false)
	# parents don't matter as long as it's in group; up to you to reparent back if desired

# ---------------------------------------------------------------------
# UNDO — fully recovers pieces, promotions, castling, and has_moved
# ---------------------------------------------------------------------
func undo_last_move() -> void:
	if move_history.is_empty(): return

	is_animating = true
	_clear_move_tiles()

	var last = move_history.pop_back()
	var p: Node = last.get("piece", null)
	var from: Vector2i = last.get("from", Vector2i(-1,-1))
	var to: Vector2i = last.get("to", Vector2i(-1,-1))
	var captured: Node = last.get("captured", null)
	var was_castle: bool = last.get("was_castle", false)
	var rook_moved: Node = last.get("rook", null)
	var rook_from: Vector2i = last.get("rook_from", Vector2i(-1,-1))
	var rook_to: Vector2i = last.get("rook_to", Vector2i(-1,-1))
	var did_promote: bool = last.get("did_promote", false)
	var promoted_from: String = last.get("promoted_from", "")
	var piece_had_moved: bool = last.get("piece_had_moved", false)

	# Revert board positions (king back; captured back onto 'to')
	_revert_board_move(from, to, captured)

	# If castling, slide rook back in board array
	if was_castle and rook_moved != null:
		_revert_board_move(rook_from, rook_to, null)

	# Visually snap nodes back
	var start_pos := _tile_to_global_center(from)
	var off: Vector2 = Vector2.ZERO
	var of = board_map.get("piece_pixel_offset")
	if typeof(of) == TYPE_VECTOR2: off = of as Vector2
	p.global_position = start_pos + off
	_set_piece_tile_pos(p, from)

	if was_castle and rook_moved != null:
		var rpos := _tile_to_global_center(rook_from)
		rook_moved.global_position = rpos + off
		_set_piece_tile_pos(rook_moved, rook_from)
		_set_has_moved(rook_moved, false) # rook hadn’t moved before the castle

	# Restore captured piece (if any)
	if captured != null:
		_restore_captured_piece(captured)
		_set_piece_tile_pos(captured, to)

	# Revert promotion
	if did_promote and promoted_from != "":
		p.set_meta("piece_type", promoted_from)
		if p.has_method("set"):
			p.set("piece_type", promoted_from)

	# Restore has_moved for moving piece
	_set_has_moved(p, piece_had_moved)

	# Switch turn back
	current_turn = _opponent(current_turn)

	rebuild_board()
	_update_all_indicators()

	is_animating = false
