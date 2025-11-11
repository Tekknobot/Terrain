extends Node2D
## Multi-projectile pawn attack (no highlights, no explosions)
## Right-click while selected -> fires up to N shots at nearest enemies, with optional stagger.
## Projectiles spawn from a fixed "muzzle" point; targets flash on hit (no explosion).

# --- volley / cadence ---
@export var shots_count: int = 6                    # fire up to N targets (fewer if not enough enemies)
@export var projectile_travel_time: float = 0.4     # flight time per projectile
@export var inter_shot_delay: float = 0.08          # delay between launching each shot
@export var ensure_all_spawn_before_first_hit: bool = false
# When true, we clamp the effective delay so all shots launch before the earliest possible hit.
# Effective delay = min(inter_shot_delay, (projectile_travel_time - 0.01) / max(1, shots-1))

# --- projectile visuals ---
@export var projectile_scene: PackedScene            # Node2D root (Sprite2D/AnimatedSprite2D/Particles2D)
@export var projectile_z_index: int = 9000

# --- muzzle spawn (fixed) ---
@export var muzzle_socket_path: NodePath             # optional Node2D child path (e.g. "Muzzle")
@export var muzzle_local_offset: Vector2 = Vector2(0, -6) # fallback local offset if no socket

# --- hit flash (no explosion) ---
@export var flash_times: int = 3
@export var flash_interval: float = 0.06
@export var flash_color: Color = Color(1, 1, 1, 0.18)  # quick white flicker

# --- board config ---
@export var board_size: int = 8

var tile_map: TileMap
var turn_manager: Node
var _is_firing: bool = false

func _ready() -> void:
	# Expect: TileMap in group "BoardMap", TurnManager in "TurnManager"
	tile_map = get_tree().get_first_node_in_group("BoardMap") as TileMap
	turn_manager = get_tree().get_first_node_in_group("TurnManager") as Node

func _input(event: InputEvent) -> void:
	if not _is_selected():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and not _is_firing:
			_fire_volley()

# ------------------------------------------------------------
# Selection check (reads TurnManager.selected_piece)
# ------------------------------------------------------------
func _is_selected() -> bool:
	if turn_manager == null: return false
	var sel = turn_manager.get("selected_piece")
	return sel == self

# ------------------------------------------------------------
# Volley: fire up to shots_count at nearest enemies (STAGGERED PARALLEL)
# ------------------------------------------------------------
func _fire_volley() -> void:
	var targets := _nearest_enemies(shots_count)
	if targets.is_empty():
		return
	_is_firing = true
	await _fire_targets_staggered_parallel(targets)
	_is_firing = false

func _fire_targets_staggered_parallel(targets: Array) -> void:
	var tweens: Array = []  # Array[Tween]
	# Compute effective delay if we must ensure all spawn before the first hit
	var eff_delay := inter_shot_delay
	if ensure_all_spawn_before_first_hit and targets.size() > 1:
		var max_delay := (projectile_travel_time - 0.01) / float(max(1, targets.size() - 1))
		eff_delay = min(inter_shot_delay, max_delay)

	# Launch each shot after a delay, but don't wait for completion here (parallel flights)
	for i in range(targets.size()):
		var tgt = targets[i]
		if tgt != null and is_instance_valid(tgt):
			var tw := _fire_one(tgt) # returns Tween
			if tw != null:
				tweens.append(tw)
		# Stagger next launch
		if i < targets.size() - 1 and eff_delay > 0.0:
			await get_tree().create_timer(eff_delay).timeout

	# Now wait for all shots (travel + flash) to finish before ending the volley
	for tw in tweens:
		await tw.finished

# ------------------------------------------------------------
# One shot: spawn from fixed muzzle -> tween to target -> flash target
# Returns the Tween so caller can await tw.finished (no coroutine/await inside).
# ------------------------------------------------------------
func _fire_one(target: Node) -> Tween:
	if projectile_scene == null or target == null or not (target is Node2D):
		return null

	var proj := projectile_scene.instantiate()
	var parent_for_fx: Node = (tile_map if tile_map != null else self.get_parent())
	parent_for_fx.add_child(proj)

	if not (proj is Node2D):
		proj.queue_free()
		return null

	var p2d := proj as Node2D
	p2d.top_level = true
	p2d.z_index = projectile_z_index

	# fixed spawn point (muzzle)
	var start_pos := _muzzle_global_position()
	var end_pos := (target as Node2D).global_position + _piece_offset()
	p2d.global_position = start_pos

	# orient towards target (optional)
	var dir := end_pos - start_pos
	if dir.length() > 0.001:
		p2d.rotation = dir.angle()

	# Build a single tween chain: fly -> flash target -> cleanup
	var tw := get_tree().create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# flight
	tw.tween_property(p2d, "global_position", end_pos, max(projectile_travel_time, 0.05))

	# flash (only if target is still valid and has visuals)
	if target is CanvasItem:
		var ci := target as CanvasItem
		var original := ci.modulate
		for _i in range(flash_times):
			tw.tween_property(ci, "modulate", flash_color, max(flash_interval, 0.01))
			tw.tween_property(ci, "modulate", original, max(flash_interval, 0.01))
		# ensure restoration
		tw.tween_property(ci, "modulate", original, 0.0)

	# cleanup projectile at the end
	tw.tween_callback(Callable(self, "_cleanup_projectile").bind(p2d))

	return tw

func _cleanup_projectile(p2d: Node2D) -> void:
	if is_instance_valid(p2d):
		p2d.queue_free()

func _muzzle_global_position() -> Vector2:
	# prefer explicit socket node if provided
	if muzzle_socket_path != NodePath(""):
		var n := get_node_or_null(muzzle_socket_path)
		if n is Node2D:
			return (n as Node2D).global_position
	# otherwise a consistent local offset relative to this pawn
	return to_global(muzzle_local_offset)

# ------------------------------------------------------------
# Target selection utilities
# ------------------------------------------------------------
func _my_tile() -> Vector2i:
	var t = get_meta("tile_pos")
	if typeof(t) == TYPE_VECTOR2I:
		return t
	return Vector2i(-9999, -9999)

func _nearest_enemies(limit: int) -> Array:
	var result: Array = []
	if turn_manager == null:
		return result
	var board = turn_manager.get("board")
	if typeof(board) != TYPE_ARRAY:
		return result

	var my_color := ""
	if has_meta("piece_color"):
		my_color = str(get_meta("piece_color"))

	var me := _my_tile()
	if me.x < 0:
		return result

	var candidates: Array = []  # {node, dist}
	for y in range(board_size):
		var row = board[y]
		if typeof(row) != TYPE_ARRAY: continue
		for x in range(board_size):
			var n: Node = row[x]
			if n == null: continue
			var their_color = n.get_meta("piece_color") if n.has_meta("piece_color") else ""
			if their_color == "" or their_color == my_color:
				continue
			var their_tile := _piece_tile(n)
			if their_tile.x < 0: continue
			var d = abs(their_tile.x - me.x) + abs(their_tile.y - me.y) # Manhattan distance
			candidates.append({ "node": n, "dist": d })

	# Godot 4: comparator must return bool (a < b)
	candidates.sort_custom(func(a, b):
		return (a["dist"] < b["dist"]) \
			or (a["dist"] == b["dist"] and int((a["node"] as Object).get_instance_id()) < int((b["node"] as Object).get_instance_id()))
	)

	for i in range(min(limit, candidates.size())):
		result.append(candidates[i]["node"])
	return result

func _piece_tile(p: Node) -> Vector2i:
	if p == null: return Vector2i(-9999, -9999)
	var v = p.get("tile_pos")
	if typeof(v) == TYPE_VECTOR2I:
		return v
	if p.has_meta("tile_pos"):
		return p.get_meta("tile_pos")
	return Vector2i(-9999, -9999)

func _piece_offset() -> Vector2:
	if tile_map == null:
		return Vector2.ZERO
	var o = tile_map.get("piece_pixel_offset")
	if typeof(o) == TYPE_VECTOR2:
		return (o as Vector2)
	return Vector2.ZERO
