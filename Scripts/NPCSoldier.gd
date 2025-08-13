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

	_update_z()

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

	# Consider “Enemy” group OR a Unit that is not player.
	var is_enemy := n.is_in_group("Units")
	if not is_enemy:
		# If your enemies are in "Units" with is_player == false, try to resolve the unit root
		var unit := n
		if not unit.has_method("has_adjacent_enemy") and unit.get_parent():
			unit = unit.get_parent()  # climb one level if the collider is a child
		if unit and unit.is_in_group("Units") and unit.has_method("is_player") == false:
			# If is_player is a property, try to read it safely
			if unit.has_variable("is_player") and unit.is_player == false:
				is_enemy = true

	if not is_enemy:
		return

	# Kill this civilian
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
