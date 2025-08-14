# res://Scripts/Structure.gd
extends Node2D
signal destroyed(tile_pos: Vector2i)

@export var tile_pos: Vector2i = Vector2i.ZERO
@export var y_offset: int = -8
@export var auto_add_to_group: bool = true

# ---- Soldier spawn settings ----
@export var soldier_scene: PackedScene                 # assign NPC scene (with SoldierNPC.gd)
@export var merc_scene: PackedScene  
@export var soldiers_to_spawn: int = 8                 # how many to pop out
@export var spawn_on_frame: int = 1                    # frame index inside "demolished" anim to spawn
@export var spawn_adjacent_first: bool = true          # prefer adjacent open tiles

var _tilemap: TileMap
var _demolished := false
var _spawned := false

var structure_id

@export var soldier_exit_speed: float = 12.0  # px/sec walking speed while exiting the structure
@export var soldier_exit_jitter: float = 8.0  # small random pixel jitter so exits don’t look identical
@export var mix_alternate: bool = true  # Soldier, Merc, Soldier, Merc...

func _ready() -> void:
	_tilemap = get_tree().get_current_scene().get_node_or_null("TileMap")
	if auto_add_to_group:
		add_to_group("Structures")
	_update_world_from_tile()
	_update_z()

func _process(_dt: float) -> void:
	_update_z()

	# One-shot: when demolished and not yet spawned, decide if we can spawn now.
	if _demolished and not _spawned:
		var sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null

		var can_spawn_now := true

		# If we have a playing "demolished" anim, wait until it reaches the frame.
		if sprite and sprite.sprite_frames and "demolished" in sprite.sprite_frames.get_animation_names():
			if sprite.animation == "demolished" and sprite.is_playing() and sprite.frame < spawn_on_frame:
				can_spawn_now = false

		if can_spawn_now:
			_spawn_soldiers_mid_anim()
			_emit_destroyed()
			_spawned = true

func _update_z() -> void:
	z_index = int(global_position.y)

func set_tile_pos(new_tile_pos: Vector2i) -> void:
	tile_pos = new_tile_pos
	_update_world_from_tile()
	_update_z()

func _update_world_from_tile() -> void:
	if _tilemap == null:
		push_warning("TileMap not found")
		return
	global_position = _tilemap.to_global(_tilemap.map_to_local(tile_pos)) + Vector2(0, y_offset)

# Call when this structure should blow
func demolish() -> void:
	if _demolished:
		return
	_demolished = true

	# Kick the anim if present; spawning will be handled by _process()
	var sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
	if sprite and sprite.sprite_frames and "demolished" in sprite.sprite_frames.get_animation_names():
		sprite.play("demolished")

	# Disable collisions early so pathfinding can route through the tile
	var col := get_node_or_null("CollisionShape2D")
	if col and col is CollisionShape2D:
		col.disabled = true

func _on_demo_frame_changed() -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.animation != "demolished":
		return
	# Spawn ONCE when we reach (or pass) the target frame
	if not _spawned and sprite.frame >= spawn_on_frame:
		_spawn_soldiers_mid_anim()
		_emit_destroyed()  # let listeners (if any) know the tile is effectively gone
		_spawned = true
		# Optional: disconnect so we don’t re-trigger for looping anims
		if sprite.is_connected("frame_changed", Callable(self, "_on_demo_frame_changed")):
			sprite.disconnect("frame_changed", Callable(self, "_on_demo_frame_changed"))

func _emit_destroyed() -> void:
	emit_signal("destroyed", tile_pos)
	var tm = get_node_or_null("/root/TurnManager")
	if tm and tm.has_signal("structure_demolished"):
		tm.emit_signal("structure_demolished", tile_pos)

func _spawn_soldiers_mid_anim() -> void:
	if _tilemap == null:
		return
	# If neither scene is set, nothing to spawn
	if soldier_scene == null and merc_scene == null:
		return

	var targets := _pick_spawn_tiles_adjacent_first(soldiers_to_spawn)

	for i in range(targets.size()):
		await get_tree().create_timer(randf_range(0.04, 0.14)).timeout

		var scene: PackedScene = _pick_spawn_scene_for_index(i)
		if scene == null:
			continue
		_eject_one(targets[i], scene)

func _pick_spawn_scene_for_index(i: int) -> PackedScene:
	# If both available:
	if soldier_scene != null and merc_scene != null:
		if mix_alternate:
			# Alternate Soldier/Merc based on index
			if (i % 2) == 0:
				return soldier_scene
			else:
				return merc_scene
		else:
			# Random mix 50/50
			if randi() % 2 == 0:
				return soldier_scene
			else:
				return merc_scene

	# Fallbacks if only one is set
	if soldier_scene != null:
		return soldier_scene
	if merc_scene != null:
		return merc_scene

	return null

func _pick_spawn_tiles_adjacent_first(total: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	# --- collect open ADJACENT first (up to 4) ---
	var adj: Array[Vector2i] = []
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var n = tile_pos + d
		if _is_open(n):
			adj.append(n)

	# --- then collect a MANHATTAN RING (radius 2..3) as fallback ---
	var ring: Array[Vector2i] = []
	for r in range(2, 4): # 2 and 3 like your previous search
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) + abs(dy) != r:
					continue
				var n := tile_pos + Vector2i(dx, dy)
				if _is_open(n) and not adj.has(n) and not ring.has(n):
					ring.append(n)

	# If absolutely nothing open, dump everyone on the center (they’ll hop out)
	if adj.is_empty() and ring.is_empty():
		for _i in range(total):
			result.append(tile_pos)
		return result

	# --- pick base unique tiles for half the soldiers: ADJACENT FIRST ---
	var base_needed = max(1, total / 2)
	var base: Array[Vector2i] = []

	# fill from adjacent
	var take_adj = min(base_needed, adj.size())
	for i in range(take_adj):
		base.append(adj[i])

	# still need more? take from ring (shuffle so it’s not always same)
	if base.size() < base_needed and not ring.is_empty():
		ring.shuffle()
		var take_ring = min(base_needed - base.size(), ring.size())
		for i in range(take_ring):
			base.append(ring[i])

	# 1st half: unique placements
	for t in base:
		result.append(t)

	# 2nd half: duplicates on top of those same base tiles
	var dup_needed := total - result.size()
	for i in range(dup_needed):
		result.append(base[randi() % base.size()])

	# slight final shuffle so pairs don’t always come out in strict order
	result.shuffle()
	return result

func _eject_one(at_tile: Vector2i, scene: PackedScene) -> void:
	var npc := scene.instantiate()
	get_tree().get_current_scene().add_child(npc)

	# 1) Start them *inside* the structure tile (center, tiny jitter)
	var origin := _world_pos_for_tile(tile_pos) \
		+ Vector2(randf_range(-soldier_exit_jitter, soldier_exit_jitter),
				  randf_range(-soldier_exit_jitter, soldier_exit_jitter))
	# 2) Target is the chosen tile (tiny jitter so multiple can share visually)
	var land := _world_pos_for_tile(at_tile) \
		+ Vector2(randf_range(-soldier_exit_jitter, soldier_exit_jitter),
				  randf_range(-soldier_exit_jitter, soldier_exit_jitter))

	# Place & prep visuals
	if "global_position" in npc:
		npc.global_position = origin
	if npc.has_node("AnimatedSprite2D"):
		var spr: AnimatedSprite2D = npc.get_node("AnimatedSprite2D")
		spr.flip_h = land.x > origin.x
		spr.play("move")
	npc.visible = true
	npc.z_as_relative = false
	npc.z_index = int(origin.y)

	# Let their logical tile start on the structure
	if "tile_pos" in npc:
		npc.tile_pos = tile_pos

	# ---- Pace (walk) out at soldier_exit_speed ----
	var dist := origin.distance_to(land)
	var dur: float
	if dist > 0.0 and soldier_exit_speed > 0.0:
		dur = dist / soldier_exit_speed
	else:
		dur = 0.15

	var tw := npc.create_tween()
	tw.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(npc, "global_position", land, dur)
	# keep z-sorting so they pass behind/in front of things correctly
	tw.parallel().tween_method(func(_v):
		if is_instance_valid(npc):
			npc.z_index = int(npc.global_position.y)
	, 0.0, 1.0, dur)
	await tw.finished

	# Snap cleanly to the exact tile center (no jitter) so future grid logic is perfect
	if "tile_pos" in npc:
		npc.tile_pos = at_tile
	npc.global_position = _world_pos_for_tile(at_tile)

	# --- THREAT: adjacent to the structure, or nearest adjacent if farther ---
	var threat_tile := _adjacent_threat_for(at_tile)

	# Return to idle now that they reached the tile
	if npc.has_node("AnimatedSprite2D"):
		var spr2: AnimatedSprite2D = npc.get_node("AnimatedSprite2D")
		if spr2:
			spr2.play("default")

	# Begin the scatter away from that adjacent tile
	if npc.has_method("start_scatter"):
		npc.start_scatter(threat_tile)

func _adjacent_threat_for(land_tile: Vector2i) -> Vector2i:
	# If the soldier landed on an adjacent tile (Manhattan 1), use THAT as the threat.
	if abs(land_tile.x - tile_pos.x) + abs(land_tile.y - tile_pos.y) == 1:
		return land_tile

	# Otherwise, use the closest of the 4-adjacent tiles to the structure.
	var best := tile_pos
	var best_d := 1_000_000
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var adj = tile_pos + d
		if not _tilemap.is_within_bounds(adj): 
			continue
		var dist = abs(adj.x - land_tile.x) + abs(adj.y - land_tile.y)
		if dist < best_d:
			best_d = dist
			best = adj
	return best

func _world_pos_for_tile(t: Vector2i) -> Vector2:
	return _tilemap.to_global(_tilemap.map_to_local(t)) + Vector2(0, y_offset)

func _pick_spawn_tiles() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	# 1) Prefer 4-adjacent tiles
	if spawn_adjacent_first:
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n = tile_pos + d
			if _is_open(n):
				found.append(n)
	# 2) If not enough, search a small ring (radius 2–3)
	var radius := 3
	for r in range(1, radius + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) + abs(dy) != r:
					continue  # manhattan ring
				var n := tile_pos + Vector2i(dx, dy)
				if _is_open(n) and not found.has(n):
					found.append(n)
	# Always allow the center tile as last resort (soldier will step off it)
	if found.is_empty():
		found.append(tile_pos)
	return found

func _is_open(cell: Vector2i) -> bool:
	if not _tilemap.is_within_bounds(cell):
		return false
	return _tilemap._is_tile_walkable(cell) and not _tilemap.is_tile_occupied(cell)

func _spawn_one(at_tile: Vector2i) -> void:
	var npc := soldier_scene.instantiate()
	# Put NPC in the scene root so it’s independent of this node getting freed
	get_tree().get_current_scene().add_child(npc)

	# Place the NPC and kick off fleeing (during demolition)
	if npc.has_method("place_on_tile"):
		npc.place_on_tile(at_tile)
	else:
		# fallback placement
		var wp := _tilemap.to_global(_tilemap.map_to_local(at_tile)) + Vector2(0, -8)
		if "global_position" in npc:
			npc.global_position = wp
		if "tile_pos" in npc:
			npc.tile_pos = at_tile

	# Tell the NPC to scatter immediately, using THIS structure’s tile as the threat origin
	if npc.has_method("start_scatter"):
		npc.start_scatter(tile_pos)

func _pick_spawn_tiles_paired(total: int) -> Array[Vector2i]:
	# Get a pool of open tiles around the structure (adjacent-first, then ring)
	var pool := _pick_spawn_tiles()
	var result: Array[Vector2i] = []

	# If nothing open, just drop everyone on the structure tile itself
	if pool.is_empty():
		for _i in range(total):
			result.append(tile_pos)
		return result

	# Pick base unique tiles (half the total, clamped to pool size, at least 1)
	pool.shuffle()
	var base_count = max(1, min(total / 2, pool.size()))
	var base: Array[Vector2i] = []
	for i in range(base_count):
		base.append(pool[i])

	# First half: unique placements
	for t in base:
		result.append(t)

	# Second half: duplicates—place them on top of the base tiles
	var dup_needed := total - result.size()
	for i in range(dup_needed):
		result.append(base[randi() % base.size()])

	# Randomize final order a bit
	result.shuffle()
	return result
