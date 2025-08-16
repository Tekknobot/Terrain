extends Area2D

var unit_id: int   # Local unique identifier

signal spider_arc_done

@export var is_player: bool = true
@export var unit_type: String = "Soldier"
@export var unit_name: String = "Hero"
@export var portrait: Texture
@export var mek_portrait: Texture  # drag-in your “mek” overlay texture in the editor

var health := 100
var max_health := 100
var xp := 0
var max_xp := 100
var level := 1
@export var damage := 25
@export var movement_range := 2
@export var attack_range := 3
@export var defense := 0
@export var default_special: String = ""  # e.g. "Ground Slam", "High Arching Shot"

signal movement_finished

@onready var health_bar = $HealthUI
@onready var xp_bar = $XPUI
@onready var step_player: AudioStreamPlayer2D = $SFX
@onready var sfx_player: AudioStreamPlayer2D = $SFX2

var has_moved := false
var has_attacked := false
var being_pushed: bool = false

# ─────────────────────────────────────────────────────────────────────────────
# Special ability state

# 1) Panther mark & pounce
#    We store a "marked" flag on ANY unit (via metadata).
# 2) Angel shield
var shield_amount: int = 0
var shield_duration: int = 0  # counts down at end of next turn
var _shield_just_applied := false

# 3) Multi Turret suppression
var is_suppressed: bool = false

# 4) Brute fortify
var is_fortified: bool = false

# 5) Helicopter airlift & drop
var queued_airlift_unit: Node = null
var queued_bomb_tile: Vector2i = Vector2i(-1, -1)

# 6) Spider web grid (shared 10×10). Each element is a Dictionary {"duration": int}.
static var web_grid: Array = []

var _rounds_elapsed: int = 0

var _active_arc_lines: Array[Line2D] = []

func _register_arc_line(line: Line2D) -> void:
	if line == null: return
	_active_arc_lines.append(line)
	# tag so we can find them if needed
	line.set_meta("arc_owner_id", unit_id)

func _cleanup_arc_trails() -> void:
	for l in _active_arc_lines:
		if is_instance_valid(l):
			l.queue_free()
	_active_arc_lines.clear()

func _exit_tree() -> void:
	# safety: if the unit leaves the tree for any reason, nuke its trails
	_cleanup_arc_trails()

# Ensure web_grid is initialized once
func _init():
	if web_grid.size() == 0:
		for x in range(10):
			var col = []
			for y in range(10):
				col.append({"duration": 0})
			web_grid.append(col)

# ─────────────────────────────────────────────────────────────────────────────

const Y_OFFSET := -8.0
var true_position := Vector2.ZERO

var visited_tiles: Array = []
@export var water_tile_id := 6

var level_up_material = preload("res://Textures/level_up.tres")
var original_material : Material = null

var ExplosionScene := preload("res://Scenes/VFX/Explosion.tscn")
const TILE_SIZE := Vector2(64, 64)

var missile_sfx := preload("res://Audio/SFX/missile_launch.wav")
var attack_sfx := preload("res://Audio/SFX/attack_default.wav")
var step_sfx := preload("res://Audio/SFX/step_tile.wav")

@export var LaserBeamScene: PackedScene = preload("res://Scenes/VFX/laser_beam.tscn")
@export var fortify_effect_scene := preload("res://Scenes/VFX/FortifyAura.tscn")
var _fortify_aura: Node = null

var death_messages := [
	"Downed!","Shattered!","Boom!","Deleted!",
	"Neutralized!","Eliminated!","Shutdown!","Erased!"
]

const COIN_SCENE           = preload("res://Prefabs/coin_pickup.tscn")
const HEALTH_SCENE         = preload("res://Prefabs/health_pickup.tscn")
const LIGHTNING_SCENE      = preload("res://Prefabs/lightning_pickup.tscn")
const ORBITAL_STRIKE_SCENE = preload("res://Prefabs/orbital_strike_pickup.tscn")
const EMPTY_CELL_ID        = -1   # Godot’s “no tile” value
var _open_tiles: Array[Vector2i] = []

var base_movement_range := 0
var base_attack_range   := 0
var base_defense        := 0

var prev_tile_pos: Vector2i
var queued_airlift_origin: Vector2i = Vector2i(-1, -1)

const SHIELD_ROUNDS := 1

# --- Medic Aura (passive) ---
@export var medic_aura_enabled: bool = true     # toggle in editor
@export var medic_aura_radius: int = 2          # Manhattan radius
@export var medic_aura_heal: int = 35           # HP per full round

const AURA_HEART_TSCN := preload("res://Scenes/VFX/popup_text.tscn") # will show text instead

@export var medic_aura_hint_duration: float = 0.9  # how long to show the cue each round

var is_boss: bool = false

signal tile_changed(unit, tile: Vector2i)

var _tile_pos: Vector2i = Vector2i.ZERO
var tile_pos: Vector2i:
	set(value):
		if _tile_pos == value:
			return
		_tile_pos = value
		emit_signal("tile_changed", self, _tile_pos)
	get:
		return _tile_pos

var _pending_fortify_beams: int = 0
var _fortify_finishing: bool = false
		
func _ready():
	prev_tile_pos = tile_pos
	connect("movement_finished", Callable(self, "_on_movement_finished"))
	TurnManager.connect("round_ended", Callable(self, "_on_round_ended"))
	
	# Connect once to the autoload
	if TurnManager and not TurnManager.is_connected("round_ended", Callable(self, "_on_round_ended")):
		TurnManager.connect("round_ended", Callable(self, "_on_round_ended"), CONNECT_DEFERRED)

	# (Optional) only Support units keep the aura on by default
	if unit_type == "Support":
		medic_aura_enabled = true
		
	# Assign a local unique id if not set
	if unit_id == 0 and has_meta("unit_id"):
		unit_id = get_meta("unit_id")
	elif unit_id == 0:
		unit_id = TurnManager.next_unit_id
		set_meta("unit_id", unit_id)
		TurnManager.next_unit_id += 1

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tile_pos = tilemap.local_to_map(tilemap.to_local(global_position))
	add_to_group("Units")
	print("DEBUG: Unit ", unit_id, " is ready. (", name, ")")
	update_z_index()
	update_health_bar()
	update_xp_bar()
	debug_print_units()

	base_movement_range = movement_range
	base_attack_range   = attack_range
	base_defense        = defense

	if step_player and step_sfx:
		step_player.stream = step_sfx
	
func debug_print_units():
	var units = get_tree().get_nodes_in_group("Units")
	print("DEBUG: Listing all units in the 'Units' group. Total: ", units.size())
	for u in units:
		if u.has_meta("unit_id"):
			print("   Unit Name: ", u.name, ", Unit ID: ", u.get_meta("unit_id"))
		else:
			print("   Unit Name: ", u.name, " does not have a unit_id set.")

func _process(delta):
	update_z_index()
	check_water_status()

func update_z_index():
	z_index = int(position.y)
	# Aura stays behind even with y-sort, but we still mirror relative placement:
	if _fortify_aura and is_instance_valid(_fortify_aura):
		var ci := _fortify_aura as CanvasItem
		if ci:
			ci.z_as_relative = true
			ci.z_index = -1


### PLAYER TURN ###
func start_turn():
	# Wait for player input; call on_player_done() when action is complete
	pass

func on_player_done():
	TurnManager.unit_finished_action(self)

func compute_path(from: Vector2i, to: Vector2i) -> Array:
	await get_tree().process_frame
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap.update_astar_grid()
	return tilemap.astar.get_point_path(from, to)

func _move_one(dest: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var world_target = tilemap.to_global(tilemap.map_to_local(dest)) + Vector2(0, Y_OFFSET)

	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("move")
		sprite.flip_h = global_position.x < world_target.x

	var speed := 100.0

	if step_player:
		step_player.pitch_scale = randf_range(0.9, 1.1)
		step_player.play()

	while global_position.distance_to(world_target) > 1.0:
		var delta = get_process_delta_time()
		global_position = global_position.move_toward(world_target, speed * delta)
		await Engine.get_main_loop().process_frame

	global_position = world_target
	tile_pos = dest
	if sprite:
		sprite.play("default")

func move_to(dest: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var path = tilemap.get_weighted_path(tile_pos, dest)
	if path.is_empty():
		emit_signal("movement_finished")
		return

	print("DEBUG: Path computed for unit ", unit_id, " with length: ", path.size())
	for step in path:
		await _move_one(step)

	tilemap.update_astar_grid()
	await get_tree().process_frame
	emit_signal("movement_finished")
	has_moved = true

	print("DEBUG: Finished moving unit ", unit_id, ". Tile pos: ", tile_pos, ", Global pos: ", global_position)

# ─────────────────────────────────────────────────────────────────────────────
# Damage / shields / fortify
func take_damage(amount: int) -> bool:
	# Panther “mark” bonus
	if has_meta("is_marked") and get_meta("is_marked"):
		amount = int(amount * 1.5)
		remove_meta("is_marked")

	# Brute fortify reduction
	if is_fortified:
		amount = int(amount * 0.5)

	# Angel shield blocks all while active
	if shield_duration > 0:
		return false

	# Brute fortify reduction again (if you want to stack; kept from your code)
	if is_fortified:
		amount = int(amount * 0.5)

	if not is_player:
		TurnManager.record_damage(amount)

	spawn_floating_text(amount)

	health = max(health - amount, 0)
	update_health_bar()
	if health == 0:
		die()
		return true
	return false

# ─────────────────────────────────────────────────────────────────────────────

# Optional small helper for safer writes
func _safe_set_being_pushed(n, v: bool) -> void:
	if n == null:
		return
	# Only proceed if the object is still alive
	if not is_instance_valid(n):
		return
	# Prefer direct property write if it exists, otherwise fall back to set()
	if "being_pushed" in n:
		n.being_pushed = v
	elif n.has_method("set"):
		n.set("being_pushed", v)

func auto_attack_adjacent():
	if attack_range < 1:
		return

	var tilemap: TileMap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return

	var directions: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

	# Current tile from world (safer than cached tile_pos)
	var my_tile: Vector2i = tilemap.local_to_map(tilemap.to_local(global_position - Vector2(0, Y_OFFSET)))

	for dir in directions:
		# Recompute each step to avoid stale positions after pushes / animation
		var check_pos: Vector2i = my_tile + dir

		# Pull fresh occupants *on that tile*; avoids scanning a stale "units" list
		var occs := get_occupants_at(check_pos, null)  # assumes your helper returns Nodes
		if occs.is_empty():
			continue

		# Find the first valid enemy unit on that tile
		var unit = null
		for o in occs:
			if not is_instance_valid(o):
				continue
			if not o.is_in_group("Units"):
				continue
			if o == self:
				continue
			if o.is_player == is_player:
				continue
			unit = o
			break

		if unit == null or not is_instance_valid(unit):
			continue
		if unit.health <= 0:
			continue

		# ───────────────────────────────────────── ATTACK ─────────────────────────────────────────
		var died = unit.take_damage(damage)
		if not died and is_instance_valid(unit) and unit.has_method("flash_white"):
			unit.flash_white()

		# Play our attack anim/sfx (attacker)
		var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
		if sprite:
			if tilemap.has_method("play_attack_sound"):
				tilemap.play_attack_sound(global_position)
			# flip toward push dir
			if dir.x != 0:
				sprite.flip_h = dir.x > 0
			elif dir.y != 0:
				sprite.flip_h = true
			sprite.play("attack")
			await sprite.animation_finished
			if is_instance_valid(sprite):
				sprite.play("default")

		# XP for hit
		gain_xp(25)

		# If target died, bonus XP and never touch it again
		if died:
			gain_xp(25)
			continue

		# ───────────────────────────────────────── PUSH ───────────────────────────────────────────
		# Re-validate unit before push (it might have died during VFX)
		if not is_instance_valid(unit) or unit.health <= 0:
			continue

		_safe_set_being_pushed(unit, true)
		TutorialManager.on_action("push_mechanic")

		var push_pos: Vector2i = check_pos + dir  # push from its current checked tile
		var target_world: Vector2 = tilemap.to_global(tilemap.map_to_local(push_pos)) + Vector2(0, Y_OFFSET)
		var speed := 150.0

		# Branch: WATER
		if tilemap.get_cell_source_id(0, push_pos) == water_tile_id:
			while is_instance_valid(unit) and unit.global_position.distance_to(target_world) > 1.0:
				var dt := get_process_delta_time()
				unit.global_position = unit.global_position.move_toward(target_world, speed * dt)
				await get_tree().process_frame

			if not is_instance_valid(unit):
				continue

			unit.global_position = target_world
			unit.tile_pos = push_pos  # safe now; we're holding a valid ref

			if tilemap.has_method("play_splash_sound"):
				tilemap.play_splash_sound(target_world)
			if unit.has_method("apply_water_effect"):
				apply_water_effect(unit)

			# Collisions on water tile
			if tilemap.is_tile_occupied(push_pos):
				var occupants = get_occupants_at(push_pos, unit)
				if occupants.size() > 0:
					for occ in occupants:
						if not is_instance_valid(occ): 
							continue
						if occ.is_in_group("Structures"):
							var occ_sprite: AnimatedSprite2D = occ.get_node_or_null("AnimatedSprite2D")
							if occ_sprite:
								occ_sprite.play("demolished")
								if occ_sprite.get_parent():
									occ_sprite.get_parent().modulate = Color(1,1,1,1)
							if occ.has_method("demolish"):
								occ.demolish()
						elif occ.is_in_group("Units"):
							await get_tree().create_timer(0.2).timeout
							if is_instance_valid(occ):
								occ.take_damage(damage)
								if occ.has_method("shake"):
									occ.shake()
					gain_xp(25)

					if is_instance_valid(unit):
						_safe_set_being_pushed(unit, false)
						unit.die()
					tilemap.update_astar_grid()
					continue  # do not touch unit afterward

			# Extra water damage / shake
			if is_instance_valid(unit):
				var water_damage := 25
				var died_in_water = unit.take_damage(water_damage)
				if not died_in_water and unit.has_method("shake"):
					unit.shake()

			await get_tree().create_timer(0.2).timeout
			tilemap.update_astar_grid()
			if is_instance_valid(unit):
				_safe_set_being_pushed(unit, false)
			continue

		# OFF-GRID
		if not tilemap.is_within_bounds(push_pos):
			while is_instance_valid(unit) and unit.global_position.distance_to(target_world) > 1.0:
				var dt2 := get_process_delta_time()
				unit.global_position = unit.global_position.move_toward(target_world, speed * dt2)
				await get_tree().process_frame

			await get_tree().create_timer(0.2).timeout
			gain_xp(25)
			if is_instance_valid(unit):
				_safe_set_being_pushed(unit, false)
				TutorialManager.on_action("offgrid_mechanic")
				unit.die()
			tilemap.update_astar_grid()
			continue

		# NORMAL GRID PUSH
		while is_instance_valid(unit) and unit.global_position.distance_to(target_world) > 1.0:
			var dt3 := get_process_delta_time()
			unit.global_position = unit.global_position.move_toward(target_world, speed * dt3)
			await get_tree().process_frame

		if not is_instance_valid(unit):
			continue

		unit.global_position = target_world
		unit.tile_pos = push_pos

		# Collision at destination
		if tilemap.is_tile_occupied(push_pos):
			var occupants2 = get_occupants_at(push_pos, unit)
			if occupants2.size() > 0:
				for occ2 in occupants2:
					if not is_instance_valid(occ2):
						continue
					if occ2.is_in_group("Structures"):
						var occ_sprite2: AnimatedSprite2D = occ2.get_node_or_null("AnimatedSprite2D")
						if occ_sprite2:
							occ_sprite2.play("demolished")
							if occ_sprite2.get_parent():
								occ_sprite2.get_parent().modulate = Color(1,1,1,1)
						if occ2.has_method("demolish"):
							occ2.demolish()
					elif occ2.is_in_group("Units"):
						await get_tree().create_timer(0.2).timeout
						if is_instance_valid(occ2):
							occ2.take_damage(damage)
							if occ2.has_method("shake"):
								occ2.shake()
				gain_xp(25)
				TutorialManager.on_action("collide_mechanic")
				if is_instance_valid(unit):
					_safe_set_being_pushed(unit, false)
					unit.die()
				tilemap.update_astar_grid()
				continue

		# No collision → finish safely
		tilemap.update_astar_grid()
		if is_instance_valid(unit):
			_safe_set_being_pushed(unit, false)

	# We swung in some direction(s); mark our own state
	has_moved = true
	has_attacked = true
	if is_player:
		$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)
	TutorialManager.on_action("enemy_attacked")

func get_occupants_at(pos: Vector2i, ignore: Node = null) -> Array:
	var occupants = []
	for unit in get_tree().get_nodes_in_group("Units"):
		if is_instance_valid(unit) and unit.tile_pos == pos and unit != ignore:
			occupants.append(unit)
	for structure in get_tree().get_nodes_in_group("Structures"):
		if is_instance_valid(structure) and structure.tile_pos == pos and structure != ignore:
			occupants.append(structure)
	return occupants

func spawn_explosion_at(pos: Vector2):
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	explosion.position = pos
	get_tree().get_current_scene().add_child(explosion)

func has_adjacent_enemy() -> bool:
	if attack_range < 1:
		return false

	var directions = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var actual_tile = tilemap.local_to_map(tilemap.to_local(global_position))

	for dir in directions:
		var check_pos = actual_tile + dir
		for unit in get_tree().get_nodes_in_group("Units"):
			if unit == self: continue
			var unit_pos = tilemap.local_to_map(tilemap.to_local(unit.global_position))
			if unit_pos == check_pos and unit.is_player != is_player:
				return true
	return false

func display_attack_range(range: int):
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap._highlight_range(tile_pos, range, 3)

### HEALTH & XP ###
func gain_xp(amount):
	xp += amount
	if xp >= max_xp:
		xp -= max_xp
		level += 1
		max_xp = int(max_xp * 1.5)
		health = max_health
		damage += 25
		update_health_bar()
		if health >= max_health:
			health = max_health
		play_level_up_sound()
		shake()
		apply_level_up_material()
		TutorialManager.on_action("leveled_up")
	update_xp_bar()

func play_level_up_sound():
	var level_up_audio = preload("res://Audio/SFX/powerUp.wav")
	var audio_player = AudioStreamPlayer.new()
	audio_player.stream = level_up_audio
	add_child(audio_player)
	audio_player.play()

func update_health_bar():
	if health_bar:
		health_bar.value = float(health) / max_health * 100.0

func update_xp_bar():
	if xp_bar:
		xp_bar.value = float(xp) / max_xp * 100.0

func die():
	# Free any active fortify aura before dying
	if _fortify_aura:
		_fortify_aura.queue_free()
		_fortify_aura = null

	if is_player:
		TurnManager.player_units_lost += 1

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var explosion = preload("res://Scenes/VFX/Explosion.tscn").instantiate()
	explosion.position = global_position + Vector2(0, -8)
	tilemap.add_child(explosion)

	await get_tree().process_frame

	# Store tile before anything
	var death_tile = tile_pos
	var death_scene = get_tree().get_current_scene()

	await get_tree().process_frame

	_spawn_burst(death_scene, death_tile)

	_cleanup_arc_trails()   # <-- add this
	queue_free()

	if tilemap.selected_unit == self:
		tilemap._on_selected_unit_died()
	await get_tree().process_frame

	var units = get_tree().get_nodes_in_group("Units")
	var has_players = false
	var has_enemies = false
	for u in units:
		if not is_instance_valid(u):
			continue
		if u.is_player:
			has_players = true
		else:
			has_enemies = true

	if not has_players or not has_enemies:
		print("🏁 Game Over — One team has no remaining units.")
		var tm = get_node_or_null("/root/TurnManager")
		if tm:
			tm.end_turn(true)

#–– Returns a random cell within the used rect that has no tile (i.e. open)
func cache_open_tiles() -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	_open_tiles.clear()
	for x in range(tilemap.grid_width):
		for y in range(tilemap.grid_height):
			var cell = Vector2i(x, y)
			if tilemap._is_tile_walkable(cell) and not tilemap.is_tile_occupied(cell):
				_open_tiles.append(cell)
	if _open_tiles.is_empty():
		push_warning("No open tiles found!")

func _get_random_open_tile() -> Vector2i:
	if _open_tiles.is_empty():
		cache_open_tiles()
	return _open_tiles[randi() % _open_tiles.size()]

#–– Burst spawner (random open tile)
func _spawn_burst(tilemap: Node, tile_pos: Vector2i) -> void:
	var tm = tilemap.get_node("TileMap") if tilemap.has_node("TileMap") else tilemap
	var num_attempts  := 1
	var fade_in_time  := 1.0

	for i in range(num_attempts):
		var drop_scene = _choose_drop_scene()
		if drop_scene == null:
			continue

		var cell       = _get_random_open_tile()
		var target_pos = tm.to_global(tm.map_to_local(cell))

		var drop = drop_scene.instantiate() as Node2D
		drop.global_position = target_pos
		drop.global_position.y -= 32
		drop.modulate = Color(1,1,1,0)
		var collider = drop.get_node("CollisionShape2D") as CollisionShape2D
		collider.disabled = true
		get_tree().get_current_scene().add_child(drop)

		var tween = drop.create_tween()
		tween.tween_property(drop, "modulate:a", 1.0, fade_in_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			if is_instance_valid(collider):
				collider.disabled = false
		)

func _choose_drop_scene() -> PackedScene:
	var roll = randi() % 100
	if roll < 100:
		match randi() % 3:
			0: return HEALTH_SCENE
			1: return LIGHTNING_SCENE
			2: return ORBITAL_STRIKE_SCENE
	return null

# ─────────────────────────────────────────────────────────────────────────────
# Visual feedback helpers
var _flash_tween: Tween = null
var _flash_shader := preload("res://Textures/flash.gdshader")
var _original_material: Material = null

func flash_white():
	var sprite = $AnimatedSprite2D
	if not sprite:
		return
	var original_color = sprite.self_modulate
	if _flash_tween:
		_flash_tween.kill()
		sprite.self_modulate = original_color
		_flash_tween = null

	_flash_tween = create_tween()
	for i in range(3):
		_flash_tween.tween_property(sprite, "self_modulate", Color(1,1,1,1), 0.1)
		_flash_tween.tween_property(sprite, "self_modulate", original_color, 0.1)
	_flash_tween.tween_callback(func():
		sprite.self_modulate = original_color
		_flash_tween = null
	)

func flash_blue():
	var sprite = $AnimatedSprite2D
	if not sprite:
		return
	if _flash_tween:
		_flash_tween.kill()
		sprite.self_modulate = Color(1,1,1,1)
		_flash_tween = null
	_flash_tween = create_tween()
	for i in range(3):
		_flash_tween.tween_property(sprite, "self_modulate", Color(0,0,1,1), 0.1)
		_flash_tween.tween_property(sprite, "self_modulate", Color(1,1,1,0), 0.1)
	_flash_tween.tween_callback(func():
		sprite.self_modulate = Color(1,1,1,1)
		_flash_tween = null
	)

func set_team(player_team: bool) -> void:
	is_player = player_team
	set_meta("is_player", player_team)  # local metadata usage

	var sprite = $AnimatedSprite2D
	if sprite:
		if is_player:
			sprite.modulate = Color(1,1,1)
		else:
			sprite.modulate = Color(1,0.43,1)

func check_adjacent_and_attack():
	if has_adjacent_enemy():
		auto_attack_adjacent()

var queued_move: Vector2i = Vector2i(-1, -1)
var queued_attack_target: Node2D = null

func plan_move(dest: Vector2i):
	var tilemap = get_tree().get_current_scene().get_node("TileMap")

	var frontier = [tile_pos]
	var distances = { tile_pos: 0 }
	var parents = {}
	var candidates = []

	while frontier.size() > 0:
		var current = frontier.pop_front()
		var d = distances[current]
		if current != tile_pos:
			candidates.append(current)
		if d == movement_range:
			continue
		for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor = current + dir
			if tilemap.is_within_bounds(neighbor) and not distances.has(neighbor) and tilemap._is_tile_walkable(neighbor) and not tilemap.is_tile_occupied(neighbor):
				distances[neighbor] = d + 1
				parents[neighbor] = current
				frontier.append(neighbor)

	if distances.has(dest):
		var path = []
		var current_pos = dest
		while current_pos != tile_pos:
			path.insert(0, current_pos)
			current_pos = parents[current_pos]
		var steps_to_take = min(path.size(), movement_range)
		var move_target = path[steps_to_take - 1]
		queued_move = move_target
		visited_tiles.append(move_target)
		print("🚶 Direct path: planning move to:", move_target)
		return
	else:
		print("⛔ Destination", dest, "not reachable.")

	var attack_candidates: Array = []
	for candidate in candidates:
		if candidate.distance_to(dest) <= attack_range:
			attack_candidates.append(candidate)

	if attack_candidates.size() > 0:
		var best_candidate: Vector2i = attack_candidates[0]
		var best_cost = best_candidate.distance_to(dest)
		for candidate in attack_candidates:
			var cost = candidate.distance_to(dest)
			if cost < best_cost:
				best_cost = cost
				best_candidate = candidate
		queued_move = best_candidate
		visited_tiles.append(best_candidate)
		print("🚶 Attack move found, planning move to:", best_candidate)
		return

	var best_candidate2: Vector2i = tile_pos
	var best_cost2 = INF
	for candidate2 in candidates:
		var euclid = candidate2.distance_to(dest)
		var extra_cost = 0
		if candidate2 == queued_move:
			extra_cost += 2
		if visited_tiles.has(candidate2):
			extra_cost += 5
		if candidate2.distance_to(dest) <= attack_range:
			extra_cost -= 10
		var cost = euclid + extra_cost
		if cost < best_cost2:
			best_cost2 = cost
			best_candidate2 = candidate2

	if best_candidate2 != tile_pos:
		queued_move = best_candidate2
		visited_tiles.append(best_candidate2)
		print("🚶 Fallback move to:", best_candidate2)
	else:
		print("⛔ No valid tile within range; will not move.")

func plan_attack(target: Node2D):
	queued_attack_target = target

func clear_actions():
	queued_move = Vector2i(-1, -1)
	queued_attack_target = null

func execute_actions():
	if queued_move != Vector2i(-1, -1):
		await move_to(queued_move)
		has_moved = true
		queued_move = Vector2i(-1, -1)
		emit_signal("movement_finished")
		if not is_instance_valid(self):
			return
		if not is_player and attack_range == 1:
			await auto_attack_adjacent()
			if not is_instance_valid(self):
				return

	if queued_attack_target:
		if not is_instance_valid(queued_attack_target):
			queued_attack_target = null
			return
		if queued_attack_target == self:
			queued_attack_target = null
			return
		var dir = queued_attack_target.tile_pos - tile_pos
		var sprite = get_node("AnimatedSprite2D")
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		if sprite and dir.x != 0:
			sprite.flip_h = dir.x > 0
		tilemap.play_attack_sound(global_position)
		if sprite:
			sprite.play("attack")
			await sprite.animation_finished
			if not is_instance_valid(self):
				return
			sprite.play("default")
		has_attacked = true
		queued_attack_target = null

	if not is_instance_valid(self):
		return

	if is_player:
		var tilemap2 = get_tree().get_current_scene().get_node("TileMap")
		if tilemap2.has_method("on_player_unit_done"):
			tilemap2.on_player_unit_done(self)

func execute_all_player_actions():
	var units := get_tree().get_nodes_in_group("Units").filter(func(u): return u.is_player)
	for unit in units:
		if unit.has_method("execute_actions"):
			await unit.execute_actions()
	var turn_manager = get_node("/root/TurnManager")
	if turn_manager and turn_manager.has_method("end_turn"):
		turn_manager.end_turn()

func shake():
	var original_position := global_position
	var tween := create_tween()

	# Quick left-right jitter
	tween.tween_property(self, "global_position", original_position + Vector2(5, 0), 0.05)
	tween.tween_property(self, "global_position", original_position - Vector2(5, 0), 0.05)
	
	# Always return to original position
	tween.tween_property(self, "global_position", original_position, 0.05)

	# Safety: force-set to original at the very end
	tween.tween_callback(func():
		if is_instance_valid(self):
			global_position = original_position
	)


var water_material = preload("res://Textures/in_water.tres")

func apply_water_effect(unit: Node) -> void:
	var sprite = unit.get_node("AnimatedSprite2D")
	if sprite:
		if not sprite.has_meta("original_material"):
			sprite.set_meta("original_material", sprite.material)
		sprite.material = water_material
		var base_mod: Color
		if unit.is_player:
			base_mod = Color(1,1,1,1)
		else:
			base_mod = Color(1,0.43,1,1)
		if sprite.material is ShaderMaterial:
			sprite.material.set_shader_parameter("base_modulate", base_mod)
		print("Water material applied to", unit.name)

func remove_water_effect(unit: Node) -> void:
	var sprite = unit.get_node("AnimatedSprite2D")
	if sprite and sprite.has_meta("original_material"):
		sprite.material = sprite.get_meta("original_material")
		sprite.remove_meta("original_material")
		if sprite.has_meta("original_modulate"):
			sprite.modulate = sprite.get_meta("original_modulate")
			sprite.remove_meta("original_modulate")
		print("Original material restored for", unit.name)

func check_water_status():
	var tilemap := get_tree().get_current_scene().get_node("TileMap")
	var water_id = tilemap.water_tile_id  # single source of truth
	if tilemap.get_cell_source_id(0, tile_pos) == water_id:
		apply_water_effect(self)
	else:
		remove_water_effect(self)

func auto_attack_ranged(target: Node, unit: Area2D) -> void:
	if unit.attack_range < 1:
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		tilemap.input_locked = false
		return

	if not is_instance_valid(target):
		var tilemap2 = get_tree().get_current_scene().get_node("TileMap")
		tilemap2.input_locked = false
		return

	var tilemap3 = get_tree().get_current_scene().get_node("TileMap")
	tilemap3.input_locked = true

	var attacker_pos = unit.global_position
	var target_pos   = target.global_position

	var sprite = unit.get_node("AnimatedSprite2D") as AnimatedSprite2D
	sprite.flip_h = target_pos.x > attacker_pos.x
	sprite.play("attack")
	await sprite.animation_finished
	sprite.play("default")

	var missile = preload("res://Prefabs/Missile.tscn").instantiate()
	get_tree().get_current_scene().add_child(missile)
	missile.set_target(attacker_pos, target_pos)
	missile.damage = unit.damage

	unit.gain_xp(25)

	await missile.finished

	tilemap3.input_locked = false
	unit.has_moved   = true
	unit.has_attacked = true

	TutorialManager.on_action("enemy_attacked")

func auto_attack_ranged_empty(target_tile: Vector2i, unit: Area2D) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return
 
	tilemap.input_locked = true

	var target_pos = tilemap.to_global(tilemap.map_to_local(target_tile)) + Vector2(0, unit.Y_OFFSET)
	var sprite = $AnimatedSprite2D
	sprite.flip_h = target_pos.x > global_position.x

	if sprite:
		sprite.play("attack")
		await sprite.animation_finished
		sprite.play("default")

	var missile_scene = preload("res://Prefabs/Missile.tscn")
	var missile = missile_scene.instantiate()
	get_tree().get_current_scene().add_child(missile)
	missile.set_target(global_position, target_pos)
	missile.damage = self.damage

	await missile.finished

	tilemap.input_locked = false

	has_moved = true
	has_attacked = true

	TutorialManager.on_action("enemy_attacked")

func apply_level_up_material() -> void:
	var sprite = $AnimatedSprite2D
	if sprite:
		var prior_modulate = sprite.modulate
		if not sprite.has_meta("saved_material"):
			sprite.set_meta("saved_material", sprite.material)
		sprite.material = level_up_material
		await get_tree().create_timer(1.0).timeout
		if sprite.has_meta("saved_material"):
			sprite.material = sprite.get_meta("saved_material")
			sprite.remove_meta("saved_material")
		sprite.modulate = prior_modulate

# ─────────────────────────────────────────────────────────────────────────────
# 1) Hulk – Ground Slam (local)
func ground_slam(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var dist = abs(tile_pos.x - target_tile.x) + abs(tile_pos.y - target_tile.y)
	if dist > 1:
		return

	gain_xp(25)

	var jump_height := 64.0
	var original_pos := global_position
	var up_pos := original_pos + Vector2(0, -jump_height)

	var hop_tween := create_tween()
	hop_tween.tween_property(self, "global_position", up_pos, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop_tween.tween_property(self, "global_position", original_pos, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await hop_tween.finished

	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("attack")
		await sprite.animation_finished
		sprite.play("default")

	var center_unit = tilemap.get_unit_at_tile(target_tile)
	var center_structure: Node2D = null
	for struct_node in get_tree().get_nodes_in_group("structure"):
		if struct_node.tile_pos == target_tile:
			center_structure = struct_node
			break

	var slam_position: Vector2
	if center_unit:
		slam_position = center_unit.global_position
	elif center_structure:
		slam_position = center_structure.global_position
	else:
		var tile_top_left = tilemap.to_global(tilemap.map_to_local(target_tile))
		slam_position = tile_top_left

	var slam_explosion = ExplosionScene.instantiate()
	slam_explosion.global_position = slam_position
	get_tree().get_current_scene().add_child(slam_explosion)

	var directions := [
		Vector2i( 1,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i( 0, -1),
		Vector2i( 1,  1), Vector2i( 1, -1),
		Vector2i(-1,  1), Vector2i(-1, -1),
	]

	var dmg_units := scaled_dmg(1.0)
	var dmg_struct := scaled_dmg(1.0)

	for dir in directions:
		var adj_tile = tile_pos + dir
		if not tilemap.is_within_bounds(adj_tile):
			continue

		var adj_unit = tilemap.get_unit_at_tile(adj_tile)
		var adj_structure: Node2D = null
		for struct_node in get_tree().get_nodes_in_group("structure"):
			if struct_node.tile_pos == adj_tile:
				adj_structure = struct_node
				break

		var explosion_position: Vector2
		if adj_unit:
			explosion_position = adj_unit.global_position
		elif adj_structure:
			explosion_position = adj_structure.global_position
		else:
			var tile_top_left2 = tilemap.to_global(tilemap.map_to_local(adj_tile))
			explosion_position = tile_top_left2

		var explosion_instance = ExplosionScene.instantiate()
		explosion_instance.global_position = explosion_position
		get_tree().get_current_scene().add_child(explosion_instance)

		if adj_unit and adj_unit != self:
			adj_unit.take_damage(dmg_units)
			adj_unit.shake()

		if adj_structure:
			if adj_structure.has_method("take_damage"):
				adj_structure.take_damage(dmg_struct)
			else:
				var anim_player = adj_structure.get_child(0)
				if anim_player and anim_player.has_method("play"):
					anim_player.play("demolished")
					adj_structure.modulate = Color(1,1,1,1)
				if adj_structure.has_method("demolish"):
					adj_structure.demolish()					

		await get_tree().create_timer(0.1).timeout

	has_attacked = true
	has_moved = true
	$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)

# 2) Panther – Mark & Pounce (local)
func mark_and_pounce(target_unit: Node) -> void:
	if not target_unit or not target_unit.is_inside_tree():
		return

	$AnimatedSprite2D.play("attack")
	$AudioStreamPlayer2D.play()

	var du = target_unit.tile_pos - tile_pos
	var dist = abs(du.x) + abs(du.y)
	if target_unit.is_player == is_player or dist > 3:
		return

	gain_xp(25)

	target_unit.set_meta("is_marked", true)
	print("Panther ", name, " marked ", target_unit.name)

	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap
	var start_world = global_position
	var target_world = tilemap.to_global(tilemap.map_to_local(target_unit.tile_pos))
	target_world.y += target_unit.Y_OFFSET

	if target_world.x > start_world.x:
		$AnimatedSprite2D.flip_h = false
	else:
		$AnimatedSprite2D.flip_h = true

	var tween = create_tween()
	var apex = Vector2(target_world.x, target_world.y - 32)
	tween.tween_property(self, "global_position", apex, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target_world, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(Callable(self, "_on_pounce_arrived").bind(target_unit))
	var apex_back = Vector2(start_world.x, start_world.y - 32)
	tween.tween_property(self, "global_position", apex_back, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", start_world, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(Callable(self, "_on_pounce_finished"))

func _on_pounce_arrived(target_unit: Node) -> void:
	var target_ref = weakref(target_unit)

	var hit_pos: Vector2
	if is_instance_valid(target_unit):
		hit_pos = target_unit.global_position
	else:
		hit_pos = global_position

	var explosion_instance = ExplosionScene.instantiate()
	explosion_instance.global_position = hit_pos
	get_tree().get_current_scene().add_child(explosion_instance)

	$AnimatedSprite2D.play("attack")
	await $AnimatedSprite2D.animation_finished

	var u = target_ref.get_ref()
	if is_instance_valid(u):
		var dmg_now = scaled_dmg(1.0)
		if u.has_method("take_damage"):
			u.take_damage(dmg_now)
		if u.has_method("flash_white"):
			u.flash_white()
		if u.has_method("shake"):
			u.shake()

	$AnimatedSprite2D.play("default")

func _on_pounce_finished() -> void:
	has_attacked = true
	$AnimatedSprite2D.self_modulate = Color(0.4,0.4,0.4,1)

# 3) Angel – Guardian Halo (local)
func guardian_halo(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap

	var delta = target_tile - tile_pos
	if abs(delta.x) + abs(delta.y) > 5:
		return

	var unit = tilemap.get_unit_at_tile(target_tile)
	if not is_instance_valid(unit):
		for u in get_tree().get_nodes_in_group("Units"):
			if u.tile_pos == target_tile:
				unit = u
				break

	if is_instance_valid(unit):
		unit.shield_duration = SHIELD_ROUNDS
		unit._shield_just_applied = true

		var halo = unit.get_node_or_null("Halo") as CPUParticles2D
		if not halo:
			halo = CPUParticles2D.new()
			halo.name = "Halo"
			unit.add_child(halo)
		halo.emitting = true

		$AudioStreamPlayer2D.play()
		$AnimatedSprite2D.play("attack")
		await $AnimatedSprite2D.animation_finished
		$AnimatedSprite2D.play("default")
	else:
		health = min(max_health, health + 20)
		update_health_bar()
		$AnimatedSprite2D.play("attack")
		await $AnimatedSprite2D.animation_finished
		$AnimatedSprite2D.play("default")

	has_moved = true
	has_attacked = true
	$AnimatedSprite2D.self_modulate = Color(0.4,0.4,0.4,1)

func _on_round_ended(_ended_team: int) -> void:
	_rounds_elapsed += 1
	# Tick shields once per full round for ALL units
	if shield_duration > 0:
		if _shield_just_applied:
			_shield_just_applied = false
		else:
			shield_duration -= 1
			if shield_duration <= 0:
				var halo := get_node_or_null("Halo") as CPUParticles2D
				if halo:
					halo.emitting = false

	# If Fortify is meant to last exactly one round, clear it here.
	# (Or give it a duration counter like shields if you want longer.)
	if is_fortified:
		is_fortified = false
		if _fortify_aura:
			_fortify_aura.queue_free()
			_fortify_aura = null

	# Passive Medic Aura (Support units only, alive)
	if medic_aura_enabled and unit_type == "Support" and health > 0:
		# show the “you’re in range” cue briefly
		_flash_medic_aura_hint()
		# then apply the actual round heal
		await _tick_medic_aura()
	
func _tick_medic_aura() -> void:
	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap == null: return

	for dx in range(-medic_aura_radius, medic_aura_radius + 1):
		for dy in range(-medic_aura_radius, medic_aura_radius + 1):
			if abs(dx) + abs(dy) > medic_aura_radius:
				continue  # Manhattan ring

			var t := tile_pos + Vector2i(dx, dy)
			if not tilemap.is_within_bounds(t): continue

			var ally = tilemap.get_unit_at_tile(t)
			if ally and ally.is_player == is_player and ally.health > 0:
				var before = ally.health
				ally.health = min(ally.max_health, ally.health + medic_aura_heal)
				if ally.health != before:
					if ally.has_method("update_health_bar"):
						ally.update_health_bar()
					if ally.has_method("spawn_text_popup"):
						ally.spawn_text_popup("+" + str(medic_aura_heal) + " HP", Color(0,1,0))

func _on_turn_ended(ended_team: int) -> void:
	var ended_is_player = (ended_team == TurnManager.Team.PLAYER)
	if ended_is_player == is_player:
		return

	if is_fortified:
		is_fortified = false
		if _fortify_aura:
			_fortify_aura.queue_free()
			_fortify_aura = null

func _ensure_fortify_aura_active() -> void:
	if _fortify_aura and is_instance_valid(_fortify_aura):
		if _fortify_aura is CPUParticles2D:
			(_fortify_aura as CPUParticles2D).emitting = true
		var ap := _fortify_aura.get_node_or_null("AnimationPlayer")
		if ap: ap.play("loop")
		var spr := _fortify_aura as AnimatedSprite2D
		if spr and spr.sprite_frames and spr.sprite_frames.has_animation("loop"):
			spr.play("loop")
		_place_aura_behind()
		return

	if fortify_effect_scene == null:
		return
	_fortify_aura = fortify_effect_scene.instantiate()
	_fortify_aura.name = "FortifyAura"
	add_child(_fortify_aura)                       # keep as child of the unit
	_place_aura_behind()                           # ⬅ ensure behind

	# kick visuals
	var particles := _fortify_aura as CPUParticles2D
	if particles: particles.emitting = true
	var ap2 := _fortify_aura.get_node_or_null("AnimationPlayer")
	if ap2: ap2.play("loop")
	var spr2 := _fortify_aura as AnimatedSprite2D
	if spr2 and spr2.sprite_frames and spr2.sprite_frames.has_animation("loop"):
		spr2.play("loop")


func _place_aura_behind() -> void:
	if _fortify_aura == null or not is_instance_valid(_fortify_aura):
		return
	var ci := _fortify_aura as CanvasItem
	if ci == null: return

	# Best: draw behind parent regardless of z/y-sort
	ci.show_behind_parent = true

	# Also set a relative z below the unit (helps when show_behind_parent isn’t honored)
	ci.z_as_relative = true
	ci.z_index = -1  # parent (the unit) stays at 0 by default; aura renders before it

	# Position and ordering niceties
	if _fortify_aura is Node2D:
		var n2 := _fortify_aura as Node2D
		n2.position = Vector2.ZERO

func _remove_fortify_aura() -> void:
	if _fortify_aura and is_instance_valid(_fortify_aura):
		# Try a quick fade if it’s a CanvasItem
		var ci := _fortify_aura as CanvasItem
		if ci:
			var tw := ci.create_tween()
			tw.tween_property(ci, "modulate:a", 0.0, 0.12)
			tw.tween_callback(func():
				if is_instance_valid(_fortify_aura):
					_fortify_aura.queue_free()
					_fortify_aura = null)
		else:
			_fortify_aura.queue_free()
			_fortify_aura = null

func apply_tile_effect():
	movement_range = base_movement_range
	attack_range   = base_attack_range
	defense        = base_defense

	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap
	var id = tilemap.get_cell_source_id(0, tile_pos)
	var effect = tilemap.tile_effects.get(id, null)
	if effect == null:
		return

	if effect.has("damage"):
		take_damage(effect["damage"])
		spawn_text_popup(str(effect["damage"]))

	if effect.has("heal"):
		health = min(max_health, health + effect["heal"])
		update_health_bar()
		spawn_text_popup("+" + str(effect["heal"]), Color(0,1,0))

	if effect.has("move_buff"):
		movement_range += effect["move_buff"]
		spawn_text_popup("+" + str(effect["move_buff"]) + " MOV")
	elif effect.has("move_penalty"):
		movement_range = max(0, movement_range - effect["move_penalty"])
		spawn_text_popup("-" + str(effect["move_penalty"]) + " MOV")

	if effect.has("slow"):
		attack_range = max(0, attack_range - effect["slow"])
		spawn_text_popup("-" + str(effect["slow"]) + " ATK")

	if effect.has("xp_gain"):
		gain_xp(effect["xp_gain"])

	if effect.has("slip"):
		var neighbours = tilemap.get_neighbors(tile_pos)
		if neighbours.size() > 0:
			var dest = neighbours[randi() % neighbours.size()]
			plan_move(dest)
			spawn_text_popup("-Slip!", Color(0.6, 0.8, 1))
			await get_tree().create_timer(0.5).timeout
			attack_range = max(0, attack_range - 2)
			spawn_text_popup("-2 ATK")
		return

# 4) Cannon – High-Arcing Shot (local)
func high_arcing_shot(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap
	var du = target_tile - tile_pos
	var dist = abs(du.x) + abs(du.y)
	if dist > 5:
		return

	tilemap.input_locked = true
	gain_xp(25)

	$AudioStreamPlayer2D.stream = missile_sfx
	$AudioStreamPlayer2D.play()

	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("attack")

	var start_world: Vector2 = global_position
	var end_world: Vector2 = tilemap.to_global(tilemap.map_to_local(target_tile))
	end_world.y += Y_OFFSET

	var point_count := 64
	var points := PackedVector2Array()
	for i in range(point_count + 1):
		var t = float(i) / float(point_count)
		var x = lerp(start_world.x, end_world.x, t)
		var base_y = lerp(start_world.y, end_world.y, t)
		var height_offset := -100.0 * sin(PI * t)
		var y = base_y + height_offset
		points.append(Vector2(x, y))

	var line := Line2D.new()
	line.width = 1
	line.z_index = 4000
	line.default_color = Color(1, 0.8, 0.2)
	get_tree().get_current_scene().add_child(line)

	# NEW: track this arc so it gets auto-cleaned (e.g., if the unit dies mid-shot)
	_register_arc_line(line)

	var interval = 2.0 / float(point_count)
	for i in range(points.size()):
		# If we were cleaned up (e.g. unit died), bail early.
		if not is_instance_valid(line):
			break
		line.add_point(points[i])
		await get_tree().create_timer(interval).timeout

	# Cleanup: free and remove from our tracking array if still around
	if is_instance_valid(line):
		line.queue_free()
	_active_arc_lines.erase(line)

	var dmg_center = scaled_dmg(1.0)
	var dmg_splash = scaled_dmg(0.8)
	var ExplosionScene := preload("res://Scenes/VFX/Explosion.tscn")

	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var tile := Vector2i(target_tile.x + dx, target_tile.y + dy)
			if not tilemap.is_within_bounds(tile):
				continue

			var damage_val: int
			if dx == 0 and dy == 0:
				damage_val = dmg_center
			else:
				damage_val = dmg_splash

			var u = tilemap.get_unit_at_tile(tile)
			if u:
				u.take_damage(damage_val)
				u.flash_white()
				u.shake()

			var st = tilemap.get_structure_at_tile(tile)
			if st:
				var st_sprite = st.get_node_or_null("AnimatedSprite2D")
				if st_sprite:
					st_sprite.play("demolished")
					st_sprite.get_parent().modulate = Color(1,1,1,1)
				if st.has_method("demolish"):
					st.demolish()

			var vfx := ExplosionScene.instantiate()
			vfx.global_position = tilemap.to_global(tilemap.map_to_local(tile))
			get_tree().get_current_scene().add_child(vfx)
			await get_tree().create_timer(0.1).timeout

	has_attacked = true
	has_moved = true
	if sprite:
		sprite.self_modulate = Color(0.4,0.4,0.4,1)
	$AudioStreamPlayer2D.stream = attack_sfx
	if sprite:
		sprite.play("default")

	tilemap.input_locked = false

# 5) Multi Turret – Suppressive Fire (auto-target within ability range)
func suppressive_fire(_unused: Vector2i) -> void:
	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap == null:
		return

	# 1) Read range from GameData (fallbacks if not present)
	var sup_range := 5
	if Engine.has_singleton("GameData"):
		var GD = Engine.get_singleton("GameData")
		if GD != null and GD.has_method("get") and typeof(GD.get("ability_ranges")) == TYPE_DICTIONARY:
			var ar: Dictionary = GD.get("ability_ranges")
			if ar.has("Suppressive Fire"):
				sup_range = int(ar["Suppressive Fire"])

	if sup_range <= 0:
		sup_range = 5  # final safety

	# 2) Collect enemy units in range (Manhattan distance, same as your pathing/attack rules)
	var targets: Array[Dictionary] = []  # [{unit: Node2D, tile: Vector2i}]
	for u in get_tree().get_nodes_in_group("Units"):
		if not is_instance_valid(u): continue
		if u.is_player == is_player: continue          # only enemies
		if u.health <= 0: continue
		# Use live tile with Y_OFFSET compensation to avoid stale positions
		var tile := tilemap.local_to_map(tilemap.to_local(u.global_position - Vector2(0, u.Y_OFFSET)))
		var dist = abs(tile.x - tile_pos.x) + abs(tile.y - tile_pos.y)
		if dist <= sup_range:
			targets.append({"unit": u, "tile": tile})

	# 3) Fire a projectile toward each target tile (slight stagger for style)
	gain_xp(25)
	_fire_projectiles_to_targets(targets)

	has_attacked = true
	has_moved   = true
	$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)

# Helper: staggered multi-shot at specific target tiles (from current positions)
func _fire_projectiles_to_targets(targets: Array) -> void:
	var delay_step := 0.05
	for i in range(targets.size()):
		var info: Dictionary = targets[i]
		var tile: Vector2i = info["tile"]
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = 0.01 + i * delay_step
		add_child(t)
		t.start()
		t.connect("timeout", Callable(self, "_on_fire_timer_timeout").bind(tile))

func _on_fire_timer_timeout(target_tile: Vector2i) -> void:
	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap == null:
		return

	var start_pos := global_position
	var end_pos := tilemap.to_global(tilemap.map_to_local(target_tile))
	end_pos.y += Y_OFFSET

	var proj_scene := preload("res://Scenes/Projectile_Scenes/Projectile.tscn")
	var proj = proj_scene.instantiate()
	get_tree().get_current_scene().add_child(proj)
	proj.set_target(start_pos, end_pos)
	proj.connect("reached_target", Callable(self, "_on_projectile_impact").bind(target_tile))

func _on_projectile_impact(target_tile: Vector2i) -> void:
	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap == null:
		return

	var explosion_scene := preload("res://Scenes/VFX/Explosion.tscn")
	var vfx = explosion_scene.instantiate()
	vfx.global_position = tilemap.to_global(tilemap.map_to_local(target_tile))
	get_tree().get_current_scene().add_child(vfx)

	# Damage unit if enemy is still there
	var enemy = tilemap.get_unit_at_tile(target_tile)
	if enemy and enemy.is_player != is_player:
		var dmg_now = scaled_dmg(1.0)
		enemy.take_damage(dmg_now)
		enemy.flash_white()
		enemy.is_suppressed = true
		print("Multi Turret suppressed ", enemy.name, " at ", target_tile)

	# Damage structures as before
	var st = tilemap.get_structure_at_tile(target_tile)
	if st:
		if st.has_method("take_damage"):
			st.take_damage(scaled_dmg(1.0))
		else:
			var st_sprite = st.get_node_or_null("AnimatedSprite2D")
			if st_sprite:
				st_sprite.play("demolished")
				st.modulate = Color(1, 1, 1, 1)
				if st.has_method("demolish"):
					st.demolish()

# 6) Brute – Fortify (LOCAL SHOCKS FROM THE UNIT)
const SHOCK_WIDTH  := 1               # Line2D width
const SHOCK_COLOR  := Color(0.6, 0.95, 1.0, 1.0)  # electric cyan
# At top (keep the preload but switch to OGG if you can)
const ELECTRIC_SFX := preload("res://Audio/SFX/electric.mp3") # <— prefer ogg on Web

var _zap_player: AudioStreamPlayer2D

func _ensure_zap_player() -> void:
	if _zap_player and is_instance_valid(_zap_player):
		return
	_zap_player = AudioStreamPlayer2D.new()
	_zap_player.bus = "SFX"
	_zap_player.stream = ELECTRIC_SFX
	# Keep polyphony sane on Web by reusing a single player
	add_child(_zap_player)

# ─────────────────────────────────────────────────────────────────────────────
# Feature detection
func _is_web() -> bool:
	return OS.has_feature("web") or OS.has_feature("HTML5")

# ─────────────────────────────────────────────────────────────────────────────
# Ability config lookups (kept local to this script)
func _get_fortify_range(default_val: int = 5) -> int:
	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap == null:
		return default_val

	var range := default_val

	# Try TurnManager.ability_ranges["Fortify"]
	var tm := get_node_or_null("/root/TurnManager")
	if tm and tm.has_method("get") and typeof(tm.get("ability_ranges")) == TYPE_DICTIONARY:
		var ar: Dictionary = tm.get("ability_ranges")
		if ar.has("Fortify"):
			range = int(ar["Fortify"])

	# Fallback: tilemap.ability_ranges["Fortify"]
	if range <= 0 and typeof(tilemap.ability_ranges) == TYPE_DICTIONARY and tilemap.ability_ranges.has("Fortify"):
		range = int(tilemap.ability_ranges["Fortify"])

	if range <= 0:
		range = default_val
	return range

func _enemies_in_range(range_tiles: int) -> Array:
	var results: Array = []
	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap == null:
		return results

	for u in get_tree().get_nodes_in_group("Units"):
		if not is_instance_valid(u):
			continue
		if u.is_player == is_player:
			continue
		if u.health <= 0:
			continue

		# sample current world position (safer with offsets/motion)
		var t := tilemap.local_to_map(tilemap.to_local(u.global_position - Vector2(0, u.Y_OFFSET)))
		if not tilemap.is_within_bounds(t):
			continue
		var dist = abs(t.x - tile_pos.x) + abs(t.y - tile_pos.y)
		if dist <= range_tiles:
			results.append(u)
	return results

# ─────────────────────────────────────────────────────────────────────────────
# 8) Foritfy
func fortify() -> void:
	is_fortified = true
	gain_xp(25)
	_ensure_fortify_aura_active()

	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap:
		tilemap.input_locked = true

	var range := _get_fortify_range(5)
	var targets := _enemies_in_range(range)

	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")

	var dmg_each = max(1, self.damage)
	var travel_time := 2.0
	var arc_height := 160.0

	var launch_gap: float
	if _is_web():
		launch_gap = 0.06
	else:
		launch_gap = 0.10

	# reset pending & finishing flags
	_pending_fortify_beams = 0
	_fortify_finishing = false

	for i in range(targets.size()):
		var u = targets[i]
		if not is_instance_valid(u): 
			continue
		if u.health <= 0: 
			continue

		_pending_fortify_beams += 1
		_launch_fortify_beam(u, dmg_each, travel_time, arc_height, Color(1,0,0,1), i * launch_gap)

	# if nothing actually launched (all targets invalid), finish immediately
	if _pending_fortify_beams == 0:
		_finish_fortify(tilemap, sprite)

func _launch_fortify_beam(u: Node, dmg_each: int, travel_time: float, arc_height: float, col: Color, launch_delay: float) -> void:
	# optional stagger before launching this particular beam
	if launch_delay > 0.0:
		await get_tree().create_timer(launch_delay).timeout

	# re-validate right before launch
	if not is_instance_valid(u) or u.health <= 0:
		_on_fortify_beam_done()
		return

	# ── start from THIS UNIT (slightly above its sprite)
	var start_pos := global_position + Vector2(0, Y_OFFSET)

	# end point at target (slightly above sprite center)
	var end_pos = u.global_position

	# draw the beam prefab (plays its own SFX) and let it “fly” for travel_time
	_spawn_laser_beam(start_pos, end_pos, travel_time, arc_height, col)

	# when the beam "arrives", explode + apply damage, then mark done
	var t := get_tree().create_timer(travel_time)
	t.timeout.connect(func():
		if ExplosionScene != null:
			var vfx := ExplosionScene.instantiate()
			vfx.global_position = end_pos
			get_tree().get_current_scene().add_child(vfx)

		if is_instance_valid(u) and u.health > 0:
			u.take_damage(dmg_each)
			if u.has_method("flash_white"): u.flash_white()
			if u.has_method("shake"): u.shake()

		_on_fortify_beam_done()
	)

func _on_fortify_beam_done() -> void:
	_pending_fortify_beams = max(0, _pending_fortify_beams - 1)
	if _pending_fortify_beams == 0 and not _fortify_finishing:
		_fortify_finishing = true
		var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
		var sprite: AnimatedSprite2D = $AnimatedSprite2D
		_finish_fortify(tilemap, sprite)

func _finish_fortify(tilemap: TileMap, sprite: AnimatedSprite2D) -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("default"):
		sprite.play("default")

	if tilemap:
		tilemap.input_locked = false

	has_attacked = true
	has_moved   = true
	$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)

func _spawn_laser_beam(from_pos: Vector2, to_pos: Vector2, travel_time: float, arc_height: float, color: Color) -> void:
	if LaserBeamScene == null:
		return

	var beam := LaserBeamScene.instantiate()
	get_tree().get_current_scene().add_child(beam)

	# grab parts
	var line: Line2D = beam.get_node_or_null("Line2D")
	if line == null:
		beam.queue_free()
		return
	line.clear_points()
	line.width = 1
	line.default_color = color
	line.z_index = 5000

	var sfx: AudioStreamPlayer2D = beam.get_node_or_null("SFX")
	if sfx:
		sfx.global_position = from_pos
		sfx.pitch_scale = 1.0
		sfx.play()

	# quadratic bezier control
	var mid := (from_pos + to_pos) * 0.5
	var ctrl := mid
	ctrl.y -= arc_height

	# progressive draw along the path
	var steps := 64
	var step_time := travel_time / float(steps)

	var i := 0
	while i <= steps:
		var t := float(i) / float(steps)
		var one := 1.0 - t
		var p := one * one * from_pos + 2.0 * one * t * ctrl + t * t * to_pos
		line.add_point(p)
		await get_tree().create_timer(step_time).timeout
		i += 1

	# fade and clean up
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(beam):
			beam.queue_free())

func _draw_laser_beam(from_pos: Vector2, to_pos: Vector2, lifetime: float = 2) -> void:
	var line := Line2D.new()
	line.width = 1
	line.z_index = 5000
	line.default_color = Color(1, 0, 0, 1)  # red
	get_tree().get_current_scene().add_child(line)

	# --- curve shape ---
	var arc_height := 80.0                  # raise/lower the arc
	var mid := (from_pos + to_pos) * 0.5
	var ctrl := mid
	ctrl.y -= arc_height                     # apex above the middle

	# --- draw progressively along the curve ---
	var point_count := 48
	var draw_time := 0.12                    # how long the “tracer” takes to grow
	var step := draw_time / float(point_count)

	for i in range(point_count + 1):
		var t := float(i) / float(point_count)
		# Quadratic Bezier: B(t) = (1-t)^2*P0 + 2(1-t)t*C + t^2*P1
		var one_minus := 1.0 - t
		var p := one_minus * one_minus * from_pos \
			+ 2.0 * one_minus * t * ctrl \
			+ t * t * to_pos
		line.add_point(p)
		await get_tree().create_timer(step).timeout

	# --- fade out and clean up ---
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, lifetime).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(line):
			line.queue_free()
	)


# 7) Helicopter – Airlift (local)
func airlift_pick(ally: Node) -> void:
	if ally == null:
		return
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	queued_airlift_origin = tile_pos

	# find a walkable tile adjacent to the ally
	var ally_tile = ally.tile_pos
	var target_adjacent = Vector2i(-1, -1)
	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var candidate = ally_tile + dir
		if tilemap.is_within_bounds(candidate) and tilemap._is_tile_walkable(candidate) and not tilemap.is_tile_occupied(candidate):
			target_adjacent = candidate
			break
	if target_adjacent == Vector2i(-1, -1):
		push_warning("Helicopter cannot find adjacent tile to pick up ally.")
		return

	# move heli to that adjacent tile
	var path_to_ally = tilemap.get_weighted_path(tile_pos, target_adjacent)
	for step in path_to_ally:
		await move_to(step)
		tilemap.update_astar_grid()

	# teleport & hide the ally onto the helicopter’s tile
	ally.tile_pos = tile_pos
	ally.global_position = tilemap.to_global(tilemap.map_to_local(tile_pos)) + Vector2(0, ally.Y_OFFSET)
	ally.visible = false
	queued_airlift_unit = ally

	tilemap.update_astar_grid()

	# move helicopter BACK to its original origin
	var path_back = tilemap.get_weighted_path(tile_pos, queued_airlift_origin)
	for step2 in path_back:
		await move_to(step2)
		tilemap.update_astar_grid()

	has_moved = true
	has_attacked = false
	$AnimatedSprite2D.self_modulate = Color(0.4,0.4,0.4,1)

func airlift_drop(drop_tile: Vector2i) -> void:
	if queued_airlift_unit == null:
		return

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var carried = queued_airlift_unit

	# If drop_tile itself is not empty, pick an adjacent tile automatically
	var final_drop = _get_adjacent_tile(tilemap, drop_tile)
	if final_drop == Vector2i(-1, -1):
		push_warning("No valid adjacent tile to actually drop the ally.")
		return

	# move helicopter from queued_airlift_origin to drop_tile
	var path_to_drop = tilemap.get_weighted_path(queued_airlift_origin, drop_tile)
	for step in path_to_drop:
		await move_to(step)
		tilemap.update_astar_grid()

	# unhide & place the ally
	carried.tile_pos = final_drop
	carried.global_position = tilemap.to_global(tilemap.map_to_local(final_drop)) + Vector2(0, carried.Y_OFFSET)
	carried.visible = true

	queued_airlift_unit = null

	var vfx = ExplosionScene.instantiate()
	vfx.global_position = tilemap.to_global(tilemap.map_to_local(final_drop))
	get_tree().get_current_scene().add_child(vfx)

	tilemap.update_astar_grid()

	has_attacked = true
	has_moved = true
	$AnimatedSprite2D.self_modulate = Color(0.4,0.4,0.4,1)

func _get_adjacent_tile(tilemap: TileMap, base: Vector2i) -> Vector2i:
	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var n = base + dir
		if tilemap.is_within_bounds(n) and tilemap._is_tile_walkable(n) and not tilemap.is_tile_occupied(n):
			return n
	return Vector2i(-1, -1)

#Heavy Rain
func spider_blast(target_tile: Vector2i) -> void:
	var tilemap: TileMap = get_tree().get_current_scene().get_node("TileMap") as TileMap
	var du: Vector2i = target_tile - tile_pos
	var dist: int = abs(du.x) + abs(du.y)
	if dist > 5:
		return

	tilemap.input_locked = true
	gain_xp(25)

	$AudioStreamPlayer2D.stream = missile_sfx
	$AudioStreamPlayer2D.play()
	var sprite: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D
	if sprite:
		sprite.play("attack")

	var ExplosionScene: PackedScene = preload("res://Scenes/VFX/Explosion.tscn")
	var point_count: int = 64
	var step_time: float = 2.0 / float(point_count)
	var arc_height: float = 100.0
	var trail_color: Color = Color(0.85, 0.85, 0.85, 1.0)
	var launch_interval: float = 0.12

	var pattern: Array[Vector2i] = [
		Vector2i( 0,  0),
		Vector2i(-1, -1), Vector2i( 0, -1), Vector2i( 1, -1),
		Vector2i(-1,  0),                   Vector2i( 1,  0),
		Vector2i(-1,  1), Vector2i( 0,  1), Vector2i( 1,  1)
	]

	var dmg_center = scaled_dmg(1.0)
	var dmg_splash = scaled_dmg(0.8)

	var launched := 0
	var completed := 0

	var on_arc := func() -> void:
		completed += 1
	self.spider_arc_done.connect(on_arc)

	var _cleanup := func() -> void:
		if sprite:
			sprite.self_modulate = Color(0.4, 0.4, 0.4, 1.0)
			sprite.play("default")
		$AudioStreamPlayer2D.stream = attack_sfx
		if is_instance_valid(tilemap):
			tilemap.input_locked = false
		if self.spider_arc_done.is_connected(on_arc):
			self.spider_arc_done.disconnect(on_arc)

	for i in range(pattern.size()):
		var offset: Vector2i = pattern[i]
		var tile: Vector2i = target_tile + offset
		if not tilemap.is_within_bounds(tile):
			continue

		var damage_val = dmg_splash
		if offset == Vector2i.ZERO:
			damage_val = dmg_center

		call_deferred("_fire_arc_to_tile_impl", tile, damage_val, point_count, step_time, arc_height, trail_color, ExplosionScene)
		launched += 1
		if i < pattern.size() - 1:
			await get_tree().create_timer(launch_interval).timeout

	if launched == 0:
		_cleanup.call()
		return

	var timeout_ms := 500
	var start_ms := Time.get_ticks_msec()
	var tick := 0.1
	while completed < launched and (Time.get_ticks_msec() - start_ms) < timeout_ms:
		await get_tree().create_timer(tick).timeout

	has_attacked = true
	has_moved = true
	_cleanup.call()

func _fire_arc_to_tile_impl(tile: Vector2i, damage_val: int, point_count: int, step_time: float, arc_height: float, trail_color: Color, ExplosionScene: PackedScene) -> void:
	var tilemap: TileMap = get_tree().get_current_scene().get_node("TileMap") as TileMap

	var start_world: Vector2 = global_position
	var end_world: Vector2 = tilemap.to_global(tilemap.map_to_local(tile))
	end_world.y += Y_OFFSET

	var points: PackedVector2Array = PackedVector2Array()
	for i in range(point_count + 1):
		var t: float = float(i) / float(point_count)
		var x: float = lerp(start_world.x, end_world.x, t)
		var base_y: float = lerp(start_world.y, end_world.y, t)
		var height_offset: float = -arc_height * sin(PI * t)
		points.append(Vector2(x, base_y + height_offset))

	var line: Line2D = Line2D.new()
	line.width = 1
	line.z_index = 4000
	line.default_color = trail_color
	get_tree().get_current_scene().add_child(line)

	for i in range(points.size()):
		line.add_point(points[i])
		await get_tree().create_timer(step_time).timeout

	if is_instance_valid(line):
		line.queue_free()

	var u = tilemap.get_unit_at_tile(tile)
	if u:
		u.take_damage(damage_val)
		u.flash_white()
		u.shake()

	var st = tilemap.get_structure_at_tile(tile)
	if st:
		var st_sprite: AnimatedSprite2D = st.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if st_sprite:
			st_sprite.play("demolished")
			st_sprite.get_parent().modulate = Color(1, 1, 1, 1)
			if st.has_method("demolish"):
				st.demolish()	
	var vfx = ExplosionScene.instantiate()
	vfx.global_position = tilemap.to_global(tilemap.map_to_local(tile))
	get_tree().get_current_scene().add_child(vfx)

	emit_signal("spider_arc_done")

# 9) Spider – Thread Attack (local)
func thread_attack(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var start_tile: Vector2i = tile_pos
	var line_tiles: Array = TurnManager.manhattan_line(start_tile, target_tile)
	var offset: Vector2i = Vector2i(0, -3)
	var global_path: Array = []
	for tile in line_tiles:
		global_path.append(tilemap.to_global(tilemap.map_to_local(tile + offset)))
	for i in range(global_path.size()):
		var p = global_path[i]
		p.y -= 24
		global_path[i] = p
	var missile_scene = preload("res://Prefabs/ThreadAttackMissile.tscn")
	var missile = missile_scene.instantiate()
	get_tree().get_current_scene().add_child(missile)
	missile.get_child(0).emitting = true
	missile.global_position = global_path[0]
	missile.follow_path(global_path)
	missile.connect("reached_target", Callable(self, "_on_thread_attack_reached").bind(target_tile))
	has_attacked = true
	has_moved = true

	gain_xp(25)

	var sprite = get_node("AnimatedSprite2D")
	if sprite:
		sprite.self_modulate = Color(0.4,0.4,0.4,1)

func _on_thread_attack_reached(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return
	if not tilemap.is_within_bounds(target_tile):
		print("Thread Attack: impact out of bounds; skipping explosions.")
		return
	spawn_explosions_at_tile(target_tile)
	print("Thread Attack exploded at tile: ", target_tile)

# 10) Lightning Surge (local)
func lightning_surge(target_tile: Vector2i) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	var target_pos: Vector2 = tilemap.to_global(tilemap.map_to_local(target_tile)) + Vector2(0, Y_OFFSET)
	target_pos.y -= 8
	var missile_scene = preload("res://Prefabs/LightningSurgeMissile.tscn")
	var missile = missile_scene.instantiate()
	get_tree().get_current_scene().add_child(missile)
	tilemap.play_attack_sound(global_position)
	missile.global_position = global_position
	missile.set_target(global_position, target_pos)
	print("Lightning Surge toward ", target_tile)
	has_attacked = true
	has_moved = true
	var sprite := get_node("AnimatedSprite2D")
	if sprite:
		sprite.self_modulate = Color(0.4,0.4,0.4,1)
	missile.connect("reached_target", Callable(self, "on_lightning_surge_reached").bind(target_tile))

func on_lightning_surge_reached(target_tile: Vector2i) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")

	var du = target_tile - tile_pos
	var dist = abs(du.x) + abs(du.y)
	if dist > 5:
		return

	gain_xp(25)

	for x in range(-1, 2):
		for y in range(-1, 2):
			var tile = target_tile + Vector2i(x, y)
			var explosion = explosion_scene.instantiate()
			explosion.global_position = tilemap.to_global(tilemap.map_to_local(tile))
			get_tree().get_current_scene().add_child(explosion)
			var dmg: int
			if x == 0 and y == 0:
				dmg = 50
			else:
				dmg = 30
			var enemy_unit = tilemap.get_unit_at_tile(tile)
			if enemy_unit and not enemy_unit.is_player:
				enemy_unit.take_damage(dmg)
				enemy_unit.flash_white()
				enemy_unit.shake()
				print("Lightning Surge: ", enemy_unit.name, "took", dmg, "damage at tile", tile)
	print("Lightning Surge exploded at tile:", target_tile)

# Spawn 3×3 explosions around a tile (used by Thread Attack) — on-map only
func spawn_explosions_at_tile(target_tile: Vector2i) -> void:
	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap == null:
		return
	if not tilemap.is_within_bounds(target_tile):
		print("Thread Attack: center out of bounds; skipping explosions.")
		return

	var explosion_scene: PackedScene = preload("res://Scenes/VFX/Explosion.tscn")
	var dmg_center := scaled_dmg(1.0)
	var dmg_splash := scaled_dmg(0.8)

	for x in range(-1, 2):
		for y in range(-1, 2):
			var tile := target_tile + Vector2i(x, y)
			if not tilemap.is_within_bounds(tile):
				continue  # ← skip off-map tiles

			var explosion = explosion_scene.instantiate()
			explosion.global_position = tilemap.to_global(tilemap.map_to_local(tile))
			get_tree().get_current_scene().add_child(explosion)

			var dmg: int
			if x == 0 and y == 0:
				dmg = dmg_center
			else:
				dmg = dmg_splash

			var unit = tilemap.get_unit_at_tile(tile)
			if unit:
				unit.take_damage(dmg)
				unit.flash_white()
				unit.shake()

		# small pacing delay per ring-column (optional)
		await get_tree().create_timer(0.2).timeout

	print("Explosions spawned at and around tile: ", target_tile)

# Compute push direction for melee if needed
func _compute_push_direction(target: Node) -> Vector2i:
	var delta = target.tile_pos - tile_pos
	if abs(delta.x) > abs(delta.y):
		return Vector2i(sign(delta.x), 0)
	else:
		return Vector2i(0, sign(delta.y))

# Original “core” abilities
func critical_strike(target_tile: Vector2i) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	var target_pos = tilemap.to_global(tilemap.map_to_local(target_tile)) + Vector2(0, Y_OFFSET)
	target_pos.y -= 8
	var missile_scene = preload("res://Prefabs/CriticalStrikeMissile.tscn")
	var missile = missile_scene.instantiate()
	get_tree().get_current_scene().add_child(missile)
	missile.global_position = global_position
	missile.set_target(global_position, target_pos)
	print("Unit ", name, " launched Critical Strike missile toward ", target_tile)
	has_attacked = true
	has_moved = true
	get_child(0).self_modulate = Color(0.4,0.4,0.4,1)

func rapid_fire(target_tile: Vector2i) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	for x in range(-1, 2):
		for y in range(-1, 2):
			var this_tile = target_tile + Vector2i(x, y)
			var target_pos = tilemap.to_global(tilemap.map_to_local(this_tile))
			var projectile_scene = preload("res://Scenes/Projectile_Scenes/Projectile.tscn")
			var projectile = projectile_scene.instantiate()
			get_tree().get_current_scene().add_child(projectile)
			projectile.global_position = global_position
			projectile.set_target(global_position, target_pos)
			print("Rapid Fire projectile launched toward tile: ", this_tile)
			await get_tree().create_timer(0.1).timeout
	has_attacked = true
	has_moved = true
	get_child(0).self_modulate = Color(0.4,0.4,0.4,1)
	print("Rapid Fire activated by unit: ", name)

func healing_wave(target_tile: Vector2i) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	var target_unit = tilemap.get_unit_at_tile(target_tile)
	if target_unit:
		target_unit.health += 50
		if target_unit.health > target_unit.max_health:
			target_unit.health = target_unit.max_health
		target_unit.update_health_bar()
		print("Healing Wave: ", target_unit.name, " healed. Current HP: ", target_unit.health)
		if target_unit.has_method("apply_level_up_material"):
			target_unit.apply_level_up_material()
		if target_unit.has_method("play_level_up_sound"):
			target_unit.play_level_up_sound()
		has_attacked = true
		has_moved = true
		get_child(0).self_modulate = Color(0.4,0.4,0.4,1)
	else:
		print("No unit on tile: ", target_tile, "; no healing.")

func overcharge_attack(target_tile: Vector2i) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	var center_tile = target_tile
	var overcharge_effect_scene = preload("res://Scenes/VFX/Explosion.tscn")
	if overcharge_effect_scene:
		var effect = overcharge_effect_scene.instantiate()
		effect.global_position = tilemap.to_global(tilemap.map_to_local(center_tile))
		get_tree().get_current_scene().add_child(effect)
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("attack")
	for x in range(-1, 2):
		for y in range(-1, 2):
			var tile = center_tile + Vector2i(x, y)
			var dmg: int = 25
			var enemy_unit = tilemap.get_unit_at_tile(tile)
			if enemy_unit and not enemy_unit.is_player:
				enemy_unit.take_damage(dmg)
				enemy_unit.flash_white()
				enemy_unit.shake()
				tilemap.play_attack_sound(global_position)
				print("Overcharge: ", enemy_unit.name, " took ", dmg, " at ", tile)
				await get_tree().create_timer(0.2).timeout
	has_attacked = true
	has_moved = true
	get_child(0).self_modulate = Color(0.4,0.4,0.4,1)
	print("Overcharge activated by ", name, " at ", center_tile)
	if sprite:
		sprite.play("default")

func explosive_rounds(target_tile: Vector2i) -> void:
	var tilemap = get_node("/root/BattleGrid/TileMap")
	var target_pos = tilemap.to_global(tilemap.map_to_local(target_tile)) + Vector2(0, Y_OFFSET)
	target_pos.y -= 8
	var missile_scene = preload("res://Scenes/Projectile_Scenes/Grenade.tscn")
	var missile = missile_scene.instantiate()
	get_tree().get_current_scene().add_child(missile)
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("attack")
	missile.global_position = global_position
	missile.set_target(global_position, target_pos)
	print("Unit ", name, " launched Explosive Rounds at ", target_tile)
	has_attacked = true
	has_moved = true
	get_child(0).self_modulate = Color(0.4,0.4,0.4,1)
	if sprite:
		sprite.play("default")

func play_heal_sound():
	var sfx = preload("res://Audio/SFX/powerUp.wav")
	var player = AudioStreamPlayer.new()
	player.stream = sfx
	add_child(player)
	player.play()

func play_aura_sound():
	var sfx = preload("res://Audio/SFX/aura.wav")
	var player = AudioStreamPlayer.new()
	player.stream = sfx
	player.volume_db = -6  # ≈ 50% volume
	add_child(player)
	player.play()

func spawn_floating_text(amount: int):
	var floating_text_scene = preload("res://Scenes/VFX/floating_text.tscn")
	var text_instance = floating_text_scene.instantiate()
	text_instance.position = global_position
	text_instance.set_damage(amount)
	get_tree().get_current_scene().add_child(text_instance)

func spawn_text_popup(message: String, color: Color = Color.WHITE):
	var popup_scene = preload("res://Scenes/VFX/popup_text.tscn")
	var popup = popup_scene.instantiate()
	popup.position = global_position + Vector2(0, -64)
	popup.set_text(message, color)
	get_tree().get_current_scene().add_child(popup)

func apply_upgrade(upgrade: String) -> void:
	match upgrade:
		"hp_boost":
			max_health += 20
			health = max_health
			update_health_bar()
		"damage_boost":
			damage += 10
		"range_boost":
			attack_range += 1
			base_attack_range += 1
		"move_boost":
			movement_range += 1
			base_movement_range += 1
		_:
			print("⚠️ Unknown upgrade:", upgrade)

func get_mek_portrait() -> Texture:
	return mek_portrait

func _on_movement_finished() -> void:
	# only apply when the tile actually changed
	if tile_pos != prev_tile_pos:
		apply_tile_effect()
		prev_tile_pos = tile_pos

func _assign_special_for_unit(u: Node2D) -> void:
	var uid = u.unit_id
	var existing := GameData.get_unit_special(uid)
	if typeof(existing) == TYPE_STRING and existing != "":
		return

	var special := ""
	if u.has_variable("default_special") and u.default_special != "":
		special = u.default_special
	else:
		# fallback: first ability in list
		if GameData.available_abilities.size() > 0:
			special = GameData.available_abilities[0]

	GameData.set_unit_special(uid, special)
	print("⭐ Assigned special '%s' → unit_id:%d" % [special, uid])

# Handy scaler so we always pull from the live damage stat
func scaled_dmg(mult: float = 1.0) -> int:
	return int(round(max(1, damage * mult)))

var _aura_hint_nodes: Array = []

# Call this from _on_round_ended (you already do)
func _flash_medic_aura_hint() -> void:
	var tilemap := get_tree().get_current_scene().get_node("TileMap") as TileMap
	if tilemap == null:
		return

	# Optional ring
	if tilemap.has_method("_highlight_range"):
		tilemap._highlight_range(tile_pos, medic_aura_radius, 5)

	# Pulse the SUPPORT (caster) faster
	_pulse_green(self, medic_aura_hint_duration / 2)  # ~3x faster

	# Pulse allies at normal speed
	for ally in _collect_allies_in_aura(tilemap):
		if ally != self:  # avoid double-pulsing the caster
			_pulse_green(ally, medic_aura_hint_duration)

	await get_tree().create_timer(medic_aura_hint_duration).timeout
	if tilemap and tilemap.has_method("_clear_highlights"):
		tilemap._clear_highlights()

func _collect_allies_in_aura(tilemap: TileMap) -> Array:
	var found: Array = []
	for dx in range(-medic_aura_radius, medic_aura_radius + 1):
		for dy in range(-medic_aura_radius, medic_aura_radius + 1):
			if abs(dx) + abs(dy) > medic_aura_radius:
				continue
			var t := tile_pos + Vector2i(dx, dy)
			if not tilemap.is_within_bounds(t):
				continue
			var ally = tilemap.get_unit_at_tile(t)
			if ally and ally.is_player == is_player and ally.health > 0:
				found.append(ally)
	return found

func _pulse_green(ally: Node, duration: float = 0.6) -> void:
	if ally == null or not ally.is_inside_tree():
		return

	var sprite := ally.get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		sprite = ally as CanvasItem
	if sprite == null:
		return

	# Prevent overlapping pulses
	if sprite.has_meta("aura_pulsing") and sprite.get_meta("aura_pulsing") == true:
		return
	sprite.set_meta("aura_pulsing", true)

	# --- Play your existing audio once per ally (with a short cooldown) ---
	# Skip playing SFX during the very first round-end (match start)
	if _rounds_elapsed > 1 and not ally.has_meta("aura_chime_cd"):
		if ally.has_method("play_aura_sound"):
			ally.play_aura_sound()
		elif has_method("play_aura_sound"):
			play_aura_sound()
		ally.set_meta("aura_chime_cd", true)

		# cooldown timer stays the same
		var timer := get_tree().create_timer(0.4)
		timer.timeout.connect(func():
			if is_instance_valid(ally) and ally.has_meta("aura_chime_cd"):
				ally.remove_meta("aura_chime_cd")
		)

	var original: Color = sprite.self_modulate
	sprite.set_meta("aura_original_mod", original)

	# Dark → light green values (fast, high-contrast)
	var dark_green := Color(0.0, 0.3, 0.0, original.a)
	var light_green := Color(0.7, 1.0, 0.7, original.a)

	# Very quick cycle steps
	var wave_time = max(0.05, duration * 0.25)

	var tw := sprite.create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 2 quick pulses
	tw.tween_property(sprite, "self_modulate", light_green, wave_time)
	tw.tween_property(sprite, "self_modulate", dark_green,  wave_time)
	tw.tween_property(sprite, "self_modulate", light_green, wave_time)
	tw.tween_property(sprite, "self_modulate", original,    wave_time)

	tw.tween_callback(func():
		if is_instance_valid(sprite):
			var orig := original
			if sprite.has_meta("aura_original_mod"):
				orig = sprite.get_meta("aura_original_mod")
				sprite.remove_meta("aura_original_mod")
			sprite.self_modulate = orig
			sprite.remove_meta("aura_pulsing")
	)
