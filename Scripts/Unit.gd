extends Area2D

var unit_id: int   # Unique identifier for networking
var peer_id: int   

@export var is_player: bool = true  
@export var unit_type: String = "Soldier"  
@export var unit_name: String = "Hero"
@export var portrait: Texture
@export var mek_portrait: Texture  # drag-in your “mek” overlay texture in the editor

var health := 100
var max_health := 100
var xp := 0
var max_xp := 100
var level = 1
@export var damage = 25
@export var movement_range := 2  
@export var attack_range := 3 
@export var defense := 0

var tile_pos: Vector2i

signal movement_finished

@onready var health_bar = $HealthUI
@onready var xp_bar = $XPUI
@onready var step_player: AudioStreamPlayer2D = $SFX

var has_moved : = false
var has_attacked : = false
var being_pushed: bool = false

# ─────────────────────────────────────────────────────────────────────────────
# New state for special abilities:

# 1) Panther mark & pounce
#    We store a "marked" flag on ANY unit (via metadata).
# 2) Angel shield
var shield_amount: int = 0
var shield_duration: int = 0  # counts down at end of next turn

# 3) Multi Turret suppression
var is_suppressed: bool = false

# 4) Brute fortify
var is_fortified: bool = false

# 5) Helicopter airlift & drop
var queued_airlift_unit: Node = null
var queued_bomb_tile: Vector2i = Vector2i(-1, -1)

# 6) Spider web grid (shared 10×10). Each element is a Dictionary {"duration": int}.
static var web_grid: Array = []
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
var true_position := Vector2.ZERO  # we manage this ourselves

var visited_tiles: Array = []
@export var water_tile_id := 6

var level_up_material = preload("res://Textures/level_up.tres")
var original_material : Material = null

var ExplosionScene := preload("res://Scenes/VFX/Explosion.tscn")
const TILE_SIZE := Vector2(64, 64)

var missile_sfx := preload("res://Audio/SFX/missile_launch.wav")
var attack_sfx := preload("res://Audio/SFX/attack_default.wav")
var step_sfx := preload("res://Audio/SFX/step_tile.wav")  # Replace with your actual file

@export var fortify_effect_scene := preload("res://Scenes/VFX/FortifyAura.tscn")
var _fortify_aura: Node = null

var death_messages := [
	"Downed!",
	"Shattered!",
	"Boom!",
	"Deleted!",
	"Neutralized!",
	"Eliminated!",
	"Shutdown!",
	"Erased!"
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

func _ready():
	prev_tile_pos = tile_pos
	connect("movement_finished", Callable(self, "_on_movement_finished"))
		
	# On the host (authoritative), assign a new ID if one is not already set.
	if is_multiplayer_authority():
		if not has_meta("unit_id"):
			unit_id = TurnManager.next_unit_id
			set_meta("unit_id", unit_id)
			TurnManager.next_unit_id += 1
		else:
			unit_id = get_meta("unit_id")
	else:
		if has_meta("unit_id"):
			unit_id = get_meta("unit_id")
		else:
			print("WARNING: Unit ", name, " does not have a unit_id set on the client!")

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

	var tm = get_node("/root/TurnManager")
	if tm:
		tm.connect("round_ended", Callable(self, "_on_round_ended"))
			
	print("Multiplayer authority? ", get_tree().get_multiplayer().is_server())
	
	# Assign footstep audio stream to the AudioStreamPlayer2D
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
	_update_tile_pos()    # updates tile_pos behind the scenes
	check_water_status()

	# Did we change cells since last frame?
	if tile_pos != prev_tile_pos:
		apply_tile_effect()
		prev_tile_pos = tile_pos

func _update_tile_pos():
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var old = tile_pos
	tile_pos = tilemap.local_to_map(tilemap.to_local(global_position))
	if tile_pos != old:
		# We’ve stepped onto a different tile—clear out the old effect
		apply_tile_effect()
		prev_tile_pos = tile_pos

func update_z_index():
	z_index = int(position.y)


### PLAYER TURN ###
func start_turn():
	# Wait for player input; call on_player_done() when action is complete
	#apply_tile_effect()
	pass

func on_player_done():
	TurnManager.unit_finished_action(self)


func compute_path(from: Vector2i, to: Vector2i) -> Array:
	await get_tree().process_frame
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap.update_astar_grid()  # 🔥 Crucial step!
	return tilemap.astar.get_point_path(from, to)


func _move_one(dest: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var world_target = tilemap.to_global(tilemap.map_to_local(dest)) + Vector2(0, Y_OFFSET)

	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("move")
		sprite.flip_h = global_position.x < world_target.x

	var speed := 100.0
	
	# Play the step SFX as we begin moving toward the tile
	if step_player:
		step_player.pitch_scale = randf_range(0.9, 1.1)
		step_player.play()

	while global_position.distance_to(world_target) > 1.0:
		var delta = get_process_delta_time()
		global_position = global_position.move_toward(world_target, speed * delta)
		# ← this will always be valid
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
	
	if is_multiplayer_authority():
		print("DEBUG: Authority moving unit:", unit_id, ", new tile:", tile_pos, ", new global pos:", global_position)
		rpc("remote_update_unit_position", unit_id, tile_pos, global_position)
	else:
		print("DEBUG: Not the authority for unit:", unit_id)

@rpc("reliable")
func remote_update_unit_position(remote_id: int, new_tile: Vector2i, new_position: Vector2) -> void:
	var unit = get_unit_by_id(remote_id)
	if unit and unit != self:
		unit.tile_pos = new_tile
		unit.global_position = new_position
		print("Updated unit ", remote_id, " to new_tile: ", new_tile, ", new global pos: ", new_position)
	else:
		print("Failed to update unit with remote_id: ", remote_id)


# ─────────────────────────────────────────────────────────────────────────────
# Modified take_damage to include: 
#  1) Panther “marked” amplification
#  2) Angel shield absorption
#  3) Brute fortify reduction
func take_damage(amount: int) -> bool:
	# 0) Panther “mark” bonus
	if has_meta("is_marked") and get_meta("is_marked"):
		amount = int(amount * 1.5)
		remove_meta("is_marked")
		
	if is_fortified:
		amount = int(amount * 0.5)
		# After it absorbs damage once, you might want to drop the buff immediately:
		#is_fortified = false
			
	# 1) Angel shield duration
	if shield_duration > 0:
		return false
	
	# 2) Brute fortify: reduce by half if fortified
	if is_fortified:
		amount = int(amount * 0.5)
		
	if not is_player:
		TurnManager.record_damage(amount)
	
	
	spawn_floating_text(amount)
		
	health = max(health - amount, 0)
	update_health_bar()
	if health == 0:
		die()
		return true  # Unit is dead
	return false

# ─────────────────────────────────────────────────────────────────────────────

func auto_attack_adjacent():
	# no melee attacks if you have zero range
	if attack_range < 1:
		# show a little “no attack” popup in red
		spawn_text_popup("No ATK!", Color(1, 0, 0))
		return
			
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0)
	]

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var raw_units = get_tree().get_nodes_in_group("Units")
	var units = []

	for u in raw_units:
		if is_instance_valid(u):
			units.append(u)

	for dir in directions:
		var actual_pos = tilemap.local_to_map(tilemap.to_local(global_position))
		var check_pos = actual_pos + dir

		for unit in units:
			if not is_instance_valid(unit) or unit == self:
				continue
			if unit.tile_pos == check_pos and unit.is_player != is_player:
				var push_pos = unit.tile_pos + dir

				var died = unit.take_damage(damage)
				unit.flash_white()

				var sprite = get_node("AnimatedSprite2D")
				if sprite:
					tilemap.play_attack_sound(global_position)
					if dir.x != 0:
						sprite.flip_h = dir.x > 0
					elif dir.y != 0:
						sprite.flip_h = true
					sprite.play("attack")
					await sprite.animation_finished
					sprite.play("default")
				
				gain_xp(25)
				
				if died:
					gain_xp(25)
					continue

				# Mark as “being pushed” before any movement/awaits
				unit.being_pushed = true
				
				TutorialManager.on_action("push_mechanic")	
				
				# ─── Push logic branch 1: into water ──────────────────
				var tile_id = tilemap.get_cell_source_id(0, push_pos)
				if tile_id == water_tile_id:
					var target_pos = tilemap.to_global(tilemap.map_to_local(push_pos)) + Vector2(0, Y_OFFSET)
					var push_speed = 150.0
					# Move unit step‐by‐step into the water
					while unit.global_position.distance_to(target_pos) > 1.0:
						var delta = get_process_delta_time()
						unit.global_position = unit.global_position.move_toward(target_pos, push_speed * delta)
						await get_tree().process_frame
					unit.global_position = target_pos
					unit.tile_pos = push_pos
					tilemap.play_splash_sound(target_pos)
					apply_water_effect(unit)

					if tilemap.is_tile_occupied(push_pos):
						var occupants = get_occupants_at(push_pos, unit)
						if occupants.size() > 0:
							for occ in occupants:
								if occ.is_in_group("Structures"):
									var occ_sprite = occ.get_node("AnimatedSprite2D")
									if occ_sprite:
										occ_sprite.play("demolished")
										occ_sprite.get_parent().modulate = Color(1, 1, 1, 1)
								elif occ.is_in_group("Units"):
									await get_tree().create_timer(0.2).timeout
									occ.take_damage(damage)
									occ.shake()
							gain_xp(25)
							# Push is “done” even if unit died
							unit.being_pushed = false							
							unit.die()
							tilemap.update_astar_grid()
							continue  # go to next direction

					var water_damage = 25
					died = unit.take_damage(water_damage)
					if not died:
						unit.shake()

					# **At this point, water‐push and splash‐damage have finished.**
					await get_tree().create_timer(0.2).timeout
					tilemap.update_astar_grid()
					
					# Turn off “being_pushed” now that all movement/awaits are done
					if is_instance_valid(unit):
						unit.being_pushed = false
					continue
				# ────────────────────────────────────────────────────────

				# ─── Push logic branch 2: off-grid (unit falls out of bounds) ──────────────────
				elif not tilemap.is_within_bounds(push_pos):
					var target_pos = tilemap.to_global(tilemap.map_to_local(push_pos)) + Vector2(0, Y_OFFSET)
					var push_speed = 150.0
					while unit.global_position.distance_to(target_pos) > 1.0:
						var delta = get_process_delta_time()
						unit.global_position = unit.global_position.move_toward(target_pos, push_speed * delta)
						await get_tree().process_frame
					# Brief delay so death animation can play, etc.
					await get_tree().create_timer(0.2).timeout
					gain_xp(25)
					# Push is done (unit died off-grid)
					unit.being_pushed = false	
					TutorialManager.on_action("offgrid_mechanic")				
					unit.die()
					tilemap.update_astar_grid()
					continue
				# ────────────────────────────────────────────────────────

				# ─── Push logic branch 3: normal on‐grid push ──────────────────
				elif tilemap.is_within_bounds(push_pos):
					var target_pos = tilemap.to_global(tilemap.map_to_local(push_pos)) + Vector2(0, Y_OFFSET)
					var push_speed = 150.0
					while unit.global_position.distance_to(target_pos) > 1.0:
						var delta = get_process_delta_time()
						unit.global_position = unit.global_position.move_toward(target_pos, push_speed * delta)
						await get_tree().process_frame
					unit.global_position = target_pos
					unit.tile_pos = push_pos

					if tilemap.is_tile_occupied(push_pos):
						var occupants = get_occupants_at(push_pos, unit)
						if occupants.size() > 0:
							for occ in occupants:
								if occ.is_in_group("Structures"):
									var occ_sprite = occ.get_node("AnimatedSprite2D")
									if occ_sprite:
										occ_sprite.play("demolished")
										occ_sprite.get_parent().modulate = Color(1, 1, 1, 1)
								elif occ.is_in_group("Units"):
									await get_tree().create_timer(0.2).timeout
									occ.take_damage(damage)
									occ.shake()
							gain_xp(25)
							unit.being_pushed = false
							TutorialManager.on_action("collide_mechanic")
							unit.die()
					tilemap.update_astar_grid()

					# **At this point, the on‐grid push has finished.**
					unit.being_pushed = false
					continue
				# ────────────────────────────────────────────────────────
				
			# end of “if unit to push” block
		# end of “for unit in units” block
	# end of “for dir in directions” block
	has_moved = true
	has_attacked = true
	
	if is_player:
		$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)
	
	# After performing the attack
	TutorialManager.on_action("enemy_attacked")	

# Helper to retrieve occupant nodes (unit or structure) at a tile.
func get_occupants_at(pos: Vector2i, ignore: Node = null) -> Array:
	var occupants = []
	for unit in get_tree().get_nodes_in_group("Units"):
		if is_instance_valid(unit) and unit.tile_pos == pos and unit != ignore:
			occupants.append(unit)
	for structure in get_tree().get_nodes_in_group("Structures"):
		if is_instance_valid(structure) and structure.tile_pos == pos and structure != ignore:
			occupants.append(structure)
	return occupants


# Spawn an explosion VFX at a world position.
func spawn_explosion_at(pos: Vector2):
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	var explosion = explosion_scene.instantiate()
	explosion.position = pos
	get_tree().get_current_scene().add_child(explosion)


func has_adjacent_enemy() -> bool:
	if attack_range < 1:
		# show a little “no attack” popup in red
		spawn_text_popup("No ATK!", Color(1, 0, 0))	
		return false
			
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, 0), Vector2i(1, 0)
	]

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var actual_tile = tilemap.local_to_map(tilemap.to_local(global_position))

	for dir in directions:
		var check_pos = actual_tile + dir
		for unit in get_tree().get_nodes_in_group("Units"):
			if unit == self:
				continue
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
		#max_health += 50
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
		health_bar.value = float(health) / max_health * 100

func update_xp_bar():
	if xp_bar:
		xp_bar.value = float(xp) / max_xp * 100


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
	if is_multiplayer_authority():
		rpc("remote_unit_died", unit_id)

	# Random death popup
	#var msg_index = randi() % death_messages.size()
	#spawn_text_popup(death_messages[msg_index], Color(1, 0.3, 0.3))
		
	# Store tile before anything
	var death_tile = tile_pos
	var death_scene = get_tree().get_current_scene()

	# Delay one frame to let everything settle (optional)
	await get_tree().process_frame

	# Spawn coins **first**
	_spawn_burst(death_scene, death_tile)

	# Now free this unit AFTER coins exist
	queue_free()

	# Tell the TileMap that we lost our selected_unit
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
	
#–– Your burst spawner, but now landing on a random open tile
func _spawn_burst(tilemap: Node, tile_pos: Vector2i) -> void:
	var tm = tilemap.get_node("TileMap") if tilemap.has_node("TileMap") else tilemap
	var num_attempts  := 3
	var spawn_height  := 200.0
	var fall_time     := 5.0
	var fade_in_time  := 1

	for i in range(num_attempts):
		var drop_scene = _choose_drop_scene()
		if drop_scene == null:
			continue

		# pick a random open cell & get its world position
		var cell       = _get_random_open_tile()
		var target_pos = tm.to_global(tm.map_to_local(cell))

		# instantiate it right at the landing spot
		var drop = drop_scene.instantiate() as Node2D
		drop.global_position = target_pos
		drop.global_position.y -= 32
		# start fully transparent
		drop.modulate = Color(1,1,1,0)
		# disable its collision until after fade
		var collider = drop.get_node("CollisionShape2D") as CollisionShape2D
		collider.disabled = true
		get_tree().get_current_scene().add_child(drop)

		# make a tween for fading in → then enable collider
		var tween = drop.create_tween()
		tween.tween_property(drop, "modulate:a", 1.0, fade_in_time) \
			 .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			if is_instance_valid(collider):
				collider.disabled = false
		)


#–– same drop‐choosing logic you had before
func _choose_drop_scene() -> PackedScene:
	var roll = randi() % 100
	if roll < 50:  # 50% chance to drop something
		match randi() % 4:
			0: return HEALTH_SCENE
			1: return LIGHTNING_SCENE
			2: return ORBITAL_STRIKE_SCENE
	return null
	
@rpc("reliable")
func remote_unit_died(remote_id: int) -> void:
	var unit = get_unit_by_id(remote_id)
	if unit and unit != self:
		unit.queue_free()

func get_unit_by_id(target_id: int) -> Node:
	for u in get_tree().get_nodes_in_group("Units"):
		if u.has_meta("unit_id"):
			var uid = u.get_meta("unit_id")
			if uid == target_id:
				return u
	return null


var _flash_tween: Tween = null
var _flash_shader := preload("res://Textures/flash.gdshader")
var _original_material: Material = null

func flash_white():
	var sprite = $AnimatedSprite2D
	if not sprite:
		return

	# Capture the current modulate color before flashing
	var original_color = sprite.self_modulate

	# If a previous flash‐tween is running, kill it and immediately restore the original
	if _flash_tween:
		_flash_tween.kill()
		sprite.self_modulate = original_color
		_flash_tween = null

	_flash_tween = create_tween()
	# Flash 3 times: white → original_color → white → original_color → …
	for i in range(3):
		# Tween from original_color → white over 0.1s
		_flash_tween.tween_property(sprite, "self_modulate", Color(1, 1, 1, 1), 0.1)
		# Then tween back from white → original_color over 0.1s
		_flash_tween.tween_property(sprite, "self_modulate", original_color, 0.1)

	# At the end, make absolutely sure we’re back to the original, and clear the tween reference
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
	set_meta("is_player", player_team)  # ✅ ensure consistent access and multiplayer sync

	var sprite = $AnimatedSprite2D
	if sprite:
		if is_player:
			sprite.modulate = Color(1, 1, 1)  # white for player
		else:
			sprite.modulate = Color(1, 0.43, 1)  # magenta for enemy

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
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
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
	
	# Check for candidates that allow attack in range (same as before)
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
	
	var best_candidate: Vector2i = tile_pos
	var best_cost = INF
	for candidate in candidates:
		var euclid = candidate.distance_to(dest)
		var extra_cost = 0
		if candidate == queued_move:
			extra_cost += 2
		if visited_tiles.has(candidate):
			extra_cost += 5
		if candidate.distance_to(dest) <= attack_range:
			extra_cost -= 10
		var cost = euclid + extra_cost
		if cost < best_cost:
			best_cost = cost
			best_candidate = candidate
	
	if best_candidate != tile_pos:
		queued_move = best_candidate
		visited_tiles.append(best_candidate)
		print("🚶 Fallback move to:", best_candidate)
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
		if sprite and dir.x != 0:
			sprite.flip_h = dir.x > 0
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
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
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		if tilemap.has_method("on_player_unit_done"):
			tilemap.on_player_unit_done(self)

func execute_all_player_actions():
	var units := get_tree().get_nodes_in_group("Units").filter(func(u): return u.is_player)
	for unit in units:
		if unit.has_method("execute_actions"):
			await unit.execute_actions()
	var turn_manager = get_node("/root/TurnManager")
	if turn_manager and turn_manager.has_method("end_turn"):
		turn_manager.end_turn()

func shake():
	var original_position = global_position
	var tween = create_tween()
	tween.tween_property(self, "global_position", original_position + Vector2(5, 0), 0.05)
	tween.tween_property(self, "global_position", original_position - Vector2(5, 0), 0.05)
	tween.tween_property(self, "global_position", original_position, 0.05)

var water_material = preload("res://Textures/in_water.tres")

func apply_water_effect(unit: Node) -> void:
	var sprite = unit.get_node("AnimatedSprite2D")
	if sprite:
		# Save original material if not stored already.
		if not sprite.has_meta("original_material"):
			sprite.set_meta("original_material", sprite.material)
		# Apply the water material.
		sprite.material = water_material

		# Determine which base_modulate to use via if/else instead of a ternary.
		var base_mod: Color
		if unit.is_player:
			base_mod = Color(1, 1, 1, 1)
		else:
			base_mod = Color(1, 0.43, 1, 1)

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
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap.get_cell_source_id(0, tile_pos) == water_tile_id:
		apply_water_effect(self)
	else:
		remove_water_effect(self)

func auto_attack_ranged(target: Node, unit: Area2D) -> void:
	# no ranged attacks if you have zero range
	if unit.attack_range < 1:
		# make sure to unlock input if you’d previously locked it
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		tilemap.input_locked = false
		return
			
	# 1) Early‐exit & unlock if the target’s already gone
	if not is_instance_valid(target):
		var tilemap = get_tree().get_current_scene().get_node("TileMap")
		tilemap.input_locked = false
		return

	# 2) Lock input
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	tilemap.input_locked = true

	# 3) Capture both positions before any await
	var attacker_pos = unit.global_position
	var target_pos   = target.global_position

	# 4) Flip & play the attack animation on the attacker
	var sprite = unit.get_node("AnimatedSprite2D") as AnimatedSprite2D
	sprite.flip_h = target_pos.x > attacker_pos.x
	sprite.play("attack")
	await sprite.animation_finished
	sprite.play("default")

	# 5) Spawn & fire the missile
	var missile = preload("res://Prefabs/Missile.tscn").instantiate()
	get_tree().get_current_scene().add_child(missile)
	missile.set_target(attacker_pos, target_pos)
	missile.damage = unit.damage

	# 6) Award XP
	unit.gain_xp(25)

	# 7) Wait for missile to finish
	await missile.finished

	# 8) Unlock input & mark the unit
	tilemap.input_locked = false
	unit.has_moved   = true
	unit.has_attacked = true

	# 9) Notify tutorial
	TutorialManager.on_action("enemy_attacked")
	
func auto_attack_ranged_empty(target_tile: Vector2i, unit: Area2D) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return

	# ── LOCK TILEMAP INPUT ──
	tilemap.input_locked = true

	var target_pos = tilemap.to_global(tilemap.map_to_local(target_tile)) + Vector2(0, unit.Y_OFFSET)
	var sprite = $AnimatedSprite2D

	# Flip sprite if target is to the right
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

	# ── UNLOCK TILEMAP INPUT ──
	tilemap.input_locked = false

	has_moved = true
	has_attacked = true
	
	# After performing the attack
	TutorialManager.on_action("enemy_attacked")	
	
func apply_level_up_material() -> void:
	var sprite = $AnimatedSprite2D
	if sprite:
		# 1) Grab the current modulate color before changing anything:
		var prior_modulate = sprite.modulate

		# 2) Remember the current material if needed
		if not sprite.has_meta("saved_material"):
			sprite.set_meta("saved_material", sprite.material)

		# 3) Apply the level-up material
		sprite.material = level_up_material

		# 4) Wait for the effect duration (1 second):
		await get_tree().create_timer(1.0).timeout

		# 5) Restore the old material:
		if sprite.has_meta("saved_material"):
			sprite.material = sprite.get_meta("saved_material")
			sprite.remove_meta("saved_material")
		
		# 6) Set modulation tint:
		sprite.modulate = prior_modulate
		
		

# ─────────────────────────────────────────────────────────────────────────────
# 1) Hulk – Ground Slam
@rpc("any_peer", "reliable")
func request_ground_slam(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.ground_slam(target_tile)
	rpc("sync_ground_slam", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_ground_slam(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if atk and not is_multiplayer_authority():
		atk.ground_slam(target_tile)

func ground_slam(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var dist = abs(tile_pos.x - target_tile.x) + abs(tile_pos.y - target_tile.y)
	if dist > 1:
		return

	gain_xp(25)
	
	# — hop up and slam down effect —
	var jump_height := 64.0
	var original_pos := global_position
	var up_pos := original_pos + Vector2(0, -jump_height)

	var hop_tween := create_tween()
	hop_tween.tween_property(self, "global_position", up_pos, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop_tween.tween_property(self, "global_position", original_pos, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await hop_tween.finished

	# — play the attack animation on ourselves —
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("attack")
		await sprite.animation_finished
		sprite.play("default")

	# — spawn explosion at the slam location itself —
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

	# — spawn explosion on tiles adjacent to the *attacker’s* position —
	var directions := [
		Vector2i( 1,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i( 0, -1),
		Vector2i( 1,  1), Vector2i( 1, -1),
		Vector2i(-1,  1), Vector2i(-1, -1),
	]

	for dir in directions:
		var adj_tile = tile_pos + dir
		if not tilemap.is_within_bounds(adj_tile):
			continue

		# 1) See if any unit is on this adjacent tile
		var adj_unit = tilemap.get_unit_at_tile(adj_tile)

		# 2) See if any structure is on this adjacent tile
		var adj_structure: Node2D = null
		for struct_node in get_tree().get_nodes_in_group("structure"):
			if struct_node.tile_pos == adj_tile:
				adj_structure = struct_node
				break

		# 3) Compute the correct global position for the explosion
		var explosion_position: Vector2
		if adj_unit:
			explosion_position = adj_unit.global_position
		elif adj_structure:
			explosion_position = adj_structure.global_position
		else:
			var tile_top_left = tilemap.to_global(tilemap.map_to_local(adj_tile))
			explosion_position = tile_top_left

		# 4) Instantiate & add the Explosion effect
		var explosion_instance = ExplosionScene.instantiate()
		explosion_instance.global_position = explosion_position
		get_tree().get_current_scene().add_child(explosion_instance)

		# 5) Damage any unit found (friend or foe), but skip self
		if adj_unit and adj_unit != self:
			adj_unit.take_damage(30)
			adj_unit.shake()

		# 6) Damage or demolish the structure found
		if adj_structure:
			if adj_structure.has_method("take_damage"):
				adj_structure.take_damage(50)
			else:
				var anim_player = adj_structure.get_child(0)
				if anim_player and anim_player.has_method("play"):
					anim_player.play("demolished")
					adj_structure.modulate = Color(1, 1, 1, 1)

		await get_tree().create_timer(0.1).timeout

	has_attacked = true
	has_moved = true
	$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)

# 2) Panther – Mark & Pounce
@rpc("any_peer", "reliable")
func request_mark_and_pounce(attacker_id: int, target_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	var tgt = get_unit_by_id(target_id)
	if atk and tgt:
		atk.mark_and_pounce(tgt)
	rpc("sync_mark_and_pounce", attacker_id, target_id)

@rpc("any_peer", "reliable")
func sync_mark_and_pounce(attacker_id: int, target_id: int) -> void:
	var atk = get_unit_by_id(attacker_id)
	var tgt = get_unit_by_id(target_id)
	if atk and tgt and not is_multiplayer_authority():
		atk.mark_and_pounce(tgt)

func mark_and_pounce(target_unit: Node) -> void:
	if not target_unit or not target_unit.is_inside_tree():
		return

	$AnimatedSprite2D.play("attack")
	$AudioStreamPlayer2D.play()
	
	# 1) Basic distance-check
	var du = target_unit.tile_pos - tile_pos
	var dist = abs(du.x) + abs(du.y)
	if target_unit.is_player == is_player or dist > 3:
		return

	gain_xp(25)

	# 2) “Mark” the target
	target_unit.set_meta("is_marked", true)
	print("Panther ", name, " marked ", target_unit.name)

	# 3) Compute world positions:
	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap
	var start_world = global_position
	var target_world = tilemap.to_global(tilemap.map_to_local(target_unit.tile_pos))
	# If units sit above the tile:
	target_world.y += target_unit.Y_OFFSET

	# 4) Face the target:
	if target_world.x > start_world.x:
		$AnimatedSprite2D.flip_h = false
	else:
		$AnimatedSprite2D.flip_h = true

	# 5) Build a Tween with a small “hop” in Y:
	var tween = create_tween()

	# (a) First, move to an “apex” above the target (e.g. 32 pixels up) in 0.1s
	var apex = Vector2(target_world.x, target_world.y - 32)
	tween.tween_property(self, "global_position", apex, 0.4) \
		 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# (b) Then, drop down onto the actual target in 0.4s
	tween.tween_property(self, "global_position", target_world, 0.4) \
		 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# (c) Once we arrive, call _on_pounce_arrived(target_unit)
	var cb_arrived = Callable(self, "_on_pounce_arrived").bind(target_unit)
	tween.tween_callback(cb_arrived)

	# (d) Now move back—first hover up from the target, then return to start:
	#     (d1) hop back up 32px above target in 0.1s
	var apex_back = Vector2(start_world.x, start_world.y - 32)
	tween.tween_property(self, "global_position", apex_back, 0.1) \
		 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	#     (d2) drop from that apex back to the original start position in 0.1s
	tween.tween_property(self, "global_position", start_world, 0.1) \
		 .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# (e) Once fully back, call _on_pounce_finished()
	var cb_finished = Callable(self, "_on_pounce_finished")
	tween.tween_callback(cb_finished)

func _on_pounce_arrived(target_unit: Node) -> void:
	var explosion_instance = ExplosionScene.instantiate()
	explosion_instance.global_position = target_unit.global_position
	get_tree().get_current_scene().add_child(explosion_instance)
			
	# Play “attack” animation, then damage:
	$AnimatedSprite2D.play("attack")
	await $AnimatedSprite2D.animation_finished

	if target_unit.has_method("take_damage"):
		target_unit.take_damage(damage)
		target_unit.flash_white()
		target_unit.shake()

	$AnimatedSprite2D.play("default")

func _on_pounce_finished() -> void:
	has_attacked = true
	$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)

# 3) Angel – Guardian Halo
@rpc("any_peer", "reliable")
func request_guardian_halo(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority(): return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.guardian_halo(target_tile)
	rpc("sync_guardian_halo", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_guardian_halo(attacker_id: int, target_tile: Vector2i) -> void:
	if is_multiplayer_authority(): return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.guardian_halo(target_tile)

func guardian_halo(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap

	# 1) Distance check
	var du = target_tile - tile_pos
	var dist = abs(du.x) + abs(du.y)
	print("Guardian Halo called by ", name, "for tile", target_tile, "— dist:", dist)
	if dist > 5:
		print(" → out of range")
		return

	# 2) Try to find the ally
	var ally = tilemap.get_unit_at_tile(target_tile)
	if not ally:
		# fallback: search the Units group manually
		for u in get_tree().get_nodes_in_group("Units"):
			if u.is_player == is_player and u.tile_pos == target_tile:
				ally = u
				break
	print(" → found ally:", ally)

	# 3) Grant shield if it really is an ally
	if ally and ally.is_player == is_player:
		ally.shield_duration = 1
		print("Angel ", name, " granted Guardian Halo to ", ally.name)

		# Turn on the Halo particle (or create one if missing)
		var halo: CPUParticles2D = null
		if ally.has_node("Halo"):
			halo = ally.get_node("Halo")
		else:
			halo = CPUParticles2D.new()
			halo.name = "Halo"
			ally.add_child(halo)
			# configure your particles here…

		halo.emitting = true

		# play effect + sound
		$AudioStreamPlayer2D.play()
		$AnimatedSprite2D.play("attack")
		await $AnimatedSprite2D.animation_finished
		$AnimatedSprite2D.play("default")

	else:
		# no valid ally → fallback heal
		print("Angel ", name, " found no ally → healing self")
		health = min(max_health, health + 20)
		update_health_bar()
		$AnimatedSprite2D.play("attack")
		await $AnimatedSprite2D.animation_finished
		$AnimatedSprite2D.play("default")

	# 4) mark done
	has_attacked = true
	has_moved   = true
	$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)

func _on_round_ended() -> void:
	# (Your existing shield_duration logic, if any)
	if shield_duration > 0:
		shield_duration -= 1
		if shield_duration == 0 and has_node("Halo"):
			get_node("Halo").emitting = false

	# Clear Fortify status
	if is_fortified:
		is_fortified = false

		# Remove the aura if it’s still active
		if _fortify_aura:
			_fortify_aura.queue_free()
			_fortify_aura = null

	#apply_tile_effect()

func apply_tile_effect():
	# ─── Reset to base stats first ─────────────────────────
	movement_range = base_movement_range
	attack_range   = base_attack_range
	defense        = base_defense
		
	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap
	var id = tilemap.get_cell_source_id(0, tile_pos)
	var effect = tilemap.tile_effects.get(id, null)
	if effect == null:
		return

	# Damage‐over‐time:
	if effect.has("damage"):
		take_damage(effect["damage"])
		spawn_text_popup(str(effect["damage"]))

	# Healing:
	if effect.has("heal"):
		health = min(max_health, health + effect["heal"])
		update_health_bar()
		spawn_text_popup("+" + str(effect["heal"]), Color(0, 1, 0))  # bright green “+5”

	# Movement buff / penalty:
	if effect.has("move_buff"):
		movement_range += effect["move_buff"]
		spawn_text_popup("+" + str(effect["move_buff"]) + " MOV")
	elif effect.has("move_penalty"):
		movement_range = max(0, movement_range - effect["move_penalty"])
		spawn_text_popup("-" + str(effect["move_penalty"]) + " MOV")

	# Attack‐range buff / penalty:
	if effect.has("slow"):
		attack_range = max(0, attack_range - effect["slow"])
		spawn_text_popup("-" + str(effect["slow"]) + " ATK")

	# XP gain:
	if effect.has("xp_gain"):
		gain_xp(effect["xp_gain"])

	# Special “slip” or custom effects:
	if effect.has("slip"):
		var neighbours = tilemap.get_neighbors(tile_pos)
		if neighbours.size() > 0:
			var dest = neighbours[randi() % neighbours.size()]
			plan_move(dest)
			spawn_text_popup("Slip!", Color(0.6, 0.8, 1))
			await get_tree().create_timer(0.5).timeout
			# ── apply a -2 ATK penalty on slip:
			attack_range = max(0, attack_range - 2)
			spawn_text_popup("-2 ATK")
		return
					
# 4) Cannon – High-Arcing Shot (animated trajectory over 2 seconds, no ternary)
@rpc("any_peer", "reliable")
func request_high_arcing_shot(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.high_arcing_shot(target_tile)
	rpc("sync_high_arcing_shot", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_high_arcing_shot(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if atk and not is_multiplayer_authority():
		atk.high_arcing_shot(target_tile)

func high_arcing_shot(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap
	var du = target_tile - tile_pos
	var dist = abs(du.x) + abs(du.y)
	if dist > 5:
		return

	# ── LOCK TILEMAP INPUT ──
	tilemap.input_locked = true

	gain_xp(25)

	$AudioStreamPlayer2D.stream = missile_sfx
	$AudioStreamPlayer2D.play()

	# (1) Immediately play attack animation
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("attack")

	# (2) Compute world start/end positions
	var start_world: Vector2 = global_position
	var end_world: Vector2 = tilemap.to_global(tilemap.map_to_local(target_tile))
	end_world.y += Y_OFFSET

	# (3) Build parabolic trajectory points
	var point_count := 64
	var points := PackedVector2Array()
	for i in range(point_count + 1):
		var t = float(i) / float(point_count)
		var x = lerp(start_world.x, end_world.x, t)
		var base_y = lerp(start_world.y, end_world.y, t)
		var height_offset := -100.0 * sin(PI * t)
		var y = base_y + height_offset
		points.append(Vector2(x, y))

	# (4) Create a Line2D and add it to the scene, but don’t add points yet
	var line := Line2D.new()
	line.width = 1
	line.z_index = 4000
	line.default_color = Color(1, 0.8, 0.2)
	get_tree().get_current_scene().add_child(line)

	# (5) Animate the line being drawn over 2 seconds
	var interval = 2.0 / float(point_count)
	for i in range(points.size()):
		line.add_point(points[i])
		await get_tree().create_timer(interval).timeout

	# (6) Once the trajectory is fully drawn, remove the line
	if is_instance_valid(line):
		line.queue_free()

	# (7) Damage & VFX in a 3×3 around target_tile (no ternary)
	var ExplosionScene := preload("res://Scenes/VFX/Explosion.tscn")
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var tile := Vector2i(target_tile.x + dx, target_tile.y + dy)
			if not tilemap.is_within_bounds(tile):
				continue

			# Determine damage without a ternary
			var damage_val: int
			if dx == 0 and dy == 0:
				damage_val = 40
			else:
				damage_val = 30

			# (7a) Damage enemy units
			var u = tilemap.get_unit_at_tile(tile)
			if u:
				u.take_damage(damage_val)
				u.flash_white()
				u.shake()

			# (7b) Damage or demolish any structure on this tile
			var st = tilemap.get_structure_at_tile(tile)
			if st:
				var st_sprite = st.get_node_or_null("AnimatedSprite2D")
				if st_sprite:
					st_sprite.play("demolished")
					st_sprite.get_parent().modulate = Color(1, 1, 1, 1)

			# (7c) Spawn explosion VFX
			var vfx := ExplosionScene.instantiate()
			vfx.global_position = tilemap.to_global(tilemap.map_to_local(tile))
			get_tree().get_current_scene().add_child(vfx)
			await get_tree().create_timer(0.1).timeout

	# (8) Mark cannon as used
	has_attacked = true
	has_moved = true
	if sprite:
		sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)
	$AudioStreamPlayer2D.stream = attack_sfx
	if sprite:
		sprite.play("default")

	# ── UNLOCK TILEMAP INPUT ──
	tilemap.input_locked = false

# 5) Multi Turret – Suppressive Fire
@rpc("any_peer", "reliable")
func request_suppressive_fire(attacker_id: int, dir: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.suppressive_fire(dir)
	rpc("sync_suppressive_fire", attacker_id, dir)

@rpc("any_peer", "reliable")
func sync_suppressive_fire(attacker_id: int, dir: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if atk and not is_multiplayer_authority():
		atk.suppressive_fire(dir)

func suppressive_fire(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap
		
	gain_xp(25)
		
	# 3) Build a list of the four directly adjacent neighbors of this unit
	var neighbors := [
		tile_pos + Vector2i( 1,  0),
		tile_pos + Vector2i(-1,  0),
		tile_pos + Vector2i( 0,  1),
		tile_pos + Vector2i( 0, -1)
	]

	# 4) Filter out any neighbor that lies outside the map bounds
	var tiles_to_hit := []
	for n in neighbors:
		if tilemap.is_within_bounds(n):
			tiles_to_hit.append(n)

	# 5) Fire one projectile at each valid neighbor (0.1 seconds apart)
	_fire_projectiles_along(tiles_to_hit)

	# 6) Mark this unit as used
	has_attacked = true
	has_moved   = true
	$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)

func _fire_projectiles_along(tiles: Array) -> void:
	for i in range(tiles.size()):
		var tile = tiles[i]
		var delay_time = 0.01  # tile 0: 0 s, tile 1: 0.1 s, tile 2: 0.2 s, etc.

		var t = Timer.new()
		t.one_shot = true
		t.wait_time = delay_time
		add_child(t)
		t.start()
		t.connect("timeout", Callable(self, "_on_fire_timer_timeout").bind(tile))

func _on_fire_timer_timeout(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return

	# 1) Compute world‐space start/end positions
	var start_pos = global_position
	var end_pos = tilemap.to_global(tilemap.map_to_local(target_tile))
	end_pos.y += Y_OFFSET  # adjust vertically so the missile aims at the unit’s sprite height

	# 2) Instantiate the projectile scene
	var proj_scene = preload("res://Scenes/Projectile_Scenes/Projectile.tscn")
	var proj = proj_scene.instantiate()
	get_tree().get_current_scene().add_child(proj)

	# 3) Call set_target(...) instead of assigning to a nonexistent property
	proj.set_target(start_pos, end_pos)

	# 4) Connect its “reached_target” signal to handle impact
	proj.connect("reached_target", Callable(self, "_on_projectile_impact").bind(target_tile))

func _on_projectile_impact(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	if tilemap == null:
		return

	# 1) Spawn an explosion VFX at the tile’s center
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	var vfx = explosion_scene.instantiate()
	vfx.global_position = tilemap.to_global(tilemap.map_to_local(target_tile))
	get_tree().get_current_scene().add_child(vfx)

	# 2) Damage any enemy unit on that tile
	var enemy = tilemap.get_unit_at_tile(target_tile)
	if enemy and enemy.is_player != is_player:
		enemy.take_damage(30)
		enemy.flash_white()
		enemy.is_suppressed = true
		print("Multi Turret suppressed ", enemy.name, "at ", target_tile)

	# 3) Damage or demolish any structure on that tile
	var st = tilemap.get_structure_at_tile(target_tile)
	if st:
		if st.has_method("take_damage"):
			st.take_damage(50)
		else:
			var st_sprite = st.get_node_or_null("AnimatedSprite2D")
			if st_sprite:
				st_sprite.play("demolished")
				st.modulate = Color(1, 1, 1, 1)

# 6) Brute – Fortify
@rpc("any_peer", "reliable")
func request_fortify(attacker_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.fortify()
	rpc("sync_fortify", attacker_id)

@rpc("any_peer", "reliable")
func sync_fortify(attacker_id: int) -> void:
	var atk = get_unit_by_id(attacker_id)
	if atk and not is_multiplayer_authority():
		atk.fortify()

func fortify(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap") as TileMap

	gain_xp(25)

	# 2) Apply the "fortify" buff
	is_fortified = true
	print("Brute ", name, " is now fortified.")

	# 3) Play the Brute’s attack animation and sound
	var sprite = $AnimatedSprite2D
	if sprite:
		sprite.play("attack")
		$AudioStreamPlayer2D.play()
		await sprite.animation_finished
		sprite.play("default")

	# 4) Spawn a visual “fortify aura” effect at the Brute’s position
	if fortify_effect_scene:
		# If an aura is already active, remove it first
		if _fortify_aura:
			_fortify_aura.queue_free()
			_fortify_aura = null

		_fortify_aura = fortify_effect_scene.instantiate()
		_fortify_aura.global_position = global_position
		get_tree().get_current_scene().add_child(_fortify_aura)
		# (We’ll free this aura later in _on_round_ended())

	# 5) Mark the Brute as having acted
	has_attacked = true
	has_moved = true
	$AnimatedSprite2D.self_modulate = Color(0.4, 0.4, 0.4, 1)
		
# We’ll store the allied unit we’re “carrying”, and the original tile so we can return.
var queued_airlift_origin: Vector2i = Vector2i(-1, -1)

# ─────────────────────────────────────────────────────────────────────────────
# 7a) RPC: Pick Up an Ally
# The helicopter will move adjacent to the ally, pick it up (hide), then return.
# ─────────────────────────────────────────────────────────────────────────────
# 7a) RPC: Pick Up an Ally
@rpc("any_peer", "reliable")
func request_airlift_pick(attacker_id: int, ally_id: int) -> void:
	if not is_multiplayer_authority():
		return

	var heli = get_unit_by_id(attacker_id)
	var ally = get_unit_by_id(ally_id)
	if heli == null or ally == null:
		return

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	queued_airlift_origin = heli.tile_pos

	# 1) find a walkable tile adjacent to the ally
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

	# 2) move heli step-by-step to that adjacent tile
	var path_to_ally = tilemap.get_weighted_path(heli.tile_pos, target_adjacent)
	for step in path_to_ally:
		await heli.move_to(step)
		tilemap.update_astar_grid()

	# 3) teleport & hide the ally onto the helicopter’s tile
	ally.tile_pos = heli.tile_pos
	ally.global_position = tilemap.to_global(tilemap.map_to_local(heli.tile_pos)) + Vector2(0, ally.Y_OFFSET)
	ally.visible = false
	heli.queued_airlift_unit = ally

	tilemap.update_astar_grid()

	# 4) move helicopter BACK to its original origin
	var path_back = tilemap.get_weighted_path(heli.tile_pos, queued_airlift_origin)
	for step in path_back:
		await heli.move_to(step)
		tilemap.update_astar_grid()

	# 5) mark heli as having used its move
	heli.has_moved = true
	heli.has_attacked = false
	heli.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)

	# 6) tell all clients the pickup is complete
	rpc("sync_airlift_pick", attacker_id, ally_id)

@rpc("any_peer", "reliable")
func sync_airlift_pick(attacker_id: int, ally_id: int) -> void:
	if is_multiplayer_authority():
		return

	var heli = get_unit_by_id(attacker_id)
	var ally = get_unit_by_id(ally_id)
	if heli == null or ally == null:
		return

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	queued_airlift_origin = heli.tile_pos
	ally.tile_pos = heli.tile_pos
	ally.global_position = tilemap.to_global(tilemap.map_to_local(heli.tile_pos)) + Vector2(0, ally.Y_OFFSET)
	ally.visible = false
	tilemap.update_astar_grid()

# ─────────────────────────────────────────────────────────────────────────────
# 7b) RPC: Drop the carried ally
@rpc("any_peer", "reliable")
func request_airlift_drop(attacker_id: int, ally_id: int, drop_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return

	var heli = get_unit_by_id(attacker_id)
	if heli == null or heli.queued_airlift_unit == null:
		return

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var carried = heli.queued_airlift_unit

	# 0) If drop_tile itself is not empty, pick an adjacent tile automatically
	var final_drop = _get_adjacent_tile(tilemap, drop_tile)
	if final_drop == Vector2i(-1, -1):
		push_warning("No valid adjacent tile to actually drop the ally.")
		return

	# 1) move helicopter from queued_airlift_origin to final_drop
	var path_to_drop = tilemap.get_weighted_path(queued_airlift_origin, drop_tile)
	for step in path_to_drop:
		await heli.move_to(step)
		tilemap.update_astar_grid()

	# 2) unhide & teleport the ally onto final_drop
	carried.tile_pos = final_drop
	carried.global_position = tilemap.to_global(tilemap.map_to_local(final_drop)) + Vector2(0, carried.Y_OFFSET)
	carried.visible = true

	# 3) clear heli’s carried pointer
	heli.queued_airlift_unit = null

	# 4) spawn explosion VFX (optional)
	var vfx = ExplosionScene.instantiate()
	vfx.global_position = tilemap.to_global(tilemap.map_to_local(final_drop))
	get_tree().get_current_scene().add_child(vfx)

	tilemap.update_astar_grid()

	heli.has_attacked = true
	heli.has_moved = true
	heli.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)

	rpc("sync_airlift_drop", attacker_id, ally_id, final_drop)

@rpc("any_peer", "reliable")
func sync_airlift_drop(attacker_id: int, ally_id: int, drop_tile: Vector2i) -> void:
	if is_multiplayer_authority():
		return

	var heli = get_unit_by_id(attacker_id)
	var carried = get_unit_by_id(ally_id)
	if heli == null or carried == null:
		return

	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	carried.tile_pos = drop_tile
	carried.global_position = tilemap.to_global(tilemap.map_to_local(drop_tile)) + Vector2(0, carried.Y_OFFSET)
	carried.visible = true
	heli.queued_airlift_unit = null

	var vfx = ExplosionScene.instantiate()
	vfx.global_position = tilemap.to_global(tilemap.map_to_local(drop_tile))
	get_tree().get_current_scene().add_child(vfx)

	tilemap.update_astar_grid()

	heli.has_attacked = true
	heli.has_moved = true
	heli.get_node("AnimatedSprite2D").self_modulate = Color(0.4, 0.4, 0.4, 1)

func _get_adjacent_tile(tilemap: TileMap, base: Vector2i) -> Vector2i:
	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var n = base + dir
		if tilemap.is_within_bounds(n) and tilemap._is_tile_walkable(n) and not tilemap.is_tile_occupied(n):
			return n
	return Vector2i(-1, -1)


# ─────────────────────────────────────────────────────────────────────────────
# 8) (Re‐using “Web Field” button) → actually call spider_blast
# ─────────────────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func request_spider_blast(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.spider_blast(target_tile)
	# propagate to all peers:
	rpc("sync_spider_blast", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_spider_blast(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if atk and not is_multiplayer_authority():
		atk.spider_blast(target_tile)

# Called when a Spider’s “thread_attack” missile reaches its target:
func _on_thread_attack_reached(target_tile: Vector2i) -> void:
	spawn_explosions_at_tile(target_tile)
	print("Thread Attack exploded at tile: ", target_tile)

# 9) Thread Attack
@rpc("any_peer", "reliable")
func request_thread_attack(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.thread_attack(target_tile)
	rpc("sync_thread_attack", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_thread_attack(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if atk and not is_multiplayer_authority():
		atk.thread_attack(target_tile)

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
		sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)

# 10) Lightning Surge
@rpc("any_peer", "reliable")
func request_lightning_surge(attacker_id: int, target_tile: Vector2i) -> void:
	if not is_multiplayer_authority():
		return
	var atk = get_unit_by_id(attacker_id)
	if atk:
		atk.lightning_surge(target_tile)
	rpc("sync_lightning_surge", attacker_id, target_tile)

@rpc("any_peer", "reliable")
func sync_lightning_surge(attacker_id: int, target_tile: Vector2i) -> void:
	var atk = get_unit_by_id(attacker_id)
	if atk and not is_multiplayer_authority():
		atk.lightning_surge(target_tile)

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
		sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)
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

# Spawn 3×3 explosions around a tile (used by Thread Attack)
func spawn_explosions_at_tile(target_tile: Vector2i) -> void:
	var tilemap = get_tree().get_current_scene().get_node("TileMap")
	var explosion_scene = preload("res://Scenes/VFX/Explosion.tscn")
	for x in range(-1, 2):
		for y in range(-1, 2):
			var tile = target_tile + Vector2i(x, y)
			var explosion = explosion_scene.instantiate()
			explosion.global_position = tilemap.to_global(tilemap.map_to_local(tile))
			get_tree().get_current_scene().add_child(explosion)
			var dmg: int
			if x == 0 and y == 0:
				dmg = 40
			else:
				dmg = 25
			var unit = tilemap.get_unit_at_tile(tile)
			if unit:
				unit.take_damage(dmg)
				unit.flash_white()
				unit.shake()
		await get_tree().create_timer(0.2).timeout		
	print("Explosions spawned at and around tile: ", target_tile)

# Compute push direction for melee if needed
func _compute_push_direction(target: Node) -> Vector2i:
	var delta = target.tile_pos - tile_pos
	if abs(delta.x) > abs(delta.y):
		return Vector2i(sign(delta.x), 0)
	else:
		return Vector2i(0, sign(delta.y))


# ─────────────────────────────────────────────────────────────────────────────
# Original “critical_strike” and other existing methods remain unchanged:
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
	get_child(0).self_modulate = Color(0.4, 0.4, 0.4, 1)


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
	get_child(0).self_modulate = Color(0.4, 0.4, 0.4, 1)
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
		get_child(0).self_modulate = Color(0.4, 0.4, 0.4, 1)
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
			var dmg: int
			if x == 0 and y == 0:
				dmg = 25
			else:
				dmg = 25
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
	get_child(0).self_modulate = Color(0.4, 0.4, 0.4, 1)
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
	get_child(0).self_modulate = Color(0.4, 0.4, 0.4, 1)
	if sprite:
		sprite.play("default")


func spider_blast(target_tile: Vector2i) -> void:
	var dist = abs(tile_pos.x - target_tile.x) + abs(tile_pos.y - target_tile.y)
	if dist > 5:
		return
			
	gain_xp(25)
			
	var tilemap = get_node("/root/BattleGrid/TileMap")
	for x in range(-1, 2):
		for y in range(-1, 2):
			var blast_tile = target_tile + Vector2i(x, y)
			var target_pos = tilemap.to_global(tilemap.map_to_local(blast_tile)) + Vector2(0, Y_OFFSET)
			target_pos.y -= 8
			var missile_scene = preload("res://Prefabs/SpiderBlastMissile.tscn")
			var missile = missile_scene.instantiate()
			get_tree().get_current_scene().add_child(missile)
			missile.global_position = global_position
			missile.set_target(global_position, target_pos)
			print("Spider Blast toward: ", blast_tile)
			await get_tree().create_timer(0.2).timeout
	print("Spider Blast activated on ", target_tile)
	has_attacked = true
	has_moved = true
	var sprite = get_child(0)
	if sprite:
		sprite.self_modulate = Color(0.4, 0.4, 0.4, 1)

# ─────────────────────────────────────────────────────────────────────────────
# 7) Healing Wave (localized “heal an ally” ability)
#    RPCs for networked healing:
# ─────────────────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func request_healing_wave(attacker_id: int, target_id: int) -> void:
	# Only the server (authority) actually executes the heal, then broadcasts
	if not is_multiplayer_authority():
		return

	var healer = get_unit_by_id(attacker_id)
	var ally   = get_unit_by_id(target_id)
	if not healer or not ally:
		return

	# Check range on the server side
	var dist = abs(healer.tile_pos.x - ally.tile_pos.x) + abs(healer.tile_pos.y - ally.tile_pos.y)
	if dist > 5:
		return

	# Perform heal
	ally.health = min(ally.max_health, ally.health + 50)
	ally.update_health_bar()

	# (Optional) play VFX/audio on server
	if healer.has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.play("attack")
	# broadcast to all peers so they update this unit’s health locally
	rpc("sync_healing_wave", attacker_id, target_id, ally.health)


@rpc("any_peer", "reliable")
func sync_healing_wave(attacker_id: int, target_id: int, new_health: int) -> void:
	# Every client (including the server) forces its local copy of the target’s health
	var healer = get_unit_by_id(attacker_id)
	var ally   = get_unit_by_id(target_id)
	if not healer or not ally:
		return

	ally.health = new_health
	ally.update_health_bar()

	# Play the same “heal” animation/VFX on each peer
	if healer.has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.play("attack")
	if ally.has_node("AnimatedSprite2D"):
		# flash the healed ally blue briefly
		ally.flash_blue()


func play_heal_sound():
	var sfx = preload("res://Audio/SFX/powerUp.wav") # make sure you have a heal.wav in this path
	var player = AudioStreamPlayer.new()
	player.stream = sfx
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
	popup.position = global_position + Vector2(0, -32)  # Slightly above the unit
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
			base_attack_range += 1   # <— keep the base in sync
		"move_boost":
			movement_range += 1
			base_movement_range += 1 # <— bump the base too
		_:
			print("⚠️ Unknown upgrade:", upgrade)

func get_mek_portrait() -> Texture:
	return mek_portrait

func _on_movement_finished():
	# only re-apply if the tile actually changed
	if tile_pos != prev_tile_pos:
		apply_tile_effect()
		prev_tile_pos = tile_pos
