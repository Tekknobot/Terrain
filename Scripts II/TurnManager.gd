# TurnManager.gd
extends Node

@export var board_map_path: NodePath
@export var show_highlights: bool = true            # controls tile markers (on/off)
@export var allow_select_any_color: bool = false
@export var ai_plays_white: bool = false
@export var ai_plays_black: bool = true

# Move tile overlay settings
@export var move_layer: int = 1                     # overlay layer to paint moves on
@export var move_tile_id: int = 5                   # tile ID for "legal move" marker

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

	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if board_map == null:
		return

	rebuild_board()

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
			await _perform_move(selected_piece, tile)  # now async
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
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var q: Vector2i = pos + Vector2i(dx, dy)
				if _in_bounds(q):
					var occ2: Node = board[q.y][q.x] as Node
					if occ2 == null or _effective_color(occ2) != col:
						out.append(q)
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

	# pawns
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

func legal_moves_for(p: Node) -> Array[Vector2i]:
	var pseudo: Array[Vector2i] = pseudo_moves_for(p)
	var legal: Array[Vector2i] = []
	var from: Vector2i = _get_piece_tile_pos(p)
	var my_col: String = _effective_color(p)
	for to in pseudo:
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
# PERFORM MOVE (SCENE + STATE)  — now animated + plays "move"
# ---------------------------------------------------------------------
func _perform_move(p: Node, to: Vector2i) -> void:
	await _perform_move_impl(p, to)

func _perform_move_impl(p: Node, to: Vector2i) -> void:
	is_animating = true
	_clear_move_tiles()

	var from: Vector2i = _get_piece_tile_pos(p)
	var captured: Node = board[to.y][to.x] as Node

	# Update board state first (rules remain correct during animation)
	_apply_board_move(from, to)

	# Compute destination position (+ pixel offset, same as spawn)
	var world_end: Vector2 = _tile_to_global_center(to)
	var pixel_offset: Vector2 = Vector2.ZERO
	var off = board_map.get("piece_pixel_offset")
	if typeof(off) == TYPE_VECTOR2:
		pixel_offset = off as Vector2
	world_end += pixel_offset

	# Play "move" animation if available
	_try_play_move_anim(p)

	# Tween the piece to the destination
	var tween := get_tree().create_tween()
	_configure_tween_ease(tween)
	tween.tween_property(p, "global_position", world_end, max(0.0, move_duration))
	await tween.finished

	# Now lock in the tile_pos & remove captured piece (if still alive)
	_set_piece_tile_pos(p, to)
	if captured != null and is_instance_valid(captured):
		captured.queue_free()

	# Promotion (auto-queen)
	var typ: String = _effective_type(p)
	var col: String = _effective_color(p)
	var promote_row: int = (0 if col == "white" else 7)
	if typ == "pawn" and to.y == promote_row:
		p.set_meta("piece_type", "queen")
		if p.has_method("set"):
			p.set("piece_type", "queen")

	move_history.append({"from": from, "to": to, "captured": captured})
	current_turn = _opponent(current_turn)

	rebuild_board()
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
		# Some sprites need setting the current animation name first
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
			# default: sine in/out
			t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

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
# MOVE TILE OVERLAY (instead of highlight nodes)
# ---------------------------------------------------------------------
func _clear_move_tiles() -> void:
	# wipe overlay layer
	for y in range(8):
		for x in range(8):
			board_map.set_cell(move_layer, Vector2i(x, y), -1)

func _paint_move_tiles() -> void:
	_clear_move_tiles()
	if not show_highlights or selected_piece == null:
		return
	for t in legal_for_selected:
		board_map.set_cell(move_layer, t, move_tile_id, Vector2i.ZERO)
