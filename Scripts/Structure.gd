# res://Scripts/Structure.gd
extends Node2D
signal destroyed(tile_pos: Vector2i)

@export var tile_pos: Vector2i = Vector2i.ZERO
@export var y_offset: int = -8
@export var auto_add_to_group: bool = true

# ---- Soldier spawn settings ----
@export var soldier_scene: PackedScene                 # assign NPC scene (with SoldierNPC.gd)
@export var soldiers_to_spawn: int = 8                 # how many to pop out
@export var spawn_on_frame: int = 1                    # frame index inside "demolished" anim to spawn
@export var spawn_adjacent_first: bool = true          # prefer adjacent open tiles

var _tilemap: TileMap
var _demolished := false
var _spawned := false

var structure_id

func _ready() -> void:
	_tilemap = get_tree().get_current_scene().get_node_or_null("TileMap")
	if auto_add_to_group:
		add_to_group("Structures")
	_update_world_from_tile()
	_update_z()

func _process(_dt: float) -> void:
	_update_z()

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

	var sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
	if sprite and sprite.sprite_frames and "demolished" in sprite.sprite_frames.get_animation_names():
		# Connect to the frame tick so we can spawn WHILE the anim is playing
		if not sprite.is_connected("frame_changed", Callable(self, "_on_demo_frame_changed")):
			sprite.connect("frame_changed", Callable(self, "_on_demo_frame_changed"))
		sprite.play("demolished")
	else:
		# No animation; spawn immediately and still emit destroyed
		_spawn_soldiers_mid_anim()
		_emit_destroyed()

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
	if soldier_scene == null or _tilemap == null:
		return
	var targets := _pick_spawn_tiles()
	for i in range(min(soldiers_to_spawn, targets.size())):
		_spawn_one(targets[i])

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
