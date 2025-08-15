extends Area2D

# --- CONFIG / ADAPTERS --------------------------------------------------------

@export_node_path("TileMap") var tilemap_path: NodePath
# If left empty, it will try get_tree().get_current_scene().get_node("TileMap")

# If your TileMap uses different method names, set them here (or leave blank to auto-detect):
@export var m_is_within_bounds := ""      # e.g. "is_within_bounds", "in_bounds"
@export var m_is_walkable := ""           # e.g. "_is_tile_walkable", "is_tile_walkable", "is_walkable"
@export var m_is_occupied := ""           # e.g. "is_tile_occupied", "is_occupied", "has_unit_at"
@export var m_has_explosion := ""         # e.g. "has_explosion_at", "explosion_at", "is_exploding"
@export var m_get_path := ""              # e.g. "get_weighted_path", "get_path", "find_path"
@export var m_update_astar := ""          # e.g. "update_astar_grid", "rebuild_graph"

# Optional crowding helpers (if your TileMap supplies them)
@export var m_crowd_claim := "crowd_claim"
@export var m_crowd_release := "crowd_release"

# Optional signals (if your TileMap emits them)
@export var s_tile_occupied := "tile_occupied"   # (tile: Vector2i, by: Node)
@export var s_tile_exploded := "tile_exploded"   # (tile: Vector2i)

@export var kill_on_enemy_collision: bool = true
var _dying: bool = false

# --- BEHAVIOR TUNING ----------------------------------------------------------

@export var panic_steps: int = 0
@export var panic_speed: float = 4.0
@export var despawn_at_edge: bool = true

@export var react_to_mech_or_occupant := true
@export var react_to_explosions := true
@export var auto_evacuate_steps := 6
@export var auto_evacuate_speed := 5.0

@export var auto_fade_after_scatter: bool = false
@export var fade_delay_range: Vector2 = Vector2(0.25, 0.9)
@export var fade_duration_range: Vector2 = Vector2(0.7, 1.4)

const Y_OFFSET := -8.0

@export var m_get_occupant := ""          # e.g. "get_occupant", "actor_at", "unit_at"; returns Node or null
@export var occupancy_method_counts_self := true  # set to true if your is_occupied counts the current NPC as occupied

@export var eviction_speed_multiplier: float = 10.0   # run faster when evicted
@export var post_evade_cooldown: float = 0.25        # brief ignore window to avoid re-trigger spam

@export var attack_enabled: bool = true
@export var attack_damage: int = 25
@export var attack_animation: String = "attack"
@export var target_players: bool = false  # false = shoot AI/enemy units (non-player). true = shoot player units.

var _attack_loop_running: bool = false
@export var attack_interval: float = 0.35  # seconds to wait between swings if no animation is playing

var CARDINAL_DIRS := [
	Vector2i( 1,  0), Vector2i(-1,  0),
	Vector2i( 0,  1), Vector2i( 0, -1)
]

# --- STATE --------------------------------------------------------------------

var tile_pos: Vector2i
var _tilemap: TileMap
var _sprite: AnimatedSprite2D

var _crowd_offset: Vector2 = Vector2.ZERO
var _claimed_tile: Vector2i = Vector2i(-999, -999)
var _is_evacuating: bool = false
var _cooldown_until: float = 0.0

# --- READY --------------------------------------------------------------------

func _ready() -> void:
	# Resolve tilemap
	if tilemap_path != NodePath():
		_tilemap = get_node(tilemap_path) as TileMap
	else:
		var root := get_tree().get_current_scene()
		if root and root.has_node("TileMap"):
			_tilemap = root.get_node("TileMap") as TileMap

	_sprite = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
	z_as_relative = false

	# Auto-detect common method names if user left adapters blank
	_autodetect_tilemap_methods()

	if _tilemap:
		# Connect optional signals if present
		if s_tile_occupied != "" and _tilemap.has_signal(s_tile_occupied):
			_tilemap.connect(s_tile_occupied, Callable(self, "_on_tile_occupied"))
		if s_tile_exploded != "" and _tilemap.has_signal(s_tile_exploded):
			_tilemap.connect(s_tile_exploded, Callable(self, "_on_tile_exploded"))

		# Compute starting tile from current world position
		tile_pos = _tilemap.local_to_map(_tilemap.to_local(global_position))

		# Claim crowd slot if available
		if _has_method(_tilemap, m_crowd_claim):
			_crowd_offset = _tilemap.call(m_crowd_claim, tile_pos)
			_claimed_tile = tile_pos

		# Snap to center + offset
		global_position = _tilemap.to_global(_tilemap.map_to_local(tile_pos)) + Vector2(0, Y_OFFSET) + _crowd_offset

	# --- collision kill wiring ---
	if kill_on_enemy_collision:
		if not is_connected("body_entered", Callable(self, "_on_body_entered")):
			connect("body_entered", Callable(self, "_on_body_entered"))
		if not is_connected("area_entered", Callable(self, "_on_area_entered")):
			connect("area_entered", Callable(self, "_on_area_entered"))

	# Make sure this node is in the Civilians group (optional if you add via editor)
	if not is_in_group("Civilians"):
		add_to_group("Civilians")

	# ✅ Connect once to the autoloaded TurnManager
	if TurnManager and not TurnManager.is_connected("round_ended", Callable(self, "_on_round_ended")):
		TurnManager.connect("round_ended", Callable(self, "_on_round_ended"), CONNECT_DEFERRED)

	_update_z()

func _on_round_ended(ended_team: int) -> void:
	# Only civilians do this
	if not is_in_group("Civilians"):
		return
	# Act when the ENEMY just finished (i.e., once per full round)
	if ended_team == TurnManager.Team.ENEMY:
		await perform_round_action()

# Replace your current perform_round_action() with this:
func perform_round_action() -> void:
	if _dying or _is_evacuating or not attack_enabled:
		return
	await attack_rapid_taps_4way(5, 5)  # or (25,1) if you want the full burst

func attack_rapid_taps_8way(burst_count: int = 25, per_hit_damage: int = 1) -> void:
	if _attack_loop_running or _dying or _is_evacuating or not attack_enabled:
		return
	_attack_loop_running = true

	var taps_done := 0
	while taps_done < burst_count:
		# find current adjacent targets (8-way)
		var targets := _collect_enemies_8way()
		if targets.is_empty():
			break  # nothing to hit, stop early

		# face first target
		var first = targets[0]
		if _sprite and first is Node2D:
			_sprite.flip_h = (first.global_position.x > global_position.x)

		# play attack once per tap
		var played_sprites := _play_anim_on_all_sprites(self, attack_animation)
		var played := played_sprites.size() > 0

		# apply tiny damage to everything adjacent this tap
		for e in targets:
			if is_instance_valid(e):
				_apply_damage(e, per_hit_damage)
				if e.has_method("flash_white"): e.flash_white()
				if e.has_method("shake"): e.shake()

		# wait until the swing finishes (or a tiny fallback delay)
		if played:
			# If you want to wait roughly one swing worth of time,
			# waiting on the main sprite is usually fine:
			if _sprite and _sprite.is_playing():
				await _sprite.animation_finished
			_restore_default_on_sprites(played_sprites)

		else:
			await get_tree().create_timer(max(0.05, attack_interval * 0.4)).timeout

		taps_done += 1

		# bail if interrupted mid-burst
		if _dying or _is_evacuating:
			break

		# let frees/deaths settle
		await get_tree().process_frame

	_attack_loop_running = false

func _attack_adjacent_enemies_8way() -> void:
	if not _tilemap:
		return

	var dirs := [
		Vector2i( 1,  0), Vector2i(-1,  0), Vector2i( 0,  1), Vector2i( 0, -1),
		Vector2i( 1,  1), Vector2i( 1, -1), Vector2i(-1,  1), Vector2i(-1, -1)
	]

	var targets: Array = []
	var first_target: Node = null
	for d in dirs:
		var n = tile_pos + d
		if not _tilemap.is_within_bounds(n): continue
		var enemy = _get_enemy_at(n)        # uses your adapter/meta checks
		if enemy:
			if first_target == null:
				first_target = enemy
			targets.append(enemy)

	if targets.is_empty():
		return

	# Face the first target and play attack anim once
	if _sprite and first_target and first_target is Node2D:
		_sprite.flip_h = (first_target.global_position.x > global_position.x)

	var played := false
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(attack_animation):
		_sprite.play(attack_animation)
		played = true

	for e in targets:
		if is_instance_valid(e):
			_apply_damage(e, 1)  # or attack_damage / 1 etc.
			_play_target_hurt(e)              # ← NEW: make the target animate too
			if e.has_method("flash_white"): e.flash_white()
			if e.has_method("shake"): e.shake()

	if played:
		await _sprite.animation_finished
		if _sprite.sprite_frames.has_animation("default"):
			_sprite.play("default")

func _get_enemy_at(t: Vector2i) -> Node:
	var tilemap: TileMap = get_tree().get_current_scene().get_node("TileMap")

	# Preferred: use TileMap API if it exists
	if tilemap and tilemap.has_method("get_unit_at_tile"):
		var who = tilemap.get_unit_at_tile(t)
		return who if _is_valid_enemy(who) else null

	# Fallback: scan groups
	for u in get_tree().get_nodes_in_group("Units"):
		if is_instance_valid(u) and u.tile_pos == t and _is_valid_enemy(u):
			return u
	for s in get_tree().get_nodes_in_group("Enemies"):
		if not target_players and is_instance_valid(s) and s.has_method("tile_pos") and s.tile_pos == t:
			return s
	return null

func _apply_damage(target: Object, amount: int) -> void:
	# Try common damage method names
	for n in ["take_damage", "apply_damage", "damage", "receive_damage", "hit"]:
		if target.has_method(n):
			target.call(n, amount)
			return
	# Last-ditch: a generic signal
	if target.has_signal("damaged"):
		target.emit_signal("damaged", amount)

func _process(_dt: float) -> void:
	# Polling fallback so it still reacts without signals
	if not _tilemap or _is_evacuating:
		return
	if _is_tile_threatened(tile_pos):
		_evict_from(tile_pos)

	if _dying: return
	if not _tilemap or _is_evacuating:
		return
	if _is_tile_threatened(tile_pos):
		_evict_from(tile_pos)
		
# --- PUBLIC API (kept compatible) --------------------------------------------

func place_on_tile(t: Vector2i) -> void:
	tile_pos = t
	# claim a visual crowd slot if available
	if _tilemap and _has_method(_tilemap, m_crowd_claim):
		_crowd_offset = _tilemap.call(m_crowd_claim, t)
		_claimed_tile = t
	else:
		_crowd_offset = Vector2.ZERO

	var wp: Vector2 = _tilemap.to_global(_tilemap.map_to_local(t)) + Vector2(0, Y_OFFSET) + _crowd_offset
	global_position = wp
	_update_z()

func start_scatter(threat_tile: Vector2i) -> void:
	visible = true
	if _sprite:
		_sprite.play("move")

	var target: Vector2i = _pick_flee_target(threat_tile, panic_steps)
	await _walk_path_to(target, panic_speed)

	if _sprite:
		_sprite.play("default")

	# If we left the grid → release slot and despawn immediately
	if despawn_at_edge and not _is_within_bounds(tile_pos):
		if _claimed_tile.x != -999 and _tilemap and _has_method(_tilemap, m_crowd_release):
			_tilemap.call(m_crowd_release, _claimed_tile)
		queue_free()
		return

	# Otherwise: brief delay, fade out, then free
	if auto_fade_after_scatter:
		await _fade_and_free()

# --- REACTIVE PATHS -----------------------------------------------------------

func _on_tile_occupied(t: Vector2i, by: Node) -> void:
	if not react_to_mech_or_occupant:
		return
	# ignore if it's us
	if by == self:
		return
	if t == tile_pos:
		_evict_from(t)

func _on_tile_exploded(t: Vector2i) -> void:
	if not react_to_explosions:
		return
	if t == tile_pos:
		_evict_from(t)

func _evict_from(threat_tile: Vector2i) -> void:
	if _dying: return
	if _is_evacuating:
		return
	# brief debounce so we don't immediately re-trigger after landing
	if Engine.get_physics_frames() < _cooldown_until:
		return

	_is_evacuating = true
	visible = true
	if _sprite: _sprite.play("move")

	var dest = _pick_nearest_safe_step(threat_tile)
	# If nowhere to go, bail cleanly
	if dest == tile_pos:
		if _sprite: _sprite.play("default")
		_is_evacuating = false
		return

	var speed := (auto_evacuate_speed if auto_evacuate_speed > 0.0 else panic_speed) * eviction_speed_multiplier
	await _move_one(dest, speed)

	if _sprite: _sprite.play("default")
	_is_evacuating = false
	# tiny cooldown (~N physics frames) before we can be evicted again
	_cooldown_until = Engine.get_physics_frames() + int(ceil(post_evade_cooldown / Engine.get_physics_ticks_per_second()))

func _pick_nearest_safe_step(threat_tile: Vector2i) -> Vector2i:
	# choose among 4-neighbors: must be in-bounds, walkable, not occupied
	var best := tile_pos
	var best_score := -INF
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var n = tile_pos + d
		if _is_within_bounds(n) and _is_walkable(n) and not _is_occupied(n):
			# prefer increasing distance away from the threat and small y for nicer layering
			var score = abs(n.x - threat_tile.x) + abs(n.y - threat_tile.y)
			# slight bias to keep NPCs from oscillating vertically too much (optional)
			score += 0.01 * float(-n.y)
			if score > best_score:
				best_score = score
				best = n
	return best

func _scatter_from_threat(threat_tile: Vector2i, steps: int, spd: float) -> void:
	visible = true
	if _sprite:
		_sprite.play("move")
	var target: Vector2i = _pick_flee_target(threat_tile, steps)
	await _walk_path_to(target, spd)
	if _sprite:
		_sprite.play("default")

	if despawn_at_edge and not _is_within_bounds(tile_pos):
		if _claimed_tile.x != -999 and _tilemap and _has_method(_tilemap, m_crowd_release):
			_tilemap.call(m_crowd_release, _claimed_tile)
		queue_free()
		return
	if auto_fade_after_scatter:
		await _fade_and_free()

# --- EFFECTS / LIFECYCLE ------------------------------------------------------

func _fade_and_free() -> void:
	var wait := randf_range(fade_delay_range.x, fade_delay_range.y)
	await get_tree().create_timer(wait).timeout

	var dur := randf_range(fade_duration_range.x, fade_duration_range.y)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _sprite:
		tw.tween_property(_sprite, "modulate:a", 0.0, dur)
	else:
		tw.tween_property(self, "modulate:a", 0.0, dur)

	await tw.finished

	if _claimed_tile.x != -999 and _tilemap and _has_method(_tilemap, m_crowd_release):
		_tilemap.call(m_crowd_release, _claimed_tile)

	queue_free()

# --- PATHFIND / MOVEMENT ------------------------------------------------------

func _pick_flee_target(threat_tile: Vector2i, steps: int) -> Vector2i:
	var frontier := [tile_pos]
	var visited := { tile_pos: null }
	for _i in range(steps):
		var nxt := []
		for t in frontier:
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var n = t + d
				if visited.has(n):
					continue
				if not _is_within_bounds(n):
					visited[n] = t
					nxt.append(n)
					continue
				if _is_walkable(n) and not _is_occupied(n):
					visited[n] = t
					nxt.append(n)
		frontier = nxt
	var best := tile_pos
	var best_cost := -INF
	for k in visited.keys():
		var c = abs(k.x - threat_tile.x) + abs(k.y - threat_tile.y)
		if c > best_cost:
			best_cost = c
			best = k
	return best

func _walk_path_to(dest: Vector2i, speed: float) -> void:
	if _dying: return
	var path: Array = []
	if _is_within_bounds(tile_pos) and _is_within_bounds(dest):
		path = _get_path(tile_pos, dest)
	else:
		path = [dest]
	for step in path:
		await _move_one(step, speed)
	_update_astar_if_any()
	await get_tree().process_frame

func _move_one(dest: Vector2i, speed: float) -> void:
	if _dying: return
	# If we’re leaving this tile, release its crowd slot
	if dest != tile_pos and _claimed_tile == tile_pos and _tilemap and _has_method(_tilemap, m_crowd_release):
		_tilemap.call(m_crowd_release, _claimed_tile)
		_claimed_tile = Vector2i(-999, -999)

	# claim a slot on the destination tile (so several can land there)
	var dest_offset: Vector2 = Vector2.ZERO
	if _tilemap and _has_method(_tilemap, m_crowd_claim):
		dest_offset = _tilemap.call(m_crowd_claim, dest)

	var target: Vector2 = _tilemap.to_global(_tilemap.map_to_local(dest)) + Vector2(0, Y_OFFSET) + dest_offset

	# Flip based on movement direction (default facing left)
	if _sprite:
		var dx := dest.x - tile_pos.x
		if dx != 0:
			_sprite.flip_h = dx > 0  # going right => flip_h = true (face right), going left => false (face left)

	while global_position.distance_to(target) > 1.0:
		var dt := get_process_delta_time()
		global_position = global_position.move_toward(target, speed * dt)
		_update_z()
		await Engine.get_main_loop().process_frame

	global_position = target
	tile_pos = dest
	_crowd_offset = dest_offset
	_claimed_tile = dest
	_update_z()

func _update_z() -> void:
	z_as_relative = false
	z_index = int(global_position.y)

# --- THREAT CHECKS ------------------------------------------------------------

# Replace the old version with this adjacency-only check for occupants.
# Same-tile EXPLOSIONS still count as a threat; same-tile OCCUPANTS do NOT.
func _is_tile_threatened(t: Vector2i) -> bool:
	if not _tilemap:
		return false

	var occ_adj := false
	if react_to_mech_or_occupant:
		# Only check the 4 neighbors, not the tile we're standing on.
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n = t + d
			if _is_occupied_by_other(n):
				occ_adj = true
				break

	var boom := false
	if react_to_explosions:
		# Keep same-tile explosion as a threat (makes sense to flee).
		boom = _has_explosion(t)

	return occ_adj or boom


# --- ADAPTER AUTO-DETECTOR ----------------------------------------------------

func _autodetect_tilemap_methods() -> void:
	if not _tilemap:
		return

	m_is_within_bounds = _pick_method(m_is_within_bounds, [
		"is_within_bounds", "in_bounds", "is_in_bounds", "_is_within_bounds"
	])

	m_is_walkable = _pick_method(m_is_walkable, [
		"_is_tile_walkable", "is_tile_walkable", "is_walkable", "walkable"
	])

	m_is_occupied = _pick_method(m_is_occupied, [
		"is_tile_occupied", "is_occupied", "has_unit_at", "has_actor_at", "has_blocker_at"
	])

	m_has_explosion = _pick_method(m_has_explosion, [
		"has_explosion_at", "explosion_at", "is_exploding", "has_blast_at"
	])

	m_get_path = _pick_method(m_get_path, [
		"get_weighted_path", "get_path", "find_path", "astar_path", "get_astar_path"
	])

	m_update_astar = _pick_method(m_update_astar, [
		"update_astar_grid", "rebuild_graph", "refresh_nav", "rebuild_astar"
	])

	# Crowd helpers are optional; if absent, blank them so calls are skipped.
	if m_crowd_claim != "" and not _tilemap.has_method(m_crowd_claim):
		m_crowd_claim = ""
	if m_crowd_release != "" and not _tilemap.has_method(m_crowd_release):
		m_crowd_release = ""

# Helper: pick the first method name that exists on the TileMap, unless already set.
func _pick_method(into: String, candidates: Array[String]) -> String:
	if into != "":
		return into
	if not _tilemap:
		return ""
	for name in candidates:
		if _tilemap.has_method(name):
			return name
	return ""

# --- ADAPTER HELPERS ----------------------------------------------------------

func _is_within_bounds(t: Vector2i) -> bool:
	if not _tilemap:
		return false
	# explicit override
	if m_is_within_bounds != "" and _has_method(_tilemap, m_is_within_bounds):
		return bool(_tilemap.call(m_is_within_bounds, t))
	# As a last resort, use TileMap bounds (layer 0)
	var used := _tilemap.get_used_rect()
	return Rect2i(used.position, used.size).has_point(t)

func _is_walkable(t: Vector2i) -> bool:
	if not _tilemap:
		return false
	if m_is_walkable != "" and _has_method(_tilemap, m_is_walkable):
		return bool(_tilemap.call(m_is_walkable, t))
	# default: a tile inside bounds with any navigation allowed
	return _is_within_bounds(t)

func _is_occupied(t: Vector2i) -> bool:
	if not _tilemap:
		return false
	if m_is_occupied != "" and _has_method(_tilemap, m_is_occupied):
		return bool(_tilemap.call(m_is_occupied, t))
	# default: assume not occupied
	return false

func _has_explosion(t: Vector2i) -> bool:
	if not _tilemap:
		return false
	if m_has_explosion != "" and _has_method(_tilemap, m_has_explosion):
		return bool(_tilemap.call(m_has_explosion, t))
	# default: assume no explosion
	return false

func _get_path(from_tile: Vector2i, to_tile: Vector2i) -> Array:
	if not _tilemap:
		return [to_tile]
	if m_get_path != "" and _has_method(_tilemap, m_get_path):
		return _tilemap.call(m_get_path, from_tile, to_tile)
	# fallback: straight-line stepping (Manhattan)
	var path: Array = []
	var cur := from_tile
	while cur != to_tile:
		var dx := signi(to_tile.x - cur.x)
		var dy := signi(to_tile.y - cur.y)
		if abs(to_tile.x - cur.x) >= abs(to_tile.y - cur.y):
			cur = Vector2i(cur.x + dx, cur.y)
		else:
			cur = Vector2i(cur.x, cur.y + dy)
		path.append(cur)
	return path

func _update_astar_if_any() -> void:
	if not _tilemap:
		return
	if m_update_astar != "" and _has_method(_tilemap, m_update_astar):
		_tilemap.call(m_update_astar)

func _has_method(obj: Object, name: String) -> bool:
	return name != "" and obj.has_method(name)

func signi(v: int) -> int:
	return 1 if v > 0 else (-1 if v < 0 else 0)

func _is_occupied_by_other(t: Vector2i) -> bool:
	if not _tilemap:
		return false

	# Preferred: ask the map who is there and compare to self.
	if m_get_occupant != "" and _has_method(_tilemap, m_get_occupant):
		var who = _tilemap.call(m_get_occupant, t)
		return who != null and who != self

	# Fallback: use boolean occupancy but avoid treating *self* as a threat.
	if m_is_occupied != "" and _has_method(_tilemap, m_is_occupied):
		var occ := bool(_tilemap.call(m_is_occupied, t))
		if not occ:
			return false
		# If the occupancy method counts this NPC too, try not to loop:
		if occupancy_method_counts_self:
			# Without a "get_occupant" API, we can't distinguish; treat as non-threat to avoid infinite evacuations.
			# Signals (tile_occupied) will still trigger when a mech steps onto us.
			return false
		return true

	return false

func _on_body_entered(body: Node) -> void:
	_maybe_die_from_node(body)

func _on_area_entered(area: Area2D) -> void:
	_maybe_die_from_node(area)

func _maybe_die_from_node(n: Node) -> void:
	if _dying or not kill_on_enemy_collision:
		return

	# Find the nearest ancestor that belongs to "Units"
	var unit := n
	while unit and not unit.is_in_group("Units"):
		unit = unit.get_parent()

	# Enemy = in "Units" AND meta is_player is explicitly false
	var is_enemy := false
	if unit and unit.is_in_group("Units"):
		if unit.has_meta("is_player") and unit.get_meta("is_player") == false:
			is_enemy = true

	if not is_enemy:
		return

	_die_now()

func _die_now() -> void:
	# Prevent any further processing or eviction
	_dying = true
	set_process(false)
	set_physics_process(false)

	# Disable collisions completely
	_disable_all_collisions()

	# Release crowd slot if you grabbed one
	if _claimed_tile.x != -999 and _tilemap and _has_method(_tilemap, m_crowd_release):
		_tilemap.call(m_crowd_release, _claimed_tile)
		_claimed_tile = Vector2i(-999, -999)

	# Play SFX if we have one (assume AudioStreamPlayer named "SFX" exists)
	if has_node("DeathAudio"):
		var sfx = $DeathAudio
		if sfx and sfx is AudioStreamPlayer2D:
			sfx.play()

	# Try death animation first
	if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation("death"):
		_sprite.play("death")
		await _sprite.animation_finished
		queue_free()
		return

	# Fallback: quick fade+shrink
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(self, "scale", self.scale * 0.6, 0.25)
	await tw.finished
	queue_free()


func _disable_all_collisions() -> void:
	for c in get_children():
		if c is CollisionShape2D:
			c.disabled = true
		if c is CollisionPolygon2D:
			c.disabled = true
	# Also clear collision layers/masks so nothing else hits us
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	# Area2D specific
	monitoring = false
	monitorable = false

func _is_valid_enemy(node: Node) -> bool:
	# Units set meta("is_player", true/false). We compare that to our target.
	if node == null: 
		return false
	# Prefer Units group + metadata
	if node.is_in_group("Units") and node.has_meta("is_player"):
		var is_player_unit := bool(node.get_meta("is_player"))
		return (is_player_unit == target_players)
	# Also treat anything in an "Enemies" group as enemy when we’re set to target AI
	if not target_players and node.is_in_group("Enemies"):
		return true
	return false

func _collect_enemies_8way() -> Array:
	if not _tilemap: 
		return []
	var dirs := [
		Vector2i( 1,  0), Vector2i(-1,  0), Vector2i( 0,  1), Vector2i( 0, -1),
		Vector2i( 1,  1), Vector2i( 1, -1), Vector2i(-1,  1), Vector2i(-1, -1)
	]
	var out: Array = []
	for d in dirs:
		var n = tile_pos + d
		if _tilemap.is_within_bounds(n):
			var e := _get_enemy_at(n)
			if e: out.append(e)
	return out

func attack_until_clear_8way() -> void:
	if _attack_loop_running or _dying or _is_evacuating or not attack_enabled:
		return
	_attack_loop_running = true

	while true:
		# re-scan each cycle
		var targets := _collect_enemies_8way()
		if targets.is_empty():
			break

		# face first target
		var first = targets[0]
		if _sprite and first is Node2D:
			_sprite.flip_h = (first.global_position.x > global_position.x)

		# play attack once
		var played := false
		if _sprite and _sprite.sprite_frames and _sprite.sprite_frames.has_animation(attack_animation):
			_sprite.play(attack_animation)
			played = true

		# apply damage this cycle
		for e in targets:
			if is_instance_valid(e):
				_apply_damage(e, attack_damage)
				if e.has_method("flash_white"): e.flash_white()
				if e.has_method("shake"): e.shake()

		# wait for the anim (or a small interval) before the next scan
		if played:
			await _sprite.animation_finished
			if _sprite.sprite_frames.has_animation("default"):
				_sprite.play("default")
		else:
			await get_tree().create_timer(attack_interval).timeout

		# optional: break if something interrupted us
		if _dying or _is_evacuating:
			break

		# yield a frame so deaths/freeing settle
		await get_tree().process_frame

	# done
	_attack_loop_running = false

# Plays `anim` on **all** AnimatedSprite2D under `root` (recursive).
# Returns the list of sprites that actually started that anim so we can restore them later.
func _play_anim_on_all_sprites(root: Node, anim: String) -> Array:
	var started: Array = []
	if root is AnimatedSprite2D:
		var sp: AnimatedSprite2D = root
		if sp.sprite_frames and sp.sprite_frames.has_animation(anim):
			sp.play(anim)
			started.append(sp)

	for c in root.get_children():
		started.append_array(_play_anim_on_all_sprites(c, anim))
	return started

# Returns true if we set *any* sprite back to "default".
func _restore_default_on_sprites(sprites: Array) -> bool:
	var any := false
	for s in sprites:
		if is_instance_valid(s) and s is AnimatedSprite2D:
			var sp: AnimatedSprite2D = s
			if sp.sprite_frames and sp.sprite_frames.has_animation("default"):
				sp.play("default")
				any = true
	return any

# Try common “hurt” anim names on a target. Falls back to nothing if none exist.
func _play_target_hurt(target: Node) -> void:
	var names := ["hit", "hurt", "damaged", "flinch", "impact"]
	# search target and all descendants for any AnimatedSprite2D that has one of these
	var to_play: Array = []
	for c in target.get_children():
		to_play.append_array(_collect_sprites_recursive(c))
	to_play.append_array(_collect_sprites_recursive(target))

	for sp in to_play:
		for n in names:
			if sp.sprite_frames and sp.sprite_frames.has_animation(n):
				sp.play(n)
				break

func _collect_sprites_recursive(node: Node) -> Array:
	var out: Array = []
	if node is AnimatedSprite2D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_sprites_recursive(c))
	return out

func _collect_enemies_4way() -> Array:
	if not _tilemap:
		return []
	var out: Array = []
	for d in CARDINAL_DIRS:
		var n = tile_pos + d
		if _tilemap.is_within_bounds(n):
			var e := _get_enemy_at(n)
			if e:
				out.append(e)
	return out

func attack_rapid_taps_4way(burst_count: int = 25, per_hit_damage: int = 1) -> void:
	if _attack_loop_running or _dying or _is_evacuating or not attack_enabled:
		return
	_attack_loop_running = true

	var taps_done := 0
	while taps_done < burst_count:
		var targets := _collect_enemies_4way()
		if targets.is_empty():
			break

		var first = targets[0]
		if _sprite and first is Node2D:
			_sprite.flip_h = (first.global_position.x > global_position.x)

		var played_sprites := _play_anim_on_all_sprites(self, attack_animation)
		var played := played_sprites.size() > 0

		for e in targets:
			if is_instance_valid(e):
				_apply_damage(e, per_hit_damage)
				_play_target_hurt(e)
				if e.has_method("flash_white"): e.flash_white()
				if e.has_method("shake"): e.shake()

		if played:
			if _sprite and _sprite.is_playing():
				await _sprite.animation_finished
			_restore_default_on_sprites(played_sprites)
		else:
			await get_tree().create_timer(max(0.05, attack_interval * 0.4)).timeout

		# Play SFX if we have one (assume AudioStreamPlayer named "AttackAudio" exists)
		if has_node("AttackAudio"):
			var sfx = $AttackAudio
			if sfx and sfx is AudioStreamPlayer2D:
				sfx.volume_db = -12  # roughly half volume
				sfx.play()
				
		taps_done += 1
		if _dying or _is_evacuating:
			break
		await get_tree().process_frame

	_attack_loop_running = false

func _attack_adjacent_enemies_4way() -> void:
	if not _tilemap:
		return
	var targets := _collect_enemies_4way()
	if targets.is_empty():
		return

	var first = targets[0]
	if _sprite and first is Node2D:
		_sprite.flip_h = (first.global_position.x > global_position.x)

	var played_sprites := _play_anim_on_all_sprites(self, attack_animation)
	var played := played_sprites.size() > 0

	for e in targets:
		if is_instance_valid(e):
			_apply_damage(e, 1)
			_play_target_hurt(e)
			if e.has_method("flash_white"): e.flash_white()
			if e.has_method("shake"): e.shake()

	if played:
		if _sprite and _sprite.is_playing():
			await _sprite.animation_finished
		_restore_default_on_sprites(played_sprites)

func attack_until_clear_4way() -> void:
	if _attack_loop_running or _dying or _is_evacuating or not attack_enabled:
		return
	_attack_loop_running = true

	while true:
		var targets := _collect_enemies_4way()
		if targets.is_empty():
			break

		var first = targets[0]
		if _sprite and first is Node2D:
			_sprite.flip_h = (first.global_position.x > global_position.x)

		var played_sprites := _play_anim_on_all_sprites(self, attack_animation)
		var played := played_sprites.size() > 0

		for e in targets:
			if is_instance_valid(e):
				_apply_damage(e, attack_damage)
				_play_target_hurt(e)
				if e.has_method("flash_white"): e.flash_white()
				if e.has_method("shake"): e.shake()

		if played:
			if _sprite and _sprite.is_playing():
				await _sprite.animation_finished
			_restore_default_on_sprites(played_sprites)
		else:
			await get_tree().create_timer(attack_interval).timeout

		if _dying or _is_evacuating:
			break
		await get_tree().process_frame

	_attack_loop_running = false
